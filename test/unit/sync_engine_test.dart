import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mybudget/database/app_database.dart';
import 'package:mybudget/database/daos/sync_dao.dart';
import 'package:mybudget/database/server_rows.dart';
import 'package:mybudget/features/categories/data/drift_category_repository.dart';
import 'package:mybudget/features/synchronization/domain/sync_engine.dart';
import 'package:mybudget/features/transactions/data/drift_transaction_repository.dart';
import 'package:mybudget/features/transactions/domain/transaction_repository.dart';

import '../support/fake_remote.dart';

const uid = 'aaaaaaaa-0000-0000-0000-000000000001';

class Device {
  Device(FakeServer server) : remote = FakeRemote(server) {
    db = AppDatabase(NativeDatabase.memory());
    engine = SyncEngine(db, remote, clock: () => DateTime.now().toUtc().add(offset), pageSize: 2);
    tx = DriftTransactionRepository(db, () => uid);
    cats = DriftCategoryRepository(db, () => uid);
  }

  final FakeRemote remote;
  late final AppDatabase db;
  late final SyncEngine engine;
  late final DriftTransactionRepository tx;
  late final DriftCategoryRepository cats;
  Duration offset = Duration.zero;

  /// Jump past any backoff.
  void later() => offset += const Duration(hours: 2);

  Future<List<TransactionRow>> visible() => tx.watchTransactions(TransactionFilter.all).first;

  Future<List<QueuedOp>> queue() => db.syncDao.watchQueue().first;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late FakeServer server;
  late Device a, b;
  late String foodId;

  setUp(() async {
    server = FakeServer(uid)..seedProfile();
    a = Device(server);
    b = Device(server);
    foodId = (await a.cats.createCategory(name: 'Food', type: 'expense', iconKey: 'cart')).id;
    await a.engine.run();
    await b.engine.run();
  });

  tearDown(() async {
    await a.db.close();
    await b.db.close();
  });

  Future<TransactionRow> expense(Device d, int minor, [String desc = '']) => d.tx.createTransaction(
    type: 'expense',
    amountMinor: minor,
    currencyCode: 'TND',
    transactionDate: '2026-10-20',
    categoryId: foodId,
    description: desc,
  );

  test('offline expense on A reaches B exactly once', () async {
    a.remote.online = false;
    final t = await expense(a, 12500, 'Groceries');
    expect(await a.visible(), hasLength(1), reason: 'visible locally while offline');

    await a.engine.run();
    expect(a.engine.state.value.phase, SyncPhase.offline);
    expect(server.rowCount('transactions'), 0);

    a.remote.online = true;
    a.later();
    await a.engine.run();
    await b.engine.run();

    expect(server.rowCount('transactions'), 1);
    final onB = await b.visible();
    expect(onB.single.id, t.id);
    expect(onB.single.amountMinor, 12500);
    expect(onB.single.version, 1);
    expect(await a.queue(), isEmpty);
  });

  test('categories and transactions created together sync parent first', () async {
    a.remote.online = false;
    final cat = await a.cats.createCategory(name: 'Pets', type: 'expense', iconKey: 'pet');
    await a.tx.createTransaction(
      type: 'expense',
      amountMinor: 900,
      currencyCode: 'TND',
      transactionDate: '2026-10-21',
      categoryId: cat.id,
    );
    a.remote.online = true;
    a.later();
    await a.engine.run();
    expect(await a.queue(), isEmpty);
    expect(server.tables['transactions']!.values.single['category_id'], cat.id);
  });

  test('unsent edits coalesce; create+delete cancels out', () async {
    a.remote.online = false;
    final t = await expense(a, 100);
    await a.tx.updateTransaction(t.copyWith(amountMinor: 200));
    await a.tx.updateTransaction(t.copyWith(amountMinor: 300));
    final q = await a.queue();
    expect(q, hasLength(1));
    expect(q.single.operation, 'create');

    final t2 = await expense(a, 50);
    await a.tx.deleteTransaction(t2.id);
    expect(await a.queue(), hasLength(1));

    a.remote.online = true;
    a.later();
    await a.engine.run();
    expect(server.tables['transactions']!.values.single['amount_minor'], 300);
  });

  test('timeout after server commit: retry creates no duplicate, later edit is kept', () async {
    final t = await expense(a, 100);
    a.remote.dropNextPushResponse = true;
    await a.engine.run();
    expect(server.rowCount('transactions'), 1, reason: 'server committed');
    expect((await a.queue()).single.attemptCount, 1, reason: 'op kept for retry');

    // Edit after the ambiguous send must not merge into the sent op.
    await a.tx.updateTransaction(t.copyWith(amountMinor: 777));
    expect(await a.queue(), hasLength(2));

    a.later();
    await a.engine.run();
    expect(server.rowCount('transactions'), 1);
    expect(server.tables['transactions']![t.id]!['amount_minor'], 777);
    expect(server.tables['transactions']![t.id]!['version'], 2);
    expect(await a.queue(), isEmpty);
    expect((await a.visible()).single.version, 2);
  });

  test('concurrent edits raise a conflict; keep server', () async {
    final t = await expense(a, 100);
    await a.engine.run();
    await b.engine.run();

    a.remote.online = false;
    b.remote.online = false;
    await a.tx.updateTransaction(t.copyWith(amountMinor: 111));
    final onB = (await b.visible()).single;
    await b.tx.updateTransaction(onB.copyWith(amountMinor: 222));

    a.remote.online = true;
    b.remote.online = true;
    a.later();
    b.later();
    await a.engine.run();
    await b.engine.run();

    final conflicts = await b.db.syncDao.watchConflicts().first;
    expect(conflicts, hasLength(1));
    expect((await b.visible()).single.amountMinor, 222, reason: 'local edit not overwritten by pull');
    expect(server.tables['transactions']![t.id]!['amount_minor'], 111);

    await b.db.syncDao.keepServer(conflicts.single);
    expect((await b.visible()).single.amountMinor, 111);
    expect(await b.queue(), isEmpty);
  });

  test('concurrent edits raise a conflict; keep mine', () async {
    final t = await expense(a, 100);
    await a.engine.run();
    await b.engine.run();

    a.remote.online = false;
    await a.tx.updateTransaction(t.copyWith(amountMinor: 111));
    await b.tx.updateTransaction((await b.visible()).single.copyWith(amountMinor: 222));
    await b.engine.run();
    a.remote.online = true;
    a.later();
    await a.engine.run();

    final c = (await a.db.syncDao.watchConflicts().first).single;
    await a.db.syncDao.keepMine(c);
    await a.engine.run();
    await b.engine.run();

    expect(server.tables['transactions']![t.id]!['amount_minor'], 111);
    expect(server.tables['transactions']![t.id]!['version'], 3);
    expect((await b.visible()).single.amountMinor, 111);
  });

  test('edit vs delete; keep mine restores the record everywhere', () async {
    final t = await expense(a, 100);
    await a.engine.run();
    await b.engine.run();

    await a.tx.deleteTransaction(t.id);
    await a.engine.run();
    b.remote.online = false;
    await b.tx.updateTransaction((await b.visible()).single.copyWith(amountMinor: 333));
    b.remote.online = true;
    b.later();
    await b.engine.run();

    final c = (await b.db.syncDao.watchConflicts().first).single;
    await b.db.syncDao.keepMine(c);
    await b.engine.run();
    await a.engine.run();

    expect(server.tables['transactions']![t.id]!['deleted_at'], isNull);
    expect(server.tables['transactions']![t.id]!['amount_minor'], 333);
    expect((await b.visible()).single.amountMinor, 333);
    expect((await a.visible()).single.amountMinor, 333, reason: 'restored on the deleting device too');
  });

  test('rejected session backs off instead of retrying immediately', () async {
    await expense(a, 100);
    a.remote.rejectToken = true;
    await a.engine.run();
    expect(a.engine.state.value.phase, SyncPhase.needsAuth);
    final op = (await a.queue()).single;
    expect(op.nextAttemptAt.isAfter(DateTime.now().toUtc()), isTrue, reason: 'no 2-second hot loop');

    a.remote.rejectToken = false;
    await a.db.syncDao.retryNow(); // what re-sign-in does
    await a.engine.run();
    expect(await a.queue(), isEmpty);
  });

  test('delete on one device propagates as a tombstone', () async {
    final t = await expense(a, 100);
    await a.engine.run();
    await b.engine.run();
    expect(await b.visible(), hasLength(1));

    await a.tx.deleteTransaction(t.id);
    await a.engine.run();
    await b.engine.run();
    expect(await b.visible(), isEmpty);
    expect(server.tables['transactions']![t.id]!['deleted_at'], isNotNull);
  });

  test('restart with an op left mid-flight still syncs it', () async {
    await expense(a, 100);
    final op = (await a.queue()).single;
    await a.db.syncDao.markSending([op], {op.id: null}); // crash right after marking
    final restarted = SyncEngine(a.db, a.remote);
    await restarted.run();
    expect(await a.queue(), isEmpty);
    expect(server.rowCount('transactions'), 1);
  });

  test('pull pages through more rows than one page', () async {
    for (var i = 1; i <= 5; i++) {
      await expense(a, i * 10);
    }
    await a.engine.run();
    await b.engine.run();
    expect(await b.visible(), hasLength(5));
    expect(await b.db.syncDao.cursor(EntityType.transaction), greaterThan(0));
  });

  test('server-side edit from elsewhere is pulled', () async {
    final t = await expense(a, 100);
    await a.engine.run();
    server.serverEdit('transactions', t.id, {'amount_minor': 4242});
    await a.engine.run();
    final local = (await a.visible()).single;
    expect(local.amountMinor, 4242);
    expect(local.version, 2);
  });

  test('signed out: sync pauses, local data stays usable', () async {
    a.remote.signedIn = false;
    await expense(a, 100);
    await a.engine.run();
    expect(a.engine.state.value.phase, SyncPhase.needsAuth);
    expect(await a.visible(), hasLength(1));
    expect((await a.queue()).single.status, OpStatus.pending);
  });

  test('keep server on a conflict stored by v1.0.0 (no workspace in server row)', () async {
    final t = await expense(a, 100);
    await a.engine.run();
    await b.engine.run();
    a.remote.online = false;
    await a.tx.updateTransaction(t.copyWith(amountMinor: 111));
    await b.tx.updateTransaction((await b.visible()).single.copyWith(amountMinor: 222));
    a.remote.online = true;
    a.later();
    b.later();
    await a.engine.run();
    await b.engine.run();
    await b.db.customStatement(r"UPDATE sync_conflicts SET server_row = json_remove(server_row, '$.workspace')");

    await b.db.syncDao.keepServer((await b.db.syncDao.watchConflicts().first).single);
    final row = (await b.visible()).single;
    expect(row.amountMinor, 111);
    expect(row.workspace, 'personal');
  });

  test('op queued by v1.0.0 (no workspace in payload) syncs as personal', () async {
    a.remote.online = false;
    final t = await expense(a, 700);
    await a.db.customStatement(r"UPDATE sync_queue SET payload = json_remove(payload, '$.workspace')");

    a.remote.online = true;
    a.later();
    await a.engine.run();
    await b.engine.run();

    expect(server.tables['transactions']![t.id]!['workspace'], 'personal');
    expect((await b.visible()).single.workspace, 'personal');
    expect(await a.queue(), isEmpty);
  });

  test('a row cannot use a category from another workspace', () async {
    final rows = server.apply({
      'op_id': 'op-free-cat',
      'entity_type': 'category',
      'entity_id': 'free-cat',
      'operation': 'create',
      'payload': {
        'workspace': 'freelancer',
        'name': 'Software',
        'type': 'expense',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      },
    });
    expect(rows['status'], 'applied');
    await a.engine.run();

    await a.tx.createTransaction(
      type: 'expense',
      amountMinor: 100,
      currencyCode: 'TND',
      transactionDate: '2026-10-20',
      categoryId: 'free-cat',
    );
    await a.engine.run();
    expect((await a.queue()).single.status, OpStatus.failed);
    expect(server.rowCount('transactions'), 0);
  });

  test('validation rejects bad input before anything is stored', () async {
    expect(() => expense(a, 0), throwsA(isA<ValidationException>()));
    expect(
      () => a.tx.createTransaction(
        type: 'income',
        amountMinor: 1,
        currencyCode: 'TND',
        transactionDate: '2026-10-20',
        categoryId: foodId,
      ),
      throwsA(isA<ValidationException>()),
      reason: 'expense category on an income',
    );
    expect(await a.queue(), isEmpty);
  });
}

import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mybudget/database/app_database.dart';
import 'package:mybudget/features/auth/data/profile_repository.dart';
import 'package:mybudget/features/budgets/data/drift_budget_repository.dart';
import 'package:mybudget/features/categories/data/drift_category_repository.dart';
import 'package:mybudget/features/synchronization/domain/sync_engine.dart';
import 'package:mybudget/features/transactions/data/drift_transaction_repository.dart';
import 'package:mybudget/features/transactions/domain/transaction_repository.dart';

import '../support/fake_remote.dart';

const uid = 'aaaaaaaa-0000-0000-0000-000000000001';

/// One device's repositories for both workspaces.
class Device {
  Device(FakeServer server) : remote = FakeRemote(server) {
    db = AppDatabase(NativeDatabase.memory());
    engine = SyncEngine(db, remote);
    personalTx = DriftTransactionRepository(db, () => uid);
    freelanceTx = DriftTransactionRepository(db, () => uid, workspace: 'freelancer');
    personalCats = DriftCategoryRepository(db, () => uid);
    freelanceCats = DriftCategoryRepository(db, () => uid, workspace: 'freelancer');
    personalBudgets = DriftBudgetRepository(db, () => uid);
    freelanceBudgets = DriftBudgetRepository(db, () => uid, workspace: 'freelancer');
    profile = ProfileRepository(db, () => uid);
  }

  final FakeRemote remote;
  late final AppDatabase db;
  late final SyncEngine engine;
  late final DriftTransactionRepository personalTx, freelanceTx;
  late final DriftCategoryRepository personalCats, freelanceCats;
  late final DriftBudgetRepository personalBudgets, freelanceBudgets;
  late final ProfileRepository profile;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late FakeServer server;
  late Device a, b;

  setUp(() async {
    server = FakeServer(uid)..seedProfile();
    a = Device(server);
    b = Device(server);
    await a.engine.run();
    await b.engine.run();
  });

  tearDown(() async {
    await a.db.close();
    await b.db.close();
  });

  Future<TransactionRow> spend(DriftTransactionRepository repo, int minor, String catId) => repo.createTransaction(
    type: 'expense',
    amountMinor: minor,
    currencyCode: 'TND',
    transactionDate: '2026-10-20',
    categoryId: catId,
  );

  test('rows, totals and budgets stay in their workspace on both devices', () async {
    final food = await a.personalCats.createCategory(name: 'Food', type: 'expense');
    final software = await a.freelanceCats.createCategory(name: 'Software', type: 'expense');
    await spend(a.personalTx, 100, food.id);
    await spend(a.freelanceTx, 900, software.id);
    await a.personalBudgets.createBudget(
      name: 'All',
      amountMinor: 5000,
      currencyCode: 'TND',
      periodStart: '2026-10-01',
      periodEnd: '2026-10-31',
    );
    await a.engine.run();
    await b.engine.run();

    for (final d in [a, b]) {
      expect((await d.personalCats.watchCategories().first).map((c) => c.name), ['Food']);
      expect((await d.freelanceCats.watchCategories().first).map((c) => c.name), ['Software']);
      expect((await d.personalTx.watchTransactions(TransactionFilter.all).first).single.amountMinor, 100);
      expect((await d.freelanceTx.watchTransactions(TransactionFilter.all).first).single.amountMinor, 900);
      expect((await d.personalTx.watchSummary().first).expense, {'TND': 100});
      expect((await d.freelanceTx.watchSummary().first).expense, {'TND': 900});
      expect(
        (await d.personalBudgets.watchBudgets().first).single.spentMinor,
        100,
        reason: 'freelance spend not counted',
      );
      expect(await d.freelanceBudgets.watchBudgets().first, isEmpty);
    }
    expect(server.tables['transactions']!.values.map((t) => t['workspace']).toSet(), {'personal', 'freelancer'});
  });

  test('a category from the other workspace is rejected before anything is queued', () async {
    final software = await a.freelanceCats.createCategory(name: 'Software', type: 'expense');
    final queued = (await a.db.syncDao.watchQueue().first).length;

    expect(() => spend(a.personalTx, 100, software.id), throwsA(isA<ValidationException>()));
    expect(
      () => a.personalBudgets.createBudget(
        name: 'Tools',
        amountMinor: 100,
        currencyCode: 'TND',
        periodStart: '2026-10-01',
        periodEnd: '2026-10-31',
        categoryId: software.id,
      ),
      throwsA(isA<ValidationException>()),
    );
    expect(await a.db.syncDao.watchQueue().first, hasLength(queued));
  });

  test('enabling Freelancer reaches the other device; a stale device renaming keeps it on', () async {
    await a.profile.update(displayName: '', currencyCode: 'TND', freelancerEnabled: true);
    await a.engine.run();
    expect(server.tables['profiles']![uid]!['freelancer_enabled'], true);

    // b hasn't pulled the flag yet and renames the user
    await b.profile.update(displayName: 'Ridha', currencyCode: 'TND');
    expect(jsonDecode((await b.db.syncDao.watchQueue().first).single.payload), isNot(contains('freelancer_enabled')));
    await b.engine.run();

    expect(server.tables['profiles']![uid]!['freelancer_enabled'], true);
    expect(server.tables['profiles']![uid]!['display_name'], 'Ridha');
    expect((await b.profile.watchProfile().first)!.freelancerEnabled, true);
  });

  test('toggle then rename before syncing keeps the toggle', () async {
    a.remote.online = false;
    await a.profile.update(displayName: '', currencyCode: 'TND', freelancerEnabled: true);
    await a.profile.update(displayName: 'Ridha', currencyCode: 'TND');
    final payload = jsonDecode((await a.db.syncDao.watchQueue().first).single.payload);
    expect(payload, {'display_name': 'Ridha', 'currency_code': 'TND', 'freelancer_enabled': true});
  });
}

// Two devices, one user, real Supabase. Needs `supabase start`; skipped otherwise.
// Run: flutter test test/integration
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mybudget/database/app_database.dart';
import 'package:mybudget/features/categories/data/drift_category_repository.dart';
import 'package:mybudget/features/synchronization/data/supabase_sync_api.dart';
import 'package:mybudget/features/synchronization/domain/sync_engine.dart';
import 'package:mybudget/features/transactions/data/drift_transaction_repository.dart';
import 'package:mybudget/features/transactions/domain/transaction_repository.dart';
import 'package:supabase/supabase.dart';

const url = String.fromEnvironment('SUPABASE_URL', defaultValue: 'http://127.0.0.1:54321');
const key = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH',
);

class Device {
  Device(this.client, String uid) : db = AppDatabase(NativeDatabase.memory()) {
    engine = SyncEngine(db, SupabaseSyncApi(client));
    tx = DriftTransactionRepository(db, () => uid);
    cats = DriftCategoryRepository(db, () => uid);
  }

  final SupabaseClient client;
  final AppDatabase db;
  late final SyncEngine engine;
  late final DriftTransactionRepository tx;
  late final DriftCategoryRepository cats;

  Future<List<TransactionRow>> visible() => tx.watchTransactions(TransactionFilter.all).first;
}

Future<bool> _reachable() async {
  try {
    final r = await HttpClient().getUrl(Uri.parse('$url/auth/v1/health')).then((q) => q.close());
    return r.statusCode < 500;
  } catch (_) {
    return false;
  }
}

void main() async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final up = await _reachable();

  group('two devices against local Supabase', skip: up ? false : 'supabase start is not running', () {
    late Device a, b;
    final email = 'it-${DateTime.now().microsecondsSinceEpoch}@test.dev';
    const password = 'integration-pass-123';

    setUpAll(() async {
      final ca = SupabaseClient(url, key, authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit));
      final res = await ca.auth.signUp(email: email, password: password);
      final cb = SupabaseClient(url, key, authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit));
      await cb.auth.signInWithPassword(email: email, password: password);
      a = Device(ca, res.user!.id);
      b = Device(cb, res.user!.id);
    });

    tearDownAll(() async {
      await a.db.close();
      await b.db.close();
    });

    test('server-seeded categories arrive once on each device', () async {
      await a.engine.run();
      await b.engine.run();
      final onA = await a.cats.watchCategories().first;
      final onB = await b.cats.watchCategories().first;
      expect(onA, hasLength(10));
      expect(onB.map((c) => c.id).toSet(), onA.map((c) => c.id).toSet());
    });

    test('expense on A reaches B; edit conflict is detected; delete propagates', () async {
      final groceries = (await a.cats.watchCategories(type: 'expense').first).first;
      final t = await a.tx.createTransaction(
        type: 'expense',
        amountMinor: 12500,
        currencyCode: 'TND',
        transactionDate: '2026-10-20',
        categoryId: groceries.id,
        description: 'Market',
      );
      await a.engine.run();
      await b.engine.run();
      expect((await b.visible()).single.id, t.id);
      expect(a.engine.state.value.phase, SyncPhase.idle);

      // concurrent edits
      await a.tx.updateTransaction((await a.visible()).single.copyWith(amountMinor: 111));
      await b.tx.updateTransaction((await b.visible()).single.copyWith(amountMinor: 222));
      await a.engine.run();
      await b.engine.run();
      final conflicts = await b.db.syncDao.watchConflicts().first;
      expect(conflicts, hasLength(1));
      await b.db.syncDao.keepServer(conflicts.single);
      expect((await b.visible()).single.amountMinor, 111);

      await a.tx.deleteTransaction(t.id);
      await a.engine.run();
      await b.engine.run();
      expect(await b.visible(), isEmpty);
    });

    test('replaying an already-applied op does not duplicate', () async {
      final t = await a.tx.createTransaction(
        type: 'income',
        amountMinor: 5000,
        currencyCode: 'EUR',
        transactionDate: '2026-10-21',
      );
      final op = (await a.db.syncDao.watchQueue().first).single;
      final api = SupabaseSyncApi(a.client);
      final payload = {
        'op_id': op.id,
        'entity_type': op.entityType,
        'entity_id': op.entityId,
        'operation': op.operation,
        'base_version': null,
        'payload': {'type': 'income', 'amount_minor': 5000, 'currency_code': 'EUR', 'transaction_date': '2026-10-21'},
      };
      expect((await api.push([payload])).single['status'], 'applied'); // "response lost"
      await a.engine.run(); // engine sends the same op_id again
      expect(await a.db.syncDao.watchQueue().first, isEmpty);
      final rows = await a.client.from('transactions').select().eq('id', t.id);
      expect(rows, hasLength(1));
    });
  });
}

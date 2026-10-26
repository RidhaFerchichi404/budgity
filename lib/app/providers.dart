import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import '../features/analytics/data/drift_analytics_repository.dart';
import '../features/analytics/domain/analytics_repository.dart';
import '../features/auth/data/profile_repository.dart';
import '../features/budgets/data/drift_budget_repository.dart';
import '../features/budgets/domain/budget_repository.dart';
import '../features/categories/data/drift_category_repository.dart';
import '../features/categories/domain/category_repository.dart';
import '../features/synchronization/data/supabase_sync_api.dart';
import '../features/synchronization/domain/sync_engine.dart';
import '../features/synchronization/domain/sync_scheduler.dart';
import '../features/transactions/data/drift_transaction_repository.dart';
import '../features/transactions/domain/transaction_repository.dart';
import '../services/supabase_service.dart';

final supabaseProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

String _uid(Ref ref) => ref.read(supabaseProvider).auth.currentUser!.id;

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.open();
  ref.onDispose(db.close);
  return db;
});

final selectedWorkspaceProvider = NotifierProvider<SelectedWorkspace, String>(SelectedWorkspace.new);

class SelectedWorkspace extends Notifier<String> {
  @override
  String build() => 'personal';

  void select(String workspace) => state = workspace;
}

/// The workspace every screen shows: Personal unless Freelancer is enabled and chosen.
/// Repositories watch it, so switching rebuilds every stream.
final workspaceProvider = Provider<String>((ref) {
  final enabled = ref.watch(profileProvider).value?.freelancerEnabled ?? false;
  return enabled ? ref.watch(selectedWorkspaceProvider) : 'personal';
});

final transactionRepositoryProvider = Provider<TransactionRepository>(
  (ref) =>
      DriftTransactionRepository(ref.watch(databaseProvider), () => _uid(ref), workspace: ref.watch(workspaceProvider)),
);

final categoryRepositoryProvider = Provider<CategoryRepository>(
  (ref) =>
      DriftCategoryRepository(ref.watch(databaseProvider), () => _uid(ref), workspace: ref.watch(workspaceProvider)),
);

final budgetRepositoryProvider = Provider<BudgetRepository>(
  (ref) => DriftBudgetRepository(ref.watch(databaseProvider), () => _uid(ref), workspace: ref.watch(workspaceProvider)),
);

final analyticsRepositoryProvider = Provider<AnalyticsRepository>(
  (ref) => DriftAnalyticsRepository(ref.watch(databaseProvider), workspace: ref.watch(workspaceProvider)),
);

/// Overridable so date-dependent screens (budget pace, this month) render deterministically in tests.
final todayProvider = Provider<DateTime>((ref) => DateTime.now());

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(databaseProvider), () => _uid(ref)),
);

final profileProvider = StreamProvider<Profile?>((ref) => ref.watch(profileRepositoryProvider).watchProfile());

/// The user's default currency; falls back until the profile has synced.
final currencyProvider = Provider<String>((ref) => ref.watch(profileProvider).value?.currencyCode ?? 'TND');

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final engine = SyncEngine(ref.watch(databaseProvider), SupabaseSyncApi(ref.watch(supabaseProvider)));
  ref.onDispose(engine.dispose);
  return engine;
});

/// Watched by the signed-in shell, so triggers only run while signed in.
final syncSchedulerProvider = Provider<SyncScheduler>((ref) {
  final scheduler = SyncScheduler(ref.watch(syncEngineProvider), ref.watch(databaseProvider))..start();
  ref.onDispose(scheduler.stop);
  return scheduler;
});

/// The local DB belongs to one user. If another user's data is found (e.g. the
/// session was revoked without a sign-out), purge it before showing anything.
final dbOwnerCheckProvider = FutureProvider<void>((ref) async {
  final uid = _uid(ref);
  final db = ref.watch(databaseProvider);
  final owner = await db.syncDao.meta('owner_user_id');
  if (owner == null) return db.syncDao.setMeta('owner_user_id', uid);
  if (owner == uid) return;
  await db.close();
  await deleteDbFiles();
  ref.invalidate(databaseProvider);
});

final signingOutProvider = NotifierProvider<SigningOut, bool>(SigningOut.new);

class SigningOut extends Notifier<bool> {
  @override
  bool build() => false;

  /// Number of local changes that would be lost, after one last sync attempt.
  Future<int> pendingAfterFinalSync() async {
    await ref.read(syncSchedulerProvider).syncNow();
    return ref.read(databaseProvider).syncDao.queueLength();
  }

  /// Purges local data (ADR 0005). Call only after the user confirmed any loss.
  Future<void> signOut() async {
    state = true; // shell unmounts its DB-backed screens
    try {
      await ref.read(syncSchedulerProvider).stop();
      await ref.read(databaseProvider).close();
      await deleteDbFiles();
      try {
        await ref.read(supabaseProvider).auth.signOut(scope: SignOutScope.local);
      } catch (_) {
        // offline: the local session must still go
        await const SecureSessionStorage().removePersistedSession();
      }
      ref.invalidate(databaseProvider);
    } finally {
      state = false;
    }
  }
}

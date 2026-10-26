import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/analytics/presentation/analytics_screen.dart';
import '../features/auth/presentation/sign_in_screen.dart';
import '../features/budgets/presentation/budgets_screen.dart';
import '../features/categories/presentation/categories_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/synchronization/presentation/sync_screen.dart';
import '../features/transactions/presentation/transaction_form_screen.dart';
import '../features/transactions/presentation/transactions_screen.dart';
import '../shared/widgets/adaptive_shell.dart';
import 'providers.dart';

/// Re-runs redirects whenever auth state changes.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Stream<Object?> s) {
    _sub = s.listen((_) => notifyListeners());
  }

  late final StreamSubscription<Object?> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(supabaseProvider).auth;
  final refresh = _AuthRefresh(auth.onAuthStateChange);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    refreshListenable: refresh,
    // Signed in = a stored session exists, even if expired: local data stays
    // usable offline and sync asks for a new sign-in when it needs one.
    redirect: (context, state) {
      final signedIn = auth.currentSession != null;
      final atLogin = state.matchedLocation == '/sign-in';
      if (!signedIn) return atLogin ? null : '/sign-in';
      return atLogin ? '/' : null;
    },
    routes: [
      GoRoute(path: '/sign-in', builder: (_, _) => const SignInScreen()),
      GoRoute(path: '/transactions/new', builder: (_, _) => const TransactionFormScreen()),
      GoRoute(
        path: '/transactions/:id',
        builder: (_, s) => TransactionFormScreen(transactionId: s.pathParameters['id']),
      ),
      GoRoute(path: '/sync', builder: (_, _) => const SyncScreen()),
      GoRoute(path: '/analytics', builder: (_, _) => const AnalyticsScreen()),
      ShellRoute(
        builder: (_, state, child) => AdaptiveShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (_, _) => const NoTransitionPage(child: DashboardScreen()),
          ),
          GoRoute(
            path: '/transactions',
            pageBuilder: (_, _) => const NoTransitionPage(child: TransactionsScreen()),
          ),
          GoRoute(
            path: '/budgets',
            pageBuilder: (_, _) => const NoTransitionPage(child: BudgetsScreen()),
          ),
          GoRoute(
            path: '/categories',
            pageBuilder: (_, _) => const NoTransitionPage(child: CategoriesScreen()),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (_, _) => const NoTransitionPage(child: SettingsScreen()),
          ),
        ],
      ),
    ],
  );
});

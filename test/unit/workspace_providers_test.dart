import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mybudget/app/providers.dart';
import 'package:mybudget/database/app_database.dart';
import 'package:mybudget/features/budgets/data/drift_budget_repository.dart';
import 'package:mybudget/features/categories/data/drift_category_repository.dart';
import 'package:mybudget/features/transactions/data/drift_transaction_repository.dart';
import 'package:mybudget/features/transactions/domain/transaction_repository.dart';
import 'package:mybudget/features/transactions/presentation/transactions_screen.dart';

Profile _profile({required bool freelancer}) => Profile(
  id: 'u',
  displayName: '',
  currencyCode: 'TND',
  freelancerEnabled: freelancer,
  updatedAt: DateTime.utc(2026),
  changeSeq: 1,
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<ProviderContainer> container({required bool freelancer}) async {
    final db = AppDatabase(NativeDatabase.memory());
    final c = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        profileProvider.overrideWith((ref) => Stream.value(_profile(freelancer: freelancer))),
      ],
    );
    addTearDown(() async {
      c.dispose();
      await db.close();
    });
    // keep the profile stream alive; an unlistened StreamProvider is disposed before it emits
    c.listen(profileProvider, (_, _) {});
    await c.read(profileProvider.future);
    return c;
  }

  List<String> repoWorkspaces(ProviderContainer c) => [
    (c.read(transactionRepositoryProvider) as DriftTransactionRepository).workspace,
    (c.read(categoryRepositoryProvider) as DriftCategoryRepository).workspace,
    (c.read(budgetRepositoryProvider) as DriftBudgetRepository).workspace,
  ];

  test('selecting Freelancer rescopes every repository', () async {
    final c = await container(freelancer: true);
    expect(repoWorkspaces(c), ['personal', 'personal', 'personal']);
    c.read(selectedWorkspaceProvider.notifier).select('freelancer');
    expect(repoWorkspaces(c), ['freelancer', 'freelancer', 'freelancer']);
  });

  test('with Freelancer disabled the selection is ignored', () async {
    final c = await container(freelancer: false);
    c.read(selectedWorkspaceProvider.notifier).select('freelancer');
    expect(c.read(workspaceProvider), 'personal');
    expect(repoWorkspaces(c), ['personal', 'personal', 'personal']);
  });

  test('switching workspace resets the transaction filter', () async {
    final c = await container(freelancer: true);
    c.read(transactionFilterProvider.notifier).set(const TransactionFilter(categoryId: 'food'));
    c.listen(transactionFilterProvider, (_, _) {});
    c.read(selectedWorkspaceProvider.notifier).select('freelancer');
    expect(c.read(transactionFilterProvider).categoryId, isNull);
  });
}

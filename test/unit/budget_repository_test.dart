import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mybudget/core/errors/validation_exception.dart';
import 'package:mybudget/database/app_database.dart';
import 'package:mybudget/features/budgets/data/drift_budget_repository.dart';
import 'package:mybudget/features/categories/data/drift_category_repository.dart';
import 'package:mybudget/features/transactions/data/drift_transaction_repository.dart';

void main() {
  late AppDatabase db;
  late DriftBudgetRepository budgets;
  late DriftTransactionRepository tx;
  late DriftCategoryRepository cats;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    budgets = DriftBudgetRepository(db, () => 'u');
    tx = DriftTransactionRepository(db, () => 'u');
    cats = DriftCategoryRepository(db, () => 'u');
  });

  tearDown(() => db.close());

  test('spent counts only matching currency, period, category and live rows', () async {
    final food = await cats.createCategory(name: 'Food', type: 'expense');
    final rent = await cats.createCategory(name: 'Rent', type: 'expense');
    Future<void> spend(int minor, String date, {String cur = 'TND', String? cat}) => tx.createTransaction(
      type: 'expense',
      amountMinor: minor,
      currencyCode: cur,
      transactionDate: date,
      categoryId: cat ?? food.id,
    );

    await spend(10000, '2026-10-01');
    await spend(2500, '2026-10-31');
    await spend(999, '2026-11-01'); // outside period
    await spend(700, '2026-10-15', cur: 'EUR'); // other currency
    await spend(50000, '2026-10-05', cat: rent.id); // other category
    final gone = await tx.createTransaction(
      type: 'expense',
      amountMinor: 4000,
      currencyCode: 'TND',
      transactionDate: '2026-10-10',
      categoryId: food.id,
    );
    await tx.deleteTransaction(gone.id);

    await budgets.createBudget(
      name: 'Food Oct',
      amountMinor: 12000,
      currencyCode: 'TND',
      periodStart: '2026-10-01',
      periodEnd: '2026-10-31',
      categoryId: food.id,
    );
    await budgets.createBudget(
      name: 'All Oct',
      amountMinor: 100000,
      currencyCode: 'TND',
      periodStart: '2026-10-01',
      periodEnd: '2026-10-31',
    );

    final list = await budgets.watchBudgets(onDate: '2026-10-20').first;
    final byName = {for (final b in list) b.budget.name: b};
    expect(byName['Food Oct']!.spentMinor, 12500);
    expect(byName['Food Oct']!.isOver, isTrue);
    expect(byName['All Oct']!.spentMinor, 62500);
    expect(await budgets.watchBudgets(onDate: '2026-12-01').first, isEmpty);
  });

  test('rejects end before start and income categories', () async {
    final salary = await cats.createCategory(name: 'Salary', type: 'income');
    expect(
      () => budgets.createBudget(
        name: 'x',
        amountMinor: 1,
        currencyCode: 'TND',
        periodStart: '2026-10-02',
        periodEnd: '2026-10-01',
      ),
      throwsA(isA<ValidationException>()),
    );
    expect(
      () => budgets.createBudget(
        name: 'x',
        amountMinor: 1,
        currencyCode: 'TND',
        periodStart: '2026-10-01',
        periodEnd: '2026-10-31',
        categoryId: salary.id,
      ),
      throwsA(isA<ValidationException>()),
    );
  });
}

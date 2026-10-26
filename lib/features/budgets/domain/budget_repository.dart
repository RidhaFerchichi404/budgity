import '../../../database/app_database.dart';

export '../../../database/app_database.dart' show Budget;

class BudgetProgress {
  const BudgetProgress(this.budget, this.spentMinor);

  final Budget budget;

  /// Expenses in the budget's currency, period and (if set) category.
  final int spentMinor;

  int get remainingMinor => budget.amountMinor - spentMinor;
  bool get isOver => spentMinor > budget.amountMinor;
  double get ratio => budget.amountMinor == 0 ? 0 : spentMinor / budget.amountMinor;
}

abstract interface class BudgetRepository {
  /// Budgets whose period contains [onDate] ('yyyy-MM-dd'), or all if null.
  Stream<List<BudgetProgress>> watchBudgets({String? onDate});

  Future<Budget> createBudget({
    required String name,
    required int amountMinor,
    required String currencyCode,
    required String periodStart,
    required String periodEnd,
    String? categoryId,
  });

  Future<void> updateBudget(Budget budget);

  Future<void> deleteBudget(String id);
}

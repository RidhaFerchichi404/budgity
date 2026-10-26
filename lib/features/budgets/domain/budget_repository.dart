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

  /// Days left including [today], or null when [today] is outside the period.
  int? daysLeft(DateTime today) {
    final d = _day(today);
    final start = _date(budget.periodStart), end = _date(budget.periodEnd);
    if (d.isBefore(start) || d.isAfter(end)) return null;
    return end.difference(d).inDays + 1;
  }

  /// Spend at the period's end if the current daily pace holds; null outside the period.
  int? projectedMinor(DateTime today) {
    final left = daysLeft(today);
    if (left == null) return null;
    final total = _date(budget.periodEnd).difference(_date(budget.periodStart)).inDays + 1;
    return (spentMinor * total / (total - left + 1)).round();
  }

  // UTC midnights, so a DST change can't make a day 23 hours long
  static DateTime _day(DateTime t) => DateTime.utc(t.year, t.month, t.day);
  static DateTime _date(String iso) => DateTime.parse('${iso}T00:00:00Z');
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

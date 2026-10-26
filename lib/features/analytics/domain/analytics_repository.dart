/// Income and expense of one month ('yyyy-MM') in one currency.
class MonthFlow {
  const MonthFlow(this.month, {this.incomeMinor = 0, this.expenseMinor = 0});

  final String month;
  final int incomeMinor;
  final int expenseMinor;

  int get netMinor => incomeMinor - expenseMinor;
}

/// Spending in one category (null = uncategorized) this month and the month before.
class CategorySpend {
  const CategorySpend(this.categoryId, {required this.currentMinor, required this.previousMinor});

  final String? categoryId;
  final int currentMinor;
  final int previousMinor;

  /// Rounded % change vs. the previous month; null when there was nothing to compare with.
  int? get changePercent => previousMinor == 0 ? null : ((currentMinor - previousMinor) * 100 / previousMinor).round();
}

/// Read-only aggregates over one workspace, always for a single currency (money never mixes).
abstract interface class AnalyticsRepository {
  /// [months] consecutive months ending at [lastMonth], oldest first; months without data are zero.
  Stream<List<MonthFlow>> watchMonthlyFlow({required String currency, required String lastMonth, int months = 6});

  /// Categories with spending in [month], largest first. The previous month counts only
  /// up to [previousUntil] ('yyyy-MM-dd') when given, so a month in progress compares like for like.
  Stream<List<CategorySpend>> watchCategorySpend({
    required String currency,
    required String month,
    String? previousUntil,
  });
}

String monthKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

/// [month] shifted by [delta] months ('2026-01' + -1 = '2025-12').
String addMonths(String month, int delta) {
  final y = int.parse(month.substring(0, 4)), m = int.parse(month.substring(5, 7));
  return monthKey(DateTime(y, m + delta));
}

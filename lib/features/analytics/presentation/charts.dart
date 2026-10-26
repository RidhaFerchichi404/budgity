import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/money/money.dart';
import '../../../shared/widgets/common.dart';
import '../../categories/domain/category_repository.dart';
import '../domain/analytics_repository.dart';

// Plain-widget charts. Specs follow the dataviz rules: bars <= 24px with a 4px rounded
// data end and a square baseline, hairline solid gridlines, a legend for two series,
// values in text colors (never the series color), and every value reachable as text.

String monthLabel(String month, {bool long = false}) =>
    (long ? DateFormat.yMMMM() : DateFormat.MMM()).format(DateTime.parse('$month-01'));

/// Axis value in major units, compact from 1,000 up: 0 / 500 / 1.5K / 2M.
String compactAmount(int minor, String currency) {
  final major = minor / math.pow(10, Money.exponentOf(currency));
  return NumberFormat.compact().format(major);
}

/// Smallest 1/2/5 × 10^k at or above [minor], so gridlines land on round values.
int niceCeiling(int minor) {
  if (minor <= 0) return 0;
  final p = math.pow(10, (math.log(minor) / math.ln10).floor()).toInt();
  final f = minor / p;
  return (f <= 1
          ? 1
          : f <= 2
          ? 2
          : f <= 5
          ? 5
          : 10) *
      p;
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.color, this.label);

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
      ),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

/// Income and spending per month as paired columns. Tapping a month selects it.
class MonthlyFlowChart extends StatelessWidget {
  const MonthlyFlowChart({
    super.key,
    required this.flows,
    required this.currency,
    required this.selected,
    required this.onSelect,
  });

  final List<MonthFlow> flows;
  final String currency;
  final String selected;
  final ValueChanged<String> onSelect;

  static const _plotHeight = 150.0;
  static const _barWidth = 12.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final finance = context.finance;
    final top = niceCeiling(flows.fold(0, (m, f) => math.max(m, math.max(f.incomeMinor, f.expenseMinor))));
    final axisStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final grid = Container(height: 1, color: theme.colorScheme.outline);

    Widget bar(int minor, Color color) => Container(
      width: _barWidth,
      height: top == 0 ? 0 : _plotHeight * minor / top,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Wrap(
            spacing: 16,
            children: [_Swatch(finance.chartIncome, 'Income'), _Swatch(finance.chartExpense, 'Spending')],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: SizedBox(
                width: 44,
                height: _plotHeight,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final v in [top, top ~/ 2, 0])
                      Transform.translate(
                        offset: Offset(0, v == top ? -7 : (v == 0 ? 7 : 0)),
                        child: Text(compactAmount(v, currency), style: axisStyle),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                children: [
                  SizedBox(
                    height: _plotHeight,
                    child: Stack(
                      children: [
                        Positioned.fill(child: Column(children: [grid, const Spacer(), grid, const Spacer(), grid])),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final f in flows)
                              Expanded(
                                child: Semantics(
                                  button: true,
                                  selected: f.month == selected,
                                  label:
                                      '${monthLabel(f.month, long: true)}: income ${Money(f.incomeMinor, currency).format()}, '
                                      'spending ${Money(f.expenseMinor, currency).format()}',
                                  excludeSemantics: true,
                                  child: InkWell(
                                    onTap: () => onSelect(f.month),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Ink(
                                      decoration: BoxDecoration(
                                        color: f.month == selected
                                            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7)
                                            : null,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          bar(f.incomeMinor, finance.chartIncome),
                                          const SizedBox(width: 2), // surface gap between touching bars
                                          bar(f.expenseMinor, finance.chartExpense),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  ExcludeSemantics(
                    child: Row(
                      children: [
                        for (final f in flows)
                          Expanded(
                            child: Text(
                              monthLabel(f.month),
                              textAlign: TextAlign.center,
                              style: f.month == selected
                                  ? theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)
                                  : theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Spending per category, largest first, each with its change vs. the previous month.
class CategorySpendBars extends StatelessWidget {
  const CategorySpendBars({
    super.key,
    required this.rows,
    required this.categories,
    required this.currency,
    required this.previousMonth,
  });

  final List<CategorySpend> rows;
  final Map<String, Category> categories;
  final String currency;
  final String previousMonth;

  @override
  Widget build(BuildContext context) {
    final max = rows.isEmpty ? 0 : rows.first.currentMinor;
    return Column(
      children: [
        for (final (i, r) in rows.indexed) ...[
          if (i > 0) const SizedBox(height: 14),
          _CategoryRow(
            spend: r,
            category: categories[r.categoryId],
            fraction: max == 0 ? 0 : r.currentMinor / max,
            currency: currency,
            previousMonth: previousMonth,
          ),
        ],
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.spend,
    required this.category,
    required this.fraction,
    required this.currency,
    required this.previousMonth,
  });

  final CategorySpend spend;
  final Category? category;
  final double fraction;
  final String currency;
  final String previousMonth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final finance = context.finance;
    final name = category?.name ?? 'Uncategorized';
    final amount = Money(spend.currentMinor, currency).format();
    final change = spend.changePercent;
    final prev = monthLabel(previousMonth);
    // Status in words and an arrow, never color alone. More spending is the cautionary direction.
    final (IconData? icon, Color color, String text, String spoken) = switch (change) {
      null => (null, theme.colorScheme.onSurfaceVariant, 'None in $prev', 'nothing spent in $prev'),
      0 => (Icons.trending_flat, theme.colorScheme.onSurfaceVariant, 'Same as $prev', 'same as $prev'),
      > 0 => (Icons.trending_up, finance.warning, '$change% more than $prev', 'up $change percent from $prev'),
      _ => (Icons.trending_down, finance.income, '${-change}% less than $prev', 'down ${-change} percent from $prev'),
    };

    return Semantics(
      label: '$name, $amount, $spoken',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CategoryBadge(iconKey: category?.iconKey),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(name, style: theme.textTheme.bodyMedium, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      amount,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                LayoutBuilder(
                  builder: (_, c) => Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: math.max(4, c.maxWidth * fraction),
                      height: 10,
                      decoration: BoxDecoration(
                        color: finance.chartExpense,
                        borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
                    Flexible(
                      child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: color)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

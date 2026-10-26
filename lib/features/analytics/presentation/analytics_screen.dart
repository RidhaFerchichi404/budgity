import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../shared/widgets/common.dart';
import '../../categories/presentation/categories_screen.dart' show categoriesByIdProvider;
import '../domain/analytics_repository.dart';
import 'charts.dart';

/// The chart shows six months ending at [windowEnd]; [selected] is the month in focus.
typedef AnalyticsView = ({String windowEnd, String selected});

final analyticsViewProvider = NotifierProvider<AnalyticsViewNotifier, AnalyticsView>(AnalyticsViewNotifier.new);

class AnalyticsViewNotifier extends Notifier<AnalyticsView> {
  static const months = 6;

  String get _current => monthKey(ref.read(todayProvider));

  @override
  AnalyticsView build() {
    final now = monthKey(ref.watch(todayProvider));
    return (windowEnd: now, selected: now);
  }

  /// Picks a month inside the visible window (tapping a column).
  void select(String month) => state = (windowEnd: state.windowEnd, selected: month);

  /// Moves the focus one month back or forward, scrolling the window only when needed.
  void step(int delta) {
    final next = addMonths(state.selected, delta);
    if (next.compareTo(_current) > 0) return;
    var end = state.windowEnd;
    if (next.compareTo(end) > 0) end = next;
    if (next.compareTo(addMonths(end, -(months - 1))) < 0) end = addMonths(next, months - 1);
    state = (windowEnd: end, selected: next);
  }
}

/// One month more than the chart shows, so the oldest visible month still has a "before".
final _flowProvider = StreamProvider<List<MonthFlow>>((ref) {
  final view = ref.watch(analyticsViewProvider);
  return ref
      .watch(analyticsRepositoryProvider)
      .watchMonthlyFlow(
        currency: ref.watch(currencyProvider),
        lastMonth: view.windowEnd,
        months: AnalyticsViewNotifier.months + 1,
      );
});

final _categoryProvider = StreamProvider<List<CategorySpend>>((ref) {
  final month = ref.watch(analyticsViewProvider.select((v) => v.selected));
  return ref.watch(analyticsRepositoryProvider).watchCategorySpend(currency: ref.watch(currencyProvider), month: month);
});

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final view = ref.watch(analyticsViewProvider);
    final notifier = ref.read(analyticsViewProvider.notifier);
    final flows = ref.watch(_flowProvider).value;
    final spend = ref.watch(_categoryProvider).value;
    final cats = ref.watch(categoriesByIdProvider).value ?? const {};
    final currency = ref.watch(currencyProvider);
    final atCurrent = view.selected == monthKey(ref.watch(todayProvider));

    final selected = flows?.where((f) => f.month == view.selected).firstOrNull;
    final before = flows?.where((f) => f.month == addMonths(view.selected, -1)).firstOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Trends')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous month',
                    onPressed: () => notifier.step(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      monthLabel(view.selected, long: true),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next month',
                    onPressed: atCurrent ? null : () => notifier.step(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Income vs. spending', style: theme.textTheme.titleSmall),
                      Text('Last ${AnalyticsViewNotifier.months} months, $currency', style: theme.textTheme.bodySmall),
                      const SizedBox(height: 16),
                      if (flows != null)
                        MonthlyFlowChart(
                          flows: flows.sublist(1),
                          currency: currency,
                          selected: view.selected,
                          onSelect: notifier.select,
                        ),
                      if (selected != null) ...[
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 12),
                        _MonthSummary(flow: selected, previous: before, currency: currency),
                      ],
                    ],
                  ),
                ),
              ),
              const SectionHeader('Spending by category'),
              if (spend == null)
                const SizedBox.shrink()
              else if (spend.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('No spending in ${monthLabel(view.selected, long: true)} yet.'),
                  ),
                )
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: CategorySpendBars(
                      rows: spend,
                      categories: cats,
                      currency: currency,
                      previousMonth: addMonths(view.selected, -1),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The selected month's numbers in text: the chart's table view, plus the month-over-month change.
class _MonthSummary extends StatelessWidget {
  const _MonthSummary({required this.flow, required this.previous, required this.currency});

  final MonthFlow flow;
  final MonthFlow? previous;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prev = previous?.expenseMinor ?? 0;
    final change = prev == 0 ? null : ((flow.expenseMinor - prev) * 100 / prev).round();
    final prevName = previous == null ? '' : monthLabel(previous!.month);

    Widget stat(String label, Widget value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        value,
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 28,
          runSpacing: 12,
          children: [
            stat(
              'Income',
              AmountText(
                minor: flow.incomeMinor,
                currency: currency,
                type: 'income',
                style: theme.textTheme.titleMedium,
              ),
            ),
            stat(
              'Spent',
              AmountText(
                minor: flow.expenseMinor,
                currency: currency,
                type: 'expense',
                style: theme.textTheme.titleMedium,
              ),
            ),
            stat(
              'Net',
              AmountText(
                minor: flow.netMinor.abs(),
                currency: currency,
                type: flow.netMinor >= 0 ? 'income' : 'expense',
                style: theme.textTheme.titleMedium,
              ),
            ),
          ],
        ),
        if (change != null) ...[
          const SizedBox(height: 12),
          Text(
            change == 0
                ? 'Spending was the same as in $prevName.'
                : 'Spending was ${change.abs()}% ${change > 0 ? 'higher' : 'lower'} than in $prevName.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

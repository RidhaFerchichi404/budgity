import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/errors/validation_exception.dart';
import '../../../core/money/money.dart';
import '../../../shared/widgets/common.dart';
import '../../categories/presentation/categories_screen.dart' show categoriesByIdProvider;
import '../domain/budget_repository.dart';

final _allBudgetsProvider = StreamProvider<List<BudgetProgress>>(
  (ref) => ref.watch(budgetRepositoryProvider).watchBudgets(),
);

class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgets = ref.watch(_allBudgetsProvider).value ?? const [];
    final cats = ref.watch(categoriesByIdProvider).value ?? const {};
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-budget',
        onPressed: () => _showBudgetDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Budget'),
      ),
      body: budgets.isEmpty
          ? const EmptyState(
              icon: Icons.pie_chart_outline,
              message: 'No budgets yet. Set a spending limit to track it here.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
              children: [
                for (final b in budgets)
                  BudgetProgressTile(
                    progress: b,
                    categoryName: cats[b.budget.categoryId]?.name,
                    onTap: () => _showBudgetDialog(context, ref, existing: b.budget),
                    today: ref.watch(todayProvider),
                  ),
              ],
            ),
    );
  }
}

/// "12 days left · on pace for 4 650.000 TND", flagged in words when the pace overshoots.
class _PaceLine extends StatelessWidget {
  const _PaceLine({required this.daysLeft, required this.projected, required this.overLimit});

  final int daysLeft;
  final Money projected;
  final bool overLimit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = overLimit ? context.finance.warning : theme.colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(overLimit ? Icons.trending_up : Icons.schedule, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${daysLeft == 1 ? 'Last day' : '$daysLeft days left'} · '
            '${overLimit ? 'on pace to go over, ' : 'on pace for '}${projected.format()}',
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class BudgetProgressTile extends StatelessWidget {
  const BudgetProgressTile({super.key, required this.progress, this.categoryName, this.onTap, this.today});

  final BudgetProgress progress;
  final String? categoryName;
  final VoidCallback? onTap;

  /// When set and inside the period, adds days left and the projected spend at this pace.
  final DateTime? today;

  @override
  Widget build(BuildContext context) {
    final b = progress.budget;
    final theme = Theme.of(context);
    final finance = context.finance;
    final percent = (progress.ratio * 100).round();
    final (color, status) = progress.isOver
        ? (finance.over, 'Over budget')
        : progress.ratio >= 0.8
        ? (finance.warning, 'Close to limit')
        : (theme.colorScheme.primary, 'On track');
    final left = today == null ? null : progress.daysLeft(today!);
    final projected = today == null ? null : progress.projectedMinor(today!);
    // Only worth saying while the period runs and the limit isn't already passed.
    final pace = left == null || projected == null || progress.isOver
        ? null
        : _PaceLine(daysLeft: left, projected: Money(projected, b.currencyCode), overLimit: projected > b.amountMinor);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(b.name, style: theme.textTheme.titleSmall),
                        Text(
                          '${categoryName ?? 'All expenses'} · ${prettyDate(b.periodStart)} – ${prettyDate(b.periodEnd)}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  // Status in words, not only color.
                  Text('$percent%', style: theme.textTheme.titleMedium?.copyWith(color: color)),
                ],
              ),
              const SizedBox(height: 12),
              Semantics(
                label: '$percent percent of budget used, $status',
                child: LinearProgressIndicator(value: progress.ratio.clamp(0, 1), color: color, minHeight: 8),
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text(
                    '${Money(progress.spentMinor, b.currencyCode).format()} of ${Money(b.amountMinor, b.currencyCode).format()}',
                    style: theme.textTheme.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                  Text(
                    progress.isOver
                        ? '$status · ${Money(-progress.remainingMinor, b.currencyCode).format()} over'
                        : '$status · ${Money(progress.remainingMinor, b.currencyCode).format()} left',
                    style: theme.textTheme.bodyMedium?.copyWith(color: color, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              if (pace != null) ...[const SizedBox(height: 6), pace],
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showBudgetDialog(BuildContext context, WidgetRef ref, {Budget? existing}) {
  final (monthStart, monthEnd) = monthRange(DateTime.now());
  final name = TextEditingController(text: existing?.name);
  String currency = existing?.currencyCode ?? ref.read(currencyProvider);
  final amount = TextEditingController(
    text: existing == null ? '' : Money(existing.amountMinor, existing.currencyCode).toDecimalString(),
  );
  String? categoryId = existing?.categoryId;
  var start = existing?.periodStart ?? monthStart;
  var end = existing?.periodEnd ?? monthEnd;
  final formKey = GlobalKey<FormState>();
  final cats = (ref.read(categoriesByIdProvider).value ?? const {}).values
      .where((c) => c.type == 'expense' && (c.deletedAt == null || c.id == categoryId))
      .toList();

  return showDialog<void>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, setState) => AlertDialog(
        title: Text(existing == null ? 'New budget' : 'Edit budget'),
        content: SizedBox(
          width: 400,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: amount,
                        decoration: const InputDecoration(labelText: 'Limit'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) => (Money.tryParse(v ?? '', currency)?.minor ?? 0) > 0 ? null : 'Invalid amount',
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 110,
                      child: DropdownButtonFormField<String>(
                        initialValue: currency,
                        decoration: const InputDecoration(labelText: 'Currency'),
                        items: [for (final c in Money.supportedCurrencies) DropdownMenuItem(value: c, child: Text(c))],
                        onChanged: (v) => setState(() => currency = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: categoryId,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All expenses')),
                    for (final c in cats) DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (v) => setState(() => categoryId = v),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.date_range),
                  title: Text('${prettyDate(start)} – ${prettyDate(end)}'),
                  trailing: const Text('Change'),
                  onTap: () async {
                    final r = await showDateRangePicker(
                      context: d,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(DateTime.now().year + 5),
                      initialDateRange: DateTimeRange(start: DateTime.parse(start), end: DateTime.parse(end)),
                    );
                    if (r != null) setState(() => (start, end) = (isoDate(r.start), isoDate(r.end)));
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (existing != null)
            TextButton(
              onPressed: () async {
                await ref.read(budgetRepositoryProvider).deleteBudget(existing.id);
                if (d.mounted) Navigator.pop(d);
              },
              child: const Text('Delete'),
            ),
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final repo = ref.read(budgetRepositoryProvider);
              final minor = Money.tryParse(amount.text, currency)!.minor;
              try {
                if (existing == null) {
                  await repo.createBudget(
                    name: name.text,
                    amountMinor: minor,
                    currencyCode: currency,
                    periodStart: start,
                    periodEnd: end,
                    categoryId: categoryId,
                  );
                } else {
                  await repo.updateBudget(
                    existing.copyWith(
                      name: name.text,
                      amountMinor: minor,
                      currencyCode: currency,
                      periodStart: start,
                      periodEnd: end,
                      categoryId: Value(categoryId),
                    ),
                  );
                }
                if (d.mounted) Navigator.pop(d);
              } on ValidationException catch (e) {
                if (d.mounted) showError(d, e);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  ).whenComplete(() {
    name.dispose();
    amount.dispose();
  });
}

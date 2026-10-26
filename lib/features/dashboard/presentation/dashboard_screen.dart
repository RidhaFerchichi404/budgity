import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/money/money.dart';
import '../../../shared/widgets/common.dart';
import '../../budgets/domain/budget_repository.dart';
import '../../budgets/presentation/budgets_screen.dart' show BudgetProgressTile;
import '../../categories/presentation/categories_screen.dart' show categoriesByIdProvider;
import '../../transactions/domain/transaction_repository.dart';
import '../../transactions/presentation/transactions_screen.dart' show TransactionTile;

final _allTimeProvider = StreamProvider<MoneySummary>((ref) => ref.watch(transactionRepositoryProvider).watchSummary());

final _thisMonthProvider = StreamProvider<MoneySummary>((ref) {
  final (from, to) = monthRange(DateTime.now());
  return ref.watch(transactionRepositoryProvider).watchSummary(from: from, to: to);
});

final _recentProvider = StreamProvider<List<TransactionRow>>(
  (ref) => ref.watch(transactionRepositoryProvider).watchTransactions(const TransactionFilter(limit: 10)),
);

final _activeBudgetsProvider = StreamProvider<List<BudgetProgress>>(
  (ref) => ref.watch(budgetRepositoryProvider).watchBudgets(onDate: isoDate(DateTime.now())),
);

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allTime = ref.watch(_allTimeProvider).value;
    final month = ref.watch(_thisMonthProvider).value;
    final recent = ref.watch(_recentProvider).value ?? const [];
    final budgets = ref.watch(_activeBudgetsProvider).value ?? const [];
    final cats = ref.watch(categoriesByIdProvider).value ?? const {};
    final currency = ref.watch(currencyProvider);
    final others = {...?allTime?.currencies}..remove(currency);

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            _BalanceHero(
              currency: currency,
              balance: allTime?.net(currency) ?? 0,
              income: month?.income[currency] ?? 0,
              spent: month?.expense[currency] ?? 0,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => context.push('/analytics'),
                icon: const Icon(Icons.insights_outlined),
                label: const Text('Trends'),
              ),
            ),
            if (others.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 0,
                  children: [
                    for (final c in others)
                      _CurrencyChipCard(currency: c, balance: allTime!.net(c), spent: month?.expense[c] ?? 0),
                  ],
                ),
              ),
            SectionHeader(
              'Budgets this period',
              action: TextButton(onPressed: () => context.go('/budgets'), child: const Text('Manage')),
            ),
            if (budgets.isEmpty)
              _Hint(
                icon: Icons.flag_outlined,
                text: 'Set a monthly limit to see how your spending tracks against it.',
                action: TextButton(onPressed: () => context.go('/budgets'), child: const Text('Create a budget')),
              )
            else
              for (final b in budgets)
                BudgetProgressTile(
                  progress: b,
                  categoryName: cats[b.budget.categoryId]?.name,
                  today: ref.watch(todayProvider),
                ),
            SectionHeader(
              'Recent activity',
              action: TextButton(onPressed: () => context.go('/transactions'), child: const Text('See all')),
            ),
            if (recent.isEmpty)
              const _Hint(icon: Icons.receipt_long_outlined, text: 'No transactions yet. Add your first one with +.')
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final (i, t) in recent.indexed) ...[
                      if (i > 0) const Divider(indent: 72),
                      TransactionTile(transaction: t, category: cats[t.categoryId]),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The one number that matters most, then this month's flow beneath it.
class _BalanceHero extends StatelessWidget {
  const _BalanceHero({required this.currency, required this.balance, required this.income, required this.spent});

  final String currency;
  final int balance;
  final int income;
  final int spent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final net = income - spent;
    return Card(
      color: scheme.primaryContainer.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total balance', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: AmountText(
                minor: balance,
                currency: currency,
                style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -1),
              ),
            ),
            const SizedBox(height: 20),
            Text('This month', style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 28,
              runSpacing: 12,
              children: [
                _Flow(label: 'Income', icon: Icons.south_west, minor: income, currency: currency, type: 'income'),
                _Flow(label: 'Spent', icon: Icons.north_east, minor: spent, currency: currency, type: 'expense'),
                _Flow(
                  label: 'Net',
                  icon: Icons.drag_handle,
                  minor: net.abs(),
                  currency: currency,
                  type: net >= 0 ? 'income' : 'expense',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Flow extends StatelessWidget {
  const _Flow({
    required this.label,
    required this.icon,
    required this.minor,
    required this.currency,
    required this.type,
  });

  final String label;
  final IconData icon;
  final int minor;
  final String currency;
  final String type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(child: Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.bodySmall),
            AmountText(minor: minor, currency: currency, type: type, style: theme.textTheme.titleMedium),
          ],
        ),
      ],
    );
  }
}

class _CurrencyChipCard extends StatelessWidget {
  const _CurrencyChipCard({required this.currency, required this.balance, required this.spent});

  final String currency;
  final int balance;
  final int spent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$currency balance', style: theme.textTheme.bodySmall),
            AmountText(minor: balance, currency: currency, style: theme.textTheme.titleMedium),
            Text('Spent this month: ${Money(spent, currency).format()}', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
          ?action,
        ],
      ),
    ),
  );
}

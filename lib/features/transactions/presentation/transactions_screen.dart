import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../shared/widgets/common.dart';
import '../../categories/domain/category_repository.dart';
import '../../categories/presentation/categories_screen.dart' show categoriesByIdProvider;
import '../domain/transaction_repository.dart';

final transactionFilterProvider = NotifierProvider<_FilterNotifier, TransactionFilter>(_FilterNotifier.new);

class _FilterNotifier extends Notifier<TransactionFilter> {
  @override
  TransactionFilter build() {
    ref.watch(workspaceProvider); // a category filter from the other workspace would match nothing
    return TransactionFilter.all;
  }

  void set(TransactionFilter f) => state = f;
}

final _filteredProvider = StreamProvider<List<TransactionRow>>(
  (ref) => ref.watch(transactionRepositoryProvider).watchTransactions(ref.watch(transactionFilterProvider)),
);

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _search.text = ref.read(transactionFilterProvider).search ?? '';
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  TransactionFilter get _f => ref.read(transactionFilterProvider);

  void _update({
    String? search,
    String? type,
    String? categoryId,
    String? from,
    String? to,
    bool clearType = false,
    bool clearCategory = false,
    bool clearDates = false,
  }) {
    ref
        .read(transactionFilterProvider.notifier)
        .set(
          TransactionFilter(
            search: search ?? _f.search,
            type: clearType ? null : type ?? _f.type,
            categoryId: clearCategory ? null : categoryId ?? _f.categoryId,
            from: clearDates ? null : from ?? _f.from,
            to: clearDates ? null : to ?? _f.to,
          ),
        );
  }

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5),
      initialDateRange: _f.from == null
          ? null
          : DateTimeRange(start: DateTime.parse(_f.from!), end: DateTime.parse(_f.to!)),
    );
    if (range != null) _update(from: isoDate(range.start), to: isoDate(range.end));
  }

  @override
  Widget build(BuildContext context) {
    final f = ref.watch(transactionFilterProvider);
    final rows = ref.watch(_filteredProvider);
    final cats = ref.watch(categoriesByIdProvider).value ?? const {};
    final wide = isWide(context);

    final filters = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: wide ? 280 : double.infinity,
          child: TextField(
            controller: _search,
            focusNode: _searchFocus,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: wide ? 'Search descriptions (Ctrl+F)' : 'Search descriptions',
              isDense: true,
            ),
            onChanged: (v) => _update(search: v),
          ),
        ),
        for (final t in ['income', 'expense'])
          FilterChip(
            label: Text(t == 'income' ? 'Income' : 'Expenses'),
            selected: f.type == t,
            onSelected: (on) => on ? _update(type: t, clearCategory: true) : _update(clearType: true),
          ),
        DropdownButton<String?>(
          value: f.categoryId,
          hint: const Text('All categories'),
          onChanged: (v) => v == null ? _update(clearCategory: true) : _update(categoryId: v),
          items: [
            const DropdownMenuItem(value: null, child: Text('All categories')),
            for (final c in cats.values.where((c) => c.deletedAt == null && (f.type == null || c.type == f.type)))
              DropdownMenuItem(value: c.id, child: Text(c.name)),
          ],
        ),
        ActionChip(
          avatar: const Icon(Icons.date_range, size: 18),
          label: Text(f.from == null ? 'Any date' : '${prettyDate(f.from!)} – ${prettyDate(f.to!)}'),
          onPressed: _pickDates,
        ),
        if (f.from != null)
          IconButton(tooltip: 'Clear dates', icon: const Icon(Icons.close), onPressed: () => _update(clearDates: true)),
      ],
    );

    final list = rows.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (items) {
        if (items.isEmpty) return const EmptyState(icon: Icons.search_off, message: 'No matching transactions.');
        if (wide) return _TransactionTable(items: items, cats: cats);
        return ListView.builder(
          itemCount: items.length,
          itemBuilder: (_, i) => TransactionTile(transaction: items[i], category: cats[items[i].categoryId]),
        );
      },
    );

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.keyF, control: true): _searchFocus.requestFocus},
      child: Column(
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), child: filters),
          Expanded(child: list),
        ],
      ),
    );
  }
}

class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.transaction, this.category});

  final TransactionRow transaction;
  final Category? category;

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final catName = category == null
        ? 'Uncategorized'
        : '${category!.name}${category!.deletedAt != null ? ' (archived)' : ''}';
    return ListTile(
      leading: CategoryBadge(iconKey: category?.iconKey, income: t.type == 'income'),
      title: Text(t.description.isEmpty ? catName : t.description),
      subtitle: Text('${prettyDate(t.transactionDate)} · $catName'),
      trailing: AmountText(
        minor: t.amountMinor,
        currency: t.currencyCode,
        type: t.type,
        style: Theme.of(context).textTheme.titleSmall,
      ),
      onTap: () => context.push('/transactions/${t.id}'),
    );
  }
}

class _TransactionTable extends StatefulWidget {
  const _TransactionTable({required this.items, required this.cats});

  final List<TransactionRow> items;
  final Map<String, Category> cats;

  @override
  State<_TransactionTable> createState() => _TransactionTableState();
}

class _TransactionTableState extends State<_TransactionTable> {
  int _sortColumn = 0;
  bool _ascending = false;

  @override
  Widget build(BuildContext context) {
    final rows = [...widget.items];
    int cmp(TransactionRow a, TransactionRow b) => switch (_sortColumn) {
      0 => a.transactionDate.compareTo(b.transactionDate),
      1 => a.description.compareTo(b.description),
      2 => (widget.cats[a.categoryId]?.name ?? '').compareTo(widget.cats[b.categoryId]?.name ?? ''),
      _ => (a.type == 'income' ? a.amountMinor : -a.amountMinor).compareTo(
        b.type == 'income' ? b.amountMinor : -b.amountMinor,
      ),
    };
    rows.sort((a, b) => _ascending ? cmp(a, b) : cmp(b, a));

    void sort(int i, bool asc) => setState(() {
      _sortColumn = i;
      _ascending = asc;
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SizedBox(
        width: double.infinity,
        child: DataTable(
          sortColumnIndex: _sortColumn,
          sortAscending: _ascending,
          showCheckboxColumn: false,
          columns: [
            DataColumn(label: const Text('Date'), onSort: sort),
            DataColumn(label: const Text('Description'), onSort: sort),
            DataColumn(label: const Text('Category'), onSort: sort),
            DataColumn(label: const Text('Amount'), numeric: true, onSort: sort),
          ],
          rows: [
            for (final t in rows)
              DataRow(
                onSelectChanged: (_) => context.push('/transactions/${t.id}'),
                cells: [
                  DataCell(Text(prettyDate(t.transactionDate))),
                  DataCell(Text(t.description)),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(categoryIcon(widget.cats[t.categoryId]?.iconKey), size: 18),
                        const SizedBox(width: 6),
                        Text(widget.cats[t.categoryId]?.name ?? 'Uncategorized'),
                      ],
                    ),
                  ),
                  DataCell(AmountText(minor: t.amountMinor, currency: t.currencyCode, type: t.type)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

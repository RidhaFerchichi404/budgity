import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/money/money.dart';
import '../../../shared/widgets/common.dart';
import '../../categories/presentation/categories_screen.dart' show categoriesByIdProvider;
import '../domain/transaction_repository.dart';

class TransactionFormScreen extends ConsumerStatefulWidget {
  const TransactionFormScreen({super.key, this.transactionId});

  /// null = create.
  final String? transactionId;

  @override
  ConsumerState<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends ConsumerState<TransactionFormScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  TransactionRow? _existing;
  String _type = 'expense';
  String? _currency;
  String? _categoryId;
  DateTime _date = DateTime.now();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.transactionId;
    if (id != null) {
      final t = await ref.read(transactionRepositoryProvider).getTransactionById(id);
      if (t != null) {
        _existing = t;
        _type = t.type;
        _currency = t.currencyCode;
        _categoryId = t.categoryId;
        _date = DateTime.parse(t.transactionDate);
        _amount.text = Money(t.amountMinor, t.currencyCode).toDecimalString();
        _description.text = t.description;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final String currency = _currency ?? ref.read(currencyProvider);
    final money = Money.tryParse(_amount.text, currency)!;
    final repo = ref.read(transactionRepositoryProvider);
    setState(() => _saving = true);
    try {
      if (_existing == null) {
        await repo.createTransaction(
          type: _type,
          amountMinor: money.minor,
          currencyCode: currency,
          transactionDate: isoDate(_date),
          categoryId: _categoryId,
          description: _description.text,
        );
      } else {
        await repo.updateTransaction(
          _existing!.copyWith(
            type: _type,
            amountMinor: money.minor,
            currencyCode: currency,
            transactionDate: isoDate(_date),
            categoryId: Value(_categoryId),
            description: _description.text,
          ),
        );
      }
      if (mounted) context.pop();
    } on ValidationException catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: const Text('It will be removed from all your devices.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(transactionRepositoryProvider).deleteTransaction(_existing!.id);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final String currency = _currency ?? ref.watch(currencyProvider);
    final cats = (ref.watch(categoriesByIdProvider).value ?? const {}).values
        .where((c) => c.type == _type && (c.deletedAt == null || c.id == _categoryId))
        .toList();
    if (_categoryId != null && !cats.any((c) => c.id == _categoryId)) _categoryId = null;

    return Scaffold(
      appBar: AppBar(
        title: Text(_existing == null ? 'New transaction' : 'Edit transaction'),
        actions: [
          if (_existing != null)
            IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Form(
                  key: _form,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'expense', label: Text('Expense'), icon: Icon(Icons.remove)),
                          ButtonSegment(value: 'income', label: Text('Income'), icon: Icon(Icons.add)),
                        ],
                        selected: {_type},
                        onSelectionChanged: (s) => setState(() {
                          _type = s.first;
                          _categoryId = null;
                        }),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _amount,
                              autofocus: _existing == null,
                              decoration: const InputDecoration(labelText: 'Amount'),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              validator: (v) {
                                final m = Money.tryParse(v ?? '', currency);
                                if (m == null) return 'Up to ${Money.exponentOf(currency)} decimals';
                                return m.minor > 0 ? null : 'Must be greater than zero';
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 110,
                            child: DropdownButtonFormField<String>(
                              initialValue: currency,
                              decoration: const InputDecoration(labelText: 'Currency'),
                              items: [
                                for (final c in Money.supportedCurrencies) DropdownMenuItem(value: c, child: Text(c)),
                              ],
                              onChanged: (v) => setState(() => _currency = v),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String?>(
                        initialValue: _categoryId,
                        decoration: const InputDecoration(labelText: 'Category'),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('Uncategorized')),
                          for (final c in cats)
                            DropdownMenuItem(
                              value: c.id,
                              child: Row(
                                children: [
                                  Icon(categoryIcon(c.iconKey), size: 20),
                                  const SizedBox(width: 8),
                                  Text(c.deletedAt == null ? c.name : '${c.name} (archived)'),
                                ],
                              ),
                            ),
                        ],
                        onChanged: (v) => setState(() => _categoryId = v),
                      ),
                      const SizedBox(height: 16),
                      InputDecorator(
                        decoration: const InputDecoration(labelText: 'Date'),
                        child: InkWell(
                          onTap: () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: _date,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(DateTime.now().year + 5),
                            );
                            if (d != null) setState(() => _date = d);
                          },
                          child: Row(
                            children: [
                              Expanded(child: Text(prettyDate(isoDate(_date)))),
                              const Icon(Icons.calendar_today, size: 18),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _description,
                        decoration: const InputDecoration(labelText: 'Description (optional)'),
                        maxLength: 500,
                        maxLines: 2,
                        minLines: 1,
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.check),
                        label: const Text('Save'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

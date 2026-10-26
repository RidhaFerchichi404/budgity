import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/errors/validation_exception.dart';
import '../../../shared/widgets/common.dart';
import '../domain/category_repository.dart';

/// All categories including archived ones, so old transactions keep their label.
final categoriesByIdProvider = StreamProvider<Map<String, Category>>(
  (ref) => ref
      .watch(categoryRepositoryProvider)
      .watchCategories(includeArchived: true)
      .map((list) => {for (final c in list) c.id: c}),
);

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = (ref.watch(categoriesByIdProvider).value ?? const {}).values.where((c) => c.deletedAt == null).toList();
    final theme = Theme.of(context);

    Widget section(String type, String title) {
      final items = all.where((c) => c.type == type).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
            child: Row(
              children: [
                Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
                TextButton.icon(
                  onPressed: () => showCategoryDialog(context, ref, type: type),
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
            ),
          ),
          for (final c in items)
            ListTile(
              leading: CategoryBadge(iconKey: c.iconKey, income: c.type == 'income'),
              title: Text(c.name),
              onTap: () => showCategoryDialog(context, ref, type: type, existing: c),
              trailing: IconButton(
                tooltip: 'Archive ${c.name}',
                icon: const Icon(Icons.archive_outlined),
                onPressed: () => _archive(context, ref, c),
              ),
            ),
        ],
      );
    }

    return ListView(children: [section('expense', 'Expense categories'), section('income', 'Income categories')]);
  }

  Future<void> _archive(BuildContext context, WidgetRef ref, Category c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Archive “${c.name}”?'),
        content: const Text('Existing transactions keep this category. You can no longer pick it for new ones.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Archive')),
        ],
      ),
    );
    if (ok == true) await ref.read(categoryRepositoryProvider).archiveCategory(c.id);
  }
}

Future<void> showCategoryDialog(BuildContext context, WidgetRef ref, {required String type, Category? existing}) {
  final name = TextEditingController(text: existing?.name);
  var icon = existing?.iconKey ?? 'tag';
  return showDialog<void>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, setState) => AlertDialog(
        title: Text(existing == null ? 'New ${type == 'income' ? 'income' : 'expense'} category' : 'Edit category'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                maxLength: 50,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final k in categoryIconKeys)
                    IconButton(
                      tooltip: k,
                      isSelected: k == icon,
                      style: IconButton.styleFrom(
                        backgroundColor: k == icon ? Theme.of(d).colorScheme.primaryContainer : null,
                      ),
                      icon: Icon(categoryIcon(k)),
                      onPressed: () => setState(() => icon = k),
                    ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final repo = ref.read(categoryRepositoryProvider);
              try {
                if (existing == null) {
                  await repo.createCategory(name: name.text, type: type, iconKey: icon);
                } else {
                  await repo.updateCategory(existing.copyWith(name: name.text, iconKey: icon));
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
  ).whenComplete(name.dispose);
}

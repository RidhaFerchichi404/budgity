import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../features/synchronization/presentation/sync_status_chip.dart';
import 'budgity_mark.dart';
import 'common.dart';

class _Dest {
  const _Dest(this.path, this.label, this.icon, this.selectedIcon);

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _dests = [
  _Dest('/', 'Dashboard', Icons.space_dashboard_outlined, Icons.space_dashboard),
  _Dest('/transactions', 'Activity', Icons.receipt_long_outlined, Icons.receipt_long),
  _Dest('/budgets', 'Budgets', Icons.pie_chart_outline, Icons.pie_chart),
  _Dest('/categories', 'Categories', Icons.category_outlined, Icons.category),
  _Dest('/settings', 'Settings', Icons.settings_outlined, Icons.settings),
];

/// Signed-in frame: bottom navigation on phones, a rail on desktop.
/// Starting the sync scheduler here ties it to the signed-in lifetime.
class AdaptiveShell extends ConsumerWidget {
  const AdaptiveShell({super.key, required this.child, required this.location});

  final Widget child;
  final String location;

  int get _index {
    final i = _dests.lastIndexWhere((d) => d.path == '/' ? location == '/' : location.startsWith(d.path));
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(signingOutProvider)) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final ownerCheck = ref.watch(dbOwnerCheckProvider);
    if (ownerCheck.isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    ref.watch(syncSchedulerProvider);

    final wide = isWide(context);
    void go(int i) => context.go(_dests[i].path);

    final body = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () => context.push('/transactions/new'),
      },
      child: Focus(autofocus: true, child: child),
    );

    return Scaffold(
      appBar: AppBar(
        // Desktop shows the brand above the rail; phones keep the full width for the title.
        leading: wide ? const Center(child: BudgityMark(size: 32)) : null,
        leadingWidth: wide ? 80 : null,
        title: Text(_dests[_index].label),
        actions: [
          if (ref.watch(profileProvider).value?.freelancerEnabled ?? false) const _WorkspaceMenu(),
          const SyncStatusChip(),
          const SizedBox(width: 8),
        ],
      ),
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: go,
                  labelType: NavigationRailLabelType.all,
                  leading: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: FloatingActionButton(
                      tooltip: 'Add transaction (Ctrl+N)',
                      onPressed: () => context.push('/transactions/new'),
                      child: const Icon(Icons.add),
                    ),
                  ),
                  destinations: [
                    for (final d in _dests)
                      NavigationRailDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.selectedIcon),
                        label: Text(d.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            )
          : body,
      floatingActionButton: wide || _index > 1
          ? null
          : FloatingActionButton(
              tooltip: 'Add transaction',
              onPressed: () => context.push('/transactions/new'),
              child: const Icon(Icons.add),
            ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: go,
              destinations: [
                for (final d in _dests)
                  NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label),
              ],
            ),
    );
  }
}

/// Switches every screen between the Personal and Freelancer workspaces.
class _WorkspaceMenu extends ConsumerWidget {
  const _WorkspaceMenu();

  static const _labels = {'personal': 'Personal', 'freelancer': 'Freelancer'};
  static const _icons = {'personal': Icons.person_outline, 'freelancer': Icons.work_outline};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(workspaceProvider);
    return PopupMenuButton<String>(
      tooltip: 'Switch workspace',
      initialValue: current,
      onSelected: ref.read(selectedWorkspaceProvider.notifier).select,
      itemBuilder: (_) => [
        for (final w in _labels.keys)
          PopupMenuItem(
            value: w,
            child: ListTile(leading: Icon(_icons[w]), title: Text(_labels[w]!), contentPadding: EdgeInsets.zero),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icons[current], size: 20),
            if (isWide(context)) ...[const SizedBox(width: 6), Text(_labels[current]!)],
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}

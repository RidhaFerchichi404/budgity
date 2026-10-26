import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/errors/validation_exception.dart';
import '../../core/money/money.dart';
import '../../shared/widgets/common.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    final email = ref.watch(supabaseProvider).auth.currentUser?.email ?? '';
    final currency = ref.watch(currencyProvider);

    Future<void> save({String? name, String? cur, bool? freelancer}) async {
      try {
        await ref
            .read(profileRepositoryProvider)
            .update(
              displayName: name ?? profile?.displayName ?? '',
              currencyCode: cur ?? currency,
              freelancerEnabled: freelancer,
            );
      } on ValidationException catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: Text(profile?.displayName.isNotEmpty == true ? profile!.displayName : 'Set your name'),
          subtitle: Text(email),
          onTap: () async {
            final c = TextEditingController(text: profile?.displayName);
            final name = await showDialog<String>(
              context: context,
              builder: (d) => AlertDialog(
                title: const Text('Display name'),
                content: TextField(controller: c, autofocus: true, maxLength: 100),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
                  FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Save')),
                ],
              ),
            );
            c.dispose();
            if (name != null) await save(name: name);
          },
        ),
        ListTile(
          leading: const Icon(Icons.payments_outlined),
          title: const Text('Default currency'),
          trailing: DropdownButton<String>(
            value: currency,
            items: [for (final c in Money.supportedCurrencies) DropdownMenuItem(value: c, child: Text(c))],
            onChanged: (v) => save(cur: v),
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.work_outline),
          title: const Text('Freelancer workspace'),
          subtitle: const Text('Business income and expenses, kept apart from your personal money'),
          value: profile?.freelancerEnabled ?? false,
          onChanged: profile == null ? null : (v) => save(freelancer: v),
        ),
        ListTile(
          leading: const Icon(Icons.sync),
          title: const Text('Synchronization'),
          subtitle: const Text('Status, pending changes and conflicts'),
          onTap: () => context.push('/sync'),
        ),
        const Divider(),
        ListTile(
          leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
          title: const Text('Sign out'),
          subtitle: const Text('Removes your data from this device. It stays in your account.'),
          onTap: () => _signOut(context, ref),
        ),
      ],
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final ctrl = ref.read(signingOutProvider.notifier);
    final pending = await ctrl.pendingAfterFinalSync();
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text(
          pending == 0
              ? 'All changes are synced. Local data will be removed from this device.'
              : '$pending change(s) have not been uploaded and will be lost. Connect to the internet first to keep them.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(
            style: pending == 0 ? null : FilledButton.styleFrom(backgroundColor: Theme.of(d).colorScheme.error),
            onPressed: () => Navigator.pop(d, true),
            child: Text(pending == 0 ? 'Sign out' : 'Discard and sign out'),
          ),
        ],
      ),
    );
    if (ok == true) await ctrl.signOut();
  }
}

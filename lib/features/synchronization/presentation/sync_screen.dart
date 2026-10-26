import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../core/money/money.dart';
import '../../../database/app_database.dart';
import '../../../database/daos/sync_dao.dart';
import '../../../shared/widgets/common.dart';
import '../domain/remote_sync_api.dart';
import '../domain/sync_engine.dart';
import 'sync_status_chip.dart';

class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.watch(syncEngineProvider);
    final queue = ref.watch(syncQueueProvider).value ?? const [];
    final conflicts = ref.watch(syncConflictsProvider).value ?? const [];
    final lastSync = ref.watch(lastSyncProvider).value;
    final failed = queue.where((o) => o.status == OpStatus.failed).toList();
    final waiting = queue.where((o) => o.status == OpStatus.pending || o.status == OpStatus.processing).toList();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Synchronization')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ValueListenableBuilder(
            valueListenable: engine.state,
            builder: (_, s, _) => Card(
              child: ListTile(
                leading: Icon(switch (s.phase) {
                  SyncPhase.offline => Icons.cloud_off,
                  SyncPhase.needsAuth => Icons.lock_outline,
                  SyncPhase.error => Icons.warning_amber,
                  SyncPhase.running => Icons.sync,
                  SyncPhase.idle => Icons.cloud_done_outlined,
                }),
                title: Text(switch (s.phase) {
                  SyncPhase.offline => 'Offline. Changes are saved on this device.',
                  SyncPhase.needsAuth => 'Session expired. Sign in again to resume syncing; your local data is kept.',
                  SyncPhase.error => 'Last sync failed',
                  SyncPhase.running => 'Syncing…',
                  SyncPhase.idle => 'Online',
                }),
                subtitle: Text(
                  [
                    'Last successful sync: ${lastSync == null ? 'never' : DateFormat.yMMMd().add_Hms().format(DateTime.parse(lastSync).toLocal())}',
                    '${waiting.length} change(s) waiting to upload',
                    if (s.message != null && s.phase != SyncPhase.idle) s.message!,
                  ].join('\n'),
                ),
                isThreeLine: true,
                trailing: s.phase == SyncPhase.needsAuth
                    ? FilledButton(onPressed: () => _reauthenticate(context, ref), child: const Text('Sign in'))
                    : FilledButton.tonal(
                        onPressed: s.phase == SyncPhase.running
                            ? null
                            : () async {
                                await ref.read(databaseProvider).syncDao.retryNow();
                                await ref.read(syncSchedulerProvider).syncNow();
                              },
                        child: const Text('Sync now'),
                      ),
              ),
            ),
          ),
          if (conflicts.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Conflicts', style: theme.textTheme.titleMedium),
            const Text(
              'This record was changed on another device while you were editing it here. Choose which version to keep.',
            ),
            for (final c in conflicts) _ConflictCard(conflict: c),
          ],
          if (failed.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Rejected changes', style: theme.textTheme.titleMedium),
            for (final op in failed)
              Card(
                child: ListTile(
                  leading: Icon(Icons.error_outline, color: theme.colorScheme.error),
                  title: Text('${op.operation} ${op.entityType}'),
                  subtitle: Text(op.lastError ?? 'Rejected by server'),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      TextButton(
                        onPressed: () => ref.read(databaseProvider).syncDao.retryNow(opId: op.id),
                        child: const Text('Retry'),
                      ),
                      TextButton(
                        onPressed: () async {
                          try {
                            await ref.read(syncEngineProvider).discardFailed(op);
                          } on RemoteException catch (e) {
                            if (context.mounted) showError(context, 'Needs a connection: ${e.message}');
                          }
                        },
                        child: const Text('Discard'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Refreshes an expired session for the same account without touching local data.
Future<void> _reauthenticate(BuildContext context, WidgetRef ref) async {
  final auth = ref.read(supabaseProvider).auth;
  final email = auth.currentUser?.email;
  if (email == null) return;
  final password = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Sign in again'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(email),
          const SizedBox(height: 8),
          TextField(
            controller: password,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Password'),
            onSubmitted: (_) => Navigator.pop(d, true),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Sign in')),
      ],
    ),
  );
  final pw = password.text;
  password.dispose();
  if (ok != true) return;
  try {
    await auth.signInWithPassword(email: email, password: pw);
    await ref.read(databaseProvider).syncDao.retryNow();
    await ref.read(syncSchedulerProvider).syncNow();
  } catch (e) {
    if (context.mounted) showError(context, 'Sign-in failed: ${e is RemoteException ? e.message : e}');
  }
}

class _ConflictCard extends ConsumerWidget {
  const _ConflictCard({required this.conflict});

  final SyncConflict conflict;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = jsonDecode(conflict.localPayload) as Map<String, dynamic>;
    final server = conflict.serverRow == null ? null : jsonDecode(conflict.serverRow!) as Map<String, dynamic>;
    final dao = ref.read(databaseProvider).syncDao;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(conflict.entityType, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _Side(title: 'This device', values: local.isEmpty ? {'': 'Deleted'} : local),
                _Side(
                  title: 'Other device',
                  values: server == null
                      ? {'': 'Missing'}
                      : server['deleted_at'] != null
                      ? {'': 'Deleted'}
                      : server,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(onPressed: () => dao.keepServer(conflict), child: const Text('Keep other device')),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () async {
                    await dao.keepMine(conflict);
                    await ref.read(syncSchedulerProvider).syncNow();
                  },
                  child: const Text('Keep this device'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows only the user-meaningful fields of one version.
class _Side extends StatelessWidget {
  const _Side({required this.title, required this.values});

  final String title;
  final Map<String, dynamic> values;

  static const _fields = {
    'name': 'Name',
    'description': 'Description',
    'type': 'Type',
    'amount_minor': 'Amount',
    'transaction_date': 'Date',
    'period_start': 'From',
    'period_end': 'To',
    '': '',
  };

  @override
  Widget build(BuildContext context) {
    String show(String k, Object? v) => k == 'amount_minor' && values['currency_code'] is String
        ? Money(v as int, values['currency_code'] as String).format()
        : '$v';
    return SizedBox(
      width: 260,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          for (final e in _fields.entries)
            if (values.containsKey(e.key))
              Text(e.key.isEmpty ? '${values['']}' : '${e.value}: ${show(e.key, values[e.key])}'),
        ],
      ),
    );
  }
}

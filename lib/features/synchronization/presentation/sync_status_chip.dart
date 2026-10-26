import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../database/app_database.dart';
import '../../../database/daos/sync_dao.dart';
import '../domain/sync_engine.dart';

final syncQueueProvider = StreamProvider<List<QueuedOp>>((ref) => ref.watch(databaseProvider).syncDao.watchQueue());

final syncConflictsProvider = StreamProvider<List<SyncConflict>>(
  (ref) => ref.watch(databaseProvider).syncDao.watchConflicts(),
);

final lastSyncProvider = StreamProvider<String?>(
  (ref) => ref.watch(databaseProvider).syncDao.watchMeta(SyncEngine.lastSyncKey),
);

/// Compact app-bar status: tapping opens the sync screen.
class SyncStatusChip extends ConsumerWidget {
  const SyncStatusChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.watch(syncEngineProvider);
    final queue = ref.watch(syncQueueProvider).value ?? const [];
    final needsAttention = queue.any((o) => o.status == OpStatus.failed || o.status == OpStatus.conflict);
    final scheme = Theme.of(context).colorScheme;

    return ValueListenableBuilder(
      valueListenable: engine.state,
      builder: (context, s, _) {
        final (icon, label, color) = switch (s.phase) {
          _ when needsAttention => (Icons.error_outline, 'Needs attention', scheme.error),
          SyncPhase.running => (Icons.sync, 'Syncing', null),
          SyncPhase.offline => (Icons.cloud_off, queue.isEmpty ? 'Offline' : 'Offline · ${queue.length}', null),
          SyncPhase.needsAuth => (Icons.lock_outline, 'Sign in required', scheme.error),
          SyncPhase.error => (Icons.warning_amber, 'Sync error', scheme.error),
          SyncPhase.idle =>
            queue.isEmpty
                ? (Icons.cloud_done_outlined, 'Synced', null)
                : (Icons.cloud_upload_outlined, '${queue.length} pending', null),
        };
        return ActionChip(
          avatar: Icon(icon, size: 18, color: color),
          label: Text(label),
          tooltip: 'Sync status',
          onPressed: () => context.push('/sync'),
        );
      },
    );
  }
}

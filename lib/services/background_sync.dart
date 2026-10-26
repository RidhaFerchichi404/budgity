import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../database/app_database.dart';
import '../features/synchronization/data/supabase_sync_api.dart';
import '../features/synchronization/domain/sync_engine.dart';
import '../features/synchronization/domain/sync_scheduler.dart';
import 'supabase_service.dart';

const _taskName = 'mybudget.sync';

/// Android periodic sync while the app is closed. Windows has no equivalent;
/// it syncs whenever the app is running.
Future<void> registerBackgroundSync() async {
  if (!Platform.isAndroid) return;
  await Workmanager().initialize(backgroundSyncDispatcher);
  await Workmanager().registerPeriodicTask(
    _taskName,
    _taskName,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}

@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((task, _) async {
    WidgetsFlutterBinding.ensureInitialized();
    final db = AppDatabase.open();
    try {
      // shortcut: the foreground heartbeat acts as a one-sided lease. If the
      // app opens mid-task both may sync briefly; upgrade to a two-sided lease
      // row if Android logs show refresh-token reuse.
      final beat = await db.syncDao.meta(SyncScheduler.heartbeatKey);
      final alive =
          beat != null && DateTime.now().toUtc().difference(DateTime.parse(beat)) < const Duration(minutes: 6);
      if (alive) return true;

      await initSupabase();
      await SyncEngine(db, SupabaseSyncApi(Supabase.instance.client)).run();
      return true;
    } catch (_) {
      return false; // WorkManager retries with its own backoff
    } finally {
      await db.close();
    }
  });
}

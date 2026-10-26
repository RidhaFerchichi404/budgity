import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import '../../../database/app_database.dart';
import '../../../database/daos/sync_dao.dart';
import 'sync_engine.dart';

/// Foreground triggers for [SyncEngine.run]: start, resume, connectivity
/// regained, a 5-minute heartbeat, and shortly after any op becomes due.
class SyncScheduler {
  SyncScheduler(this._engine, this._db);

  final SyncEngine _engine;
  final AppDatabase _db;

  static const heartbeatKey = 'foreground_heartbeat';

  AppLifecycleListener? _lifecycle;
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  StreamSubscription<List<QueuedOp>>? _queue;
  Timer? _periodic;
  Timer? _soon;

  void start() {
    _lifecycle = AppLifecycleListener(onResume: syncNow);
    _connectivity = Connectivity().onConnectivityChanged.listen((r) {
      if (!r.contains(ConnectivityResult.none)) syncNow();
    });
    _periodic = Timer.periodic(const Duration(minutes: 5), (_) => syncNow());
    _queue = _db.syncDao.watchQueue().listen(_scheduleForQueue);
    syncNow();
  }

  /// Debounces bursts of local writes and wakes up when a backoff expires.
  void _scheduleForQueue(List<QueuedOp> ops) {
    final pending = ops.where((o) => o.status == OpStatus.pending).map((o) => o.nextAttemptAt);
    if (pending.isEmpty) return;
    final earliest = pending.reduce((a, b) => a.isBefore(b) ? a : b);
    var wait = earliest.difference(DateTime.now().toUtc());
    if (wait < const Duration(seconds: 2)) wait = const Duration(seconds: 2);
    if (wait > const Duration(minutes: 5)) return; // heartbeat covers it
    _soon?.cancel();
    _soon = Timer(wait, syncNow);
  }

  Future<void> syncNow() async {
    try {
      // Lets the Android background task know the app is alive (it then skips).
      await _db.syncDao.setMeta(heartbeatKey, DateTime.now().toUtc().toIso8601String());
      await _engine.run();
    } catch (e) {
      // Never log payloads; the engine state already carries the message for the UI.
      debugPrint('sync failed: ${e.runtimeType}');
    }
  }

  Future<void> stop() async {
    _lifecycle?.dispose();
    _periodic?.cancel();
    _soon?.cancel();
    await _connectivity?.cancel();
    await _queue?.cancel();
  }
}

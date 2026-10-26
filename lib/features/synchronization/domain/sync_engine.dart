import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../database/app_database.dart';
import '../../../database/daos/sync_dao.dart';
import '../../../database/server_rows.dart';
import 'remote_sync_api.dart';

enum SyncPhase { idle, running, offline, needsAuth, error }

@immutable
class SyncState {
  const SyncState(this.phase, {this.message});

  final SyncPhase phase;
  final String? message;
}

/// The single synchronization path (docs/synchronization.md). Every trigger
/// calls [run]; concurrent calls share one run and request one follow-up.
class SyncEngine {
  SyncEngine(this._db, this._remote, {DateTime Function()? clock, Random? random, this.pageSize = 500})
    : _clock = clock ?? (() => DateTime.now().toUtc()),
      _random = random ?? Random();

  final AppDatabase _db;
  final RemoteSyncApi _remote;
  final DateTime Function() _clock;
  final Random _random;
  final int pageSize;

  static const maxBatch = 200;
  static const lastSyncKey = 'last_sync';

  final state = ValueNotifier(const SyncState(SyncPhase.idle));

  Future<void>? _current;
  bool _again = false;

  SyncDao get _dao => _db.syncDao;

  Future<void> run() {
    if (_current != null) {
      _again = true;
      return _current!;
    }
    return _current = _loop().whenComplete(() => _current = null);
  }

  Future<void> _loop() async {
    do {
      _again = false;
      await _runOnce();
    } while (_again);
  }

  Future<void> _runOnce() async {
    if (!_remote.hasSession) {
      state.value = const SyncState(SyncPhase.needsAuth);
      return;
    }
    state.value = const SyncState(SyncPhase.running);
    try {
      await _dao.resetProcessing();
      await _push();
      await _pull();
      await _dao.setMeta(lastSyncKey, _clock().toIso8601String());
      state.value = const SyncState(SyncPhase.idle);
    } on RemoteException catch (e) {
      state.value = SyncState(switch (e.kind) {
        RemoteErrorKind.network => SyncPhase.offline,
        RemoteErrorKind.auth => SyncPhase.needsAuth,
        _ => SyncPhase.error,
      }, message: e.message);
    } catch (e) {
      state.value = SyncState(SyncPhase.error, message: '$e');
      rethrow;
    }
  }

  // ---------- push ----------

  Future<void> _push() async {
    // Each round sends at most one op per entity; terminates because every sent
    // op is acked, parked (conflict/failed), or rescheduled into the future.
    while (true) {
      final heads = await _dao.dueHeads(_clock());
      if (heads.isEmpty) return;
      final headIds = heads.map((o) => o.id).toSet();
      final busyCategories = await _dao.blockedCategoryIds(headIds);
      final ready = heads.where((op) {
        if (op.entityType != EntityType.transaction.name && op.entityType != EntityType.budget.name) return true;
        final cat = (jsonDecode(op.payload) as Json)['category_id'] as String?;
        return cat == null || !busyCategories.contains(cat);
      }).toList();
      if (ready.isEmpty) return;

      final profileOps = ready.where((o) => o.entityType == EntityType.profile.name).toList();
      final batch = ready.where((o) => o.entityType != EntityType.profile.name).take(maxBatch).toList();
      for (final op in profileOps) {
        await _pushProfile(op);
      }
      if (batch.isNotEmpty) await _pushBatch(batch);
    }
  }

  Future<void> _pushProfile(QueuedOp op) async {
    await _dao.markSending([op], {op.id: null});
    try {
      final row = await _remote.updateProfile(jsonDecode(op.payload) as Json);
      await _dao.ack(op, row, row);
    } on RemoteException catch (e) {
      await _reschedule([op], e);
      rethrow;
    }
  }

  Future<void> _pushBatch(List<QueuedOp> batch) async {
    final bases = <String, int?>{
      for (final op in batch)
        op.id: op.operation == 'create' ? null : await _db.localVersion(EntityType.byName(op.entityType), op.entityId),
    };
    await _dao.markSending(batch, bases);

    final List<Json> results;
    try {
      results = await _remote.push([
        for (final op in batch)
          {
            'op_id': op.id,
            'entity_type': op.entityType,
            'entity_id': op.entityId,
            'operation': op.operation,
            'base_version': bases[op.id],
            'payload': jsonDecode(op.payload),
          },
      ]);
    } on RemoteException catch (e) {
      await _reschedule(batch, e);
      rethrow;
    }

    final byId = {for (final r in results) r['op_id'] as String: r};
    for (final op in batch) {
      final r = byId[op.id];
      final status = r?['status'] as String?;
      switch (status) {
        case 'applied' || 'duplicate':
          await _dao.ack(op, r!['row'] as Json, r['current'] as Json?);
        case 'conflict':
          await _dao.markConflict(op, r!['row'] as Json?);
        case 'invalid':
          await _dao.markFailed(op, (r!['error'] as String?) ?? 'rejected by server');
        default: // 'blocked' or missing: parent not there yet, try again later
          await _dao.retryLater(
            op.id,
            _clock().add(backoff(op.attemptCount + 1)),
            r?['error'] as String? ?? 'no result',
          );
      }
    }
  }

  Future<void> _reschedule(List<QueuedOp> ops, RemoteException e) async {
    for (final op in ops) {
      final at = switch (e.kind) {
        // auth uses normal backoff too (an immediate retry would spin every 2 s);
        // re-sign-in calls SyncDao.retryNow to resume at once.
        RemoteErrorKind.rateLimited when e.retryAfter != null => _clock().add(e.retryAfter!),
        _ => _clock().add(backoff(op.attemptCount + 1)),
      };
      await _dao.retryLater(op.id, at, e.message);
    }
  }

  /// min(2^n * 5s, 1h) with ±20% jitter.
  Duration backoff(int attempt) {
    final base = min(5 * pow(2, min(attempt, 20)), 3600).toDouble();
    return Duration(milliseconds: (base * (0.8 + 0.4 * _random.nextDouble()) * 1000).round());
  }

  // ---------- pull ----------

  Future<void> _pull() async {
    for (final type in EntityType.values) {
      while (true) {
        final rows = await _remote.pull(type.table, await _dao.cursor(type), pageSize);
        await _dao.applyPulledPage(type, rows);
        if (rows.length < pageSize) break;
      }
    }
  }

  // ---------- user actions ----------

  /// Drops a failed op and restores the server's copy of the entity.
  Future<void> discardFailed(QueuedOp op) async {
    final type = EntityType.byName(op.entityType);
    final row = await _remote.fetchById(type.table, op.entityId);
    await _dao.discardFailed(op, row);
  }

  void dispose() => state.dispose();
}

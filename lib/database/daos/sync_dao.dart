import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../app_database.dart';
import '../server_rows.dart';
import '../tables.dart';

part 'sync_dao.g.dart';

abstract final class OpStatus {
  static const pending = 'pending';
  static const processing = 'processing';
  static const failed = 'failed';
  static const conflict = 'conflict';
}

/// Queue, cursor and conflict bookkeeping. Callers that also write an entity
/// row must wrap both in one `db.transaction` (see the repositories).
@DriftAccessor(tables: [SyncQueue, SyncMetadata, SyncConflicts])
class SyncDao extends DatabaseAccessor<AppDatabase> with _$SyncDaoMixin {
  SyncDao(super.db);

  static const _uuid = Uuid();

  // ---------- enqueue ----------

  /// Records a local change. Merges into the latest op for the entity only if
  /// that op has never been sent; a sent op may already be applied server-side.
  Future<void> enqueue(EntityType type, String entityId, String operation, Json payload) async {
    final last =
        await (select(syncQueue)
              ..where((q) => q.entityType.equals(type.name) & q.entityId.equals(entityId))
              ..orderBy([(q) => OrderingTerm.desc(q.seq)])
              ..limit(1))
            .getSingleOrNull();

    if (last != null && last.attemptCount == 0 && last.status == OpStatus.pending) {
      if (last.operation == 'create' && operation == 'delete') {
        await (delete(syncQueue)..where((q) => q.id.equals(last.id))).go();
        return;
      }
      await (update(syncQueue)..where((q) => q.id.equals(last.id))).write(
        SyncQueueCompanion(
          operation: Value(last.operation == 'create' ? 'create' : operation),
          // merged: an unsent profile op may carry a field the newer one omits
          payload: Value(jsonEncode({...jsonDecode(last.payload) as Json, ...payload})),
        ),
      );
      return;
    }

    final maxSeq = syncQueue.seq.max();
    final seq = await (selectOnly(syncQueue)..addColumns([maxSeq])).map((r) => r.read(maxSeq)).getSingle();
    final now = DateTime.now().toUtc();
    await into(syncQueue).insert(
      SyncQueueCompanion.insert(
        id: _uuid.v4(),
        seq: (seq ?? 0) + 1,
        entityType: type.name,
        entityId: entityId,
        operation: operation,
        payload: jsonEncode(payload),
        createdAt: now,
        nextAttemptAt: now,
      ),
    );
  }

  // ---------- push side ----------

  /// The oldest op of each entity, if it is pending and due. Later ops of the
  /// same entity wait so their base_version is read after the earlier ack.
  /// Results are in dependency order (categories before their children).
  Future<List<QueuedOp>> dueHeads(DateTime now) async {
    final all = await (select(syncQueue)..orderBy([(q) => OrderingTerm.asc(q.seq)])).get();
    final seen = <String>{};
    final heads = <QueuedOp>[];
    for (final op in all) {
      if (!seen.add('${op.entityType}:${op.entityId}')) continue;
      if (op.status == OpStatus.pending && !op.nextAttemptAt.isAfter(now)) heads.add(op);
    }
    heads.sort((a, b) {
      final byType = EntityType.byName(a.entityType).index - EntityType.byName(b.entityType).index;
      return byType != 0 ? byType : a.seq - b.seq;
    });
    return heads;
  }

  /// Category ids that have an op not yet acked and not going out in this batch.
  Future<Set<String>> blockedCategoryIds(Set<String> sendingOpIds) async {
    final rows = await (select(syncQueue)..where((q) => q.entityType.equals(EntityType.category.name))).get();
    return {
      for (final r in rows)
        if (!sendingOpIds.contains(r.id)) r.entityId,
    };
  }

  /// Marks ops as sent *before* the request: after a crash they must be treated
  /// as possibly applied (never coalesced into).
  Future<void> markSending(List<QueuedOp> ops, Map<String, int?> baseVersions) => batch((b) {
    for (final op in ops) {
      b.update(
        syncQueue,
        SyncQueueCompanion(
          status: const Value(OpStatus.processing),
          attemptCount: Value(op.attemptCount + 1),
          baseVersion: Value(baseVersions[op.id]),
        ),
        where: (q) => q.id.equals(op.id),
      );
    }
  });

  /// Crash recovery: anything left mid-flight goes back to pending.
  Future<void> resetProcessing() => (update(syncQueue)..where((q) => q.status.equals(OpStatus.processing))).write(
    const SyncQueueCompanion(status: Value(OpStatus.pending)),
  );

  Future<bool> hasOtherOps(EntityType type, String entityId, String exceptOpId) async {
    final row =
        await (select(syncQueue)
              ..where(
                (q) => q.entityType.equals(type.name) & q.entityId.equals(entityId) & q.id.equals(exceptOpId).not(),
              )
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  /// Server accepted (or had already accepted) the op.
  Future<void> ack(QueuedOp op, Json row, Json? current) => transaction(() async {
    final type = EntityType.byName(op.entityType);
    await (delete(syncQueue)..where((q) => q.id.equals(op.id))).go();
    if (await hasOtherOps(type, op.entityId, op.id)) {
      // A newer local edit is queued: keep it, only adopt the acked version
      // so that edit conflicts properly if `current` moved on.
      await db.setLocalVersion(type, op.entityId, row['version'] as int);
    } else {
      await ServerRows.upsert(db, type, current ?? row);
    }
  });

  Future<void> markConflict(QueuedOp op, Json? serverRow) => transaction(() async {
    await (update(
      syncQueue,
    )..where((q) => q.id.equals(op.id))).write(const SyncQueueCompanion(status: Value(OpStatus.conflict)));
    await into(syncConflicts).insert(
      SyncConflictsCompanion.insert(
        opId: op.id,
        entityType: op.entityType,
        entityId: op.entityId,
        localPayload: op.payload,
        serverRow: Value(serverRow == null ? null : jsonEncode(serverRow)),
        createdAt: DateTime.now().toUtc(),
      ),
    );
  });

  Future<void> markFailed(QueuedOp op, String error) => (update(syncQueue)..where((q) => q.id.equals(op.id))).write(
    SyncQueueCompanion(status: const Value(OpStatus.failed), lastError: Value(error)),
  );

  Future<void> retryLater(String opId, DateTime at, String error) =>
      (update(syncQueue)..where((q) => q.id.equals(opId))).write(
        SyncQueueCompanion(status: const Value(OpStatus.pending), nextAttemptAt: Value(at), lastError: Value(error)),
      );

  /// User-triggered retry of a failed op, or "retry now" for everything waiting.
  Future<void> retryNow({String? opId}) {
    final q = update(syncQueue)
      ..where(
        (t) =>
            (opId == null ? const Constant(true) : t.id.equals(opId)) &
            t.status.isIn([OpStatus.pending, OpStatus.failed]),
      );
    return q.write(
      SyncQueueCompanion(status: const Value(OpStatus.pending), nextAttemptAt: Value(DateTime.now().toUtc())),
    );
  }

  // ---------- pull side ----------

  /// Applies one pulled page and advances the cursor atomically. Rows whose
  /// entity still has a queued op are skipped: that op will push or conflict.
  Future<void> applyPulledPage(EntityType type, List<Json> rows) => transaction(() async {
    if (rows.isEmpty) return;
    final queued = (await (select(
      syncQueue,
    )..where((q) => q.entityType.equals(type.name))).get()).map((q) => q.entityId).toSet();
    for (final r in rows) {
      if (!queued.contains(r['id'])) await ServerRows.upsert(db, type, r);
    }
    await setMeta('cursor:${type.table}', '${rows.last['change_seq']}');
  });

  Future<int> cursor(EntityType type) async => int.parse(await meta('cursor:${type.table}') ?? '0');

  // ---------- conflicts & failures ----------

  Future<void> keepMine(SyncConflict c) => transaction(() async {
    final type = EntityType.byName(c.entityType);
    final server = c.serverRow == null ? null : jsonDecode(c.serverRow!) as Json;
    if (server != null) await db.setLocalVersion(type, c.entityId, server['version'] as int);
    final op = await (select(syncQueue)..where((q) => q.id.equals(c.opId))).getSingleOrNull();
    if (op != null) {
      await (update(syncQueue)..where((q) => q.id.equals(op.id))).write(
        SyncQueueCompanion(
          // the row exists server-side now, so a conflicted create becomes an update
          operation: Value(op.operation == 'create' && server != null ? 'update' : op.operation),
          status: const Value(OpStatus.pending),
          nextAttemptAt: Value(DateTime.now().toUtc()),
        ),
      );
    }
    await (delete(syncConflicts)..where((t) => t.id.equals(c.id))).go();
  });

  Future<void> keepServer(SyncConflict c) => transaction(() async {
    final type = EntityType.byName(c.entityType);
    await dropAllOps(type, c.entityId);
    if (c.serverRow != null) {
      await ServerRows.upsert(db, type, jsonDecode(c.serverRow!) as Json);
    } else {
      await db.deleteLocal(type, c.entityId);
    }
    await (delete(syncConflicts)..where((t) => t.id.equals(c.id))).go();
  });

  /// Discards a failed op and replaces the local row with the server's copy
  /// (null = the server never had it).
  Future<void> discardFailed(QueuedOp op, Json? serverRow) => transaction(() async {
    final type = EntityType.byName(op.entityType);
    await dropAllOps(type, op.entityId);
    if (serverRow != null) {
      await ServerRows.upsert(db, type, serverRow);
    } else {
      await db.deleteLocal(type, op.entityId);
    }
  });

  Future<void> dropAllOps(EntityType type, String entityId) =>
      (delete(syncQueue)..where((q) => q.entityType.equals(type.name) & q.entityId.equals(entityId))).go();

  // ---------- status ----------

  Stream<List<QueuedOp>> watchQueue() => (select(syncQueue)..orderBy([(q) => OrderingTerm.asc(q.seq)])).watch();

  Stream<List<SyncConflict>> watchConflicts() => select(syncConflicts).watch();

  Future<int> queueLength() async {
    final c = syncQueue.id.count();
    return (selectOnly(syncQueue)..addColumns([c])).map((r) => r.read(c)!).getSingle();
  }

  // ---------- metadata ----------

  Future<String?> meta(String key) async =>
      (await (select(syncMetadata)..where((m) => m.key.equals(key))).getSingleOrNull())?.value;

  Future<void> setMeta(String key, String value) =>
      into(syncMetadata).insertOnConflictUpdate(SyncMetadataCompanion.insert(key: key, value: value));

  Stream<String?> watchMeta(String key) =>
      (select(syncMetadata)..where((m) => m.key.equals(key))).watchSingleOrNull().map((e) => e?.value);
}

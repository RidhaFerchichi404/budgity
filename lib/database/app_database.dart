import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_database.steps.dart';
import 'daos/sync_dao.dart';
import 'server_rows.dart';
import 'tables.dart';

part 'app_database.g.dart';

/// Separates databases when several "devices" run on one machine
/// (`--dart-define=DB_NAME=device2`).
const dbName = String.fromEnvironment('DB_NAME', defaultValue: 'main');

/// Per-user app-support dir, not Documents (which may be synced to OneDrive).
Future<String> dbFilePath() async => p.join((await getApplicationSupportDirectory()).path, 'mybudget_$dbName.sqlite');

/// Deletes the database and its WAL/SHM side files. The DB must be closed first.
Future<void> deleteDbFiles() async {
  final path = await dbFilePath();
  for (final f in [path, '$path-wal', '$path-shm', '$path-journal']) {
    final file = File(f);
    if (await file.exists()) await file.delete();
  }
}

@DriftDatabase(
  tables: [Profiles, Categories, Transactions, Budgets, SyncQueue, SyncMetadata, SyncConflicts],
  daos: [SyncDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  AppDatabase.open()
    : super(
        driftDatabase(
          name: 'mybudget',
          native: const DriftNativeOptions(databasePath: dbFilePath),
        ),
      );

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement('CREATE INDEX tx_date_idx ON transactions (transaction_date)');
      await customStatement('CREATE INDEX queue_entity_idx ON sync_queue (entity_type, entity_id)');
    },
    // New steps: bump schemaVersion, then `dart run drift_dev make-migrations`.
    onUpgrade: stepByStep(
      // Every v1 row is personal, which is the column default (ADR 0006). No queue ops.
      from1To2: (m, schema) async {
        await m.addColumn(schema.categories, schema.categories.workspace);
        await m.addColumn(schema.transactions, schema.transactions.workspace);
        await m.addColumn(schema.budgets, schema.budgets.workspace);
        await m.addColumn(schema.profiles, schema.profiles.freelancerEnabled);
      },
    ),
  );

  TableInfo<Table, dynamic>? _synced(EntityType type) => switch (type) {
    EntityType.profile => null,
    EntityType.category => categories,
    EntityType.transaction => transactions,
    EntityType.budget => budgets,
  };

  /// Last server-acked version of a local row (0 = never synced, null = no row).
  Future<int?> localVersion(EntityType type, String id) async {
    final t = _synced(type);
    if (t == null) return null;
    final row = await customSelect(
      'SELECT version FROM ${t.actualTableName} WHERE id = ?',
      variables: [Variable.withString(id)],
      readsFrom: {t},
    ).getSingleOrNull();
    return row?.read<int>('version');
  }

  Future<void> setLocalVersion(EntityType type, String id, int version) async {
    final t = _synced(type);
    if (t == null) return;
    await customUpdate(
      'UPDATE ${t.actualTableName} SET version = ? WHERE id = ?',
      variables: [Variable.withInt(version), Variable.withString(id)],
      updates: {t},
    );
  }

  Future<void> deleteLocal(EntityType type, String id) async {
    final t = _synced(type);
    if (t == null) return;
    await customUpdate(
      'DELETE FROM ${t.actualTableName} WHERE id = ?',
      variables: [Variable.withString(id)],
      updates: {t},
      updateKind: UpdateKind.delete,
    );
  }
}

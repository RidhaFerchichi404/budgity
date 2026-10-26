import 'package:drift/drift.dart';

// Synced tables mirror supabase/migrations/*_schema.sql. `version` is the last
// server-acknowledged version (0 = never reached the server). Dates are
// 'yyyy-MM-dd' text so they never shift with time zones.

mixin SyncedColumns on Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(0))();
  IntColumn get changeSeq => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 'personal' or 'freelancer' (ADR 0006). Set on create, never changed.
mixin WorkspaceColumn on Table {
  TextColumn get workspace => text().withDefault(const Constant('personal'))();
}

class Profiles extends Table {
  TextColumn get id => text()();
  TextColumn get displayName => text().withDefault(const Constant(''))();
  TextColumn get currencyCode => text().withDefault(const Constant('TND'))();
  BoolColumn get freelancerEnabled => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get changeSeq => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

class Categories extends Table with SyncedColumns, WorkspaceColumn {
  TextColumn get name => text().withLength(min: 1, max: 50)();
  TextColumn get type => text()();
  TextColumn get iconKey => text().withDefault(const Constant('tag'))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}

@DataClassName('TransactionRow')
class Transactions extends Table with SyncedColumns, WorkspaceColumn {
  TextColumn get categoryId => text().nullable()();
  TextColumn get type => text()();
  IntColumn get amountMinor => integer()();
  TextColumn get currencyCode => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get transactionDate => text()();
}

class Budgets extends Table with SyncedColumns, WorkspaceColumn {
  TextColumn get categoryId => text().nullable()();
  TextColumn get name => text().withLength(min: 1, max: 50)();
  IntColumn get amountMinor => integer()();
  TextColumn get currencyCode => text()();
  TextColumn get periodStart => text()();
  TextColumn get periodEnd => text()();
}

// ---------- local-only sync bookkeeping ----------

@DataClassName('QueuedOp')
class SyncQueue extends Table {
  TextColumn get id => text()(); // op uuid, sent to the server as op_id
  IntColumn get seq => integer()(); // local enqueue order; timestamps can tie
  TextColumn get entityType => text()(); // profile | category | transaction | budget
  TextColumn get entityId => text()();
  TextColumn get operation => text()(); // create | update | delete
  TextColumn get payload => text()(); // JSON, server column names
  IntColumn get baseVersion => integer().nullable()(); // filled when sent
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SyncMetadataEntry')
class SyncMetadata extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DataClassName('SyncConflict')
class SyncConflicts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get opId => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get localPayload => text()();
  TextColumn get serverRow => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}

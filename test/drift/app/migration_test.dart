// dart format width=80
// ignore_for_file: unused_local_variable, unused_import
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:mybudget/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'generated/schema.dart';

import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('simple database migrations', () {
    // These simple tests verify all possible schema updates with a simple (no
    // data) migration. This is a quick way to ensure that written database
    // migrations properly alter the schema.
    const versions = GeneratedHelper.versions;
    for (final (i, fromVersion) in versions.indexed) {
      group('from $fromVersion', () {
        for (final toVersion in versions.skip(i + 1)) {
          test('to $toVersion', () async {
            final schema = await verifier.schemaAt(fromVersion);
            final db = AppDatabase(schema.newConnection());
            await verifier.migrateAndValidate(db, toVersion);
            await db.close();
          });
        }
      });
    }
  });

  // v1 rows keep every value and become personal; queued v1 ops are untouched
  // (their payload has no workspace, which the server reads as personal).
  test('migration from v1 to v2 keeps data', () async {
    const uid = 'u1';
    const ts = '2026-10-01T10:00:00.000Z';
    final oldProfilesData = [
      const v1.ProfilesData(
        id: uid,
        displayName: 'Ridha',
        currencyCode: 'TND',
        updatedAt: ts,
        changeSeq: 3,
      ),
    ];
    final expectedNewProfilesData = [
      const v2.ProfilesData(
        id: uid,
        displayName: 'Ridha',
        currencyCode: 'TND',
        freelancerEnabled: 0,
        updatedAt: ts,
        changeSeq: 3,
      ),
    ];

    final oldCategoriesData = [
      const v1.CategoriesData(
        id: 'c1',
        userId: uid,
        createdAt: ts,
        updatedAt: ts,
        version: 2,
        changeSeq: 4,
        name: 'Groceries',
        type: 'expense',
        iconKey: 'cart',
        sortOrder: 0,
      ),
    ];
    final expectedNewCategoriesData = [
      const v2.CategoriesData(
        id: 'c1',
        userId: uid,
        createdAt: ts,
        updatedAt: ts,
        version: 2,
        changeSeq: 4,
        workspace: 'personal',
        name: 'Groceries',
        type: 'expense',
        iconKey: 'cart',
        sortOrder: 0,
      ),
    ];

    final oldTransactionsData = [
      const v1.TransactionsData(
        id: 't1',
        userId: uid,
        createdAt: ts,
        updatedAt: ts,
        deletedAt: ts,
        version: 1,
        changeSeq: 5,
        categoryId: 'c1',
        type: 'expense',
        amountMinor: 12500,
        currencyCode: 'TND',
        description: 'Market',
        transactionDate: '2026-10-01',
      ),
    ];
    final expectedNewTransactionsData = [
      const v2.TransactionsData(
        id: 't1',
        userId: uid,
        createdAt: ts,
        updatedAt: ts,
        deletedAt: ts,
        version: 1,
        changeSeq: 5,
        workspace: 'personal',
        categoryId: 'c1',
        type: 'expense',
        amountMinor: 12500,
        currencyCode: 'TND',
        description: 'Market',
        transactionDate: '2026-10-01',
      ),
    ];

    final oldBudgetsData = [
      const v1.BudgetsData(
        id: 'b1',
        userId: uid,
        createdAt: ts,
        updatedAt: ts,
        version: 0,
        changeSeq: 0,
        categoryId: null,
        name: 'Month',
        amountMinor: 500000,
        currencyCode: 'TND',
        periodStart: '2026-10-01',
        periodEnd: '2026-10-31',
      ),
    ];
    final expectedNewBudgetsData = [
      const v2.BudgetsData(
        id: 'b1',
        userId: uid,
        createdAt: ts,
        updatedAt: ts,
        version: 0,
        changeSeq: 0,
        workspace: 'personal',
        categoryId: null,
        name: 'Month',
        amountMinor: 500000,
        currencyCode: 'TND',
        periodStart: '2026-10-01',
        periodEnd: '2026-10-31',
      ),
    ];

    final oldSyncQueueData = [
      const v1.SyncQueueData(
        id: 'op1',
        seq: 1,
        entityType: 'budget',
        entityId: 'b1',
        operation: 'create',
        payload: '{"name":"Month"}',
        createdAt: ts,
        attemptCount: 0,
        nextAttemptAt: ts,
        status: 'pending',
      ),
    ];
    final expectedNewSyncQueueData = [
      const v2.SyncQueueData(
        id: 'op1',
        seq: 1,
        entityType: 'budget',
        entityId: 'b1',
        operation: 'create',
        payload: '{"name":"Month"}',
        createdAt: ts,
        attemptCount: 0,
        nextAttemptAt: ts,
        status: 'pending',
      ),
    ];

    final oldSyncMetadataData = [
      const v1.SyncMetadataData(key: 'cursor.transactions', value: '5'),
    ];
    final expectedNewSyncMetadataData = [
      const v2.SyncMetadataData(key: 'cursor.transactions', value: '5'),
    ];

    final oldSyncConflictsData = <v1.SyncConflictsData>[];
    final expectedNewSyncConflictsData = <v2.SyncConflictsData>[];

    await verifier.testWithDataIntegrity(
      oldVersion: 1,
      newVersion: 2,
      createOld: v1.DatabaseAtV1.new,
      createNew: v2.DatabaseAtV2.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insertAll(oldDb.profiles, oldProfilesData);
        batch.insertAll(oldDb.categories, oldCategoriesData);
        batch.insertAll(oldDb.transactions, oldTransactionsData);
        batch.insertAll(oldDb.budgets, oldBudgetsData);
        batch.insertAll(oldDb.syncQueue, oldSyncQueueData);
        batch.insertAll(oldDb.syncMetadata, oldSyncMetadataData);
        batch.insertAll(oldDb.syncConflicts, oldSyncConflictsData);
      },
      validateItems: (newDb) async {
        expect(
          expectedNewProfilesData,
          await newDb.select(newDb.profiles).get(),
        );
        expect(
          expectedNewCategoriesData,
          await newDb.select(newDb.categories).get(),
        );
        expect(
          expectedNewTransactionsData,
          await newDb.select(newDb.transactions).get(),
        );
        expect(expectedNewBudgetsData, await newDb.select(newDb.budgets).get());
        expect(
          expectedNewSyncQueueData,
          await newDb.select(newDb.syncQueue).get(),
        );
        expect(
          expectedNewSyncMetadataData,
          await newDb.select(newDb.syncMetadata).get(),
        );
        expect(
          expectedNewSyncConflictsData,
          await newDb.select(newDb.syncConflicts).get(),
        );
      },
    );
  });
}

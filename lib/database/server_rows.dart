import 'package:drift/drift.dart';

import 'app_database.dart';

/// Synced entity kinds, in push/pull dependency order (parents first).
enum EntityType {
  profile('profiles'),
  category('categories'),
  transaction('transactions'),
  budget('budgets');

  const EntityType(this.table);

  /// Supabase table name.
  final String table;

  static EntityType byName(String name) => values.byName(name);
}

typedef Json = Map<String, dynamic>;

DateTime _ts(Object? v) => DateTime.parse(v as String);
DateTime? _tsOrNull(Object? v) => v == null ? null : DateTime.parse(v as String);

/// Converts rows to and from the Supabase JSON shape (snake_case server columns).
/// Payloads carry only client-owned fields; the server owns user_id, version,
/// change_seq and updated_at.
abstract final class ServerRows {
  static Json categoryPayload(Category c) => {
    'workspace': c.workspace,
    'name': c.name,
    'type': c.type,
    'icon_key': c.iconKey,
    'sort_order': c.sortOrder,
    'created_at': c.createdAt.toUtc().toIso8601String(),
  };

  static Json transactionPayload(TransactionRow t) => {
    'workspace': t.workspace,
    'category_id': t.categoryId,
    'type': t.type,
    'amount_minor': t.amountMinor,
    'currency_code': t.currencyCode,
    'description': t.description,
    'transaction_date': t.transactionDate,
    'created_at': t.createdAt.toUtc().toIso8601String(),
  };

  static Json budgetPayload(Budget b) => {
    'workspace': b.workspace,
    'category_id': b.categoryId,
    'name': b.name,
    'amount_minor': b.amountMinor,
    'currency_code': b.currencyCode,
    'period_start': b.periodStart,
    'period_end': b.periodEnd,
    'created_at': b.createdAt.toUtc().toIso8601String(),
  };

  static Json profilePayload(Profile p) => {
    'display_name': p.displayName,
    'currency_code': p.currencyCode,
    'freelancer_enabled': p.freelancerEnabled,
  };

  /// Inserts or replaces the local row with the server's version of it.
  static Future<void> upsert(AppDatabase db, EntityType type, Json r) {
    switch (type) {
      case EntityType.profile:
        return db
            .into(db.profiles)
            .insertOnConflictUpdate(
              ProfilesCompanion.insert(
                id: r['id'] as String,
                displayName: Value(r['display_name'] as String),
                currencyCode: Value(r['currency_code'] as String),
                freelancerEnabled: Value(r['freelancer_enabled'] as bool),
                updatedAt: _ts(r['updated_at']),
                changeSeq: Value(r['change_seq'] as int),
              ),
            );
      case EntityType.category:
        return db
            .into(db.categories)
            .insertOnConflictUpdate(
              CategoriesCompanion.insert(
                id: r['id'] as String,
                userId: r['user_id'] as String,
                workspace: Value(r['workspace'] as String),
                name: r['name'] as String,
                type: r['type'] as String,
                iconKey: Value(r['icon_key'] as String),
                sortOrder: Value(r['sort_order'] as int),
                createdAt: _ts(r['created_at']),
                updatedAt: _ts(r['updated_at']),
                deletedAt: Value(_tsOrNull(r['deleted_at'])),
                version: Value(r['version'] as int),
                changeSeq: Value(r['change_seq'] as int),
              ),
            );
      case EntityType.transaction:
        return db
            .into(db.transactions)
            .insertOnConflictUpdate(
              TransactionsCompanion.insert(
                id: r['id'] as String,
                userId: r['user_id'] as String,
                workspace: Value(r['workspace'] as String),
                categoryId: Value(r['category_id'] as String?),
                type: r['type'] as String,
                amountMinor: r['amount_minor'] as int,
                currencyCode: r['currency_code'] as String,
                description: Value(r['description'] as String),
                transactionDate: r['transaction_date'] as String,
                createdAt: _ts(r['created_at']),
                updatedAt: _ts(r['updated_at']),
                deletedAt: Value(_tsOrNull(r['deleted_at'])),
                version: Value(r['version'] as int),
                changeSeq: Value(r['change_seq'] as int),
              ),
            );
      case EntityType.budget:
        return db
            .into(db.budgets)
            .insertOnConflictUpdate(
              BudgetsCompanion.insert(
                id: r['id'] as String,
                userId: r['user_id'] as String,
                workspace: Value(r['workspace'] as String),
                categoryId: Value(r['category_id'] as String?),
                name: r['name'] as String,
                amountMinor: r['amount_minor'] as int,
                currencyCode: r['currency_code'] as String,
                periodStart: r['period_start'] as String,
                periodEnd: r['period_end'] as String,
                createdAt: _ts(r['created_at']),
                updatedAt: _ts(r['updated_at']),
                deletedAt: Value(_tsOrNull(r['deleted_at'])),
                version: Value(r['version'] as int),
                changeSeq: Value(r['change_seq'] as int),
              ),
            );
    }
  }
}

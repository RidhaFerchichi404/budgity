import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/validation_exception.dart';
import '../../../database/app_database.dart';
import '../../../database/server_rows.dart';
import '../domain/budget_repository.dart';

class DriftBudgetRepository implements BudgetRepository {
  /// Reads and creates are scoped to [workspace] (ADR 0006).
  DriftBudgetRepository(this._db, this._userId, {this.workspace = 'personal'});

  final AppDatabase _db;
  final String Function() _userId;
  final String workspace;

  static const _uuid = Uuid();
  static final _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  @override
  Stream<List<BudgetProgress>> watchBudgets({String? onDate}) {
    final vars = <Variable>[Variable.withString(workspace)];
    var where = 'b.deleted_at IS NULL AND b.workspace = ?';
    if (onDate != null) {
      where += ' AND b.period_start <= ? AND b.period_end >= ?';
      vars.addAll([Variable.withString(onDate), Variable.withString(onDate)]);
    }
    return _db
        .customSelect(
          'SELECT b.*, COALESCE(SUM(t.amount_minor), 0) AS spent FROM budgets b '
          'LEFT JOIN transactions t ON t.deleted_at IS NULL AND t.type = \'expense\' '
          'AND t.workspace = b.workspace AND t.currency_code = b.currency_code '
          'AND t.transaction_date BETWEEN b.period_start AND b.period_end '
          'AND (b.category_id IS NULL OR t.category_id = b.category_id) '
          'WHERE $where GROUP BY b.id ORDER BY b.period_start DESC, b.name',
          variables: vars,
          readsFrom: {_db.budgets, _db.transactions},
        )
        .watch()
        .map((rows) => [for (final r in rows) BudgetProgress(_db.budgets.map(r.data), r.read<int>('spent'))]);
  }

  @override
  Future<Budget> createBudget({
    required String name,
    required int amountMinor,
    required String currencyCode,
    required String periodStart,
    required String periodEnd,
    String? categoryId,
  }) async {
    final now = DateTime.now().toUtc();
    final row = Budget(
      id: _uuid.v4(),
      userId: _userId(),
      workspace: workspace,
      categoryId: categoryId,
      name: name.trim(),
      amountMinor: amountMinor,
      currencyCode: currencyCode,
      periodStart: periodStart,
      periodEnd: periodEnd,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      version: 0,
      changeSeq: 0,
    );
    await _validate(row);
    await _db.transaction(() async {
      await _db.into(_db.budgets).insert(row);
      await _db.syncDao.enqueue(EntityType.budget, row.id, 'create', ServerRows.budgetPayload(row));
    });
    return row;
  }

  @override
  Future<void> updateBudget(Budget b) async {
    final row = b.copyWith(name: b.name.trim(), updatedAt: DateTime.now().toUtc());
    await _validate(row);
    await _db.transaction(() async {
      await (_db.update(_db.budgets)..where((x) => x.id.equals(row.id))).write(
        BudgetsCompanion(
          categoryId: Value(row.categoryId),
          name: Value(row.name),
          amountMinor: Value(row.amountMinor),
          currencyCode: Value(row.currencyCode),
          periodStart: Value(row.periodStart),
          periodEnd: Value(row.periodEnd),
          updatedAt: Value(row.updatedAt),
        ),
      );
      await _db.syncDao.enqueue(EntityType.budget, row.id, 'update', ServerRows.budgetPayload(row));
    });
  }

  @override
  Future<void> deleteBudget(String id) => _db.transaction(() async {
    final now = DateTime.now().toUtc();
    final n = await (_db.update(_db.budgets)..where((b) => b.id.equals(id) & b.deletedAt.isNull())).write(
      BudgetsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
    if (n > 0) await _db.syncDao.enqueue(EntityType.budget, id, 'delete', const {});
  });

  Future<void> _validate(Budget b) async {
    if (b.name.isEmpty || b.name.length > 50) throw const ValidationException('Name must be 1–50 characters');
    if (b.amountMinor <= 0) throw const ValidationException('Limit must be greater than zero');
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(b.currencyCode)) throw const ValidationException('Invalid currency');
    if (!_date.hasMatch(b.periodStart) || !_date.hasMatch(b.periodEnd)) throw const ValidationException('Invalid date');
    if (b.periodEnd.compareTo(b.periodStart) < 0) throw const ValidationException('End date is before start date');
    if (b.categoryId != null) {
      final cat = await (_db.select(_db.categories)..where((c) => c.id.equals(b.categoryId!))).getSingleOrNull();
      if (cat == null || cat.type != 'expense' || cat.workspace != b.workspace) {
        throw const ValidationException('Budget category must be an expense category');
      }
    }
  }
}

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../database/app_database.dart';
import '../../../database/server_rows.dart';
import '../domain/transaction_repository.dart';

class DriftTransactionRepository implements TransactionRepository {
  DriftTransactionRepository(this._db, this._userId);

  final AppDatabase _db;
  final String Function() _userId;

  static const _uuid = Uuid();
  static final _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  @override
  Stream<List<TransactionRow>> watchTransactions(TransactionFilter f) {
    final q = _db.select(_db.transactions)..where((t) => t.deletedAt.isNull());
    if (f.from != null) q.where((t) => t.transactionDate.isBiggerOrEqualValue(f.from!));
    if (f.to != null) q.where((t) => t.transactionDate.isSmallerOrEqualValue(f.to!));
    if (f.categoryId != null) q.where((t) => t.categoryId.equals(f.categoryId!));
    if (f.type != null) q.where((t) => t.type.equals(f.type!));
    if (f.search != null && f.search!.trim().isNotEmpty) {
      q.where((t) => t.description.like('%${f.search!.trim()}%'));
    }
    q.orderBy([(t) => OrderingTerm.desc(t.transactionDate), (t) => OrderingTerm.desc(t.createdAt)]);
    if (f.limit != null) q.limit(f.limit!);
    return q.watch();
  }

  @override
  Future<TransactionRow?> getTransactionById(String id) =>
      (_db.select(_db.transactions)..where((t) => t.id.equals(id))).getSingleOrNull();

  @override
  Future<TransactionRow> createTransaction({
    required String type,
    required int amountMinor,
    required String currencyCode,
    required String transactionDate,
    String? categoryId,
    String description = '',
  }) async {
    final now = DateTime.now().toUtc();
    final row = TransactionRow(
      id: _uuid.v4(),
      userId: _userId(),
      workspace: 'personal',
      categoryId: categoryId,
      type: type,
      amountMinor: amountMinor,
      currencyCode: currencyCode,
      description: description.trim(),
      transactionDate: transactionDate,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      version: 0,
      changeSeq: 0,
    );
    await _validate(row, isNew: true);
    await _db.transaction(() async {
      await _db.into(_db.transactions).insert(row);
      await _db.syncDao.enqueue(EntityType.transaction, row.id, 'create', ServerRows.transactionPayload(row));
    });
    return row;
  }

  @override
  Future<void> updateTransaction(TransactionRow t) async {
    final row = t.copyWith(description: t.description.trim(), updatedAt: DateTime.now().toUtc());
    await _validate(row, isNew: false);
    await _db.transaction(() async {
      // version/change_seq stay as last acked by the server
      await (_db.update(_db.transactions)..where((x) => x.id.equals(row.id))).write(
        TransactionsCompanion(
          categoryId: Value(row.categoryId),
          type: Value(row.type),
          amountMinor: Value(row.amountMinor),
          currencyCode: Value(row.currencyCode),
          description: Value(row.description),
          transactionDate: Value(row.transactionDate),
          updatedAt: Value(row.updatedAt),
        ),
      );
      await _db.syncDao.enqueue(EntityType.transaction, row.id, 'update', ServerRows.transactionPayload(row));
    });
  }

  @override
  Future<void> deleteTransaction(String id) => _db.transaction(() async {
    final now = DateTime.now().toUtc();
    final n = await (_db.update(_db.transactions)..where((t) => t.id.equals(id) & t.deletedAt.isNull())).write(
      TransactionsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
    if (n > 0) await _db.syncDao.enqueue(EntityType.transaction, id, 'delete', const {});
  });

  @override
  Stream<MoneySummary> watchSummary({String? from, String? to}) {
    final where = StringBuffer('deleted_at IS NULL');
    final vars = <Variable>[];
    if (from != null) {
      where.write(' AND transaction_date >= ?');
      vars.add(Variable.withString(from));
    }
    if (to != null) {
      where.write(' AND transaction_date <= ?');
      vars.add(Variable.withString(to));
    }
    return _db
        .customSelect(
          'SELECT type, currency_code, SUM(amount_minor) AS total FROM transactions '
          'WHERE $where GROUP BY type, currency_code',
          variables: vars,
          readsFrom: {_db.transactions},
        )
        .watch()
        .map((rows) {
          final income = <String, int>{}, expense = <String, int>{};
          for (final r in rows) {
            (r.read<String>('type') == 'income' ? income : expense)[r.read<String>('currency_code')] = r.read<int>(
              'total',
            );
          }
          return MoneySummary(income: income, expense: expense);
        });
  }

  Future<void> _validate(TransactionRow t, {required bool isNew}) async {
    if (t.type != 'income' && t.type != 'expense') throw const ValidationException('Type must be income or expense');
    if (t.amountMinor <= 0) throw const ValidationException('Amount must be greater than zero');
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(t.currencyCode)) throw const ValidationException('Invalid currency');
    if (!_date.hasMatch(t.transactionDate) || DateTime.tryParse(t.transactionDate) == null) {
      throw const ValidationException('Invalid date');
    }
    if (t.description.length > 500) throw const ValidationException('Description is too long');
    if (t.categoryId != null) {
      final cat = await (_db.select(_db.categories)..where((c) => c.id.equals(t.categoryId!))).getSingleOrNull();
      if (cat == null) throw const ValidationException('Unknown category');
      if (cat.type != t.type) throw const ValidationException('Category type does not match');
      if (isNew && cat.deletedAt != null) throw const ValidationException('Category is archived');
    }
  }
}

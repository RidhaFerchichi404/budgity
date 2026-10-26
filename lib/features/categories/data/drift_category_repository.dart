import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../database/app_database.dart';
import '../../../database/server_rows.dart';
import '../../../core/errors/validation_exception.dart';
import '../domain/category_repository.dart';

class DriftCategoryRepository implements CategoryRepository {
  /// Reads and creates are scoped to [workspace] (ADR 0006).
  DriftCategoryRepository(this._db, this._userId, {this.workspace = 'personal'});

  final AppDatabase _db;
  final String Function() _userId;
  final String workspace;

  static const _uuid = Uuid();

  @override
  Stream<List<Category>> watchCategories({String? type, bool includeArchived = false}) {
    final q = _db.select(_db.categories)..where((c) => c.workspace.equals(workspace));
    if (!includeArchived) q.where((c) => c.deletedAt.isNull());
    if (type != null) q.where((c) => c.type.equals(type));
    q.orderBy([(c) => OrderingTerm.asc(c.type), (c) => OrderingTerm.asc(c.sortOrder), (c) => OrderingTerm.asc(c.name)]);
    return q.watch();
  }

  @override
  Future<Category> createCategory({required String name, required String type, String iconKey = 'tag'}) async {
    final now = DateTime.now().toUtc();
    final row = Category(
      id: _uuid.v4(),
      userId: _userId(),
      workspace: workspace,
      name: name.trim(),
      type: type,
      iconKey: iconKey,
      sortOrder: 100,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      version: 0,
      changeSeq: 0,
    );
    _validate(row);
    await _db.transaction(() async {
      await _db.into(_db.categories).insert(row);
      await _db.syncDao.enqueue(EntityType.category, row.id, 'create', ServerRows.categoryPayload(row));
    });
    return row;
  }

  @override
  Future<void> updateCategory(Category c) async {
    final row = c.copyWith(name: c.name.trim(), updatedAt: DateTime.now().toUtc());
    _validate(row);
    await _db.transaction(() async {
      await (_db.update(_db.categories)..where((x) => x.id.equals(row.id))).write(
        CategoriesCompanion(
          name: Value(row.name),
          iconKey: Value(row.iconKey),
          sortOrder: Value(row.sortOrder),
          updatedAt: Value(row.updatedAt),
        ),
      );
      await _db.syncDao.enqueue(EntityType.category, row.id, 'update', ServerRows.categoryPayload(row));
    });
  }

  @override
  Future<void> archiveCategory(String id) => _db.transaction(() async {
    final now = DateTime.now().toUtc();
    final n = await (_db.update(_db.categories)..where((c) => c.id.equals(id) & c.deletedAt.isNull())).write(
      CategoriesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
    if (n > 0) await _db.syncDao.enqueue(EntityType.category, id, 'delete', const {});
  });

  void _validate(Category c) {
    if (c.name.isEmpty || c.name.length > 50) throw const ValidationException('Name must be 1–50 characters');
    if (c.type != 'income' && c.type != 'expense') throw const ValidationException('Type must be income or expense');
    if (!categoryIconKeys.contains(c.iconKey)) throw const ValidationException('Unknown icon');
  }
}

import '../../../database/app_database.dart';

export '../../../database/app_database.dart' show Category;

/// Icon keys shared with the server-side defaults (supabase/migrations/*_signup.sql).
const categoryIconKeys = [
  'tag', 'salary', 'gift', 'cart', 'home', 'car', 'restaurant', 'bolt', 'health', 'movie', //
  'book', 'school', 'travel', 'phone', 'pet', 'sport', 'clothes', 'savings',
];

abstract interface class CategoryRepository {
  /// Active categories, optionally of one [type]. Archived ones are included
  /// only with [includeArchived] (needed to label old transactions).
  Stream<List<Category>> watchCategories({String? type, bool includeArchived = false});

  Future<Category> createCategory({required String name, required String type, String iconKey = 'tag'});

  /// Type is immutable once created; existing transactions depend on it.
  Future<void> updateCategory(Category category);

  /// Soft delete; transactions keep pointing at it.
  Future<void> archiveCategory(String id);
}

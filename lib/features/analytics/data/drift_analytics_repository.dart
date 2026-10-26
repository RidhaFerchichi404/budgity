import 'package:drift/drift.dart';

import '../../../database/app_database.dart';
import '../domain/analytics_repository.dart';

class DriftAnalyticsRepository implements AnalyticsRepository {
  DriftAnalyticsRepository(this._db, {this.workspace = 'personal'});

  final AppDatabase _db;
  final String workspace;

  @override
  Stream<List<MonthFlow>> watchMonthlyFlow({required String currency, required String lastMonth, int months = 6}) {
    final keys = [for (var i = months - 1; i >= 0; i--) addMonths(lastMonth, -i)];
    return _db
        .customSelect(
          'SELECT substr(transaction_date, 1, 7) AS month, type, SUM(amount_minor) AS total FROM transactions '
          'WHERE deleted_at IS NULL AND workspace = ? AND currency_code = ? '
          'AND transaction_date >= ? AND transaction_date < ? GROUP BY month, type',
          variables: [
            Variable.withString(workspace),
            Variable.withString(currency),
            Variable.withString('${keys.first}-01'),
            Variable.withString('${addMonths(lastMonth, 1)}-01'),
          ],
          readsFrom: {_db.transactions},
        )
        .watch()
        .map((rows) {
          final income = <String, int>{}, expense = <String, int>{};
          for (final r in rows) {
            (r.read<String>('type') == 'income' ? income : expense)[r.read<String>('month')] = r.read<int>('total');
          }
          return [for (final k in keys) MonthFlow(k, incomeMinor: income[k] ?? 0, expenseMinor: expense[k] ?? 0)];
        });
  }

  @override
  Stream<List<CategorySpend>> watchCategorySpend({required String currency, required String month}) {
    final prev = addMonths(month, -1);
    return _db
        .customSelect(
          'SELECT category_id, '
          'SUM(CASE WHEN substr(transaction_date, 1, 7) = ? THEN amount_minor ELSE 0 END) AS cur, '
          'SUM(CASE WHEN substr(transaction_date, 1, 7) = ? THEN amount_minor ELSE 0 END) AS prev '
          'FROM transactions WHERE deleted_at IS NULL AND type = \'expense\' AND workspace = ? '
          'AND currency_code = ? AND transaction_date >= ? AND transaction_date < ? '
          'GROUP BY category_id HAVING cur > 0 ORDER BY cur DESC',
          variables: [
            Variable.withString(month),
            Variable.withString(prev),
            Variable.withString(workspace),
            Variable.withString(currency),
            Variable.withString('$prev-01'),
            Variable.withString('${addMonths(month, 1)}-01'),
          ],
          readsFrom: {_db.transactions},
        )
        .watch()
        .map(
          (rows) => [
            for (final r in rows)
              CategorySpend(
                r.readNullable<String>('category_id'),
                currentMinor: r.read<int>('cur'),
                previousMinor: r.read<int>('prev'),
              ),
          ],
        );
  }
}

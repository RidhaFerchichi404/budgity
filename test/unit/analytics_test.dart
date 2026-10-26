import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mybudget/app/providers.dart';
import 'package:mybudget/database/app_database.dart';
import 'package:mybudget/features/analytics/data/drift_analytics_repository.dart';
import 'package:mybudget/features/analytics/domain/analytics_repository.dart';
import 'package:mybudget/features/analytics/presentation/analytics_screen.dart';
import 'package:mybudget/features/analytics/presentation/charts.dart';
import 'package:mybudget/features/budgets/domain/budget_repository.dart';
import 'package:mybudget/features/categories/data/drift_category_repository.dart';
import 'package:mybudget/features/transactions/data/drift_transaction_repository.dart';

void main() {
  group('repository totals', () {
    late AppDatabase db;
    late DriftAnalyticsRepository analytics;
    late DriftTransactionRepository personal, freelance;
    late String food, rent;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      analytics = DriftAnalyticsRepository(db);
      personal = DriftTransactionRepository(db, () => 'u');
      freelance = DriftTransactionRepository(db, () => 'u', workspace: 'freelancer');
      final cats = DriftCategoryRepository(db, () => 'u');
      food = (await cats.createCategory(name: 'Food', type: 'expense')).id;
      rent = (await cats.createCategory(name: 'Rent', type: 'expense')).id;
      final freeCat = await DriftCategoryRepository(
        db,
        () => 'u',
        workspace: 'freelancer',
      ).createCategory(name: 'Software', type: 'expense');

      Future<void> add(String type, int minor, String date, {String cur = 'TND', String? cat}) => personal
          .createTransaction(type: type, amountMinor: minor, currencyCode: cur, transactionDate: date, categoryId: cat);
      await add('income', 3000000, '2026-10-01');
      await add('expense', 40000, '2026-10-03', cat: food);
      await add('expense', 10000, '2026-10-31', cat: food);
      await add('expense', 900000, '2026-10-05', cat: rent);
      await add('expense', 25000, '2026-10-06'); // uncategorized
      await add('expense', 40000, '2026-09-15', cat: food);
      await add('expense', 950000, '2026-09-02', cat: rent);
      await add('income', 2800000, '2026-08-01');
      await add('expense', 7000, '2026-10-07', cur: 'EUR', cat: food); // other currency
      await add('expense', 1, '2026-11-01', cat: food); // after the window
      final gone = await personal.createTransaction(
        type: 'expense',
        amountMinor: 999999,
        currencyCode: 'TND',
        transactionDate: '2026-10-10',
        categoryId: food,
      );
      await personal.deleteTransaction(gone.id);
      await freelance.createTransaction(
        type: 'expense',
        amountMinor: 555000,
        currencyCode: 'TND',
        transactionDate: '2026-10-04',
        categoryId: freeCat.id,
      );
    });

    tearDown(() => db.close());

    test('monthly flow: one currency, one workspace, live rows, zero-filled months', () async {
      final flows = await analytics.watchMonthlyFlow(currency: 'TND', lastMonth: '2026-10', months: 4).first;
      expect(flows.map((f) => f.month), ['2026-07', '2026-08', '2026-09', '2026-10']);
      expect(flows.map((f) => (f.incomeMinor, f.expenseMinor)), [(0, 0), (2800000, 0), (0, 990000), (3000000, 975000)]);
      expect(flows.last.netMinor, 2025000);
    });

    test('category spend: largest first, previous month, uncategorized, no zero rows', () async {
      final rows = await analytics.watchCategorySpend(currency: 'TND', month: '2026-10').first;
      expect(rows.map((r) => (r.categoryId, r.currentMinor, r.previousMinor)), [
        (rent, 900000, 950000),
        (food, 50000, 40000),
        (null, 25000, 0),
      ]);
      expect(rows.map((r) => r.changePercent), [-5, 25, null]);
    });

    test('freelancer analytics only sees freelancer rows', () async {
      final repo = DriftAnalyticsRepository(db, workspace: 'freelancer');
      expect(
        (await repo.watchMonthlyFlow(currency: 'TND', lastMonth: '2026-10', months: 1).first).single.expenseMinor,
        555000,
      );
      expect((await repo.watchCategorySpend(currency: 'TND', month: '2026-10').first).single.currentMinor, 555000);
    });
  });

  test('month arithmetic crosses years', () {
    expect(addMonths('2026-01', -1), '2025-12');
    expect(addMonths('2025-12', 1), '2026-01');
    expect(addMonths('2026-03', -14), '2025-01');
    expect(monthKey(DateTime(2026, 7, 31)), '2026-07');
  });

  test('axis ceiling lands on 1/2/5 steps', () {
    expect([0, 1, 7, 150, 2000, 3000001, 9500].map(niceCeiling), [0, 1, 10, 200, 2000, 5000000, 10000]);
  });

  group('budget pace', () {
    BudgetProgress progress(int spent) => BudgetProgress(
      Budget(
        id: 'b',
        userId: 'u',
        workspace: 'personal',
        name: 'Month',
        amountMinor: 3100,
        currencyCode: 'TND',
        periodStart: '2026-10-01',
        periodEnd: '2026-10-31',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        version: 1,
        changeSeq: 1,
      ),
      spent,
    );

    test('days left and projection inside the period', () {
      expect(progress(1000).daysLeft(DateTime(2026, 10, 10)), 22);
      expect(progress(1000).projectedMinor(DateTime(2026, 10, 10)), 3100); // 100/day × 31
      expect(progress(1000).daysLeft(DateTime(2026, 10, 31, 23, 59)), 1);
      expect(progress(1000).projectedMinor(DateTime(2026, 10, 31)), 1000);
    });

    test('nothing outside the period, and DST weekends count as whole days', () {
      expect(progress(1000).daysLeft(DateTime(2026, 9, 30)), isNull);
      expect(progress(1000).projectedMinor(DateTime(2026, 11, 1)), isNull);
      expect(progress(1000).daysLeft(DateTime(2026, 10, 26)), 6); // after the EU switch on Oct 25
    });
  });

  group('month stepping', () {
    ProviderContainer container() {
      final c = ProviderContainer(overrides: [todayProvider.overrideWithValue(DateTime(2026, 10, 26))]);
      addTearDown(c.dispose);
      return c;
    }

    test('starts on the current month and cannot go into the future', () {
      final c = container();
      expect(c.read(analyticsViewProvider), (windowEnd: '2026-10', selected: '2026-10'));
      c.read(analyticsViewProvider.notifier).step(1);
      expect(c.read(analyticsViewProvider).selected, '2026-10');
    });

    test('selecting inside the window keeps it; stepping past its start scrolls it', () {
      final c = container();
      final n = c.read(analyticsViewProvider.notifier)..select('2026-05');
      expect(c.read(analyticsViewProvider), (windowEnd: '2026-10', selected: '2026-05'));
      n.step(-1);
      expect(c.read(analyticsViewProvider), (windowEnd: '2026-09', selected: '2026-04'));
      n.step(1);
      expect(c.read(analyticsViewProvider), (windowEnd: '2026-09', selected: '2026-05'));
    });
  });
}

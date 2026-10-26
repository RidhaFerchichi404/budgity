// Renders key screens with real fonts + sample data for visual review.
// Regenerate: flutter test test/visual --update-goldens   (PNGs land in test/visual/goldens/)
@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mybudget/app/providers.dart';
import 'package:mybudget/app/theme/app_theme.dart';
import 'package:mybudget/database/app_database.dart';
import 'package:mybudget/features/auth/presentation/sign_in_screen.dart';
import 'package:mybudget/features/budgets/domain/budget_repository.dart';
import 'package:mybudget/features/budgets/presentation/budgets_screen.dart';
import 'package:mybudget/features/categories/presentation/categories_screen.dart';
import 'package:mybudget/features/dashboard/presentation/dashboard_screen.dart';
import 'package:mybudget/features/transactions/domain/transaction_repository.dart';
import 'package:mybudget/features/transactions/presentation/transactions_screen.dart';

final _now = DateTime(2026, 10, 26);

Category _cat(String id, String name, String type, String icon) => Category(
  id: id,
  userId: 'u',
  workspace: 'personal',
  name: name,
  type: type,
  iconKey: icon,
  sortOrder: 0,
  createdAt: _now,
  updatedAt: _now,
  version: 1,
  changeSeq: 1,
);

TransactionRow _tx(String id, String type, int minor, String date, String cat, String desc) => TransactionRow(
  id: id,
  userId: 'u',
  workspace: 'personal',
  categoryId: cat,
  type: type,
  amountMinor: minor,
  currencyCode: 'TND',
  description: desc,
  transactionDate: date,
  createdAt: _now,
  updatedAt: _now,
  version: 1,
  changeSeq: 1,
);

final _cats = {
  for (final c in [
    _cat('salary', 'Salary', 'income', 'salary'),
    _cat('groceries', 'Groceries', 'expense', 'cart'),
    _cat('rent', 'Rent', 'expense', 'home'),
    _cat('transport', 'Transport', 'expense', 'car'),
    _cat('food', 'Restaurants', 'expense', 'restaurant'),
  ])
    c.id: c,
};

final _txs = [
  _tx('1', 'expense', 48750, '2026-10-25', 'groceries', 'Carrefour weekly shop'),
  _tx('2', 'expense', 12000, '2026-10-24', 'transport', 'Metro card top-up'),
  _tx('3', 'expense', 36500, '2026-10-22', 'food', 'Dinner with friends'),
  _tx('4', 'income', 3200000, '2026-10-20', 'salary', 'October salary'),
  _tx('5', 'expense', 950000, '2026-10-02', 'rent', 'Apartment rent'),
];

Budget _budget(String id, String name, int limit, String? cat) => Budget(
  id: id,
  userId: 'u',
  workspace: 'personal',
  categoryId: cat,
  name: name,
  amountMinor: limit,
  currencyCode: 'TND',
  periodStart: '2026-10-01',
  periodEnd: '2026-10-31',
  createdAt: _now,
  updatedAt: _now,
  version: 1,
  changeSeq: 1,
);

final _budgets = [
  BudgetProgress(_budget('b1', 'Groceries', 400000, 'groceries'), 248750),
  BudgetProgress(_budget('b2', 'Eating out', 150000, 'food'), 136500),
  BudgetProgress(_budget('b3', 'Transport', 80000, 'transport'), 92000),
];

class _Tx implements TransactionRepository {
  @override
  Stream<List<TransactionRow>> watchTransactions(TransactionFilter f) =>
      Stream.value(f.limit == null ? _txs : _txs.take(f.limit!).toList());

  @override
  Stream<MoneySummary> watchSummary({String? from, String? to}) => Stream.value(
    from == null
        ? const MoneySummary(income: {'TND': 9600000}, expense: {'TND': 5212250})
        : const MoneySummary(income: {'TND': 3200000}, expense: {'TND': 1047250}),
  );

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Budgets implements BudgetRepository {
  @override
  Stream<List<BudgetProgress>> watchBudgets({String? onDate}) => Stream.value(_budgets);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> _loadFonts() async {
  final plex = FontLoader('IBMPlexSans');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    plex.addFont(Future.value(ByteData.sublistView(File('assets/fonts/IBMPlexSans-$w.ttf').readAsBytesSync())));
  }
  await plex.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      Future.value(
        ByteData.sublistView(
          File(
            '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytesSync(),
        ),
      ),
    );
  await icons.load();
}

Widget _frame(String title, Widget body, {Widget? fab}) => ProviderScope(
  overrides: [
    transactionRepositoryProvider.overrideWithValue(_Tx()),
    budgetRepositoryProvider.overrideWithValue(_Budgets()),
    categoriesByIdProvider.overrideWith((ref) => Stream.value(_cats)),
    currencyProvider.overrideWithValue('TND'),
  ],
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: Chip(avatar: Icon(Icons.cloud_done_outlined, size: 18), label: Text('Synced')),
          ),
        ],
      ),
      body: body,
      floatingActionButton: fab,
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.space_dashboard_outlined), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Activity'),
          NavigationDestination(icon: Icon(Icons.pie_chart_outline), label: 'Budgets'),
          NavigationDestination(icon: Icon(Icons.category_outlined), label: 'Categories'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    ),
  ),
);

void main() {
  setUpAll(_loadFonts);

  Future<void> shot(WidgetTester tester, String name, Widget w, {Size size = const Size(390, 844)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(w);
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
  }

  testWidgets('dashboard phone', (t) => shot(t, 'dashboard_phone', _frame('Dashboard', const DashboardScreen())));
  testWidgets(
    'dashboard desktop',
    (t) => shot(t, 'dashboard_desktop', _frame('Dashboard', const DashboardScreen()), size: const Size(1280, 860)),
  );
  testWidgets(
    'transactions phone',
    (t) => shot(t, 'transactions_phone', _frame('Activity', const TransactionsScreen())),
  );
  testWidgets('budgets phone', (t) => shot(t, 'budgets_phone', _frame('Budgets', const BudgetsScreen())));
  testWidgets(
    'sign in',
    (t) => shot(
      t,
      'sign_in',
      ProviderScope(
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildAppTheme(), home: const SignInScreen()),
      ),
    ),
  );
}

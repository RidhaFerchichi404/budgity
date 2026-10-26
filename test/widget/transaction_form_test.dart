import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mybudget/app/providers.dart';
import 'package:mybudget/features/categories/presentation/categories_screen.dart';
import 'package:mybudget/features/transactions/domain/transaction_repository.dart';
import 'package:mybudget/features/transactions/presentation/transaction_form_screen.dart';

class _RecordingRepo implements TransactionRepository {
  final created = <Map<String, Object?>>[];

  @override
  Future<TransactionRow> createTransaction({
    required String type,
    required int amountMinor,
    required String currencyCode,
    required String transactionDate,
    String? categoryId,
    String description = '',
  }) async {
    created.add({'type': type, 'amount': amountMinor, 'currency': currencyCode, 'description': description});
    final now = DateTime.now();
    return TransactionRow(
      id: 'x',
      userId: 'u',
      type: type,
      amountMinor: amountMinor,
      currencyCode: currencyCode,
      description: description,
      transactionDate: transactionDate,
      createdAt: now,
      updatedAt: now,
      version: 0,
      changeSeq: 0,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('validates precision and saves exact minor units', (tester) async {
    final repo = _RecordingRepo();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (c, _) => Scaffold(
            body: TextButton(onPressed: () => c.push('/new'), child: const Text('open')),
          ),
        ),
        GoRoute(path: '/new', builder: (_, _) => const TransactionFormScreen()),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transactionRepositoryProvider.overrideWithValue(repo),
          categoriesByIdProvider.overrideWith((ref) => Stream.value(const {})),
          currencyProvider.overrideWithValue('TND'),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final amount = find.widgetWithText(TextFormField, 'Amount');
    await tester.enterText(amount, '1.0005');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Up to 3 decimals'), findsOneWidget);
    expect(repo.created, isEmpty);

    await tester.enterText(amount, '12,5');
    await tester.enterText(find.widgetWithText(TextFormField, 'Description (optional)'), 'Market');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repo.created.single, {'type': 'expense', 'amount': 12500, 'currency': 'TND', 'description': 'Market'});
    expect(find.text('open'), findsOneWidget, reason: 'form closed after saving');
  });
}

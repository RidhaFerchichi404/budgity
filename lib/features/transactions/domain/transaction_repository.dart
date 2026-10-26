import '../../../database/app_database.dart';

export '../../../core/errors/validation_exception.dart';
export '../../../database/app_database.dart' show TransactionRow;

class TransactionFilter {
  const TransactionFilter({this.search, this.from, this.to, this.categoryId, this.type, this.limit});

  final String? search;

  /// Inclusive 'yyyy-MM-dd' bounds.
  final String? from;
  final String? to;
  final String? categoryId;
  final String? type;
  final int? limit;

  static const all = TransactionFilter();
}

/// Per-currency totals; amounts in different currencies are never combined.
class MoneySummary {
  const MoneySummary({required this.income, required this.expense});

  final Map<String, int> income;
  final Map<String, int> expense;

  Set<String> get currencies => {...income.keys, ...expense.keys};

  int net(String currency) => (income[currency] ?? 0) - (expense[currency] ?? 0);
}

abstract interface class TransactionRepository {
  Stream<List<TransactionRow>> watchTransactions(TransactionFilter filter);

  Future<TransactionRow?> getTransactionById(String id);

  Future<TransactionRow> createTransaction({
    required String type,
    required int amountMinor,
    required String currencyCode,
    required String transactionDate,
    String? categoryId,
    String description = '',
  });

  Future<void> updateTransaction(TransactionRow transaction);

  Future<void> deleteTransaction(String id);

  /// Totals for transactions dated within [from]..[to] (inclusive), or all time if null.
  Stream<MoneySummary> watchSummary({String? from, String? to});
}

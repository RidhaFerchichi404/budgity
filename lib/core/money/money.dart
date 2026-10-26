/// Exact money: integer minor units plus a currency. Never use doubles for amounts.
class Money implements Comparable<Money> {
  const Money(this.minor, this.currency);

  final int minor;
  final String currency;

  /// Minor-unit digits per ISO 4217. Unknown currencies default to 2.
  static const _exponents = {'TND': 3, 'EUR': 2, 'USD': 2, 'GBP': 2, 'CHF': 2, 'MAD': 2, 'DZD': 2, 'JPY': 0};

  static const supportedCurrencies = ['TND', 'EUR', 'USD', 'GBP', 'CHF', 'MAD', 'DZD', 'JPY'];

  static int exponentOf(String currency) => _exponents[currency] ?? 2;

  int get exponent => exponentOf(currency);

  /// Parses user input like "12", "12.5", "12,500" (comma = decimal separator).
  /// Returns null for anything that isn't a plain non-negative decimal with at
  /// most [exponent] fraction digits; we never round silently.
  static Money? tryParse(String input, String currency) {
    final s = input.trim().replaceAll(' ', '').replaceAll(',', '.');
    final m = RegExp(r'^(\d+)(?:\.(\d*))?$').firstMatch(s);
    if (m == null) return null;
    final exp = exponentOf(currency);
    final frac = m.group(2) ?? '';
    if (frac.length > exp) return null;
    final whole = m.group(1)!;
    if (whole.length > 13) return null; // keeps minor units far below 2^53
    final minor = int.parse(whole + frac.padRight(exp, '0'));
    return Money(minor, currency);
  }

  /// "1234.500" style, always with the currency's full precision, no grouping.
  String toDecimalString() {
    if (exponent == 0) return '$minor';
    final abs = minor.abs().toString().padLeft(exponent + 1, '0');
    final cut = abs.length - exponent;
    return '${minor < 0 ? '-' : ''}${abs.substring(0, cut)}.${abs.substring(cut)}';
  }

  /// Display form with thousands grouping, e.g. "1 234.500 TND".
  String format() {
    final dec = toDecimalString();
    final neg = dec.startsWith('-');
    final parts = (neg ? dec.substring(1) : dec).split('.');
    final grouped = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');
    return '${neg ? '-' : ''}$grouped${parts.length > 1 ? '.${parts[1]}' : ''} $currency';
  }

  Money operator +(Money other) {
    _same(other);
    return Money(minor + other.minor, currency);
  }

  Money operator -(Money other) {
    _same(other);
    return Money(minor - other.minor, currency);
  }

  Money operator -() => Money(-minor, currency);

  void _same(Money other) {
    if (other.currency != currency) {
      throw ArgumentError('Cannot combine $currency with ${other.currency}');
    }
  }

  @override
  int compareTo(Money other) {
    _same(other);
    return minor.compareTo(other.minor);
  }

  @override
  bool operator ==(Object other) => other is Money && other.minor == minor && other.currency == currency;

  @override
  int get hashCode => Object.hash(minor, currency);

  @override
  String toString() => format();
}

/// Sums amounts per currency; different currencies are never added together.
Map<String, int> sumByCurrency(Iterable<({int minor, String currency})> items) {
  final out = <String, int>{};
  for (final i in items) {
    out[i.currency] = (out[i.currency] ?? 0) + i.minor;
  }
  return out;
}

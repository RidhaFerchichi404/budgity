import 'package:flutter_test/flutter_test.dart';
import 'package:mybudget/core/money/money.dart';

void main() {
  test('parses respecting currency precision', () {
    expect(Money.tryParse('12.5', 'TND'), const Money(12500, 'TND'));
    expect(Money.tryParse('12,345', 'TND'), const Money(12345, 'TND'));
    expect(Money.tryParse('0.1', 'EUR'), const Money(10, 'EUR'));
    expect(Money.tryParse('7', 'JPY'), const Money(7, 'JPY'));
  });

  test('rejects input it would have to round', () {
    expect(Money.tryParse('1.005', 'EUR'), isNull);
    expect(Money.tryParse('1.0001', 'TND'), isNull);
    expect(Money.tryParse('-3', 'EUR'), isNull);
    expect(Money.tryParse('abc', 'EUR'), isNull);
    expect(Money.tryParse('', 'EUR'), isNull);
  });

  test('formats with full precision', () {
    expect(const Money(1234500, 'TND').toDecimalString(), '1234.500');
    expect(const Money(5, 'EUR').toDecimalString(), '0.05');
    expect(const Money(-5, 'EUR').toDecimalString(), '-0.05');
    expect(const Money(123456789, 'EUR').format(), '1 234 567.89 EUR');
  });

  test('exact arithmetic: 0.1 + 0.2 == 0.3', () {
    expect(Money.tryParse('0.1', 'EUR')! + Money.tryParse('0.2', 'EUR')!, Money.tryParse('0.3', 'EUR'));
  });

  test('never mixes currencies', () {
    expect(() => const Money(1, 'EUR') + const Money(1, 'TND'), throwsArgumentError);
    expect(
      sumByCurrency([(minor: 100, currency: 'EUR'), (minor: 2000, currency: 'TND'), (minor: 50, currency: 'EUR')]),
      {'EUR': 150, 'TND': 2000},
    );
  });
}

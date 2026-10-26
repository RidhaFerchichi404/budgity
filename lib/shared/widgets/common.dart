import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../core/money/money.dart';

/// Width at which layouts switch to desktop (rail + tables).
const wideBreakpoint = 840.0;

bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= wideBreakpoint;

final _isoDate = DateFormat('yyyy-MM-dd');

String isoDate(DateTime d) => _isoDate.format(d);

String prettyDate(String iso) => DateFormat.yMMMd().format(DateTime.parse(iso));

/// First and last day of [d]'s month as 'yyyy-MM-dd'.
(String, String) monthRange(DateTime d) =>
    (isoDate(DateTime(d.year, d.month, 1)), isoDate(DateTime(d.year, d.month + 1, 0)));

const categoryIcons = <String, IconData>{
  'tag': Icons.sell_outlined,
  'salary': Icons.payments_outlined,
  'gift': Icons.card_giftcard_outlined,
  'cart': Icons.shopping_cart_outlined,
  'home': Icons.home_outlined,
  'car': Icons.directions_car_outlined,
  'restaurant': Icons.restaurant_outlined,
  'bolt': Icons.bolt_outlined,
  'health': Icons.local_hospital_outlined,
  'movie': Icons.movie_outlined,
  'book': Icons.menu_book_outlined,
  'school': Icons.school_outlined,
  'travel': Icons.flight_outlined,
  'phone': Icons.phone_android_outlined,
  'pet': Icons.pets_outlined,
  'sport': Icons.sports_soccer_outlined,
  'clothes': Icons.checkroom_outlined,
  'savings': Icons.savings_outlined,
};

IconData categoryIcon(String? key) => categoryIcons[key] ?? Icons.sell_outlined;

/// Rounded-square category glyph; the shape reads as "ledger entry" rather than avatar.
class CategoryBadge extends StatelessWidget {
  const CategoryBadge({super.key, this.iconKey, this.income = false});

  final String? iconKey;
  final bool income;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: income ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(categoryIcon(iconKey), size: 20, color: income ? scheme.onPrimaryContainer : scheme.onSurfaceVariant),
    );
  }
}

/// Small uppercase section label used above groups of content.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        ?action,
      ],
    ),
  );
}

/// Amount with sign and income/expense color; screen readers get the words.
class AmountText extends StatelessWidget {
  const AmountText({super.key, required this.minor, required this.currency, this.type, this.style});

  final int minor;
  final String currency;

  /// 'income' / 'expense' to show a sign and color, null for a neutral amount.
  final String? type;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final finance = context.finance;
    final text = Money(minor, currency).format();
    final color = switch (type) {
      'income' => finance.income,
      'expense' => finance.expense,
      _ => null,
    };
    final sign = switch (type) {
      'income' => '+',
      'expense' => '−',
      _ => '',
    };
    return Semantics(
      label: '${type ?? 'amount'} $text',
      excludeSemantics: true,
      child: Text(
        '$sign$text',
        style: (style ?? const TextStyle()).copyWith(color: color, fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
}

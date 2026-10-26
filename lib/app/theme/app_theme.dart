import 'package:flutter/material.dart';

/// Money semantics that Material's ColorScheme has no slot for.
/// Contrast ratios are checked in test/unit/theme_contrast_test.dart.
@immutable
class FinanceColors extends ThemeExtension<FinanceColors> {
  const FinanceColors({
    required this.income,
    required this.expense,
    required this.warning,
    required this.over,
    required this.chartIncome,
    required this.chartExpense,
  });

  /// Money in. Expenses stay neutral on purpose: red is reserved for "over budget".
  final Color income;
  final Color expense;
  final Color warning;
  final Color over;

  /// Chart marks only, never text. A separate pair because the text colors fail as bars:
  /// near-white expense reads as gray and both sit above the dark lightness band.
  /// Validated with the dataviz palette checks against [AppPalette.surface].
  final Color chartIncome;
  final Color chartExpense;

  @override
  FinanceColors copyWith({
    Color? income,
    Color? expense,
    Color? warning,
    Color? over,
    Color? chartIncome,
    Color? chartExpense,
  }) => FinanceColors(
    income: income ?? this.income,
    expense: expense ?? this.expense,
    warning: warning ?? this.warning,
    over: over ?? this.over,
    chartIncome: chartIncome ?? this.chartIncome,
    chartExpense: chartExpense ?? this.chartExpense,
  );

  @override
  FinanceColors lerp(FinanceColors? other, double t) => other == null
      ? this
      : FinanceColors(
          income: Color.lerp(income, other.income, t)!,
          expense: Color.lerp(expense, other.expense, t)!,
          warning: Color.lerp(warning, other.warning, t)!,
          over: Color.lerp(over, other.over, t)!,
          chartIncome: Color.lerp(chartIncome, other.chartIncome, t)!,
          chartExpense: Color.lerp(chartExpense, other.chartExpense, t)!,
        );
}

extension FinanceTheme on BuildContext {
  FinanceColors get finance => Theme.of(this).extension<FinanceColors>()!;
}

/// "Evergreen" palette: green-tinted near-black neutrals, one emerald accent.
abstract final class AppPalette {
  static const background = Color(0xFF0B1210);
  static const surface = Color(0xFF111A17);
  static const surfaceHigh = Color(0xFF17221E);
  static const surfaceHighest = Color(0xFF1E2B26);
  static const outline = Color(0xFF2A3A34);
  static const onSurface = Color(0xFFE6EFEB);
  static const muted = Color(0xFF9BB0A7);
  static const primary = Color(0xFF3DD9A0);
  static const onPrimary = Color(0xFF032619);
  static const primaryContainer = Color(0xFF0F3B2C);
  static const onPrimaryContainer = Color(0xFFB4F3D8);
  static const secondary = Color(0xFF9CC9B6);
  static const income = Color(0xFF4ADE9A);
  static const warning = Color(0xFFF2C25B);
  static const over = Color(0xFFFF8A80);
  static const onOver = Color(0xFF3B0A06);
  static const chartIncome = Color(0xFF1FA874);
  static const chartExpense = Color(0xFF8A80E6);
}

ThemeData buildAppTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AppPalette.primary,
    onPrimary: AppPalette.onPrimary,
    primaryContainer: AppPalette.primaryContainer,
    onPrimaryContainer: AppPalette.onPrimaryContainer,
    secondary: AppPalette.secondary,
    onSecondary: AppPalette.onPrimary,
    secondaryContainer: AppPalette.surfaceHighest,
    onSecondaryContainer: AppPalette.onSurface,
    tertiary: AppPalette.warning,
    onTertiary: Color(0xFF2B1D00),
    error: AppPalette.over,
    onError: AppPalette.onOver,
    surface: AppPalette.surface,
    onSurface: AppPalette.onSurface,
    onSurfaceVariant: AppPalette.muted,
    surfaceContainerLowest: AppPalette.background,
    surfaceContainerLow: AppPalette.surface,
    surfaceContainer: AppPalette.surface,
    surfaceContainerHigh: AppPalette.surfaceHigh,
    surfaceContainerHighest: AppPalette.surfaceHighest,
    outline: AppPalette.outline,
    outlineVariant: AppPalette.outline,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'IBMPlexSans');
  final text = base.textTheme.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
  const radius = BorderRadius.all(Radius.circular(14));

  return base.copyWith(
    scaffoldBackgroundColor: AppPalette.background,
    textTheme: text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.5),
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.3),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant, letterSpacing: 0.2),
      bodySmall: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
    ),
    extensions: const [
      FinanceColors(
        income: AppPalette.income,
        expense: AppPalette.onSurface,
        warning: AppPalette.warning,
        over: AppPalette.over,
        chartIncome: AppPalette.chartIncome,
        chartExpense: AppPalette.chartExpense,
      ),
    ],
    appBarTheme: const AppBarTheme(
      backgroundColor: AppPalette.background,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    // Flat cards with a hairline border: calm, ledger-like, no glow.
    cardTheme: const CardThemeData(
      color: AppPalette.surface,
      elevation: 0,
      margin: EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: AppPalette.outline),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppPalette.outline, space: 1),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: AppPalette.surfaceHigh,
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: AppPalette.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: AppPalette.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: AppPalette.primary, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: const RoundedRectangleBorder(borderRadius: radius),
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        side: const BorderSide(color: AppPalette.outline),
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppPalette.primary,
      foregroundColor: AppPalette.onPrimary,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppPalette.surface,
      indicatorColor: AppPalette.primaryContainer,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStatePropertyAll(text.labelMedium?.copyWith(fontWeight: FontWeight.w500)),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: AppPalette.background,
      indicatorColor: AppPalette.primaryContainer,
      selectedIconTheme: IconThemeData(color: AppPalette.onPrimaryContainer),
      unselectedIconTheme: IconThemeData(color: AppPalette.muted),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppPalette.surface,
      selectedColor: AppPalette.primaryContainer,
      side: const BorderSide(color: AppPalette.outline),
      shape: const StadiumBorder(),
      labelStyle: text.labelLarge?.copyWith(color: AppPalette.onSurface),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppPalette.primary,
      linearTrackColor: AppPalette.surfaceHighest,
      borderRadius: BorderRadius.all(Radius.circular(4)),
    ),
    listTileTheme: const ListTileThemeData(iconColor: AppPalette.muted, minVerticalPadding: 10),
    dataTableTheme: DataTableThemeData(
      headingTextStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      dividerThickness: 1,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    dialogTheme: const DialogThemeData(
      backgroundColor: AppPalette.surfaceHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
    ),
  );
}

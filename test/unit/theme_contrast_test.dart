import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mybudget/app/theme/app_theme.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

void main() {
  // The dashboard hero paints primaryContainer at 35% over the page background.
  final hero = Color.alphaBlend(AppPalette.primaryContainer.withValues(alpha: 0.35), AppPalette.background);

  final textPairs = <String, (Color, Color)>{
    'body on background': (AppPalette.onSurface, AppPalette.background),
    'body on card': (AppPalette.onSurface, AppPalette.surface),
    'body on input/dialog': (AppPalette.onSurface, AppPalette.surfaceHigh),
    'muted on card': (AppPalette.muted, AppPalette.surface),
    'muted on input/dialog': (AppPalette.muted, AppPalette.surfaceHigh),
    'muted on badge': (AppPalette.muted, AppPalette.surfaceHighest),
    'income on card': (AppPalette.income, AppPalette.surface),
    'income on hero': (AppPalette.income, hero),
    'muted on hero': (AppPalette.muted, hero),
    'warning on card': (AppPalette.warning, AppPalette.surface),
    'over on card': (AppPalette.over, AppPalette.surface),
    'primary text on background': (AppPalette.primary, AppPalette.background),
    'button label on primary': (AppPalette.onPrimary, AppPalette.primary),
    'on primary container': (AppPalette.onPrimaryContainer, AppPalette.primaryContainer),
    'error button label': (AppPalette.onOver, AppPalette.over),
  };

  for (final MapEntry(key: name, value: (fg, bg)) in textPairs.entries) {
    test('$name ≥ 4.5:1', () => expect(contrast(fg, bg), greaterThanOrEqualTo(4.5)));
  }

  test('non-text: progress bar and focus ring ≥ 3:1 against their track/surface', () {
    expect(contrast(AppPalette.primary, AppPalette.surfaceHighest), greaterThanOrEqualTo(3));
    expect(contrast(AppPalette.primary, AppPalette.surfaceHigh), greaterThanOrEqualTo(3));
  });
}

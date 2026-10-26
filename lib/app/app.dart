import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme/app_theme.dart';

final _theme = buildAppTheme();

class BudgityApp extends ConsumerWidget {
  const BudgityApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'Budgity',
    debugShowCheckedModeBanner: false,
    // Dark-only by design (product decision); no light palette is maintained.
    theme: _theme,
    themeMode: ThemeMode.dark,
    routerConfig: ref.watch(routerProvider),
  );
}

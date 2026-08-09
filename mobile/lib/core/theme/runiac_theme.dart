import 'package:flutter/material.dart';

import 'runiac_colors.dart';

ThemeData buildRuniacTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: RuniacColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: RuniacColors.white,
      foregroundColor: RuniacColors.textPrimary,
      elevation: 0,
      surfaceTintColor: RuniacColors.white,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: RuniacColors.white,
      selectedItemColor: RuniacColors.primaryBlue,
      unselectedItemColor: RuniacColors.textSecondary,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: RuniacColors.primaryBlue,
        foregroundColor: RuniacColors.white,
      ),
    ),
  );
}

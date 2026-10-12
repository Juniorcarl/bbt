import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFF1F86C8);
  static const bg = Color(0xFFF3F8FD);
  static const ink = Color(0xFF14233A);
  static const muted = Color(0xFF7D8DA3);
  static const income = Color(0xFF2E9E6B);
  static const expense = Color(0xFF14233A);
}

ThemeData buildTheme() => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
      scaffoldBackgroundColor: AppColors.bg,
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: AppColors.primary.withValues(alpha: 0.12),
      ),
    );

import 'package:flutter/material.dart';

class AppTheme {
  static const cream = Color(0xFFF0E0FF);
  static const paper = Color(0xFFFFF8FF);
  static const sand = Color(0xFFD8B8FF);
  static const peach = Color(0xFFFFAACC);
  static const orange = Color(0xFFD040E0);
  static const brown = Color(0xFF2A0840);
  static const espresso = Color(0xFF140828);
  static const sage = Color(0xFFA0D8FF);
  static const mist = Color(0xFFF0E8FF);
  static const cardBorder = Color(0xFFD0A0F0);
  static const moss = Color(0xFF1060A0);
  static const gold = Color(0xFFFFB800);

  static const heroGradient = LinearGradient(
    colors: [Color(0xFFFF88BB), Color(0xFFDDB8FF), Color(0xFF88CCFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: orange,
      brightness: Brightness.light,
      primary: orange,
      surface: paper,
      secondary: sand,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: cream,
      appBarTheme: const AppBarTheme(
        backgroundColor: paper,
        foregroundColor: brown,
        elevation: 0,
        toolbarHeight: 72,
        centerTitle: true,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: paper,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        surfaceTintColor: paper,
        shadowColor: const Color(0x1C000000),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: paper,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        hintStyle: TextStyle(color: brown.withValues(alpha: 0.52)),
        labelStyle: TextStyle(color: brown.withValues(alpha: 0.72)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: orange, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: orange,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: brown,
          side: const BorderSide(color: cardBorder),
          backgroundColor: paper,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: paper,
        indicatorColor: peach,
        surfaceTintColor: paper,
        shadowColor: const Color(0x12000000),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: brown,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        behavior: SnackBarBehavior.floating,
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w800,
          color: brown,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: brown,
        ),
        bodyLarge: TextStyle(color: brown, fontSize: 16),
        bodyMedium: TextStyle(color: brown, fontSize: 14),
      ),
    );
  }
}

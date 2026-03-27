import 'package:flutter/material.dart';

class AppTheme {
  static const cream = Color(0xFFFFF7ED);
  static const sand = Color(0xFFF6E7D3);
  static const peach = Color(0xFFFFE5D2);
  static const orange = Color(0xFFE86E35);
  static const brown = Color(0xFF5A3828);
  static const sage = Color(0xFFDCEAD6);
  static const mist = Color(0xFFFDFCF9);
  static const cardBorder = Color(0xFFF0DDC6);

  static const heroGradient = LinearGradient(
    colors: [Color(0xFFFFE9D8), Color(0xFFF6ECD9), Color(0xFFE5F1DC)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: orange,
      brightness: Brightness.light,
      primary: orange,
      surface: Colors.white,
      secondary: peach,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: cream,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: brown,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        surfaceTintColor: Colors.white,
        shadowColor: const Color(0x14000000),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: mist,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        hintStyle: TextStyle(color: brown.withOpacity(0.52)),
        labelStyle: TextStyle(color: brown.withOpacity(0.72)),
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
        backgroundColor: Colors.white,
        indicatorColor: sand,
        surfaceTintColor: Colors.white,
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
          fontWeight: FontWeight.w700,
          color: brown,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: brown,
        ),
        bodyLarge: TextStyle(color: brown, fontSize: 16),
        bodyMedium: TextStyle(color: brown, fontSize: 14),
      ),
    );
  }
}

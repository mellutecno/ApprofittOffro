import 'package:flutter/material.dart';

class AppTheme {
  static const cream = Color(0xFFF6F0E7);
  static const paper = Color(0xFFFFFBF7);
  static const sand = Color(0xFFE6D8C8);
  static const peach = Color(0xFFD8A484);
  static const orange = Color(0xFFAD5A3C);
  static const brown = Color(0xFF49362D);
  static const espresso = Color(0xFF221914);
  static const sage = Color(0xFF96A182);
  static const mist = Color(0xFFF3E8DA);
  static const cardBorder = Color(0xFFD8C5AE);
  static const moss = Color(0xFF657353);
  static const gold = Color(0xFFD3A24E);
  static const berry = Color(0xFF6A4744);
  static const plum = Color(0xFF5E4A63);
  static const shadow = Color(0x18000000);

  static const heroGradient = LinearGradient(
    colors: [Color(0xFFF4E1CB), Color(0xFFD39573), Color(0xFF8F9882)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const accentGradient = LinearGradient(
    colors: [orange, berry],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const surfaceGradient = LinearGradient(
    colors: [Color(0xFFFFFCF9), Color(0xFFF4E9DC)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const elevatedSurfaceGradient = LinearGradient(
    colors: [Color(0xFFFFFBF7), Color(0xFFF0E2D4), Color(0xFFE9DDD1)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const softAccentGradient = LinearGradient(
    colors: [Color(0xFFF7E5D4), Color(0xFFE7D8CC)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: orange,
      secondary: sand,
      onPrimary: Colors.white,
      onSecondary: espresso,
      error: Color(0xFFB64C3A),
      onError: Colors.white,
      surface: paper,
      onSurface: espresso,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: cream,
      canvasColor: cream,
      appBarTheme: const AppBarTheme(
        backgroundColor: paper,
        foregroundColor: espresso,
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
        shadowColor: shadow,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFFF6EC),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        hintStyle: TextStyle(color: brown.withValues(alpha: 0.52)),
        labelStyle: TextStyle(color: brown.withValues(alpha: 0.74)),
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
          foregroundColor: espresso,
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
        indicatorColor: const Color(0xFFEED9CC),
        surfaceTintColor: paper,
        shadowColor: shadow,
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: berry,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        behavior: SnackBarBehavior.floating,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFFFF6EE),
        selectedColor: const Color(0xFFECD4C4),
        disabledColor: sand.withValues(alpha: 0.45),
        secondarySelectedColor: const Color(0xFFECD4C4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        labelStyle: const TextStyle(
          color: espresso,
          fontWeight: FontWeight.w700,
        ),
        secondaryLabelStyle: const TextStyle(
          color: espresso,
          fontWeight: FontWeight.w800,
        ),
        brightness: Brightness.light,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: cardBorder),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: cardBorder,
        thickness: 1,
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w800,
          color: espresso,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: espresso,
        ),
        titleMedium: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: espresso,
        ),
        bodyLarge: TextStyle(color: brown, fontSize: 16, height: 1.4),
        bodyMedium: TextStyle(color: brown, fontSize: 14, height: 1.35),
        bodySmall: TextStyle(color: brown, fontSize: 12.5, height: 1.3),
      ),
    );
  }
}

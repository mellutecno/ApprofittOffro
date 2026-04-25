import 'package:flutter/material.dart';

class AppTheme {
  /// Test palette switch:
  /// - true  => look "Music AI" (violet / blue neon style)
  /// - false => palette originale ApprofittOffro
  static const bool useMusicAiPalette = true;

  static const cream =
      useMusicAiPalette ? Color(0xFF080B12) : Color(0xFFF6F0E7);
  static const paper =
      useMusicAiPalette ? Color(0xFF0F1422) : Color(0xFFFFFBF7);
  static const sand = useMusicAiPalette ? Color(0xFF1A2336) : Color(0xFFE6D8C8);
  static const peach =
      useMusicAiPalette ? Color(0xFF222C44) : Color(0xFFD8A484);
  static const orange =
      useMusicAiPalette ? Color(0xFF755CFF) : Color(0xFFAD5A3C);
  static const brown =
      useMusicAiPalette ? Color(0xFFDDE5FF) : Color(0xFF49362D);
  static const espresso =
      useMusicAiPalette ? Color(0xFFF4F7FF) : Color(0xFF221914);
  static const sage = useMusicAiPalette ? Color(0xFF38CCFF) : Color(0xFF96A182);
  static const mist = useMusicAiPalette ? Color(0xFF121A2B) : Color(0xFFF3E8DA);
  static const cardBorder =
      useMusicAiPalette ? Color(0xFF2D3A59) : Color(0xFFD8C5AE);
  static const moss = useMusicAiPalette ? Color(0xFF49A5FF) : Color(0xFF657353);
  static const gold = useMusicAiPalette ? Color(0xFF9A7DFF) : Color(0xFFD3A24E);
  static const berry =
      useMusicAiPalette ? Color(0xFF4C37C9) : Color(0xFF6A4744);
  static const plum = useMusicAiPalette ? Color(0xFF6A4CFF) : Color(0xFF5E4A63);
  static const vividViolet =
      useMusicAiPalette ? Color(0xFFC94DFF) : Color(0xFF7A4EC7);
  static const shadow = Color(0x18000000);

  static const heroGradient = useMusicAiPalette
      ? LinearGradient(
          colors: [Color(0xFF121A31), Color(0xFF2A1F66), Color(0xFF154763)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        )
      : LinearGradient(
          colors: [Color(0xFFF4E1CB), Color(0xFFD39573), Color(0xFF8F9882)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );

  static const accentGradient = useMusicAiPalette
      ? LinearGradient(
          colors: [Color(0xFF7B63FF), Color(0xFF3DD0FF)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        )
      : LinearGradient(
          colors: [orange, berry],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        );

  static const surfaceGradient = useMusicAiPalette
      ? LinearGradient(
          colors: [Color(0xFF0F1422), Color(0xFF141C2E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        )
      : LinearGradient(
          colors: [Color(0xFFFFFCF9), Color(0xFFF4E9DC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );

  static const elevatedSurfaceGradient = useMusicAiPalette
      ? LinearGradient(
          colors: [Color(0xFF12192A), Color(0xFF172038), Color(0xFF1B2842)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        )
      : LinearGradient(
          colors: [Color(0xFFFFFBF7), Color(0xFFF0E2D4), Color(0xFFE9DDD1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );

  static const softAccentGradient = useMusicAiPalette
      ? LinearGradient(
          colors: [Color(0xFF1D2540), Color(0xFF202B49)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        )
      : LinearGradient(
          colors: [Color(0xFFF7E5D4), Color(0xFFE7D8CC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );

  static ThemeData light() {
    if (useMusicAiPalette) {
      return _musicAiDark();
    }

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
        indicatorColor: vividViolet.withValues(alpha: 0.32),
        surfaceTintColor: paper,
        shadowColor: vividViolet.withValues(alpha: 0.46),
        elevation: 14,
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? vividViolet : brown.withValues(alpha: 0.78),
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
            color: selected ? vividViolet : brown.withValues(alpha: 0.82),
          );
        }),
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

  static ThemeData _musicAiDark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: orange,
      secondary: sage,
      onPrimary: Colors.white,
      onSecondary: Colors.black,
      error: Color(0xFFFF6B88),
      onError: Colors.black,
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
        surfaceTintColor: Colors.transparent,
        shadowColor: const Color(0x44000000),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: sand,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        hintStyle: TextStyle(color: brown.withValues(alpha: 0.64)),
        labelStyle: TextStyle(color: brown.withValues(alpha: 0.82)),
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
        indicatorColor: vividViolet.withValues(alpha: 0.34),
        surfaceTintColor: Colors.transparent,
        shadowColor: vividViolet.withValues(alpha: 0.55),
        elevation: 16,
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? vividViolet : brown.withValues(alpha: 0.86),
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
            color: selected ? vividViolet : brown.withValues(alpha: 0.9),
          );
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF2B3552),
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        behavior: SnackBarBehavior.floating,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: sand,
        selectedColor: const Color(0xFF2A3350),
        disabledColor: sand.withValues(alpha: 0.45),
        secondarySelectedColor: const Color(0xFF2A3350),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        labelStyle: const TextStyle(
          color: espresso,
          fontWeight: FontWeight.w700,
        ),
        secondaryLabelStyle: const TextStyle(
          color: espresso,
          fontWeight: FontWeight.w800,
        ),
        brightness: Brightness.dark,
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

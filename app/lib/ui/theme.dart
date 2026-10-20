import 'package:flutter/material.dart';

import 'widgets/motion.dart';

/// Клубный стиль: чёрный фон, красный акцент, узкий спортивный шрифт для заголовков.
/// Интерфейс тёмный всегда — так задумано айдентикой и так лучше читается на поле вечером.
class AppBrand {
  static const appName = 'CoachPilot';

  /// Название клуба задаётся при сборке: --dart-define=CLUB_NAME="ФК ..."
  static const clubName = String.fromEnvironment('CLUB_NAME', defaultValue: 'ФК Амкар');
}

class AppColors {
  static const red = Color(0xFFE30613);
  static const redDeep = Color(0xFF3A0A0D);
  static const black = Color(0xFF0B0B0C);
  static const surface = Color(0xFF141416);
  static const surfaceHigh = Color(0xFF1C1C1F);
  static const surfaceHighest = Color(0xFF26262A);
  static const outline = Color(0xFF3A3A40);
  static const text = Color(0xFFF4F4F5);
  static const textMuted = Color(0xFFA1A1AA);
  static const good = Color(0xFF4CD27A);
  static const warn = Color(0xFFFFA726);
}

class AppTheme {
  static const display = 'Oswald';

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: AppColors.red,
      onPrimary: Colors.white,
      primaryContainer: AppColors.redDeep,
      onPrimaryContainer: Color(0xFFFFD9DB),
      secondary: Colors.white,
      onSecondary: AppColors.black,
      secondaryContainer: AppColors.surfaceHighest,
      onSecondaryContainer: AppColors.text,
      tertiary: Color(0xFFFF8A80),
      tertiaryContainer: Color(0xFF2A1416),
      onTertiaryContainer: Color(0xFFFFDAD6),
      error: Color(0xFFFF5A5F),
      surface: AppColors.black,
      onSurface: AppColors.text,
      onSurfaceVariant: AppColors.textMuted,
      surfaceContainerLowest: AppColors.black,
      surfaceContainerLow: AppColors.surface,
      surfaceContainer: AppColors.surfaceHigh,
      surfaceContainerHigh: AppColors.surfaceHigh,
      surfaceContainerHighest: AppColors.surfaceHighest,
      outline: AppColors.outline,
      outlineVariant: Color(0xFF2A2A2F),
    );
    final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: Brightness.dark);
    final text = base.textTheme.copyWith(
      headlineLarge: base.textTheme.headlineLarge?.copyWith(fontFamily: display, fontWeight: FontWeight.w700),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(fontFamily: display, fontWeight: FontWeight.w700),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(fontFamily: display, fontWeight: FontWeight.w600),
      titleLarge: base.textTheme.titleLarge?.copyWith(fontFamily: display, fontWeight: FontWeight.w600, letterSpacing: 0.3),
      titleMedium: base.textTheme.titleMedium?.copyWith(fontFamily: display, fontWeight: FontWeight.w500, letterSpacing: 0.3),
      labelLarge: base.textTheme.labelLarge?.copyWith(fontFamily: display, fontWeight: FontWeight.w600, letterSpacing: 0.6),
    );
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
    const transitions = FadeSlidePageTransitionsBuilder();
    return base.copyWith(
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: transitions,
        TargetPlatform.iOS: transitions,
        TargetPlatform.macOS: transitions,
        TargetPlatform.windows: transitions,
        TargetPlatform.linux: transitions,
        TargetPlatform.fuchsia: transitions,
      }),
      scaffoldBackgroundColor: AppColors.black,
      textTheme: text,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        backgroundColor: AppColors.black,
        foregroundColor: AppColors.text,
        surfaceTintColor: Colors.transparent,
        // Красная линия под шапкой — фирменный элемент.
        shape: Border(bottom: BorderSide(color: AppColors.red, width: 2)),
        titleTextStyle: TextStyle(
          fontFamily: display,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: AppColors.text,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.red,
        surfaceTintColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? Colors.white : AppColors.textMuted),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontFamily: display,
            fontSize: 12,
            letterSpacing: 0.4,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? Colors.white : AppColors.textMuted,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          textStyle: const TextStyle(fontFamily: display, fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: 0.6),
          shape: shape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          foregroundColor: AppColors.text,
          side: const BorderSide(color: AppColors.outline),
          textStyle: const TextStyle(fontFamily: display, fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: 0.5),
          shape: shape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFFFF4D57),
          textStyle: const TextStyle(fontFamily: display, fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: 0.4),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.red,
        foregroundColor: Colors.white,
        shape: shape,
        extendedTextStyle: const TextStyle(fontFamily: display, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceHigh,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.outline)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.outline)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.red, width: 2)),
        floatingLabelStyle: const TextStyle(color: Color(0xFFFF4D57)),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.surfaceHigh,
        selectedColor: AppColors.redDeep,
        side: const BorderSide(color: AppColors.outline),
        checkmarkColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.red : AppColors.surface),
          foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : AppColors.text),
          side: const WidgetStatePropertyAll(BorderSide(color: AppColors.outline)),
          textStyle: const WidgetStatePropertyAll(TextStyle(fontFamily: display, fontWeight: FontWeight.w500, letterSpacing: 0.4)),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFF232327)),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFF232327)),
      sliderTheme: base.sliderTheme.copyWith(activeTrackColor: AppColors.red, thumbColor: AppColors.red),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.surfaceHighest,
        contentTextStyle: TextStyle(color: AppColors.text),
        behavior: SnackBarBehavior.floating,
      ),
      listTileTheme: const ListTileThemeData(minVerticalPadding: 12, iconColor: AppColors.textMuted),
    );
  }
}

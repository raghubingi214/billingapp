import 'package:flutter/material.dart';

abstract final class AppTheme {
  // Stitch Design System - Obsidian & Electric Blue SuperAdmin Palette
  static const darkBackground = Color(0xff0a0e17);
  static const darkSurface = Color(0xff0f131c);
  static const darkCard = Color(0xff1c1f29);
  static const darkCardHigh = Color(0xff262a34);
  static const darkBorder = Color(0xff31353f);
  static const darkBorderSubtle = Color(0xff434655);

  static const navy = Color(0xff0f172a);
  static const blue = Color(0xff2563eb);
  static const electricBlue = Color(0xff3b82f6);
  static const sapphire = Color(0xff3b82f6);
  static const lightBlue = Color(0xffb4c5ff);
  static const emerald = Color(0xff10b981);
  static const neonMint = Color(0xff4edea3);
  static const amber = Color(0xfff59e0b);
  static const rose = Color(0xfff43f5e);
  static const textWhite = Color(0xffdfe2ef);
  static const textMuted = Color(0xff8d90a0);

  static ThemeData get light {
    final scheme = const ColorScheme.dark().copyWith(
      primary: blue,
      onPrimary: Colors.white,
      secondary: lightBlue,
      onSecondary: Color(0xff002a78),
      tertiary: emerald,
      onTertiary: Colors.white,
      error: rose,
      onError: Colors.white,
      surface: darkSurface,
      onSurface: textWhite,
      surfaceContainerLowest: darkBackground,
      surfaceContainer: darkCard,
      surfaceContainerHigh: darkCardHigh,
      surfaceContainerHighest: darkBorder,
      outline: textMuted,
      outlineVariant: darkBorder,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: darkBackground,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        foregroundColor: textWhite,
        backgroundColor: darkBackground,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: textWhite,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xff181b25),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: blue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: rose, width: 1.5),
        ),
        labelStyle: const TextStyle(
          fontSize: 14,
          color: textMuted,
          fontWeight: FontWeight.w500,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: blue,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          elevation: 2,
          shadowColor: blue.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: lightBlue,
          side: const BorderSide(color: darkBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: darkBorder, width: 1),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: darkBackground,
        indicatorColor: blue.withValues(alpha: 0.22),
        elevation: 4,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: lightBlue,
            );
          }
          return const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: textMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: lightBlue, size: 24);
          }
          return const IconThemeData(color: textMuted, size: 24);
        }),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: blue,
        foregroundColor: Colors.white,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: darkCard,
        selectedColor: blue.withValues(alpha: 0.2),
        side: const BorderSide(color: darkBorder),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9999),
        ),
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: textWhite,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: darkBorder,
        thickness: 1,
        space: 24,
      ),
      listTileTheme: const ListTileThemeData(
        textColor: textWhite,
        iconColor: lightBlue,
        subtitleTextStyle: TextStyle(
          fontSize: 13,
          color: textMuted,
        ),
      ),
    );
  }
}

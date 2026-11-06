import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const navy = Color(0xff152b49);
  static const blue = Color(0xff2563eb);
  static const teal = Color(0xff0d9488);

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(seedColor: blue).copyWith(
      primary: blue,
      secondary: teal,
      onSurface: navy,
      surface: const Color(0xfff7f9fc),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        foregroundColor: navy,
        backgroundColor: Color(0xfff7f9fc),
        scrolledUnderElevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xffcbd5e1)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xffe2e8f0)),
        ),
      ),
    );
  }
}

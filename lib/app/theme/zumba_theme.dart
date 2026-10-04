import 'package:flutter/material.dart';

abstract final class ZumbaTheme {
  static const _magenta = Color(0xFFE91E8C);
  static const _purple = Color(0xFF5A248A);
  static const _lime = Color(0xFFB7E432);
  static const _orange = Color(0xFFFFA726);

  static ThemeData get light => _buildTheme(
        brightness: Brightness.light,
        background: const Color(0xFFFFF8FC),
        surface: Colors.white,
        foreground: const Color(0xFF25162D),
      );

  static ThemeData get dark => _buildTheme(
        brightness: Brightness.dark,
        background: const Color(0xFF17131B),
        surface: const Color(0xFF241D2A),
        foreground: const Color(0xFFFFF7FC),
      );

  static ThemeData _buildTheme({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color foreground,
  }) {
    final colors = ColorScheme.fromSeed(
      seedColor: _magenta,
      brightness: brightness,
      primary: _magenta,
      secondary: _orange,
      tertiary: _lime,
      surface: surface,
      onSurface: foreground,
    ).copyWith(
      primary: _magenta,
      secondary: _orange,
      tertiary: _lime,
      surface: surface,
      onSurface: foreground,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colors,
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: foreground,
        centerTitle: false,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: brightness == Brightness.dark ? 2 : 1,
        shadowColor: brightness == Brightness.dark
            ? _magenta.withValues(alpha: 0.24)
            : _purple.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      textTheme: ThemeData(brightness: brightness).textTheme.apply(
            bodyColor: foreground,
            displayColor: foreground,
          ),
    );
  }
}

import 'package:flutter/material.dart';

abstract final class ZumbaTheme {
  static const _magenta = Color(0xFFF500A8);
  static const _purple = Color(0xFF7200C8);
  static const _lime = Color(0xFFC6FF00);
  static const _orange = Color(0xFFFF8A00);

  static ThemeData get light => _buildTheme(
    brightness: Brightness.light,
    surface: Colors.white,
    foreground: const Color(0xFF25162D),
  );

  static ThemeData get dark => _buildTheme(
    brightness: Brightness.dark,
    surface: const Color(0xFF241D2A),
    foreground: const Color(0xFFFFF7FC),
  );

  static ThemeData _buildTheme({
    required Brightness brightness,
    required Color surface,
    required Color foreground,
  }) {
    final colors =
        ColorScheme.fromSeed(
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
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: foreground,
        centerTitle: false,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: surface.withValues(
          alpha: brightness == Brightness.dark ? .91 : .94,
        ),
        elevation: brightness == Brightness.dark ? 2 : 1,
        shadowColor: brightness == Brightness.dark
            ? _magenta.withValues(alpha: 0.24)
            : _purple.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface.withValues(alpha: .96),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textTheme: ThemeData(brightness: brightness).textTheme
          .apply(bodyColor: foreground, displayColor: foreground),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
}

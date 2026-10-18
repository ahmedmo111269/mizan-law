import 'package:flutter/material.dart';

abstract final class MizanTheme {
  static const Color _petrol = Color(0xFF125E60);
  static const Color _background = Color(0xFFF5F4F0);
  static const Color _ink = Color(0xFF182C30);
  static const Color _secondary = Color(0xFF52636A);
  static const Color _outline = Color(0xFF7A898D);
  static const Color _focus = Color(0xFF1B64B0);

  static final ThemeData light = _build(
    brightness: Brightness.light,
    background: _background,
    surface: Colors.white,
    foreground: _ink,
    secondary: _secondary,
    primary: _petrol,
    outline: _outline,
    focus: _focus,
  );

  static final ThemeData dark = _build(
    brightness: Brightness.dark,
    background: const Color(0xFF101C20),
    surface: const Color(0xFF17282D),
    foreground: const Color(0xFFE7EEEC),
    secondary: const Color(0xFFB2C1C3),
    primary: const Color(0xFF82CDC4),
    outline: const Color(0xFF6E858B),
    focus: const Color(0xFFA9D4FF),
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color foreground,
    required Color secondary,
    required Color primary,
    required Color outline,
    required Color focus,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
      surface: surface,
    ).copyWith(
      primary: primary,
      onPrimary: brightness == Brightness.light
          ? Colors.white
          : const Color(0xFF0F2625),
      surface: surface,
      onSurface: foreground,
      outline: outline,
      secondary: secondary,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      dividerColor: brightness == Brightness.light
          ? const Color(0xFFDDE4E2)
          : const Color(0xFF31454A),
      textTheme: Typography.material2021().black.apply(
        bodyColor: foreground,
        displayColor: foreground,
        fontFamily: null,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: foreground,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: foreground,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: outline.withValues(alpha: 0.72)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: focus, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFA33135), width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFA33135), width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          side: BorderSide(color: outline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: outline.withValues(alpha: 0.35)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: primary.withValues(alpha: brightness == Brightness.light ? 0.12 : 0.2),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
              fontSize: 12,
            )),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      focusColor: focus.withValues(alpha: 0.22),
    );
    return base.copyWith(
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: primary,
        selectionColor: primary.withValues(alpha: 0.24),
        selectionHandleColor: primary,
      ),
    );
  }
}

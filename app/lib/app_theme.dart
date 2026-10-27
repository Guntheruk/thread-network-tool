import 'package:flutter/material.dart';

// Neutral surfaces and a single interaction colour, following the Recursive
// Systems Elixir interface. Semantic colours remain separate from selection.
abstract final class ThreadColors {
  static const background = Color(0xFFFAF9F8);
  static const surface = Color(0xFFFFFFFF);
  static const subtle = Color(0xFFF3F2F1);
  static const border = Color(0xFFEDEBE9);
  static const ink = Color(0xFF201F1E);
  static const secondary = Color(0xFF605E5C);
  static const blue = Color(0xFF0F6CBD);
  static const blueSoft = Color(0xFFDEECF9);
  static const error = Color(0xFFC50F1F);
}

ThemeData threadTheme() {
  const shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(4)),
  );
  final base = ThemeData(
    useMaterial3: true,
    // Flutter's platform typography supplies Segoe UI on Windows and the
    // native system face on Apple platforms; no downloaded font is required.
    scaffoldBackgroundColor: ThreadColors.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: ThreadColors.blue,
      primary: ThreadColors.blue,
      onPrimary: Colors.white,
      primaryContainer: ThreadColors.blueSoft,
      onPrimaryContainer: ThreadColors.ink,
      secondary: ThreadColors.secondary,
      surface: ThreadColors.surface,
      onSurface: ThreadColors.ink,
      onSurfaceVariant: ThreadColors.secondary,
      surfaceContainerHighest: ThreadColors.subtle,
      outline: const Color(0xFF8A8886),
      outlineVariant: ThreadColors.border,
      error: ThreadColors.error,
    ),
  );
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium
          ?.copyWith(fontSize: 28, height: 1.2, fontWeight: FontWeight.w600),
      titleLarge: base.textTheme.titleLarge
          ?.copyWith(fontSize: 22, height: 1.25, fontWeight: FontWeight.w600),
      titleMedium: base.textTheme.titleMedium
          ?.copyWith(fontSize: 16, height: 1.35, fontWeight: FontWeight.w600),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 16, height: 1.45),
      bodyMedium:
          base.textTheme.bodyMedium?.copyWith(fontSize: 14, height: 1.45),
      bodySmall: base.textTheme.bodySmall
          ?.copyWith(fontSize: 12, height: 1.4, color: ThreadColors.secondary),
      labelLarge: base.textTheme.labelLarge
          ?.copyWith(fontSize: 14, height: 1.25, fontWeight: FontWeight.w600),
    ),
    cardTheme: const CardThemeData(
      margin: EdgeInsets.zero,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      color: ThreadColors.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: ThreadColors.border),
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: shape,
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: shape,
        side: const BorderSide(color: Color(0xFFD2D0CE)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 44),
        shape: shape,
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: ThreadColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: shape,
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: ThreadColors.subtle,
      side: BorderSide.none,
      shape: shape,
    ),
    dividerTheme: const DividerThemeData(
      color: ThreadColors.border,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
    ),
  );
}

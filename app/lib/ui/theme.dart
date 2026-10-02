import 'package:flutter/material.dart';

ThemeData buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final colors =
      ColorScheme.fromSeed(
        seedColor: const Color(0xff2455c6),
        brightness: brightness,
      ).copyWith(
        primary: dark ? const Color(0xff95b5ff) : const Color(0xff2455c6),
        onPrimary: dark ? const Color(0xff17243b) : Colors.white,
        surface: dark ? const Color(0xff101826) : const Color(0xfff5f7fb),
        surfaceContainerLow: dark ? const Color(0xff172235) : Colors.white,
        onSurface: dark ? const Color(0xffe5edf9) : const Color(0xff17243b),
        onSurfaceVariant: dark
            ? const Color(0xffa8b6cb)
            : const Color(0xff57657a),
        outlineVariant: dark
            ? const Color(0xff34445b)
            : const Color(0xffdbe2ec),
        primaryContainer: dark
            ? const Color(0xff243858)
            : const Color(0xffeaf0ff),
        onPrimaryContainer: dark
            ? const Color(0xffcaddff)
            : const Color(0xff2455c6),
      );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colors,
    scaffoldBackgroundColor: colors.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: colors.surface,
      foregroundColor: colors.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    dividerTheme: DividerThemeData(color: colors.outlineVariant, thickness: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.surfaceContainerLow,
      indicatorColor: colors.primaryContainer,
      height: 72,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colors.primary, width: 2),
      ),
    ),
  );
}

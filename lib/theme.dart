import 'package:flutter/material.dart';

/// Single source of truth for the app's colour palette.
///
/// Strategy:
///   • Brand colour — Deep Violet #6A1B9A
///   • Accent — Magenta #D81B60 (badges, pending indicators)
///   • Status/data colours (green=Present, amber=Leave, red=Absent) are preserved
///
/// Usage:
///   AppTheme.primary          — Deep Violet
///   AppTheme.accent           — Magenta
///   AppTheme.background       — light lavender page background
///   AppTheme.success/warning/danger — semantic data colours
abstract class AppTheme {
  // ── Brand palette ─────────────────────────────────────────────────────────

  static const Color primary      = Color(0xFF6A1B9A); // Deep Violet
  static const Color primaryDark  = Color(0xFF4A148C); // Darker shade for gradient
  static const Color primaryMid   = Color(0xFF7B1FA2); // Mid shade
  static const Color primaryLight = Color(0xFFAB47BC); // Light shade / gradient end
  static const Color accent       = Color(0xFFD81B60); // Magenta — badges, pending

  /// Light lavender page background
  static const Color background   = Color(0xFFF3E5F5);

  /// Pure-white card / tile surface
  static const Color surface      = Colors.white;

  // ── Semantic / status colours (kept for data-driven states) ─────────────

  static const Color success = Color(0xFF2E7D32); // Present · paid · ok
  static const Color warning = Color(0xFFF57F17); // Leave · pending · caution
  static const Color danger  = Color(0xFFC62828); // Absent · overdue · error

  // ── ThemeData ─────────────────────────────────────────────────────────────

  static ThemeData get light => ThemeData(
    useMaterial3: false,
    primaryColor: primary,
    primarySwatch: Colors.purple,
    scaffoldBackgroundColor: background,

    // AppBar: deep violet everywhere, no elevation
    appBarTheme: const AppBarTheme(
      backgroundColor: primary,
      foregroundColor: Colors.white,
      elevation: 0,
    ),

    // Elevated buttons: deep violet
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10))),
      ),
    ),

    // Outlined buttons: violet border + text
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        side: const BorderSide(color: primary),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10))),
      ),
    ),

    // Text buttons
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: primary),
    ),

    // FABs
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: Colors.white,
    ),

    // Inputs
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
      labelStyle: const TextStyle(color: Colors.black87),
      floatingLabelStyle: const TextStyle(color: primary),
    ),

    // Progress indicators
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),

    // Checkboxes
    checkboxTheme: CheckboxThemeData(
      fillColor: MaterialStateProperty.resolveWith((states) =>
          states.contains(MaterialState.selected) ? primary : null),
    ),

    // Dividers
    dividerColor: Color(0xFFE0E0E0),
    dividerTheme: const DividerThemeData(
      color: Color(0xFFE0E0E0), thickness: 1, space: 1),
  );
}

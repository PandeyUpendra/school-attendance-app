import 'package:flutter/material.dart';

/// Single source of truth for the app's colour palette.
///
/// Strategy:
///   • One brand colour everywhere — Deep Blue #1565C0
///   • Role-specific hues (red/indigo/teal/purple) are gone
///   • Status/data colours (green=Present, amber=Leave, red=Absent) are preserved
///
/// Usage:
///   AppTheme.primary          — the brand blue
///   AppTheme.background       — off-white page background
///   AppTheme.success/warning/danger — semantic data colours
abstract class AppTheme {
  // ── Brand palette ─────────────────────────────────────────────────────────

  static const Color primary      = Color(0xFF1565C0); // Deep Blue
  static const Color primaryDark  = Color(0xFF0D47A1); // Darker shade for gradient
  static const Color primaryMid   = Color(0xFF1976D2); // Mid shade
  static const Color primaryLight = Color(0xFF42A5F5); // Light shade / gradient end

  /// Off-white page background (instead of grey #F5F5F5 or pure white)
  static const Color background   = Color(0xFFF7F8FC);

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
    primarySwatch: Colors.blue,
    scaffoldBackgroundColor: background,

    // AppBar: deep blue everywhere, no elevation
    appBarTheme: const AppBarTheme(
      backgroundColor: primary,
      foregroundColor: Colors.white,
      elevation: 0,
    ),

    // Elevated buttons: deep blue
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10))),
      ),
    ),

    // Outlined buttons: blue border + text
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

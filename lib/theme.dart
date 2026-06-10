import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Single source of truth for the app's colour palette.
///
/// Strategy:
///   • One brand colour everywhere — Deep teal-green #003D33
///   • Sea-green accent for badges, CTAs, pending indicators
///   • Semantic colours (green=Present, amber=Leave, red=Absent) are preserved
///
/// Usage:
///   AppTheme.primary          — deep teal-green
///   AppTheme.accent           — sea green for badges & CTAs
///   AppTheme.background       — off-white page background
///   AppTheme.success/warning/danger — semantic data colours
abstract class AppTheme {
  // ── Brand palette ─────────────────────────────────────────────────────────

  static const Color primary      = Color(0xFF003D33); // Deep teal-green (brand)
  static const Color secondary    = Color(0xFF00473A); // Secondary teal
  static const Color primaryDark  = Color(0xFF002A24); // Darker teal (gradient start)
  static const Color primaryMid   = Color(0xFF2E8B74); // Medium green (gradient end)
  static const Color primaryLight = Color(0xFFA7D3C7); // Light teal / chips

  /// Sea green — used for pending badges, notification dots, key CTAs
  static const Color accent       = Color(0xFF2E8B74);

  /// Off-white page background
  static const Color background   = Color(0xFFF5F7F6);

  /// Pure-white card / tile surface
  static const Color surface      = Color(0xFFFFFFFF);

  // ── Text & lines ──────────────────────────────────────────────────────────

  static const Color textPrimary   = Color(0xFF1A1A1A); // Headings / body text
  static const Color textSecondary = Color(0xFF6B7280); // Muted / secondary text
  static const Color border        = Color(0xFFE4E8E7); // Hairlines / dividers

  // ── Semantic / status colours (preserved for data-driven states) ──────────

  static const Color success = Color(0xFF4CAF50); // Present · paid · ok
  static const Color warning = Color(0xFFFFB020); // Leave · pending · caution
  static const Color danger  = Color(0xFFE53935); // Absent · overdue · error

  /// Alias for [danger] — matches the supplied palette's `error` name.
  static const Color error   = danger;

  // Light variants for backgrounds / badges
  static const Color successLight = Color(0xFFE8F5E9);
  static const Color warningLight = Color(0xFFFFF8E1);
  static const Color dangerLight  = Color(0xFFFFEBEE);

  // WhatsApp brand color
  static const Color whatsapp     = Color(0xFF25D366);

  // ── ThemeData ─────────────────────────────────────────────────────────────

  static ThemeData get light => ThemeData(
    useMaterial3: false,
    primaryColor: primary,
    primarySwatch: Colors.teal,
    scaffoldBackgroundColor: background,

    // AppBar: deep teal-green everywhere, no elevation, white status-bar icons.
    // Uses the darker shade so headers match the dark hero banners that sit
    // directly beneath them (single continuous dark block, no seam).
    appBarTheme: const AppBarTheme(
      backgroundColor: primaryDark,
      foregroundColor: Colors.white,
      elevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
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
      fillColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? primary : null),
    ),

    // Dividers
    dividerColor: border,
    dividerTheme: const DividerThemeData(
      color: border, thickness: 1, space: 1),

    // Chips (FilterChip / ChoiceChip): selecting must NOT resize the chip.
    // The default selected-state checkmark adds a leading avatar that widens
    // the chip — disable it app-wide so selection only changes colour, never
    // size. Individual chips still control their own colours/borders.
    chipTheme: const ChipThemeData(showCheckmark: false),

    // Date picker: match the brand instead of the default Material teal. The
    // header and the selected day use the deep brand green; the calendar body
    // stays white for legibility.
    datePickerTheme: DatePickerThemeData(
      backgroundColor: surface,
      headerBackgroundColor: primary,
      headerForegroundColor: Colors.white,
      dayBackgroundColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? primary : null),
      dayForegroundColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? Colors.white : null),
      todayForegroundColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? Colors.white : primary),
      todayBackgroundColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? primary : null),
      todayBorder: const BorderSide(color: primary),
      yearBackgroundColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? primary : null),
      yearForegroundColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? Colors.white : null),
    ),

    // Time picker: same brand treatment for any time-of-day dialogs.
    timePickerTheme: const TimePickerThemeData(
      backgroundColor: surface,
      hourMinuteColor: primaryLight,
      dialHandColor: primary,
      dialBackgroundColor: background,
    ),
  );
}

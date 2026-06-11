import 'package:pdf/pdf.dart';

/// Single source of truth for colours used in generated PDFs (attendance,
/// meeting points, homework, report cards, digests, …).
///
/// These mirror the app's brand palette (see `AppTheme` in `lib/theme.dart`) so
/// exported documents match the on-screen theme:
///   • primary      #003D33 — headers, table-header rows, title bars
///   • primaryDark  #002A24 — gradient ends, strong borders, emphasis
///   • accent       #2E8B74 — highlights, badges, call-outs
///
/// Kept as `const` literals (PdfColor can't be derived from a Flutter `Color`
/// at compile time). If `AppTheme`'s palette changes, update these to match.
///
/// Use these instead of ad-hoc `PdfColors.indigo*` / `PdfColors.grey*` for any
/// branded element. Semantic data colours (present/absent/leave) keep their
/// own meaning and are provided separately below.
class PdfTheme {
  PdfTheme._();

  // ── Brand (mirrors AppTheme's teal-green palette) ──────────────────────────
  static const PdfColor primary      = PdfColor.fromInt(0xFF003D33);
  static const PdfColor primaryDark  = PdfColor.fromInt(0xFF002A24);
  static const PdfColor accent       = PdfColor.fromInt(0xFF2E8B74);

  /// Very light teal tint for zebra rows / panel backgrounds.
  static const PdfColor primaryTint  = PdfColor.fromInt(0xFFE0F2EC);
  /// Light teal for secondary borders / chips (matches AppTheme.primaryLight).
  static const PdfColor primaryLight = PdfColor.fromInt(0xFFA7D3C7);

  // ── On-brand text ────────────────────────────────────────────────────────
  static const PdfColor onPrimary    = PdfColors.white;

  // ── Neutral greys (unchanged structural tones) ─────────────────────────────
  static const PdfColor grey50       = PdfColor.fromInt(0xFFF5F5F5);
  static const PdfColor grey200      = PdfColor.fromInt(0xFFEEEEEE);
  static const PdfColor grey400      = PdfColor.fromInt(0xFFBDBDBD);
  static const PdfColor text         = PdfColors.black;
  static const PdfColor textLight    = PdfColor.fromInt(0xFF616161);

  // ── Semantic data colours (keep their meaning, not re-branded) ─────────────
  static const PdfColor success      = PdfColor.fromInt(0xFF2E7D32); // present
  static const PdfColor successTint  = PdfColor.fromInt(0xFFE8F5E9);
  static const PdfColor danger       = PdfColor.fromInt(0xFFC62828); // absent
  static const PdfColor dangerTint   = PdfColor.fromInt(0xFFFFEBEE);
  static const PdfColor warning      = PdfColor.fromInt(0xFFEF6C00); // leave
}

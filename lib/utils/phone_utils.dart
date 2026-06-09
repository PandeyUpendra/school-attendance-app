/// Phone-number helpers shared by every "message on WhatsApp" / dial action.
///
/// `wa.me` requires a full international number with country code and NO `+`,
/// spaces, or separators. Numbers in this app are typically entered as local
/// 10-digit Indian numbers, so a bare `wa.me/9876543210` fails to resolve (or
/// routes to the wrong country). [whatsAppNumber] normalises to digits and
/// prepends the country code when the number looks local (#62).
abstract class PhoneUtils {
  /// Default country calling code (India). Kept as a constant so it can later be
  /// sourced from per-school settings without touching call sites.
  static const String defaultCountryCode = '91';

  /// Strips everything but digits.
  static String digitsOnly(String raw) => raw.replaceAll(RegExp(r'\D'), '');

  /// Returns a `wa.me`-ready number: digits only, country code guaranteed.
  ///   "98765 43210"   → "919876543210"
  ///   "+91 98765..."  → "919876543210"
  ///   "098765 43210"  → "919876543210" (drops the national trunk 0)
  ///   "919876543210"  → unchanged
  /// Returns '' when there are no usable digits.
  static String whatsAppNumber(String raw, {String? countryCode}) {
    var digits = digitsOnly(raw);
    if (digits.isEmpty) return '';
    // Drop a leading national-trunk 0 (e.g. "0 98765 43210").
    digits = digits.replaceFirst(RegExp(r'^0+'), '');
    final cc = countryCode ?? defaultCountryCode;
    // A bare 10-digit number is treated as local → prepend the country code.
    if (digits.length == 10) digits = '$cc$digits';
    return digits;
  }

  /// Normalises a phone number to standard E.164-like format (e.g. "+919876543210").
  static String normalize(String phone) {
    var clean = phone.replaceAll(RegExp(r'\D'), ''); // Keep only digits
    if (clean.length == 10) {
      return '+91$clean';
    } else if (clean.length == 11 && clean.startsWith('0')) {
      return '+91${clean.substring(1)}';
    } else if (clean.length == 12 && clean.startsWith('91')) {
      return '+$clean';
    } else if (phone.trim().startsWith('+')) {
      return '+$clean';
    }
    return phone.trim();
  }
}


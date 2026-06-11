/// Shared input validators so every screen enforces the same rules.
///
/// Email rule matches the regex already used across the app
/// (`^[^@]+@[^@]+\.[^@]+$`): non-empty local part, an `@`, a domain, a dot,
/// and a TLD — with no whitespace.
abstract class Validators {
  // Keep this in sync with EMAIL_RE in functions/index.js to prevent drift risk (#12).
  static final RegExp _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// True when [value] is a syntactically valid email address.
  static bool isValidEmail(String? value) {
    final v = (value ?? '').trim();
    return v.isNotEmpty && _emailRe.hasMatch(v);
  }

  /// `TextFormField.validator` for required email fields.
  /// Returns an error string when invalid, or null when valid.
  static String? email(String? value, {String fieldLabel = 'email address'}) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Enter an $fieldLabel';
    if (!_emailRe.hasMatch(v)) return 'Enter a valid $fieldLabel';
    return null;
  }

  /// `TextFormField.validator` for optional email fields — only validates
  /// format when the user actually typed something.
  static String? optionalEmail(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return null;
    if (!_emailRe.hasMatch(v)) return 'Enter a valid email address';
    return null;
  }

  /// True when [value] is a valid phone number. Strips leading `+` and non-digits,
  /// verifying the length is between 7 and 15 digits (E.164 standard).
  static bool isValidPhone(String? value) {
    var v = (value ?? '').trim();
    if (v.startsWith('+')) {
      v = v.substring(1);
    }
    final d = v.replaceAll(RegExp(r'\D'), '');
    return d.length >= 7 && d.length <= 15;
  }

  /// `TextFormField.validator` for required phone fields.
  static String? phone(String? value, {String fieldLabel = 'phone number'}) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Enter a $fieldLabel';
    if (!isValidPhone(v)) return 'Enter a valid $fieldLabel';
    return null;
  }

  /// `TextFormField.validator` for optional phone fields — only validates when
  /// the user actually typed something.
  static String? optionalPhone(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return null;
    if (!isValidPhone(v)) return 'Enter a valid phone number';
    return null;
  }

  /// `TextFormField.validator` for required name/text fields.
  static String? name(String? value, {String fieldLabel = 'name'}) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Enter a $fieldLabel';
    return null;
  }
}

/// Shared input validators so every screen enforces the same rules.
///
/// Email rule matches the regex already used across the app
/// (`^[^@]+@[^@]+\.[^@]+$`): non-empty local part, an `@`, a domain, a dot,
/// and a TLD — with no whitespace.
abstract class Validators {
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

  /// True when [value] is a usable Indian mobile number. Accepts common entry
  /// forms — spaces/dashes, a leading national-trunk `0`, or a `+91`/`91`
  /// country prefix — and checks the remaining local part is a 10-digit number
  /// starting 6–9 (the valid Indian mobile range). Mirrors
  /// `PhoneUtils.whatsAppNumber` normalisation so a number that validates here
  /// also dials/links correctly.
  static bool isValidPhone(String? value) {
    var d = (value ?? '').replaceAll(RegExp(r'\D'), '');
    d = d.replaceFirst(RegExp(r'^0+'), '');
    if (d.length == 12 && d.startsWith('91')) d = d.substring(2);
    return RegExp(r'^[6-9]\d{9}$').hasMatch(d);
  }

  /// `TextFormField.validator` for required phone fields.
  static String? phone(String? value, {String fieldLabel = 'phone number'}) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Enter a $fieldLabel';
    if (!isValidPhone(v)) return 'Enter a valid 10-digit $fieldLabel';
    return null;
  }

  /// `TextFormField.validator` for optional phone fields — only validates when
  /// the user actually typed something.
  static String? optionalPhone(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return null;
    if (!isValidPhone(v)) return 'Enter a valid 10-digit phone number';
    return null;
  }
}

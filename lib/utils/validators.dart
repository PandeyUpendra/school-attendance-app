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
}

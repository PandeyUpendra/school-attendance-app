import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../providers/locale_provider.dart';

/// Lightweight, map-based translations. Each key maps to per-language strings.
/// Hindi (`hi`) uses simple everyday wording. To translate more of the app,
/// add keys here and replace literals with `context.tr('key')`.
///
/// This intentionally avoids ARB / codegen so strings can be added incrementally
/// without a build step. English is always the fallback.
class AppStrings {
  static const Map<String, Map<String, String>> _values = {
    // ── Profile ──────────────────────────────────────────────────────────
    'myProfile':       {'en': 'My Profile',        'hi': 'मेरी प्रोफ़ाइल'},
    'account':         {'en': 'ACCOUNT',           'hi': 'खाता'},
    'email':           {'en': 'Email',             'hi': 'ईमेल'},
    'phone':           {'en': 'Phone',             'hi': 'फ़ोन'},
    'school':          {'en': 'School',            'hi': 'स्कूल'},
    'status':          {'en': 'Status',            'hi': 'स्थिति'},
    'assignedClasses': {'en': 'ASSIGNED CLASSES',  'hi': 'दी गई कक्षाएँ'},
    'children':        {'en': 'CHILDREN',          'hi': 'बच्चे'},
    'statusActive':    {'en': 'Active',            'hi': 'सक्रिय'},
    'statusPending':   {'en': 'Pending',           'hi': 'लंबित'},

    // ── Language ─────────────────────────────────────────────────────────
    'language':        {'en': 'Language',          'hi': 'भाषा'},
    'chooseLanguage':  {'en': 'Choose language',   'hi': 'भाषा चुनें'},
    'preferences':     {'en': 'PREFERENCES',       'hi': 'पसंद'},

    // ── Common actions ───────────────────────────────────────────────────
    'save':            {'en': 'Save',              'hi': 'सेव करें'},
    'cancel':          {'en': 'Cancel',            'hi': 'रद्द करें'},
    'logout':          {'en': 'Logout',            'hi': 'लॉग आउट'},

    // ── Login ────────────────────────────────────────────────────────────
    'signInSubtitle':  {'en': 'Sign in to your account', 'hi': 'अपने खाते में साइन इन करें'},
    'emailAddress':    {'en': 'Email Address',     'hi': 'ईमेल पता'},
    'password':        {'en': 'Password',          'hi': 'पासवर्ड'},
    'forgotPassword':  {'en': 'Forgot Password?',  'hi': 'पासवर्ड भूल गए?'},
    'signIn':          {'en': 'Sign In',           'hi': 'साइन इन करें'},

    // ── Guardian ─────────────────────────────────────────────────────────
    'viewing':         {'en': 'VIEWING',           'hi': 'देख रहे हैं'},

    // ── Role names ───────────────────────────────────────────────────────
    'role_owner':       {'en': 'Owner',       'hi': 'मालिक'},
    'role_principal':   {'en': 'Principal',   'hi': 'प्रधानाचार्य'},
    'role_coordinator': {'en': 'Coordinator', 'hi': 'समन्वयक'},
    'role_teacher':     {'en': 'Teacher',     'hi': 'शिक्षक'},
    'role_guardian':    {'en': 'Guardian',    'hi': 'अभिभावक'},
    'role_admin':       {'en': 'Admin',       'hi': 'एडमिन'},
  };

  /// Returns the translation for [key] in [code], falling back to English then
  /// the key itself (so a missing translation is visible but never crashes).
  static String get(String code, String key) {
    final entry = _values[key];
    if (entry == null) return key;
    return entry[code] ?? entry['en'] ?? key;
  }

  /// Localised label for a role id (e.g. 'coordinator' → 'समन्वयक').
  static String role(String code, String roleId) => get(code, 'role_$roleId');
}

/// `context.tr('key')` — resolves a translation for the current language and
/// rebuilds the widget when the language changes.
extension L10nExtension on BuildContext {
  String tr(String key) =>
      AppStrings.get(Provider.of<LocaleProvider>(this).code, key);

  String trRole(String roleId) =>
      AppStrings.role(Provider.of<LocaleProvider>(this).code, roleId);
}

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the app's current language and persists the choice. English is the
/// default; Hindi (`hi`) uses simple everyday wording, not formal/literary
/// Hindi. Add more languages by extending [supported].
class LocaleProvider extends ChangeNotifier {
  static const _prefsKey = 'app_language';

  /// Languages the app offers, code → display label (shown in its own script).
  static const Map<String, String> supported = {
    'en': 'English',
    'hi': 'हिन्दी',
  };

  Locale _locale;
  LocaleProvider([String code = 'en']) : _locale = Locale(code);

  Locale get locale => _locale;
  String get code => _locale.languageCode;
  bool get isHindi => _locale.languageCode == 'hi';

  /// Reads the saved language code (defaults to English).
  static Future<String> savedCode() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_prefsKey);
    return supported.containsKey(code) ? code! : 'en';
  }

  Future<void> setLanguage(String code) async {
    if (!supported.containsKey(code) || code == _locale.languageCode) return;
    _locale = Locale(code);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, code);
  }
}

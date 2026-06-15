import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's last-selected class and section so they are restored
/// automatically when navigating between screens (Fee Collection, Homework,
/// etc.).
///
/// Uses [SharedPreferences] for lightweight, synchronous-at-read storage.
/// Singleton pattern matches [DropdownOptionsService].
class RecentSelectionsService {
  static final RecentSelectionsService _instance = RecentSelectionsService._();
  RecentSelectionsService._();
  factory RecentSelectionsService() => _instance;

  static const _keyLastClass   = 'last_selected_class';
  static const _keyLastSection = 'last_selected_section';

  /// Saves the selected [className] and [section] for later recall.
  Future<void> saveClassSection(String className, String section) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastClass, className);
    await prefs.setString(_keyLastSection, section);
  }

  /// Returns the last-selected class name, or `null` if none was saved.
  Future<String?> getLastClass() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastClass);
  }

  /// Returns the last-selected section, or `null` if none was saved.
  Future<String?> getLastSection() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastSection);
  }

  /// Convenience getter that returns both values in a single call.
  Future<({String? className, String? section})> getLastClassSection() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      className: prefs.getString(_keyLastClass),
      section:   prefs.getString(_keyLastSection),
    );
  }
}

import 'package:shared_preferences/shared_preferences.dart';

/// Manages local session persistence via SharedPreferences.
/// Stores who is logged in (email, role, optional teacherId, optional
/// guardian's student link) so the app stays logged in across restarts
/// until the user explicitly logs out.
class AuthService {
  static const _keyEmail          = 'auth_email';
  static const _keyRole           = 'auth_role';
  static const _keyTeacherId      = 'auth_teacher_id';
  static const _keyStudentLinks    = 'auth_student_links'; // List of "className|roll|name"
  static const _keyAssignedClasses = 'auth_assigned_classes'; // comma-delimited

  static final AuthService _instance = AuthService._();
  AuthService._();
  factory AuthService() => _instance;

  Future<void> saveSession({
    required String email,
    required String role,
    String?       teacherId,
    List<String>? studentLinks,
    List<String>? assignedClasses,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyEmail, email);
    await prefs.setString(_keyRole, role);

    if (teacherId != null) {
      await prefs.setString(_keyTeacherId, teacherId);
    } else {
      await prefs.remove(_keyTeacherId);
    }

    if (studentLinks != null && studentLinks.isNotEmpty) {
      await prefs.setStringList(_keyStudentLinks, studentLinks);
    } else {
      await prefs.remove(_keyStudentLinks);
    }

    if (assignedClasses != null && assignedClasses.isNotEmpty) {
      await prefs.setString(_keyAssignedClasses, assignedClasses.join(','));
    } else {
      await prefs.remove(_keyAssignedClasses);
    }
  }

  /// Returns session map with keys: email, role, [teacherId],
  /// [studentLinks].  Returns null if no session is saved.
  Future<Map<String, dynamic>?> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(_keyEmail);
    final role  = prefs.getString(_keyRole);
    if (email == null || role == null) return null;

    final result = <String, dynamic>{'email': email, 'role': role};
    final tid = prefs.getString(_keyTeacherId);
    if (tid != null) result['teacherId'] = tid;

    final links = prefs.getStringList(_keyStudentLinks);
    if (links != null) {
      result['studentLinks'] = links;
    }

    final assignedRaw = prefs.getString(_keyAssignedClasses);
    if (assignedRaw != null && assignedRaw.isNotEmpty) {
      result['assignedClasses'] = assignedRaw.split(',');
    }
    return result;
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyEmail);
    await prefs.remove(_keyRole);
    await prefs.remove(_keyTeacherId);
    await prefs.remove(_keyStudentLinks);
    await prefs.remove(_keyAssignedClasses);
  }

  // ── Compatibility for AuthProvider ────────────────────────────────────────

  Future<dynamic> signInWithEmail(String email, String password) async {
    // This is a stub to satisfy AuthProvider. In this app, actual validation
    // happens in TimetableService.validateLogin.
    throw UnimplementedError('Use TimetableService.validateLogin instead.');
  }

  Future<void> signOut() async {
    await clearSession();
  }
}

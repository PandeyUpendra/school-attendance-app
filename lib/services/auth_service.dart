import 'package:shared_preferences/shared_preferences.dart';

/// Manages local session persistence via SharedPreferences.
/// Stores who is logged in (email, role, optional teacherId, optional
/// guardian's student link) so the app stays logged in across restarts
/// until the user explicitly logs out.
class AuthService {
  static const _keyEmail          = 'auth_email';
  static const _keyRole           = 'auth_role';
  static const _keyTeacherId      = 'auth_teacher_id';
  static const _keyStudentClass    = 'auth_student_class';
  static const _keyStudentRoll    = 'auth_student_roll';
  static const _keyStudentSection = 'auth_student_section';
  static const _keyAssignedClasses = 'auth_assigned_classes'; // comma-delimited
  static const _keyName           = 'auth_name';
  static const _keySchoolId       = 'auth_school_id';
  static const _keyStudentLinks   = 'auth_student_links'; // pipe-delimited list

  static final AuthService _instance = AuthService._();
  AuthService._();
  factory AuthService() => _instance;

  Future<void> saveSession({
    required String email,
    required String role,
    String?       teacherId,
    String?       studentClass,
    int?          studentRoll,
    String?       studentSection,
    List<String>? assignedClasses,
    String?       name,
    String?       schoolId,
    List<String>? studentLinks,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyEmail, email);
    await prefs.setString(_keyRole, role);

    if (teacherId != null) {
      await prefs.setString(_keyTeacherId, teacherId);
    } else {
      await prefs.remove(_keyTeacherId);
    }

    if (studentClass != null && studentRoll != null) {
      await prefs.setString(_keyStudentClass, studentClass);
      await prefs.setInt(_keyStudentRoll, studentRoll);
      if (studentSection != null && studentSection.isNotEmpty) {
        await prefs.setString(_keyStudentSection, studentSection);
      } else {
        await prefs.remove(_keyStudentSection);
      }
    } else {
      await prefs.remove(_keyStudentClass);
      await prefs.remove(_keyStudentRoll);
      await prefs.remove(_keyStudentSection);
    }

    if (assignedClasses != null && assignedClasses.isNotEmpty) {
      await prefs.setString(_keyAssignedClasses, assignedClasses.join(','));
    } else {
      await prefs.remove(_keyAssignedClasses);
    }

    if (name != null && name.isNotEmpty) {
      await prefs.setString(_keyName, name);
    } else {
      await prefs.remove(_keyName);
    }
    if (schoolId != null && schoolId.isNotEmpty) {
      await prefs.setString(_keySchoolId, schoolId);
    } else {
      await prefs.remove(_keySchoolId);
    }
    if (studentLinks != null && studentLinks.isNotEmpty) {
      await prefs.setString(_keyStudentLinks, studentLinks.join(';;'));
    } else {
      await prefs.remove(_keyStudentLinks);
    }
  }

  /// Returns session map with keys: email, role, [teacherId],
  /// [studentClass], [studentRoll].  Returns null if no session is saved.
  Future<Map<String, dynamic>?> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(_keyEmail);
    final role  = prefs.getString(_keyRole);
    if (email == null || role == null) return null;

    final result = <String, dynamic>{'email': email, 'role': role};
    final tid = prefs.getString(_keyTeacherId);
    if (tid != null) result['teacherId'] = tid;

    final sClass   = prefs.getString(_keyStudentClass);
    final sRoll    = prefs.getInt(_keyStudentRoll);
    final sSection = prefs.getString(_keyStudentSection);
    if (sClass != null && sRoll != null) {
      result['studentClass']   = sClass;
      result['studentRoll']    = sRoll;
      result['studentSection'] = sSection ?? '';
    }

    final assignedRaw = prefs.getString(_keyAssignedClasses);
    if (assignedRaw != null && assignedRaw.isNotEmpty) {
      result['assignedClasses'] = assignedRaw.split(',');
    }

    final nameVal = prefs.getString(_keyName);
    if (nameVal != null) result['name'] = nameVal;
    final schoolIdVal = prefs.getString(_keySchoolId);
    if (schoolIdVal != null) result['schoolId'] = schoolIdVal;
    final linksRaw = prefs.getString(_keyStudentLinks);
    if (linksRaw != null && linksRaw.isNotEmpty) {
      result['studentLinks'] = linksRaw.split(';;');
    }
    return result;
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyEmail);
    await prefs.remove(_keyRole);
    await prefs.remove(_keyTeacherId);
    await prefs.remove(_keyStudentClass);
    await prefs.remove(_keyStudentRoll);
    await prefs.remove(_keyStudentSection);
    await prefs.remove(_keyAssignedClasses);
    await prefs.remove(_keyName);
    await prefs.remove(_keySchoolId);
    await prefs.remove(_keyStudentLinks);
  }

  /// Stub: Google Sign-In is not implemented in this deployment.
  /// Returns null to indicate no result (caller should handle gracefully).
  Future<Map<String, dynamic>?> signInWithGoogle() async => null;
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'timetable_service.dart';

/// Manages authentication and session persistence.
/// Uses Firebase Auth for secure login and SharedPreferences for local metadata.
class AuthService {
  static const _keyEmail          = 'auth_email';
  static const _keyName           = 'auth_name';
  static const _keyRole           = 'auth_role';
  static const _keySchoolId       = 'auth_school_id';
  static const _keyTeacherId      = 'auth_teacher_id';
  static const _keyStudentLinks    = 'auth_student_links';
  static const _keyAssignedClasses = 'auth_assigned_classes';


  static final AuthService _instance = AuthService._();
  AuthService._();
  factory AuthService() => _instance;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;

  /// Performs a real Firebase Authentication login.
  Future<UserCredential> login(String email, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
    return credential;
  }

  /// Saves session metadata locally for UI routing and offline access.
  Future<void> saveSession({
    required String email,
    required String role,
    String?       name,
    String?       schoolId,
    String?       teacherId,
    List<String>? studentLinks,
    List<String>? assignedClasses,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyEmail, email);
    await prefs.setString(_keyRole, role);

    if (name != null) await prefs.setString(_keyName, name);
    if (schoolId != null) await prefs.setString(_keySchoolId, schoolId);

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

  /// Returns session map with keys: email, role, [teacherId], [studentLinks].
  Future<Map<String, dynamic>?> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(_keyEmail);
    final role  = prefs.getString(_keyRole);
    if (email == null || role == null) return null;

    final result = <String, dynamic>{
      'email': email,
      'role': role,
      'name': prefs.getString(_keyName),
      'schoolId': prefs.getString(_keySchoolId),
    };
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

  Future<void> signOut() async {
    await _auth.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  Future<void> clearSession() async {
    await signOut();
  }

  /// Legacy stub for backward compatibility with AuthProvider.
  /// Should be removed once AuthProvider is updated.
  Future<dynamic> signInWithEmail(String email, String password) async {
    return login(email, password);
  }
}

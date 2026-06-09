import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'base_firestore_service.dart';

import 'audit_log_service.dart';
import 'dropdown_options_service.dart';
import 'push_service.dart';

/// Outcome of a self-service password-reset request.
///
/// We deliberately do NOT expose whether the email was registered — that would
/// be an account-enumeration oracle (#19, #84). The UI shows the same neutral
/// "if an account exists, a link has been sent" message for both outcomes.
enum ResetResult {
  /// The request reached the reset service and was processed.
  sent,

  /// The reset service was unreachable; a best-effort Firebase reset email was
  /// attempted instead.
  unknown,
}

/// Manages authentication (Firebase Auth) and local session persistence
/// (SharedPreferences for role-specific data like teacherId, studentLinks).
class AuthService {
  static const _keyEmail           = 'auth_email';
  static const _keyRole            = 'auth_role';
  static const _keyTeacherId       = 'auth_teacher_id';
  static const _keyStudentClass    = 'auth_student_class';
  static const _keyStudentRoll     = 'auth_student_roll';
  static const _keyStudentSection  = 'auth_student_section';
  static const _keyStudentAdmissionId = 'auth_student_admission_id';
  static const _keyAssignedClasses = 'auth_assigned_classes';
  static const _keyName            = 'auth_name';
  static const _keySchoolId        = 'auth_school_id';
  static const _keyStudentLinks    = 'auth_student_links';

  static final _auth = FirebaseAuth.instance;

  /// The single, permanent system administrator.
  ///
  /// Admin identity is HARDCODED to this one address — it is intentionally not
  /// stored in (and not read from) Firestore. That makes it the unforgeable
  /// root of the whole role hierarchy (admin → owner → principal → …) and lets
  /// it bootstrap the system even when the database is completely empty. No
  /// other email can ever obtain admin access, request an admin password reset,
  /// or be promoted to admin. The Firestore security rules enforce the same
  /// constant server-side (`isRootAdmin()`), so this is not merely client-side.
  static const String rootAdminEmail = 'mandvishal@gmail.com';

  /// True only for [rootAdminEmail] (case-insensitive, trimmed).
  static bool isRootAdminEmail(String? email) =>
      (email ?? '').trim().toLowerCase() == rootAdminEmail;

  /// Returns the current school ID set during login, falling back to the
  /// default production school ID so pre-migration sessions still work.
  /// Delegates to [BaseFirestoreService.currentSchoolId] which is set by
  /// all three login screens as soon as the allowed_users doc is read.
  static String get currentSchoolId =>
      BaseFirestoreService.currentSchoolId ?? 'school_1';

  static final AuthService _instance = AuthService._();
  AuthService._();
  factory AuthService() => _instance;

  // ── Firebase Auth ─────────────────────────────────────────────────────────

  /// Signs in with email + password via Firebase Auth.
  /// Throws [FirebaseAuthException] on failure.
  Future<UserCredential> signInWithEmail(String email, String password) {
    return _auth.signInWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
  }

  /// Sends a password setup / reset email using Firebase Auth's BUILT-IN email
  /// (no SendGrid / Cloud Function). Used both for self-service "forgot
  /// password" and as the first-time "set your password" invite when a
  /// management user creates an account (the new Auth account already exists,
  /// so the reset email doubles as the set-password email).
  ///
  /// [invite] is kept for call-site compatibility but no longer changes behavior
  /// — Firebase sends the same reset template either way.
  Future<void> sendPasswordEmailViaFunction(String email,
      {bool invite = false}) async {
    await _auth.sendPasswordResetEmail(email: email.trim().toLowerCase());
  }

  /// Self-service password reset via Firebase Auth's built-in email.
  ///
  /// Never reveals whether the address is enrolled (#19, #84): a `user-not-found`
  /// is swallowed and reported the same as success, and the UI shows the same
  /// neutral "if an account exists…" message for both [sent] and [unknown].
  Future<ResetResult> sendResetIfRegistered(String email) async {
    final normEmail = email.trim().toLowerCase();
    try {
      await _auth.sendPasswordResetEmail(email: normEmail);
      return ResetResult.sent;
    } on FirebaseAuthException catch (e) {
      // Treat "no such user" as success so the response can't be used to
      // enumerate enrolled families. Other errors → neutral "unknown".
      return e.code == 'user-not-found' ? ResetResult.sent : ResetResult.unknown;
    } catch (_) {
      return ResetResult.unknown;
    }
  }

  /// Sends a password-reset email (also used as first-time invitation email).
  /// Routes through the Cloud Function for inbox-grade deliverability.
  Future<void> sendPasswordResetEmail(String email) async {
    await sendPasswordEmailViaFunction(email.trim().toLowerCase());
    AuditService.emit(
      action:   'update',
      entity:   'auth',
      entityId: email.trim().toLowerCase(),
      reason:   'password_reset_email_sent',
    );
  }

  /// Logs a role change for auditing. Call this from any screen that modifies
  /// a user's role in allowed_users.
  static void auditRoleChange({
    required String targetEmail,
    required String oldRole,
    required String newRole,
    String? reason,
  }) {
    AuditService.emit(
      action:   'update',
      entity:   'auth',
      entityId: targetEmail,
      before:   {'role': oldRole},
      after:    {'role': newRole},
      reason:   reason ?? 'role_change',
    );
  }

  /// Logs an account-disable event.
  static void auditAccountDisable({
    required String targetEmail,
    String? reason,
  }) {
    AuditService.emit(
      action:   'update',
      entity:   'auth',
      entityId: targetEmail,
      after:    {'status': 'disabled'},
      reason:   reason ?? 'account_disabled',
    );
  }

  /// Re-authenticates the current user (required before [updatePassword]).
  Future<void> reauthenticate(String email, String password) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in');
    final cred = EmailAuthProvider.credential(
      email: email.trim().toLowerCase(),
      password: password,
    );
    await user.reauthenticateWithCredential(cred);
  }

  /// Updates the current user's password. Call [reauthenticate] first
  /// if the user hasn't signed in recently.
  Future<void> updatePassword(String newPassword) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in');
    await user.updatePassword(newPassword);
  }

  /// The currently signed-in Firebase user, or null.
  User? get currentFirebaseUser => _auth.currentUser;

  /// Signs out from Firebase Auth and clears the local session.
  /// Delegates to [clearSession] which handles both operations.
  Future<void> signOut() => clearSession();

  // ── Session persistence (SharedPreferences) ───────────────────────────────

  Future<void> saveSession({
    required String email,
    required String role,
    String?       teacherId,
    String?       studentClass,
    int?          studentRoll,
    String?       studentSection,
    String?       studentAdmissionId,
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
      if (studentAdmissionId != null && studentAdmissionId.isNotEmpty) {
        await prefs.setString(_keyStudentAdmissionId, studentAdmissionId);
      } else {
        await prefs.remove(_keyStudentAdmissionId);
      }
    } else {
      await prefs.remove(_keyStudentClass);
      await prefs.remove(_keyStudentRoll);
      await prefs.remove(_keyStudentSection);
      await prefs.remove(_keyStudentAdmissionId);
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
    await prefs.setInt('last_activity_timestamp', DateTime.now().millisecondsSinceEpoch);

    // Refresh the ID token so freshly-minted custom claims (role/schoolId from
    // syncUserClaims, used by the tenant-scoped Storage rules, #3) take effect
    // without waiting up to an hour. Fire-and-forget.
    _auth.currentUser?.getIdToken(true);

    // Subscribe this device to its push topics for the new session (#52).
    // Fire-and-forget — push setup must never block or fail login.
    PushService().syncForSession(
      role:         role,
      schoolId:     schoolId,
      teacherId:    teacherId,
      studentClass: studentClass,
      studentRoll:  studentRoll,
    );
  }

  /// Returns session map with keys: email, role, and optional role-specific
  /// keys. Returns null if no session is saved.
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
      final sAdm = prefs.getString(_keyStudentAdmissionId);
      if (sAdm != null && sAdm.isNotEmpty) result['studentAdmissionId'] = sAdm;
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

  /// Clears the local SharedPreferences session AND signs out from Firebase Auth.
  /// All logout paths (dashboard buttons, role_guard) call this, so Firebase
  /// Auth state is always kept in sync with the local session.
  Future<void> clearSession() async {
    // Unsubscribe this device from the previous user's push topics (#52) so a
    // shared device stops receiving their notifications after logout.
    await PushService().clear();

    // Sign out of Firebase Auth (no-op if no user is signed in).
    try {
      await _auth.signOut();
    } catch (_) {}

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
    await prefs.remove('last_activity_timestamp');

    // Drop the in-memory school so it can't leak into the next session and
    // leave school-scoped streams bound to the previous user's school.
    BaseFirestoreService.currentSchoolId = null;
    // Drop cached per-school dropdown options for the same reason.
    DropdownOptionsService().clearCache();
  }

  /// Returns a human-readable message for a [FirebaseAuthException].
  static String friendlyAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Invalid email or password.';
      case 'user-disabled':
        return 'This account has been disabled. Contact your administrator.';
      case 'too-many-requests':
        return 'Too many failed attempts. Please try again later.';
      case 'network-request-failed':
        return 'No internet connection. Please check your network.';
      case 'email-already-in-use':
        return 'This email is already registered.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'requires-recent-login':
        return 'Please sign in again before changing your password.';
      default:
        return e.message ?? 'Authentication error. Please try again.';
    }
  }
}

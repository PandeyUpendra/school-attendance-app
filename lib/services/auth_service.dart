import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'base_firestore_service.dart';

import 'audit_log_service.dart';

/// Outcome of a self-service password-reset request.
enum ResetResult {
  /// Email is registered — a reset link was sent.
  sent,

  /// Email is NOT registered in the school system — nothing was sent.
  notRegistered,

  /// Registration couldn't be verified (reset function not deployed /
  /// unreachable); a best-effort reset email was attempted via Firebase.
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
  static const _keyAssignedClasses = 'auth_assigned_classes';
  static const _keyName            = 'auth_name';
  static const _keySchoolId        = 'auth_school_id';
  static const _keyStudentLinks    = 'auth_student_links';

  static final _auth = FirebaseAuth.instance;
  static final _functions = FirebaseFunctions.instance;

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

  /// Sends a password setup / reset email via the `sendPasswordEmail` Cloud
  /// Function, which delivers through an authenticated SendGrid domain so the
  /// message lands in the inbox instead of Gmail's spam folder.
  ///
  /// [invite] = true is the privileged path used when a management user creates
  /// an account (the function verifies the caller's role). [invite] = false is
  /// self-service "forgot password".
  ///
  /// Falls back to Firebase Auth's built-in email if the function call fails
  /// (e.g. not deployed yet), so account creation / reset is never blocked.
  /// The fallback's own failure is allowed to propagate so callers that need to
  /// report success/failure truthfully still can.
  Future<void> sendPasswordEmailViaFunction(String email,
      {bool invite = false}) async {
    final normEmail = email.trim().toLowerCase();
    try {
      await _functions.httpsCallable('sendPasswordEmail').call(<String, dynamic>{
        'email': normEmail,
        'type': invite ? 'invite' : 'reset',
      });
    } on FirebaseFunctionsException {
      // Function unavailable / not deployed — fall back to the built-in email so
      // the user is never blocked. Let a fallback failure propagate.
      await _auth.sendPasswordResetEmail(email: normEmail);
    }
  }

  /// Self-service password reset that only sends to registered emails.
  ///
  /// Returns [ResetResult.sent] / [ResetResult.notRegistered] based on whether
  /// the email exists in `allowed_users` (checked server-side, since
  /// unauthenticated clients can't read that collection). If the Cloud Function
  /// isn't deployed/reachable, falls back to a best-effort Firebase reset email
  /// and returns [ResetResult.unknown].
  Future<ResetResult> sendResetIfRegistered(String email) async {
    final normEmail = email.trim().toLowerCase();
    try {
      final res = await _functions
          .httpsCallable('sendPasswordEmail')
          .call(<String, dynamic>{'email': normEmail, 'type': 'reset'});
      final data = res.data;
      final registered = data is Map && data['registered'] == true;
      if (registered) {
        AuditService.emit(
          action: 'update',
          entity: 'auth',
          entityId: normEmail,
          reason: 'password_reset_email_sent',
        );
      }
      return registered ? ResetResult.sent : ResetResult.notRegistered;
    } on FirebaseFunctionsException {
      // Function unavailable — can't verify registration. Best-effort send.
      try {
        await _auth.sendPasswordResetEmail(email: normEmail);
      } catch (_) {}
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

    // Drop the in-memory school so it can't leak into the next session and
    // leave school-scoped streams bound to the previous user's school.
    BaseFirestoreService.currentSchoolId = null;
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

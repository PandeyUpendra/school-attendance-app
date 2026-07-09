import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'base_firestore_service.dart';
import '../shared/utils/app_logger.dart';

import 'audit_log_service.dart';
import 'dropdown_options_service.dart';
import 'birthday_service.dart';
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
  static const _keyUseBiometric    = 'auth_use_biometric';
  static const _keyBiometricEmail  = 'auth_biometric_email';
  static const _keyBiometricPassword = 'auth_biometric_password';

  // Lazy getter — FirebaseAuth.instance is only accessed the first time a
  // method that needs auth actually runs. This prevents the static initializer
  // from crashing unit tests that import AuthService transitively but never
  // call any sign-in methods.
  static FirebaseAuth get _auth => FirebaseAuth.instance;

  /// Private cache of root admin emails loaded at startup or on login.
  static Set<String> _cachedAdminEmails = {};

  /// Loads the cached root admin emails list from SharedPreferences.
  Future<void> loadCachedAdminEmails() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('cached_root_admins') ?? [];
      _cachedAdminEmails = list.map((e) => e.toLowerCase().trim()).toSet();
    } catch (e, stack) {
      AppLogger.e('AuthService', 'Failed to load cached admin emails: $e', e, stack);
    }
  }

  /// Fetches system/root_config from Firestore and caches the admin emails list.
  /// Only root admin accounts will have Firestore read permission for this doc.
  Future<List<String>> fetchAndCacheAdminEmails() async {
    try {
      final docRef = FirebaseFirestore.instance
          .collection('system')
          .doc('root_config');
      var doc = await docRef.get();
      if (!doc.exists) {
        // Chicken-and-egg bootstrap: if the root_config doc does not exist yet,
        // and the currently signed-in Firebase user is a hardcoded root admin,
        // we can automatically initialize the document.
        final currentUserEmail = _auth.currentUser?.email?.toLowerCase().trim();
        final hardcodedAdmins = {'mandvishal@gmail.com', 'admin@schoolapp.org'};
        if (currentUserEmail != null && hardcodedAdmins.contains(currentUserEmail)) {
          final initialData = {
            'adminEmails': hardcodedAdmins.toList(),
          };
          await docRef.set(initialData);
          doc = await docRef.get();
        } else {
          throw Exception('System root config doc does not exist.');
        }
      }
      final emailsList = List<String>.from(doc.data()?['adminEmails'] ?? []);
      final clean = emailsList.map((e) => e.toLowerCase().trim()).toList();
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('cached_root_admins', clean);
      _cachedAdminEmails = clean.toSet();
      return clean;
    } catch (e, stack) {
      AppLogger.e('AuthService', 'Failed to fetch and cache admin emails: $e', e, stack);
      rethrow;
    }
  }

  /// True only for root admin emails (case-insensitive, trimmed).
  static bool isRootAdminEmail(String? email) {
    if (email == null || email.trim().isEmpty) return false;
    final clean = email.trim().toLowerCase();
    final hardcodedAdmins = {'mandvishal@gmail.com', 'admin@schoolapp.org'};
    // If the cache is empty (e.g. first-time launch/forgot password before first login),
    // we fall back to checking the hardcoded root admin emails.
    if (_cachedAdminEmails.isEmpty) {
      return hardcodedAdmins.contains(clean);
    }
    return _cachedAdminEmails.contains(clean);
  }

  /// Returns the current school ID set during login.
  /// Throws a [StateError] if the school ID has not been initialized (session restore
  /// or login race condition), preventing queries from targeting an uninitialized
  /// context.
  static String get currentSchoolId {
    final id = BaseFirestoreService.currentSchoolId;
    if (id == null) {
      throw StateError('schoolId has not been initialized yet.');
    }
    return id;
  }

  static AuthService? _instance;
  AuthService._();
  factory AuthService() => _instance ??= AuthService._();
  static set mockInstance(AuthService? mock) => _instance = mock;

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
    await prefs.setString(_keyEmail, email.trim().toLowerCase());
    await prefs.setString(_keyRole, role.trim());

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

    // Guardian's provisioned admissionId (#39) — stored independently of the
    // single studentClass/roll because guardian logins persist a studentLinks
    // list instead. Drives the safe 'guardian_adm:' notification subscription.
    if (studentAdmissionId != null && studentAdmissionId.isNotEmpty) {
      await prefs.setString(_keyStudentAdmissionId, studentAdmissionId);
    } else {
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
      studentAdmissionId: studentAdmissionId,
    );

    // Trigger legacy birthday migration
    BirthdayService().migrateLegacyBirthdays();
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
    // Independent of studentClass (guardian logins persist studentLinks instead).
    final sAdm = prefs.getString(_keyStudentAdmissionId);
    if (sAdm != null && sAdm.isNotEmpty) result['studentAdmissionId'] = sAdm;

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
    // Issue 7: retry once on failure and log so we know if Firebase sign-out
    // is silently failing. Always proceed to clear local prefs regardless
    // so the local session is evicted even if Firebase Auth sign-out fails.
    try {
      await _auth.signOut();
    } catch (e) {
      AppLogger.e('AuthService', 'signOut failed, retrying: $e', e);
      try {
        await _auth.signOut();
      } catch (e2) {
        // Both attempts failed — log but do not block session clearing.
        AppLogger.e('AuthService', 'signOut retry also failed: $e2', e2);
      }
    }

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
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled. Contact your administrator.';
      case 'too-many-requests':
        return 'Too many failed attempts. Please try again later.';
      case 'operation-not-allowed':
        return 'Sign-in method is not enabled. Contact your administrator.';
      case 'network-request-failed':
        return 'No internet connection. Please check your network.';
      case 'email-already-in-use':
        return 'This email is already registered.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'requires-recent-login':
        return 'Please sign in again before changing your password.';
      default:
        AppLogger.e('AuthService', 'Firebase Auth Error (${e.code}): ${e.message}', e);
        return 'Authentication error. Please try again.';
    }
  }

  // ── Self-service account deletion (A4 / Google Play requirement) ───────────

  /// Files a deletion request for the CALLER's own account at
  /// `schools/{sid}/account_deletion_requests/{email}`. School management
  /// processes the request via the existing deleteAccount cascade — accounts
  /// are school-provisioned, so deletion is approved by the data controller
  /// rather than executed self-serve.
  ///
  /// Returns true when a new request was filed, false when one is already
  /// pending. Throws on permission/network failure so the UI can show an error.
  Future<bool> requestAccountDeletion({String? reason}) async {
    final email = _auth.currentUser?.email?.toLowerCase().trim();
    if (email == null || email.isEmpty) {
      throw StateError('No signed-in user to request deletion for.');
    }
    final sid = AuthService.currentSchoolId;
    // Doc ID = email → idempotent: one open request per account, and the
    // existence check is a plain get() permitted by the own-email read rule.
    final ref = FirebaseFirestore.instance
        .collection('schools')
        .doc(sid)
        .collection('account_deletion_requests')
        .doc(email);
    final existing = await ref.get();
    if (existing.exists) return false;

    final session = await getSession();
    await ref.set({
      'email':       email,
      'role':        session?['role'] ?? '',
      'name':        session?['name'] ?? '',
      'status':      'pending',
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      'requestedAt': FieldValue.serverTimestamp(),
    });
    return true;
  }

  // ── Biometric (Fingerprint/Face ID) helpers ───────────────────────────────

  Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyUseBiometric) ?? false;
  }

  Future<void> setBiometricEnabled({
    required bool enabled,
    String? email,
    String? password,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyUseBiometric, enabled);
    if (enabled && email != null && password != null) {
      await prefs.setString(_keyBiometricEmail, email);
      await prefs.setString(_keyBiometricPassword, password);
    } else {
      await prefs.remove(_keyBiometricEmail);
      await prefs.remove(_keyBiometricPassword);
    }
  }

  Future<Map<String, String>?> getBiometricCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(_keyBiometricEmail);
    final password = prefs.getString(_keyBiometricPassword);
    if (email != null && password != null) {
      return {'email': email, 'password': password};
    }
    return null;
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/teacher.dart';
import '../models/timetable_entry.dart';
import 'auth_service.dart';
import 'base_firestore_service.dart';

class TimetableService extends BaseFirestoreService {
  static final _db = FirebaseFirestore.instance;

  // allowed_users stays at the Firestore root — it is the user→school mapping
  // table and must be readable before schoolId is known (login flow reads it
  // to determine which school the user belongs to).
  static final _allowedUsers = _db.collection('allowed_users');

  static final TimetableService _instance = TimetableService._();
  TimetableService._();
  factory TimetableService() => _instance;

  // In-memory cache for settings (invalidated on every saveSettings call)
  static Map<String, dynamic>? _settingsCache;

  // ── School-scoped collection helpers ────────────────────────────────────────
  // Everything except allowed_users lives under schools/{schoolId}/.
  // _schoolId reads the value set at login time; falls back to 'school_1'
  // so existing deployments keep working before migration.

  String get _schoolId => AuthService.currentSchoolId;

  CollectionReference<Map<String, dynamic>> get _teachers =>
      schoolCollection(_schoolId, 'teachers');

  CollectionReference<Map<String, dynamic>> get _settings =>
      schoolCollection(_schoolId, 'settings');

  CollectionReference<Map<String, dynamic>> get _tt =>
      schoolCollection(_schoolId, 'timetable');

  CollectionReference<Map<String, dynamic>> get _duties =>
      schoolCollection(_schoolId, 'duties');

  CollectionReference<Map<String, dynamic>> get _substitutions =>
      schoolCollection(_schoolId, 'substitutions');

  CollectionReference<Map<String, dynamic>> get _leaveApps =>
      schoolCollection(_schoolId, 'leave_applications');

  // ── Teachers ──────────────────────────────────────────────────────────────

  Future<Teacher?> getTeacherById({String? id, String? teacherId}) async {
    final resolvedId = id ?? teacherId ?? '';
    return _getTeacherByIdInternal(resolvedId);
  }

  Future<Teacher?> _getTeacherByIdInternal(String id) async {
    final doc = await _teachers.doc(id).get();
    if (!doc.exists || doc.data() == null) return null;
    return Teacher.fromJson(Map<String, dynamic>.from(doc.data()!));
  }

  Future<List<Teacher>> getTeachers({String? schoolId, bool refresh = false}) async {
    final snap = await _teachers.get();
    final list = snap.docs
        .map((d) => Teacher.fromJson(Map<String, dynamic>.from(d.data())))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  /// Returns the classIds[] array that should be stamped on a teacher's
  /// allowed_users doc. The Firestore rules' `isClassTeacher(cls)` predicate
  /// reads from this array — without it teachers cannot write students /
  /// attendance / homework / exam results / copy_checks for their classes.
  ///
  /// Composition:
  ///   - if isClassTeacher == true, include `classTeacherOf` (if non-empty);
  ///   - plus everything in `assignedClasses` (for subject teachers).
  /// Duplicates are de-duplicated.
  List<String> _classIdsFor(Teacher t) {
    final s = <String>{};
    if (t.isClassTeacher && (t.classTeacherOf ?? '').isNotEmpty) {
      s.add(t.classTeacherOf!);
    }
    s.addAll(t.assignedClasses.where((c) => c.isNotEmpty));
    return s.toList();
  }

  Future<void> addTeacher(String schoolId, Teacher teacher) async {
    await _teachers.doc(teacher.id).set(teacher.toJson());

    // Only provision auth if the teacher has an email.
    final normEmail = teacher.email.trim().toLowerCase();
    if (normEmail.isEmpty || !normEmail.contains('@')) return;

    // Write allowed_users entry so login's role lookup succeeds.
    // classIds is stamped so the firestore.rules class-teacher checks pass
    // (otherwise teachers can't write students/attendance for their class).
    await _allowedUsers.doc(normEmail).set({
      'role':      'teacher',
      'email':     normEmail,
      'name':      teacher.name,
      'teacherId': teacher.id,
      'schoolId':  schoolId,
      'classIds':  _classIdsFor(teacher),
      'status':    'pending',
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Create Firebase Auth account via REST (does not displace current admin session).
    final tempPassword = 'Tmp_${DateTime.now().millisecondsSinceEpoch}';
    try {
      final res = await http.post(
        Uri.parse(
            'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$_firebaseApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email':             normEmail,
          'password':          tempPassword,
          'returnSecureToken': false,
        }),
      );
      final body    = jsonDecode(res.body) as Map<String, dynamic>;
      final errCode = (body['error'] as Map?)?['message'] as String? ?? '';
      if (errCode != 'EMAIL_EXISTS' && body['localId'] == null) {
        // ignore: avoid_print
        print('Firebase Auth creation warning for $normEmail: $errCode');
      }
    } catch (_) {
      // Network error — non-fatal; Firestore record is written.
    }

    // Send invitation / password-setup email.
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: normEmail);
    } catch (_) {
      // Non-fatal.
    }
  }

  Future<void> updateTeacher(String schoolId, Teacher teacher) async {
    await _teachers.doc(teacher.id).set(teacher.toJson());

    // Keep allowed_users in sync (email is the doc ID so can't change).
    // classIds is re-stamped here so changing a teacher's class assignment
    // immediately propagates to the rule-evaluation path; otherwise edits
    // would silently fail to grant/revoke per-class access.
    final normEmail = teacher.email.trim().toLowerCase();
    if (normEmail.isEmpty || !normEmail.contains('@')) return;
    try {
      await _allowedUsers.doc(normEmail).update({
        'name':     teacher.name,
        'classIds': _classIdsFor(teacher),
      });
    } catch (_) {}
  }

  Future<void> removeTeacher(String schoolId, String id) async {
    await _teachers.doc(id).delete();

    // Scrub teacher from every timetable slot
    final snap  = await _tt.get();
    final batch = _db.batch();
    for (final doc in snap.docs) {
      final raw = Map<String, dynamic>.from(
          (doc.data()['data'] as Map?) ?? {});
      var dirty = false;
      raw.forEach((day, bellsRaw) {
        final bells = Map<String, dynamic>.from(bellsRaw as Map);
        bells.forEach((bell, entryRaw) {
          final e = Map<String, dynamic>.from(entryRaw as Map);
          if (e['teacherId'] == id) {
            bells[bell] = {'teacherId': null, 'subject': null};
            dirty = true;
          }
        });
        raw[day] = bells;
      });
      if (dirty) batch.set(doc.reference, {'data': raw});
    }
    await batch.commit();
  }

  // ── Settings ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getSettings({String? schoolId}) async {
    // Return cached copy if available — avoids a Firestore round-trip every
    // time the coordinator dashboard (or any other screen) calls this.
    if (_settingsCache != null) return _settingsCache!;

    final doc = await _settings.doc('main').get();
    Map<String, dynamic> result;

    if (!doc.exists || doc.data() == null) {
      result = {
        'numberOfBells': 8,
        'classes': ['Class 6', 'Class 7', 'Class 8', 'Class 9', 'Class 10'],
      };
    } else {
      result = Map<String, dynamic>.from(doc.data()!);
      // classes is stored as List — ensure it's List<String>
      if (result['classes'] != null) {
        result['classes'] = List<String>.from(result['classes'] as List);
      }
    }

    if (!result.containsKey('bells') ||
        (result['bells'] as List?)?.isEmpty != false) {
      final n = result['numberOfBells'] as int? ?? 8;
      result['bells'] =
          List.generate(n, (_) => {'duration': 45, 'isLunch': false});
      result['firstBellTime'] = '08:00';
    } else {
      result['bells'] = List<Map<String, dynamic>>.from(
          (result['bells'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
    }

    result['numberOfBells'] = (result['bells'] as List).length;
    _settingsCache = result; // cache for all subsequent calls this session
    return result;
  }

  Future<void> saveSettings(String schoolId, Map<String, dynamic> settings) async {
    _settingsCache = null; // invalidate so next getSettings re-fetches
    await _settings.doc('main').set(settings);
  }

  /// Drops the in-memory settings cache so the next [getSettings] re-fetches.
  /// Call this after another service (e.g. SchoolSettingsService, when the
  /// owner edits the class list) writes to settings/main, so screens reading
  /// classes through getSettings pick up the change within the same session.
  static void invalidateSettingsCache() => _settingsCache = null;

  /// Adds [className] to the school's class list (if not already present) and
  /// returns the updated, de-duplicated list. Lets admins create classes on the
  /// fly without opening the full Timetable Settings screen.
  Future<List<String>> addClassToSettings(String className) async {
    final name = className.trim();
    final settings = Map<String, dynamic>.from(await getSettings());
    final classes = List<String>.from(settings['classes'] ?? []);
    if (name.isEmpty || classes.contains(name)) return classes;
    classes.add(name);
    settings['classes'] = classes;
    await saveSettings(_schoolId, settings);
    return classes;
  }

  // ── Timetable ─────────────────────────────────────────────────────────────
  // Shape: className → day → bell(1-indexed) → TimetableEntry

  Future<Map<String, Map<String, Map<int, TimetableEntry>>>> getTimetable() async {
    final snap   = await _tt.get();
    final result = <String, Map<String, Map<int, TimetableEntry>>>{};

    for (final doc in snap.docs) {
      final className = doc.id;
      final rawData   = (doc.data()['data'] as Map?) ?? {};
      final dayMap    = <String, Map<int, TimetableEntry>>{};

      rawData.forEach((day, bellsRaw) {
        final bells = Map<String, dynamic>.from(bellsRaw as Map);
        dayMap[day as String] = bells.map(
          (k, v) => MapEntry(int.parse(k), TimetableEntry.fromJson(v)),
        );
      });
      result[className] = dayMap;
    }
    return result;
  }

  Future<void> _saveTimetable(
      Map<String, Map<String, Map<int, TimetableEntry>>> tt) async {
    final batch = _db.batch();
    for (final clsEntry in tt.entries) {
      final data = clsEntry.value.map(
        (day, bells) => MapEntry(
          day,
          bells.map((k, e) => MapEntry(k.toString(), e.toJson())),
        ),
      );
      batch.set(_tt.doc(clsEntry.key), {'data': data});
    }
    await batch.commit();
  }

  Future<String?> findClash({
    required String forClass,
    required String day,
    required int    bell,
    required String teacherId,
  }) async {
    final tt = await getTimetable();
    for (final clsEntry in tt.entries) {
      if (clsEntry.key == forClass) continue;
      if (clsEntry.value[day]?[bell]?.teacherId == teacherId) {
        return clsEntry.key;
      }
    }
    return null;
  }

  // ── Duties ────────────────────────────────────────────────────────────────

  String _dutyKey() {
    final d = DateTime.now();
    return '${d.year}-${d.month}-${d.day}';
  }

  /// Returns map of teacherId → duty string for today.
  Future<Map<String, String>> getTodayDuties() async {
    final doc = await _duties.doc(_dutyKey()).get();
    if (!doc.exists || doc.data() == null) return {};
    final raw = Map<String, dynamic>.from(
        (doc.data()!['assignments'] as Map?) ?? {});
    return raw.map((k, v) => MapEntry(k, v as String));
  }

  Future<void> saveTodayDuties(Map<String, String> duties) async {
    await _duties.doc(_dutyKey()).set({
      'assignments': duties,
      'updatedAt':   FieldValue.serverTimestamp(),
    });
  }

  // ── Allowed Users (Admin manages who can log in) ──────────────────────────
  // allowed_users stays at the root — see comment at class top.

  Future<List<Map<String, dynamic>>> getAllowedUsers() async {
    final snap = await _allowedUsers.get();
    return snap.docs.map((d) {
      final data       = Map<String, dynamic>.from(d.data());
      final rawClasses = data['assignedClasses'];
      return <String, dynamic>{
        'email':           d.id,
        'role':            (data['role']         as String? ?? 'teacher'),
        'studentClass':    (data['studentClass'] as String? ?? ''),
        'studentRoll':     (data['studentRoll']  as int?    ?? 0),
        'assignedClasses': rawClasses != null
            ? List<String>.from(rawClasses as List)
            : <String>[],
      };
    }).toList()
      ..sort((a, b) => (a['email'] as String).compareTo(b['email'] as String));
  }

  Future<List<Map<String, dynamic>>> getAllowedOwners() async {
    final snap = await _allowedUsers.where('role', isEqualTo: 'owner').get();
    return snap.docs.map((d) {
      final data       = Map<String, dynamic>.from(d.data());
      final rawClasses = data['assignedClasses'];
      return <String, dynamic>{
        'email':           d.id,
        'role':            (data['role']         as String? ?? 'teacher'),
        'studentClass':    (data['studentClass'] as String? ?? ''),
        'studentRoll':     (data['studentRoll']  as int?    ?? 0),
        'assignedClasses': rawClasses != null
            ? List<String>.from(rawClasses as List)
            : <String>[],
      };
    }).toList()
      ..sort((a, b) => (a['email'] as String).compareTo(b['email'] as String));
  }

  /// Returns the assigned classes for a coordinator/principal, or null if not set.
  Future<({List<String>? assignedClasses, String? schoolId})> getAssignedClasses(
      String email) async {
    final doc = await _allowedUsers.doc(email.toLowerCase().trim()).get();
    if (!doc.exists || doc.data() == null) {
      return (assignedClasses: null, schoolId: null);
    }
    final data     = doc.data()!;
    final raw      = data['assignedClasses'];
    final schoolId = data['schoolId'] as String?;
    List<String>? classes;
    if (raw != null) {
      final list = List<String>.from(raw as List);
      classes = list.isEmpty ? null : list;
    }
    return (assignedClasses: classes, schoolId: schoolId);
  }

  Future<void> updateAllowedUser(
    String email, {
    required String role,
    // newPassword is intentionally ignored — credentials live in Firebase Auth.
    // Call resendInvitationEmail() to trigger a password-reset link instead.
    @Deprecated('Password field removed from allowed_users. Use resendInvitationEmail() instead.')
    String?       newPassword,
    String?       studentClass,
    int?          studentRoll,
    List<String>? assignedClasses,
  }) async {
    final docRef = _allowedUsers.doc(email.toLowerCase().trim());
    final data   = <String, dynamic>{'role': role};
    // password is no longer stored in Firestore — Firebase Auth owns credentials.
    if (role == 'guardian' && studentClass != null && studentRoll != null) {
      data['studentClass'] = studentClass;
      data['studentRoll']  = studentRoll;
    } else {
      data['studentClass'] = null;
      data['studentRoll']  = null;
    }
    if (role == 'coordinator' || role == 'principal' || role == 'owner') {
      data['assignedClasses'] = assignedClasses ?? [];
    } else {
      data['assignedClasses'] = null;
    }
    await docRef.update(data);
  }

  // Firebase Web API key — used only to create Auth accounts server-side
  // without displacing the currently signed-in user's session.
  static const _firebaseApiKey = 'AIzaSyB9dyjWRfwMeq8-J6juhYdizI-584MCkBE';

  /// Creates a profile in [allowed_users] and provisions a Firebase Auth account.
  ///
  /// [password] is only used as the temporary Firebase Auth credential for the
  /// REST account-creation call. It is **never** written to Firestore.
  /// Pass an empty string (or omit entirely via the named overload) to have a
  /// secure temp password generated automatically — a password-reset/invite
  /// email is always sent regardless.
  Future<void> addAllowedUser(
    String email,
    // password is ONLY used for the transient Firebase Auth REST call.
    // It is NOT stored in Firestore. Pass '' to auto-generate a temp password.
    String password,
    String role, {
    String?       name,
    String?       schoolId,
    String?       studentClass,
    int?          studentRoll,
    List<String>? assignedClasses,
    String?       createdByEmail,
    String?       createdByRole,
  }) async {
    final normEmail = email.toLowerCase().trim();

    // 1. Write to allowed_users — no password field; credentials live in Firebase Auth.
    final data = <String, dynamic>{
      'role':      role,
      'email':     normEmail,
      // 'password' intentionally omitted — Firebase Auth owns credentials.
      'status':    'pending',
      'createdAt': FieldValue.serverTimestamp(),
      if (name           != null && name.isNotEmpty)     'name':          name,
      if (schoolId       != null && schoolId.isNotEmpty) 'schoolId':      schoolId,
      if (createdByEmail != null) 'createdByEmail': createdByEmail,
      if (createdByRole  != null) 'createdByRole':  createdByRole,
    };
    if (role == 'guardian' && studentClass != null && studentRoll != null) {
      data['studentClass'] = studentClass;
      data['studentRoll']  = studentRoll;
    }
    if (role == 'coordinator' || role == 'principal' || role == 'owner') {
      data['assignedClasses'] = assignedClasses ?? [];
    }
    await _allowedUsers.doc(normEmail).set(data);

    // 2. Create Firebase Auth account via REST (doesn't sign out current user).
    //    If the account already exists, skip silently.
    //    Use caller's password if provided, otherwise generate a secure temp one.
    final authPass = password.isNotEmpty
        ? password
        : 'Tmp_${normEmail.hashCode.abs()}${DateTime.now().millisecondsSinceEpoch}!Aa1';
    try {
      final res = await http.post(
        Uri.parse(
            'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$_firebaseApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email':             normEmail,
          'password':          authPass,
          'returnSecureToken': false,
        }),
      );
      final body    = jsonDecode(res.body) as Map<String, dynamic>;
      final errCode = (body['error'] as Map?)?['message'] as String? ?? '';
      // EMAIL_EXISTS is fine — the account was already created before.
      if (body['localId'] == null && errCode != 'EMAIL_EXISTS') {
        // Log but don't rethrow — Firestore write succeeded; Auth failure is
        // non-fatal and the admin can resend the invite.
        // ignore: avoid_print
        print('Firebase Auth creation warning for $normEmail: $errCode');
      }
    } catch (_) {
      // Network error — non-fatal; Firestore record is written.
    }

    // 3. Send invitation / password-setup email via Firebase Auth.
    //    The user will click the link to set their own password.
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: normEmail);
    } catch (_) {
      // Non-fatal; admin can resend from the user management screen.
    }
  }

  /// Returns users created by the given creator email.
  Future<List<Map<String, dynamic>>> getUsersCreatedBy(
      String creatorEmail) async {
    final snap = await _allowedUsers
        .where('createdByEmail', isEqualTo: creatorEmail.toLowerCase().trim())
        .get();
    return snap.docs.map((d) {
      final data = Map<String, dynamic>.from(d.data());
      return <String, dynamic>{
        'email':           d.id,
        'role':            data['role']           as String?   ?? '',
        'createdAt':       data['createdAt'],
        'createdByEmail':  data['createdByEmail'] as String?   ?? '',
        'createdByRole':   data['createdByRole']  as String?   ?? '',
        'studentClass':    data['studentClass']   as String?   ?? '',
        'studentRoll':     data['studentRoll']    as int?      ?? 0,
        'assignedClasses': data['assignedClasses'] != null
            ? List<String>.from(data['assignedClasses'] as List)
            : <String>[],
      };
    }).toList()
      ..sort((a, b) => (a['email'] as String).compareTo(b['email'] as String));
  }

  /// Returns {studentClass, studentRoll} for a guardian, or null if not found.
  Future<Map<String, dynamic>?> getGuardianLink(String email) async {
    final doc = await _allowedUsers.doc(email.toLowerCase().trim()).get();
    if (!doc.exists || doc.data() == null) return null;
    final data = doc.data()!;
    if (data['role'] != 'guardian') return null;
    final cls     = data['studentClass']   as String?;
    final roll    = data['studentRoll']    as int?;
    final section = data['studentSection'] as String? ?? '';
    if (cls == null || roll == null) return null;
    return {'studentClass': cls, 'studentRoll': roll, 'studentSection': section};
  }

  Future<void> removeAllowedUser(String email) async {
    await _allowedUsers.doc(email.toLowerCase().trim()).delete();
  }

  /// Marks an account active after first successful login.
  Future<void> markUserActive(String email) async {
    await _allowedUsers
        .doc(email.toLowerCase().trim())
        .update({'status': 'active'});
  }

  /// Resends the invitation / password-setup email for an existing account.
  Future<void> resendInvitationEmail(String email) async {
    try {
      await FirebaseAuth.instance
          .sendPasswordResetEmail(email: email.toLowerCase().trim());
    } catch (_) {
      // Ignored — caller can surface a success message; failure is non-critical.
    }
  }

  /// Provisions Firebase Auth + allowed_users for a teacher who was added
  /// before the automatic provisioning was in place, then sends invite email.
  Future<void> provisionTeacherLoginAccess(Teacher teacher) async {
    final normEmail = teacher.email.trim().toLowerCase();
    if (normEmail.isEmpty || !normEmail.contains('@')) return;

    // The allowed_users write MUST include schoolId — both the principal- and
    // admin-scoped firestore rule branches require 'schoolId' in
    // request.resource.data and that it matches userSchoolId(). Without this
    // field the merge-set is denied as "permission-denied", which is the bug
    // that broke the Send Login Invite button. Prefer the caller's current
    // school (matches the rules' userSchoolId() check); fall back to the
    // teacher's own schoolId only when no session-scoped school is set.
    final effectiveSchoolId = _schoolId.isNotEmpty ? _schoolId : teacher.schoolId;

    // Ensure allowed_users doc exists with the correct role.
    // classIds is included so the rule-side isClassTeacher(cls) check passes
    // for teachers provisioned through the Send Login Invite path.
    await _allowedUsers.doc(normEmail).set({
      'role':      'teacher',
      'email':     normEmail,
      'name':      teacher.name,
      'teacherId': teacher.id,
      'schoolId':  effectiveSchoolId,
      'classIds':  _classIdsFor(teacher),
      'status':    'pending',
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Create Firebase Auth account (no-op if already exists).
    final tempPassword = 'Tmp_${DateTime.now().millisecondsSinceEpoch}';
    try {
      final res = await http.post(
        Uri.parse(
            'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$_firebaseApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email':             normEmail,
          'password':          tempPassword,
          'returnSecureToken': false,
        }),
      );
      final body    = jsonDecode(res.body) as Map<String, dynamic>;
      final errCode = (body['error'] as Map?)?['message'] as String? ?? '';
      if (errCode != 'EMAIL_EXISTS' && body['localId'] == null) {
        // ignore: avoid_print
        print('Firebase Auth creation warning for $normEmail: $errCode');
      }
    } catch (_) {}

    // Send invitation / password-setup email.
    await FirebaseAuth.instance.sendPasswordResetEmail(email: normEmail);
  }

  /// Provisions Firebase Auth + allowed_users for a guardian email set on a
  /// student, then sends a password-setup invite. Safe to call multiple times
  /// (arrayUnion keeps existing student links, EMAIL_EXISTS is silently skipped).
  /// Optionally stores [phone] (E.164) to enable phone-OTP sign-in later.
  Future<void> provisionGuardianLoginAccess({
    required String email,
    required String studentClass,
    required int    studentRoll,
    required String studentName,
    String?         schoolId,
    String?         phone,   // E.164 format
  }) async {
    final normEmail = email.trim().toLowerCase();
    if (!normEmail.contains('@')) return;

    // Write/merge allowed_users, preserving existing student links.
    await linkGuardianEmail(
      email:        normEmail,
      studentClass: studentClass,
      studentRoll:  studentRoll,
      studentName:  studentName,
      schoolId:     schoolId,
      phone:        phone,
    );

    // Create Firebase Auth account via REST (no-op if EMAIL_EXISTS).
    final tempPassword = 'Tmp_${DateTime.now().millisecondsSinceEpoch}';
    try {
      final res = await http.post(
        Uri.parse(
            'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$_firebaseApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email':             normEmail,
          'password':          tempPassword,
          'returnSecureToken': false,
        }),
      );
      final body    = jsonDecode(res.body) as Map<String, dynamic>;
      final errCode = (body['error'] as Map?)?['message'] as String? ?? '';
      if (errCode != 'EMAIL_EXISTS' && body['localId'] == null) {
        // ignore: avoid_print
        print('Firebase Auth creation warning for guardian $normEmail: $errCode');
      }
    } catch (_) {}

    // Send invite / password-setup email.
    await FirebaseAuth.instance.sendPasswordResetEmail(email: normEmail);
  }

  /// Returns the role if the email is registered, or null if not found.
  Future<String?> getAllowedRole(String email) async {
    final doc = await _allowedUsers.doc(email.toLowerCase().trim()).get();
    if (!doc.exists || doc.data() == null) return null;
    return doc.data()!['role'] as String?;
  }

  /// @deprecated Password-based login is now handled by Firebase Auth.
  /// This method always returns null and will be removed in a future release.
  /// Use [AuthService.signInWithEmail] + [getAllowedUserDoc] instead.
  @Deprecated('Use Firebase Auth sign-in + getAllowedUserDoc. This method always returns null.')
  Future<String?> validateLogin(String email, String password) async => null;

  /// Looks up a guardian profile by phone number stored in [allowed_users].
  /// Returns the document data (with 'email' key added) or null if not found.
  Future<Map<String, dynamic>?> getGuardianByPhone(String phone) async {
    final normalized = phone.trim();
    if (normalized.isEmpty) return null;
    final snap = await _allowedUsers
        .where('phone', isEqualTo: normalized)
        .where('role',  isEqualTo: 'guardian')
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final d = snap.docs.first;
    return <String, dynamic>{
      ...Map<String, dynamic>.from(d.data()),
      'email': d.id,
    };
  }

  // ── Leave Applications ────────────────────────────────────────────────────────

  Future<void> submitLeaveApplication({
    String? schoolId,
    required String teacherId,
    required String teacherName,
    required String teacherEmail,
    required String toRole,
    required String startDate,
    required int    numberOfDays,
    required String reason,
  }) async {
    await _leaveApps.add({
      'teacherId'   : teacherId,
      'teacherName' : teacherName,
      'teacherEmail': teacherEmail,
      'toRole'      : toRole,
      'startDate'   : startDate,
      'numberOfDays': numberOfDays,
      'reason'      : reason,
      'status'      : 'pending',
      'createdAt'   : FieldValue.serverTimestamp(),
    });
  }

  /// Returns all leave applications, newest first.
  /// Optionally filter by status: 'pending' | 'approved' | 'rejected'.
  ///
  /// NOTE: When filtering by status we deliberately skip orderBy to avoid
  /// requiring a Firestore composite index (status + createdAt).  Results are
  /// sorted in-memory instead — negligible cost for the small number of leave
  /// apps a school typically has.
  Future<List<Map<String, dynamic>>> getLeaveApplications(
      {String? status, String? schoolId}) async {
    QuerySnapshot snap;
    if (status != null) {
      // No orderBy here — composite index not guaranteed to exist on all
      // deployments; sort in-memory after fetch instead.
      snap = await _leaveApps.where('status', isEqualTo: status).get();
    } else {
      snap = await _leaveApps.orderBy('createdAt', descending: true).get();
    }

    final list = snap.docs.map((d) {
      final data = Map<String, dynamic>.from(d.data() as Map);
      data['id'] = d.id;
      return data;
    }).toList();

    // Sort newest-first in-memory (works whether createdAt is a Timestamp or null)
    if (status != null) {
      list.sort((a, b) {
        final ta = a['createdAt'];
        final tb = b['createdAt'];
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return (tb as dynamic).compareTo(ta as dynamic);
      });
    }

    return list;
  }

  /// Real-time count of pending leave applications.
  Stream<int> streamPendingLeaveCount() =>
      _leaveApps
          .where('status', isEqualTo: 'pending')
          .snapshots()
          .map((snap) => snap.docs.length);

  Future<void> updateLeaveApplication(String schoolId, String id, String status,
      {String? note}) async {
    final update = <String, dynamic>{'status': status};
    if (note != null && note.isNotEmpty) update['coordinatorNote'] = note;
    await _leaveApps.doc(id).update(update);
  }

  // ── Student Leave Applications (submitted by Guardian) ────────────────────

  Future<void> submitStudentLeaveApplication({
    required String studentClass,
    required int    studentRoll,
    required String studentName,
    String?         guardianName,
    required String startDate,
    required int    numberOfDays,
    required String reason,
  }) async {
    await _leaveApps.add({
      'applicantType': 'guardian',
      'studentClass' : studentClass,
      'studentRoll'  : studentRoll,
      'studentName'  : studentName,
      if (guardianName != null && guardianName.isNotEmpty)
        'guardianName': guardianName,
      'toRole'       : 'teacher',
      'startDate'    : startDate,
      'numberOfDays' : numberOfDays,
      'reason'       : reason,
      'status'       : 'pending',
      'createdAt'    : FieldValue.serverTimestamp(),
    });
  }

  /// All student leaves for [studentClass] (class teacher view).
  Future<List<Map<String, dynamic>>> getStudentLeaveApplications({
    required String studentClass,
    String? status,
  }) async {
    Query q = _leaveApps
        .where('applicantType', isEqualTo: 'guardian')
        .where('studentClass',  isEqualTo: studentClass);
    if (status != null) q = q.where('status', isEqualTo: status);
    final snap = await q.get();
    final list = snap.docs.map((d) {
      final data = Map<String, dynamic>.from(d.data() as Map);
      data['id'] = d.id;
      return data;
    }).toList();
    list.sort((a, b) {
      final ta = a['createdAt'];
      final tb = b['createdAt'];
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return (tb as dynamic).compareTo(ta as dynamic);
    });
    return list;
  }

  /// Student leaves for a specific student (guardian history view).
  Future<List<Map<String, dynamic>>> getGuardianStudentLeaveHistory({
    required String studentClass,
    required int    studentRoll,
  }) async {
    final snap = await _leaveApps
        .where('applicantType', isEqualTo: 'guardian')
        .where('studentClass',  isEqualTo: studentClass)
        .where('studentRoll',   isEqualTo: studentRoll)
        .get();
    final list = snap.docs.map((d) {
      final data = Map<String, dynamic>.from(d.data() as Map);
      data['id'] = d.id;
      return data;
    }).toList();
    list.sort((a, b) {
      final ta = a['createdAt'];
      final tb = b['createdAt'];
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return (tb as dynamic).compareTo(ta as dynamic);
    });
    return list;
  }

  /// Real-time pending count for the class teacher badge.
  Stream<int> streamPendingStudentLeaveCount({required String studentClass}) =>
      _leaveApps
          .where('applicantType', isEqualTo: 'guardian')
          .where('studentClass',  isEqualTo: studentClass)
          .where('status',        isEqualTo: 'pending')
          .snapshots()
          .map((snap) => snap.docs.length);

  // ── Substitutions ─────────────────────────────────────────────────────────

  String _dateKeyFor(DateTime d) => '${d.year}-${d.month}-${d.day}';

  /// Returns map of '${className}_$bell' → teacherId for today's substitutions.
  Future<Map<String, String>> getTodaySubstitutions() =>
      getSubstitutionsForDate(DateTime.now());

  /// Returns substitutions for the given calendar date.
  Future<Map<String, String>> getSubstitutionsForDate(DateTime date) async {
    final doc = await _substitutions.doc(_dateKeyFor(date)).get();
    if (!doc.exists || doc.data() == null) return {};
    final raw = Map<String, dynamic>.from(doc.data()!);
    // Defensive: only keep String values (skip 'updatedAt' Timestamp etc).
    final out = <String, String>{};
    raw.forEach((k, v) {
      if (v is String && v.isNotEmpty) out[k] = v;
    });
    return out;
  }

  Future<void> setSubstitution(
          String className, int bell, String? teacherId) =>
      setSubstitutionForDate(DateTime.now(), className, bell, teacherId);

  Future<void> setSubstitutionForDate(
      DateTime date, String className, int bell, String? teacherId) async {
    final key    = '${className}_$bell';
    final docKey = _dateKeyFor(date);
    if (teacherId == null || teacherId.isEmpty) {
      await _substitutions
          .doc(docKey)
          .set({key: FieldValue.delete()}, SetOptions(merge: true));
    } else {
      await _substitutions.doc(docKey).set(
          {key: teacherId, 'updatedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true));
    }
  }

  Future<String?> assignTeacher({
    required String  className,
    required List<String> days,
    required int     bell,
    required String? teacherId,
    String?          subject,
    String?          schoolId,
  }) async {
    if (teacherId != null) {
      for (final day in days) {
        final clash = await findClash(
            forClass: className, day: day, bell: bell, teacherId: teacherId);
        if (clash != null) {
          return 'Clash on $day! Teacher already has Bell $bell in $clash';
        }
      }
    }
    final tt = await getTimetable();
    tt.putIfAbsent(className, () => {});
    for (final day in days) {
      tt[className]!.putIfAbsent(day, () => {});
      tt[className]![day]![bell] =
          TimetableEntry(teacherId: teacherId, subject: subject);
    }
    await _saveTimetable(tt);
    return null;
  }

  // ── User existence & coordinator helpers ───────────────────────────────────

  /// Returns the raw allowed_user document data for an email, or null.
  Future<Map<String, dynamic>?> getAllowedUserDoc(String email) async {
    final doc = await _allowedUsers.doc(email.toLowerCase().trim()).get();
    if (!doc.exists || doc.data() == null) return null;
    return Map<String, dynamic>.from(doc.data()!);
  }

  /// Returns guardian links (list of student references) for a guardian email.
  Future<List<Map<String, dynamic>>?> getGuardianLinks(String email) async {
    final doc = await _allowedUsers.doc(email.toLowerCase().trim()).get();
    if (!doc.exists || doc.data() == null) return null;
    final data = doc.data()!;
    if (data['role'] != 'guardian') return null;
    // Support both old single-link and new multi-link format
    final links = data['studentLinks'];
    if (links is List) {
      return links.whereType<Map<String, dynamic>>().toList();
    }
    // Fall back to single link format
    final cls  = data['studentClass'] as String?;
    final roll = data['studentRoll'];
    if (cls == null || roll == null) return null;
    return [{'studentClass': cls, 'studentRoll': roll, 'studentName': ''}];
  }

  /// Returns true if the given email exists in the allowed_users collection.
  Future<bool> userExists(String email) async {
    final snap = await _allowedUsers
        .doc(email.toLowerCase().trim())
        .get();
    return snap.exists;
  }

  /// Links a guardian email to a student in the allowed_users collection.
  /// Optionally stores the guardian's phone number for phone-OTP sign-in.
  Future<void> linkGuardianEmail({
    required String email,
    required String studentClass,
    required int    studentRoll,
    String?         studentName,
    String?         schoolId,
    String?         phone,           // E.164 format, e.g. "+919876543210"
  }) async {
    final docRef = _allowedUsers.doc(email.toLowerCase().trim());
    final doc    = await docRef.get();
    final data   = doc.exists && doc.data() != null
        ? Map<String, dynamic>.from(doc.data()!)
        : <String, dynamic>{};

    final links = List<Map<String, dynamic>>.from(
        (data['studentLinks'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ?? []);

    final exists = links.any((l) =>
        l['studentClass'] == studentClass && l['studentRoll'] == studentRoll);
    if (!exists) {
      links.add({
        'studentClass': studentClass,
        'studentRoll':  studentRoll,
        if (studentName != null) 'studentName': studentName,
      });
    }

    await docRef.set({
      'role':         data['role'] ?? 'guardian',
      'email':        email.toLowerCase().trim(),
      'studentLinks': links,
      'studentClass': studentClass,  // legacy compat
      'studentRoll':  studentRoll,   // legacy compat
      if (schoolId != null) 'schoolId': schoolId,
      if (phone != null && phone.isNotEmpty) 'phone': phone.trim(),
    }, SetOptions(merge: true));
  }

  /// Removes a student link from a guardian's allowed_users document.
  Future<void> removeGuardianLink({
    required String email,
    required String studentClass,
    required int    studentRoll,
  }) async {
    final docRef = _allowedUsers.doc(email.toLowerCase().trim());
    final doc    = await docRef.get();
    if (!doc.exists || doc.data() == null) return;

    final data  = Map<String, dynamic>.from(doc.data()!);
    final links = List<Map<String, dynamic>>.from(
        (data['studentLinks'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ?? []);
    links.removeWhere((l) =>
        l['studentClass'] == studentClass && l['studentRoll'] == studentRoll);

    await docRef.update({'studentLinks': links});
  }

  /// Returns coordinators for the given school.
  ///
  /// The query MUST constrain on `schoolId` as well as `role`: the Firestore
  /// rules only allow management to read coordinator docs in their own school
  /// (`resource.data.schoolId == userSchoolId()`). Because rules are not
  /// filters, an unconstrained list query is rejected wholesale with
  /// permission-denied — the query has to prove every returned doc is readable.
  /// Two equality filters use a zigzag merge join, so no composite index needed.
  Future<List<Map<String, dynamic>>> getCoordinators(String schoolId) async {
    final snap = await _allowedUsers
        .where('role', isEqualTo: 'coordinator')
        .where('schoolId', isEqualTo: schoolId)
        .get();
    return snap.docs.map((d) {
      final data = Map<String, dynamic>.from(d.data());
      data['email'] = d.id;
      return data;
    }).toList();
  }

  // ── Overloaded getLeaveApplications with schoolId support ─────────────────

  /// [schoolId] is accepted but currently unused (single-school deployment).
  Future<List<Map<String, dynamic>>> getLeaveApplicationsForSchool({
    String? schoolId,
    String? status,
  }) => getLeaveApplications(status: status);

  // ── getTodayAbsentTeachersInfo with optional positional schoolId ──────────

  Future<Map<String, int>> getTodayAbsentTeachersInfo([String? schoolId]) async {
    final now = DateTime.now();

    final allLeavesFuture = getLeaveApplications();
    final timetableFuture = getTimetable();
    final subsFuture      = getTodaySubstitutions();

    final allLeaves = await allLeavesFuture;
    final timetable = await timetableFuture;
    final subs      = await subsFuture;

    final absentIds = <String>{};
    for (final app in allLeaves) {
      if (app['status'] != 'approved') continue;
      final startStr = app['startDate'] as String?;
      if (startStr == null) continue;
      final start = DateTime.tryParse(startStr);
      if (start == null) continue;
      final days  = (app['numberOfDays'] as num?)?.toInt() ?? 1;
      final end   = start.add(Duration(days: days - 1));
      final today = DateTime(now.year, now.month, now.day);
      if (!today.isBefore(DateTime(start.year, start.month, start.day)) &&
          !today.isAfter(DateTime(end.year, end.month, end.day))) {
        final tid = app['teacherId'] as String?;
        if (tid != null && tid.isNotEmpty) absentIds.add(tid);
      }
    }

    const dayNames = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
    ];
    final todayName  = dayNames[(now.weekday - 1).clamp(0, 5)];
    var   unassigned = 0;
    timetable.forEach((className, dayMap) {
      final bellMap = dayMap[todayName] ?? {};
      bellMap.forEach((bell, entry) {
        if (entry.teacherId != null && absentIds.contains(entry.teacherId)) {
          final key = '${className}_$bell';
          if (!subs.containsKey(key)) unassigned++;
        }
      });
    });

    return {'absentCount': absentIds.length, 'unassignedBells': unassigned};
  }
}

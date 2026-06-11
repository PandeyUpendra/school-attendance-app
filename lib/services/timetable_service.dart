import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../firebase_options.dart';
import '../models/teacher.dart';
import '../models/timetable_entry.dart';
import '../utils/app_logger.dart';
import '../utils/phone_utils.dart';
import '../utils/school_clock.dart';
import '../utils/secure_password.dart';
import 'auth_service.dart';
import 'base_firestore_service.dart';
import 'role_permission_service.dart';

/// Thrown by [TimetableService.addAllowedUser] when the target email already
/// holds a *different* role. One email maps to exactly one role — the existing
/// account must be deleted before the address can be reassigned.
class RoleConflictException implements Exception {
  final String email;
  final String existingRole;
  final String attemptedRole;
  const RoleConflictException(this.email, this.existingRole, this.attemptedRole);

  @override
  String toString() =>
      '$email already has a ${RolePermissionService.roleDisplayName(existingRole)} '
      'account. One email can hold only one role — delete that account first to '
      'reassign it as a ${RolePermissionService.roleDisplayName(attemptedRole)}.';
}

class TimetableService extends BaseFirestoreService {
  static final _db = FirebaseFirestore.instance;

  // allowed_users stays at the Firestore root — it is the user→school mapping
  // table and must be readable before schoolId is known (login flow reads it
  // to determine which school the user belongs to).
  static final _allowedUsers = _db.collection('allowed_users');

  static final TimetableService _instance = TimetableService._();
  TimetableService._();
  factory TimetableService() => _instance;
  static TimetableService get instance => _instance;

  // In-memory cache for settings. Invalidated on every saveSettings call, AND
  // expires after [_settingsCacheTtl] so a change made on ANOTHER device is
  // picked up within minutes instead of requiring an app restart (#112).
  static Map<String, dynamic>? _settingsCache;
  static DateTime? _settingsCacheAt;
  static const Duration _settingsCacheTtl = Duration(minutes: 5);

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

  Future<List<Teacher>> getTeachersForIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final uniqueIds = ids.toSet().toList();
    final chunks = <List<String>>[];
    for (var i = 0; i < uniqueIds.length; i += 30) {
      chunks.add(uniqueIds.sublist(i, i + 30 > uniqueIds.length ? uniqueIds.length : i + 30));
    }
    final results = <Teacher>[];
    for (final chunk in chunks) {
      final snap = await _teachers.where(FieldPath.documentId, whereIn: chunk).get();
      results.addAll(snap.docs.map((d) => Teacher.fromJson(Map<String, dynamic>.from(d.data()))));
    }
    results.sort((a, b) => a.name.compareTo(b.name));
    return results;
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
    final normEmail = teacher.email.trim().toLowerCase();
    if (normEmail.isEmpty || !normEmail.contains('@')) {
      await _teachers.doc(teacher.id).set(teacher.toJson());
      return;
    }

    // Verify email is not registered in another school or has role conflict
    DocumentSnapshot<Map<String, dynamic>>? existingDoc;
    try {
      existingDoc = await _allowedUsers.doc(normEmail).get();
    } catch (_) {}

    if (existingDoc != null && existingDoc.exists) {
      final existingSchoolId = existingDoc.data()?['schoolId'] as String?;
      final existingRole = existingDoc.data()?['role'] as String?;

      if (existingSchoolId != null && existingSchoolId.isNotEmpty && existingSchoolId != schoolId) {
        throw Exception(
          'This email is already in use by another school. An email address can only be associated with one school.'
        );
      }

      if (existingRole != null && existingRole.isNotEmpty && existingRole != 'teacher') {
        throw RoleConflictException(normEmail, existingRole, 'teacher');
      }
    }

    // Purge any stale Auth record before creating
    await _purgeStaleAuthRecord(normEmail);

    await _teachers.doc(teacher.id).set(teacher.toJson());

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
    // Strong random temp password — NOT timestamp-derived (which narrowed the
    // brute-force window to the createdAt millisecond, review #7). The teacher
    // sets their own password via the invite link below.
    final tempPassword = generateSecurePassword();
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
        AppLogger.d('TimetableService',
            'Firebase Auth creation warning for $normEmail: $errCode');
      }
    } catch (_) {
      // Network error — non-fatal; Firestore record is written.
    }

    // Send invitation / password-setup email.
    try {
      await AuthService().sendPasswordEmailViaFunction(normEmail, invite: true);
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

  /// Self-heal a teacher's own `allowed_users.classIds` from their
  /// authoritative `teachers/{id}` record.
  ///
  /// WHY: the firestore.rules `isClassTeacher(cls)` predicate reads
  /// `allowed_users.classIds[]`. Teachers provisioned before classIds was
  /// stamped — or whose class assignment changed without a re-stamp — end up
  /// with empty/stale classIds and hit `permission-denied` when creating
  /// students / attendance / homework for their OWN class. Calling this on
  /// teacher login (HomeScreen) repairs the doc transparently.
  ///
  /// This is a SELF-update: the rules permit a user to update their own
  /// allowed_users doc as long as `role` and `schoolId` are unchanged. We only
  /// touch `classIds` (+ `teacherId`), so the write is allowed. Idempotent —
  /// skips the write when the doc is already in sync.
  Future<void> syncTeacherClassIds(Teacher teacher) async {
    final normEmail = teacher.email.trim().toLowerCase();
    if (normEmail.isEmpty || !normEmail.contains('@')) return;
    final desired = _classIdsFor(teacher);
    if (desired.isEmpty) return; // nothing to grant (e.g. unassigned teacher)
    try {
      final docRef = _allowedUsers.doc(normEmail);
      final snap = await docRef.get();
      if (!snap.exists) return;
      final data = snap.data() as Map<String, dynamic>;
      final current = (data['classIds'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[];
      final inSync = current.length == desired.length &&
          desired.every(current.contains) &&
          data['teacherId'] == teacher.id;
      if (inSync) return;
      await docRef.update({
        'classIds':  desired,
        'teacherId': teacher.id,
      });
    } catch (_) {
      // Non-fatal — if it fails, the original permission-denied still surfaces.
    }
  }

  Future<void> removeTeacher(String schoolId, String id) async {
    // Capture the teacher's email before deletion so we can also revoke their
    // login + Firebase Auth account (otherwise the email stays registered and a
    // re-created teacher resurfaces the old login).
    String? email;
    try {
      final doc = await _teachers.doc(id).get();
      email = (doc.data()?['email'] as String?)?.trim().toLowerCase();
    } catch (_) {}

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

    // Revoke the login + Auth account so the email is fully freed. Best-effort:
    // a failure here must not leave the teacher half-deleted in the UI.
    if (email != null && email.isNotEmpty && email.contains('@')) {
      try {
        await deleteAccountFully(email);
      } catch (e) {
        AppLogger.d('TimetableService', 'removeTeacher login cleanup failed: $e');
      }
    }
  }

  // ── Settings ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getSettings({String? schoolId}) async {
    // Return cached copy if still fresh — avoids a Firestore round-trip every
    // time the coordinator dashboard (or any other screen) calls this, while
    // the TTL bounds how stale a cross-device change can be (#112).
    if (_settingsCache != null &&
        _settingsCacheAt != null &&
        DateTime.now().difference(_settingsCacheAt!) < _settingsCacheTtl) {
      return _settingsCache!;
    }

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

    // Fallback: `settings/main` may exist without a synced `classes` key (e.g.
    // only the school name was written to main, while the class list lives in
    // `settings/academic.classList`, which the School Details screen edits).
    // Pull from there so every screen reading getSettings() — coordinator class
    // chips, teacher management, etc. — sees the configured classes.
    final hasClasses = (result['classes'] as List?)?.isNotEmpty ?? false;
    if (!hasClasses) {
      try {
        final academic = await _settings.doc('academic').get();
        final list = academic.data()?['classList'];
        if (list is List && list.isNotEmpty) {
          result['classes'] = List<String>.from(list);
        }
      } catch (_) {
        // Non-fatal — leave classes as-is.
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
    _settingsCache   = result; // cache for subsequent calls (until TTL/invalidate)
    _settingsCacheAt = DateTime.now();
    return result;
  }

  Future<void> saveSettings(String schoolId, Map<String, dynamic> settings) async {
    _settingsCache   = null; // invalidate so next getSettings re-fetches
    _settingsCacheAt = null;
    await _settings.doc('main').set(settings);
  }

  /// Drops the in-memory settings cache so the next [getSettings] re-fetches.
  /// Call this after another service (e.g. SchoolSettingsService, when the
  /// owner edits the class list) writes to settings/main, so screens reading
  /// classes through getSettings pick up the change within the same session.
  static void invalidateSettingsCache() {
    _settingsCache   = null;
    _settingsCacheAt = null;
  }

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
        final dayBells = <int, TimetableEntry>{};
        bells.forEach((k, v) {
          final bellNum = int.tryParse(k);
          if (bellNum != null) {
            dayBells[bellNum] = TimetableEntry.fromJson(v);
          }
        });
        dayMap[day as String] = dayBells;
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

  String _dutyKeyForDate(DateTime d) {
    return '${d.year}-${d.month}-${d.day}';
  }

  /// Returns map of teacherId → duty string for today.
  Future<Map<String, String>> getTodayDuties() => getDutiesForDate(DateTime.now());

  /// Returns map of teacherId → duty string for a specific date.
  Future<Map<String, String>> getDutiesForDate(DateTime date) async {
    final doc = await _duties.doc(_dutyKeyForDate(date)).get();
    if (!doc.exists || doc.data() == null) return {};
    final raw = Map<String, dynamic>.from(
        (doc.data()!['assignments'] as Map?) ?? {});
    return raw.map((k, v) => MapEntry(k, v as String));
  }

  Future<void> saveTodayDuties(Map<String, String> duties) async {
    await _duties.doc(_dutyKeyForDate(DateTime.now())).set({
      'assignments': duties,
      'updatedAt':   FieldValue.serverTimestamp(),
    });
  }

  // ── Allowed Users (Admin manages who can log in) ──────────────────────────
  // allowed_users stays at the root — see comment at class top.

  Future<List<Map<String, dynamic>>> getAllowedUsers() async {
    final currentUserEmail = FirebaseAuth.instance.currentUser?.email?.toLowerCase().trim();
    Query<Map<String, dynamic>> query = _allowedUsers;
    if (currentUserEmail != null && !AuthService.isRootAdminEmail(currentUserEmail)) {
      query = query.where('schoolId', isEqualTo: AuthService.currentSchoolId);
    }
    final snap = await query.get();
    return snap.docs.map((d) {
      final data       = Map<String, dynamic>.from(d.data());
      final rawClasses = data['assignedClasses'];
      return <String, dynamic>{
        'email':           d.id,
        'role':            (data['role']         as String? ?? 'teacher'),
        'name':            (data['name']         as String? ?? ''),
        // Account lifecycle status: 'pending' (invited, not yet activated),
        // 'active', or 'inactive'/'disabled'. Legacy docs created before the
        // field existed have no status — treat them as active.
        'status':          (data['status']       as String? ?? 'active'),
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
        'schoolId':        (data['schoolId']     as String? ?? ''),
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
    String?       studentClass,
    int?          studentRoll,
    String?       studentSection,
    List<String>? assignedClasses,
  }) async {
    final docRef = _allowedUsers.doc(email.toLowerCase().trim());
    final data   = <String, dynamic>{'role': role};
    // password is no longer stored in Firestore — Firebase Auth owns credentials.
    if (role == 'guardian' && studentClass != null && studentRoll != null) {
      data['studentClass'] = studentClass;
      data['studentRoll']  = studentRoll;
      if (studentSection != null) {
        data['studentSection'] = studentSection;
      }
    } else {
      data['studentClass'] = null;
      data['studentRoll']  = null;
      data['studentSection'] = null;
    }
    if (role == 'coordinator' || role == 'principal' || role == 'owner') {
      data['assignedClasses'] = assignedClasses ?? [];
    } else {
      data['assignedClasses'] = null;
    }
    await docRef.update(data);
  }

  // Firebase Web API key — used only to provision Auth accounts via the REST
  // signUp endpoint, which (unlike the SDK's createUser) does NOT displace the
  // currently signed-in admin's session. Sourced from the generated
  // firebase_options config instead of a hardcoded literal in source.
  static String get _firebaseApiKey =>
      DefaultFirebaseOptions.currentPlatform.apiKey;

  /// Deletes any orphaned Firebase Auth user (an account that exists in Firebase Auth
  /// but has no associated document in the Firestore [allowed_users] collection) by
  /// invoking the [deleteAccount] Cloud Function. This prevents recreated emails from
  /// logging in using old/stale credentials, enforcing a fresh password setup via email.
  Future<void> _purgeStaleAuthRecord(String email) async {
    final normEmail = email.toLowerCase().trim();
    DocumentSnapshot<Map<String, dynamic>>? existingDoc;
    try {
      existingDoc = await _allowedUsers.doc(normEmail).get();
    } catch (_) {}

    if (existingDoc == null || !existingDoc.exists) {
      try {
        await FirebaseFunctions.instance
            .httpsCallable('deleteAccount')
            .call(<String, dynamic>{'email': normEmail});
      } catch (e) {
        // Safe to ignore: if the user does not exist in Auth, the function might
        // throw an exception which is fine, we still proceed with creation.
        AppLogger.d('TimetableService', 'Pre-creation cleanup of stale Auth for $normEmail ignored/skipped: $e');
      }
    }
  }

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
    String?       studentSection,
    String?       studentAdmissionId,
    List<String>? assignedClasses,
    String?       createdByEmail,
    String?       createdByRole,
  }) async {
    final normEmail = email.toLowerCase().trim();

    // 0. One email = one role. If this address already holds a *different* role,
    //    refuse outright — the existing account must be deleted before the email
    //    can be reassigned. Re-adding the SAME role is fine (re-inviting a user,
    //    or linking another child to an existing guardian).
    //
    //    The read is best-effort: the rules deny reads of a NON-EXISTENT
    //    allowed_users doc to non-owner creators, so a fresh email throws here.
    //    That's not a conflict (there's nothing to collide with), so on any read
    //    failure we fall through and let the write rules be the final authority.
    DocumentSnapshot<Map<String, dynamic>>? existingDoc;
    try {
      existingDoc = await _allowedUsers.doc(normEmail).get();
    } catch (_) {
      existingDoc = null; // unreadable (likely absent) — no provable conflict.
    }
    if (existingDoc != null && existingDoc.exists) {
      final existingSchoolId = existingDoc.data()?['schoolId'] as String?;
      final existingRole = existingDoc.data()?['role'] as String?;

      if (existingSchoolId != null && existingSchoolId.isNotEmpty && existingSchoolId != schoolId) {
        throw Exception(
          'This email is already in use by another school. An email address can only be associated with one school.'
        );
      }

      if (existingRole != null && existingRole.isNotEmpty && existingRole != role) {
        throw RoleConflictException(normEmail, existingRole, role);
      }
    }

    // Purge any stale Auth record before creating
    await _purgeStaleAuthRecord(normEmail);

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
      if (studentSection != null) {
        data['studentSection'] = studentSection;
      }
      // Stable identity for the #39 'guardian_adm:{admissionId}' rule branch.
      if (studentAdmissionId != null && studentAdmissionId.isNotEmpty) {
        data['studentAdmissionId'] = studentAdmissionId;
      }
    }
    if (role == 'coordinator' || role == 'principal' || role == 'owner') {
      data['assignedClasses'] = assignedClasses ?? [];
    }
    await _allowedUsers.doc(normEmail).set(data);

    // 2. Create Firebase Auth account via REST (doesn't sign out current user).
    //    If the account already exists, skip silently.
    //    Use caller's password if provided, otherwise generate a secure temp one.
    // Strong random temp password when the caller doesn't supply one — NOT
    // hashCode/timestamp-derived (review #6, #7). User resets via invite link.
    final authPass = password.isNotEmpty ? password : generateSecurePassword();
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
        AppLogger.d('TimetableService',
            'Firebase Auth creation warning for $normEmail: $errCode');
      }
    } catch (_) {
      // Network error — non-fatal; Firestore record is written.
    }

    // 3. Send invitation / password-setup email via Firebase Auth.
    //    The user will click the link to set their own password.
    try {
      await AuthService().sendPasswordEmailViaFunction(normEmail, invite: true);
    } catch (_) {
      // Non-fatal; admin can resend from the user management screen.
    }
  }

  /// Returns users created by the given creator email.
  Future<List<Map<String, dynamic>>> getUsersCreatedBy(
      String creatorEmail) async {
    Query<Map<String, dynamic>> query = _allowedUsers
        .where('createdByEmail', isEqualTo: creatorEmail.toLowerCase().trim());
    
    // Non-root admin users must filter by schoolId to satisfy the Firestore rules'
    // tenant isolation, otherwise the query gets rejected with permission-denied.
    if (!AuthService.isRootAdminEmail(creatorEmail)) {
      query = query.where('schoolId', isEqualTo: AuthService.currentSchoolId);
    }
    
    final snap = await query.get();
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

  /// Permanently deletes an account and all of its associated data via the
  /// `deleteAccount` Cloud Function (which can also remove the Firebase Auth
  /// login — something the client SDK cannot do for another user). This is what
  /// stops a re-created email from resurfacing old data.
  ///
  /// Returns `true` when the function performed the full cascade. If the
  /// function isn't deployed yet (or is unreachable), it falls back to revoking
  /// the login record locally and returns `false`, so access is still cut off
  /// even though deep cleanup is deferred until the function is deployed.
  /// Genuine authorization / validation errors are rethrown.
  Future<void> _cascadeDeleteSchoolLocally(String email, String? role, String? schoolId) async {
    final normEmail = email.toLowerCase().trim();
    final batch = FirebaseFirestore.instance.batch();

    if ((role == 'owner' || role == 'ownerPrincipal') && schoolId != null && schoolId.isNotEmpty) {
      AppLogger.d('TimetableService', 'Starting local cascade deletion for schoolId: $schoolId');

      // 1. Delete all allowed_users belonging to this school
      try {
        final usersSnap = await _allowedUsers.where('schoolId', isEqualTo: schoolId).get();
        for (var doc in usersSnap.docs) {
          batch.delete(doc.reference);
        }
      } catch (e) {
        AppLogger.e('TimetableService', 'Failed to fetch allowed_users for local cascade: $e');
      }

      // 2. Delete school-scoped collections: students, teachers, classes
      final schoolRef = FirebaseFirestore.instance.collection('schools').doc(schoolId);
      
      try {
        final studentsSnap = await schoolRef.collection('students').get();
        for (var doc in studentsSnap.docs) {
          batch.delete(doc.reference);
        }
      } catch (e) {
        AppLogger.e('TimetableService', 'Failed to delete students in local cascade: $e');
      }

      try {
        final teachersSnap = await schoolRef.collection('teachers').get();
        for (var doc in teachersSnap.docs) {
          batch.delete(doc.reference);
        }
      } catch (e) {
        AppLogger.e('TimetableService', 'Failed to delete teachers in local cascade: $e');
      }

      try {
        final classesSnap = await schoolRef.collection('classes').get();
        for (var doc in classesSnap.docs) {
          batch.delete(doc.reference);
        }
      } catch (e) {
        AppLogger.e('TimetableService', 'Failed to delete classes in local cascade: $e');
      }

      // 3. Delete other root collection documents scoped to the orphaned schoolId
      final rootCollections = ['homework', 'copy_checks', 'substitution_history', 'tasks'];
      for (final coll in rootCollections) {
        try {
          final snap = await FirebaseFirestore.instance.collection(coll).where('schoolId', isEqualTo: schoolId).get();
          for (var doc in snap.docs) {
            batch.delete(doc.reference);
          }
        } catch (e) {
          AppLogger.e('TimetableService', 'Failed to clean $coll for school $schoolId: $e');
        }
      }

      // Delete the root school document
      batch.delete(schoolRef);
    } else {
      // If it is not an owner or has no schoolId, just delete the user's allowed_users doc
      batch.delete(_allowedUsers.doc(normEmail));
    }

    await batch.commit();
    AppLogger.d('TimetableService', 'Local cascade deletion complete for $normEmail');
  }

  Future<void> cleanOrphanedSchools() async {
    try {
      // 1. Get all allowed_users
      final allUsersSnap = await _allowedUsers.get();
      final allUsers = allUsersSnap.docs.map((d) => d.data()).toList();

      // 2. Identify active owner schoolIds
      final activeSchoolIds = <String>{};
      for (final u in allUsers) {
        final role = u['role'] as String?;
        final schoolId = u['schoolId'] as String?;
        if ((role == 'owner' || role == 'ownerPrincipal') && schoolId != null && schoolId.isNotEmpty) {
          activeSchoolIds.add(schoolId);
        }
      }

      // 3. Find orphaned users and schoolIds
      final orphanedUsers = <String>[];
      final orphanedSchoolIds = <String>{};

      for (final doc in allUsersSnap.docs) {
        final data = doc.data();
        final email = doc.id;
        final role = data['role'] as String?;
        final schoolId = data['schoolId'] as String?;

        if (role == 'admin') continue;
        if (schoolId == null || schoolId.isEmpty) continue;

        if (!activeSchoolIds.contains(schoolId)) {
          orphanedUsers.add(email);
          orphanedSchoolIds.add(schoolId);
        }
      }

      if (orphanedUsers.isEmpty && orphanedSchoolIds.isEmpty) {
        return;
      }

      AppLogger.d('TimetableService', 'Found orphaned users: $orphanedUsers and schools: $orphanedSchoolIds. Cleaning up...');

      final batch = FirebaseFirestore.instance.batch();

      // Delete orphaned users
      for (final email in orphanedUsers) {
        batch.delete(_allowedUsers.doc(email));
      }

      // Delete orphaned schools and their subcollections
      for (final schoolId in orphanedSchoolIds) {
        final schoolRef = FirebaseFirestore.instance.collection('schools').doc(schoolId);

        try {
          final studentsSnap = await schoolRef.collection('students').get();
          for (var doc in studentsSnap.docs) {
            batch.delete(doc.reference);
          }
        } catch (e) {
          AppLogger.e('TimetableService', 'Failed to fetch students for orphan cleanup: $e');
        }

        try {
          final teachersSnap = await schoolRef.collection('teachers').get();
          for (var doc in teachersSnap.docs) {
            batch.delete(doc.reference);
          }
        } catch (e) {
          AppLogger.e('TimetableService', 'Failed to fetch teachers for orphan cleanup: $e');
        }

        try {
          final classesSnap = await schoolRef.collection('classes').get();
          for (var doc in classesSnap.docs) {
            batch.delete(doc.reference);
          }
        } catch (e) {
          AppLogger.e('TimetableService', 'Failed to fetch classes for orphan cleanup: $e');
        }

        final rootCollections = ['homework', 'copy_checks', 'substitution_history', 'tasks'];
        for (final coll in rootCollections) {
          try {
            final snap = await FirebaseFirestore.instance.collection(coll).where('schoolId', isEqualTo: schoolId).get();
            for (var doc in snap.docs) {
              batch.delete(doc.reference);
            }
          } catch (e) {
            AppLogger.e('TimetableService', 'Failed to clean $coll for orphaned school $schoolId: $e');
          }
        }

        batch.delete(schoolRef);
      }

      await batch.commit();
      AppLogger.d('TimetableService', 'Orphan cleanup complete.');
    } catch (e) {
      AppLogger.e('TimetableService', 'cleanOrphanedSchools failed: $e');
    }
  }

  Future<bool> deleteAccountFully(String email) async {
    final normEmail = email.toLowerCase().trim();
    String? schoolId;
    String? role;
    try {
      final snap = await _allowedUsers.doc(normEmail).get();
      if (snap.exists) {
        final data = snap.data();
        schoolId = data?['schoolId'] as String?;
        role = data?['role'] as String?;
      }
    } catch (e) {
      AppLogger.e('TimetableService', 'Failed to pre-fetch user doc for delete: $e');
    }

    try {
      await FirebaseFunctions.instance
          .httpsCallable('deleteAccount')
          .call(<String, dynamic>{'email': normEmail});
      return true;
    } on FirebaseFunctionsException catch (e) {
      // If the user is authenticated locally, any unauthenticated/permission-denied
      // failure from the functions endpoint is likely a Cloud Run gateway configuration
      // issue (e.g. missing allUsers invoker policy binding). Fallback to local
      // revocation so access is still revoked and the UI remains in sync.
      if ((e.code == 'unauthenticated' || e.code == 'permission-denied') &&
          FirebaseAuth.instance.currentUser != null) {
        AppLogger.d('TimetableService', 'deleteAccount Cloud Function returned auth/permission error ($e). Falling back to local Firestore revocation.');
        await _cascadeDeleteSchoolLocally(normEmail, role, schoolId);
        return false;
      }

      // Surface real validation failures to the caller.
      if (e.code == 'invalid-argument' ||
          e.code == 'failed-precondition') {
        rethrow;
      }
      // not-found / unavailable / internal / others → function not deployed or transient.
      // Fallback: revoke the login and delete associated school data locally.
      await _cascadeDeleteSchoolLocally(normEmail, role, schoolId);
      return false;
    }
  }

  /// Marks an account active after first successful login.
  Future<void> markUserActive(String email) async {
    await _allowedUsers
        .doc(email.toLowerCase().trim())
        .update({'status': 'active'});
  }

  /// Resends the invitation / password-setup email for an existing account.
  Future<void> resendInvitationEmail(String email) async {
    // Let failures propagate so callers can report truthfully and offer a
    // retry — swallowing this is what caused "invite sent" to be shown when no
    // email actually went out. Routes through the Cloud Function for
    // inbox-grade deliverability (falls back to the built-in email internally).
    await AuthService()
        .sendPasswordEmailViaFunction(email.toLowerCase().trim(), invite: true);
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

    // Verify email is not registered in another school or has role conflict
    DocumentSnapshot<Map<String, dynamic>>? existingDoc;
    try {
      existingDoc = await _allowedUsers.doc(normEmail).get();
    } catch (_) {}

    if (existingDoc != null && existingDoc.exists) {
      final existingSchoolId = existingDoc.data()?['schoolId'] as String?;
      final existingRole = existingDoc.data()?['role'] as String?;

      if (existingSchoolId != null && existingSchoolId.isNotEmpty && existingSchoolId != effectiveSchoolId) {
        throw Exception(
          'This email is already in use by another school. An email address can only be associated with one school.'
        );
      }

      if (existingRole != null && existingRole.isNotEmpty && existingRole != 'teacher') {
        throw RoleConflictException(normEmail, existingRole, 'teacher');
      }
    }

    // Purge any stale Auth record before creating
    await _purgeStaleAuthRecord(normEmail);

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
    final tempPassword = generateSecurePassword();
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
        AppLogger.d('TimetableService',
            'Firebase Auth creation warning for $normEmail: $errCode');
      }
    } catch (_) {}

    // Send invitation / password-setup email.
    await AuthService().sendPasswordEmailViaFunction(normEmail, invite: true);
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
    String          studentSection = '',
    String?         studentAdmissionId,
    String?         schoolId,
    String?         phone,   // E.164 format
  }) async {
    final normEmail = email.trim().toLowerCase();
    if (!normEmail.contains('@')) return;

    // Verify email is not registered in another school or has role conflict
    DocumentSnapshot<Map<String, dynamic>>? existingDoc;
    try {
      existingDoc = await _allowedUsers.doc(normEmail).get();
    } catch (_) {}

    if (existingDoc != null && existingDoc.exists) {
      final existingSchoolId = existingDoc.data()?['schoolId'] as String?;
      final existingRole = existingDoc.data()?['role'] as String?;

      if (existingSchoolId != null && existingSchoolId.isNotEmpty && existingSchoolId != schoolId) {
        throw Exception(
          'This email is already in use by another school. An email address can only be associated with one school.'
        );
      }

      if (existingRole != null && existingRole.isNotEmpty && existingRole != 'guardian') {
        throw RoleConflictException(normEmail, existingRole, 'guardian');
      }
    }

    // Purge any stale Auth record before creating
    await _purgeStaleAuthRecord(normEmail);

    // Write/merge allowed_users, preserving existing student links.
    await linkGuardianEmail(
      email:        normEmail,
      studentClass: studentClass,
      studentRoll:  studentRoll,
      studentSection: studentSection,
      studentName:  studentName,
      studentAdmissionId: studentAdmissionId,
      schoolId:     schoolId,
      phone:        phone,
    );

    // Create Firebase Auth account via REST (no-op if EMAIL_EXISTS).
    final tempPassword = generateSecurePassword();
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
        AppLogger.d('TimetableService',
            'Firebase Auth creation warning for guardian $normEmail: $errCode');
      }
    } catch (_) {}

    // Send invite / password-setup email.
    await AuthService().sendPasswordEmailViaFunction(normEmail, invite: true);
  }

  /// Returns the role if the email is registered, or null if not found.
  Future<String?> getAllowedRole(String email) async {
    final doc = await _allowedUsers.doc(email.toLowerCase().trim()).get();
    if (!doc.exists || doc.data() == null) return null;
    return doc.data()!['role'] as String?;
  }

  /// Looks up a guardian profile by phone number stored in [allowed_users].
  /// Returns the document data (with 'email' key added) or null if not found.
  Future<Map<String, dynamic>?> getGuardianByPhone(String phone) async {
    final normalized = PhoneUtils.normalize(phone);
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

    // Drop orphaned applications whose teacher no longer exists (e.g. the
    // teacher was deleted) — otherwise stale requests inflate the dashboard's
    // "Leave Requests" / "Teacher absent" counts even when there are no teachers.
    final validIds = await _currentTeacherIds();
    list.retainWhere((a) {
      final tid = (a['teacherId'] as String?) ?? '';
      return tid.isNotEmpty && validIds.contains(tid);
    });

    return list;
  }

  /// Set of teacher document ids currently registered in this school.
  Future<Set<String>> _currentTeacherIds() async {
    final teachers = await getTeachers();
    return teachers.map((t) => t.id).toSet();
  }

  /// Real-time count of pending leave applications, excluding orphaned requests
  /// from teachers that no longer exist (so the badge matches the list).
  Stream<int> streamPendingLeaveCount() =>
      _leaveApps
          .where('status', isEqualTo: 'pending')
          .snapshots()
          .asyncMap((snap) async {
            final validIds = await _currentTeacherIds();
            return snap.docs.where((d) {
              final tid = (d.data()['teacherId'] as String?) ?? '';
              return tid.isNotEmpty && validIds.contains(tid);
            }).length;
          });

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
    String          studentSection = '',
    // Stable identity — stored so that leave-resolved notifications can use
    // the 'guardian_adm:{id}' audience channel rather than the roll-based
    // fallback, avoiding ghost alerts if a roll is reused (#39).
    String?         admissionId,
  }) async {
    await _leaveApps.add({
      'applicantType': 'guardian',
      'studentClass' : studentClass,
      'studentSection': studentSection,
      'studentRoll'  : studentRoll,
      'studentName'  : studentName,
      if (guardianName != null && guardianName.isNotEmpty)
        'guardianName': guardianName,
      if (admissionId != null && admissionId.isNotEmpty)
        'admissionId': admissionId,
      'toRole'       : 'teacher',
      'startDate'    : startDate,
      'numberOfDays' : numberOfDays,
      'reason'       : reason,
      'status'       : 'pending',
      'createdAt'    : FieldValue.serverTimestamp(),
    });
  }

  /// All student leaves for [studentClass]/[studentSection] (class teacher view).
  Future<List<Map<String, dynamic>>> getStudentLeaveApplications({
    required String studentClass,
    String          studentSection = '',
    String? status,
  }) async {
    Query q = _leaveApps
        .where('applicantType', isEqualTo: 'guardian')
        .where('studentClass',  isEqualTo: studentClass);
    if (studentSection.isNotEmpty) {
      q = q.where('studentSection', isEqualTo: studentSection);
    }
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
  Stream<int> streamPendingStudentLeaveCount({
    required String studentClass,
    String          studentSection = '',
  }) {
    Query q = _leaveApps
        .where('applicantType', isEqualTo: 'guardian')
        .where('studentClass',  isEqualTo: studentClass)
        .where('status',        isEqualTo: 'pending');
    if (studentSection.isNotEmpty) {
      q = q.where('studentSection', isEqualTo: studentSection);
    }
    return q.snapshots().map((snap) => snap.docs.length);
  }

  // ── Substitutions ─────────────────────────────────────────────────────────

  /// Delegates to [SchoolClock.dateKey] so substitution doc keys use the same
  /// zero-padded `YYYY-MM-DD` format as attendance keys (#109).
  String _dateKeyFor(DateTime d) => SchoolClock.dateKey(d);

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
    return [{
      'studentClass': cls,
      'studentRoll':  roll,
      'studentName':  '',
      if (data['studentAdmissionId'] != null)
        'studentAdmissionId': data['studentAdmissionId'],
    }];
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
    String          studentSection = '',
    String?         studentName,
    String?         studentAdmissionId,
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
        l['studentClass'] == studentClass &&
        l['studentRoll'] == studentRoll &&
        (l['studentSection'] ?? '') == studentSection);
    if (!exists) {
      links.add({
        'studentClass': studentClass,
        'studentRoll':  studentRoll,
        'studentSection': studentSection,
        if (studentName != null) 'studentName': studentName,
        if (studentAdmissionId != null && studentAdmissionId.isNotEmpty)
          'studentAdmissionId': studentAdmissionId,
      });
    }

    await docRef.set({
      'role':         data['role'] ?? 'guardian',
      'email':        email.toLowerCase().trim(),
      'studentLinks': links,
      'studentClass': studentClass,  // legacy compat
      'studentRoll':  studentRoll,   // legacy compat
      'studentSection': studentSection,
      // Top-level stable id (last-linked child) — the firestore.rules
      // guardian_adm branch reads getUserData().studentAdmissionId (#39).
      if (studentAdmissionId != null && studentAdmissionId.isNotEmpty)
        'studentAdmissionId': studentAdmissionId,
      if (schoolId != null) 'schoolId': schoolId,
      if (phone != null && phone.isNotEmpty) 'phone': PhoneUtils.normalize(phone),
    }, SetOptions(merge: true));
  }

  /// Removes a student link from a guardian's allowed_users document.
  Future<void> removeGuardianLink({
    required String email,
    required String studentClass,
    required int    studentRoll,
    String          studentSection = '',
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
        l['studentClass'] == studentClass &&
        l['studentRoll'] == studentRoll &&
        (l['studentSection'] ?? '') == studentSection);

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

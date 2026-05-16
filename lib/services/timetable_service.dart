import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../models/teacher.dart';
import '../models/timetable_entry.dart';

class TimetableService {
  static final _db            = FirebaseFirestore.instance;
  static final _teachers      = _db.collection('teachers');
  static final _settings      = _db.collection('settings');
  static final _tt            = _db.collection('timetable');
  static final _duties        = _db.collection('duties');
  static final _allowedUsers  = _db.collection('allowed_users');
  static final _substitutions = _db.collection('substitutions');
  static final _leaveApps     = _db.collection('leave_applications');

  static final TimetableService _instance = TimetableService._();
  TimetableService._();
  factory TimetableService() => _instance;

  // In-memory cache for settings (invalidated on every saveSettings call)
  static Map<String, dynamic>? _settingsCache;

  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

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

  Future<void> addTeacher(String schoolId, Teacher teacher) async {
    await _teachers.doc(teacher.id).set(teacher.toJson());
  }

  Future<void> updateTeacher(String schoolId, Teacher teacher) async {
    await _teachers.doc(teacher.id).set(teacher.toJson());
  }

  Future<void> removeTeacher(String schoolId, String id) async {
    await _teachers.doc(id).delete();

    // Scrub teacher from every timetable slot
    final snap = await _tt.get();
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

  // ── Timetable ─────────────────────────────────────────────────────────────
  // Shape: className → day → bell(1-indexed) → TimetableEntry

  Future<Map<String, Map<String, Map<int, TimetableEntry>>>> getTimetable() async {
    final snap = await _tt.get();
    final result = <String, Map<String, Map<int, TimetableEntry>>>{};

    for (final doc in snap.docs) {
      final className = doc.id;
      final rawData = (doc.data()['data'] as Map?) ?? {};
      final dayMap = <String, Map<int, TimetableEntry>>{};

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
    required int bell,
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
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Allowed Users (Admin manages who can log in) ──────────────────────────

  Future<List<Map<String, dynamic>>> getAllowedUsers() async {
    final snap = await _allowedUsers.get();
    return snap.docs.map((d) {
      final data = Map<String, dynamic>.from(d.data());
      final rawClasses = data['assignedClasses'];
      return <String, dynamic>{
        'email':          d.id,
        'role':           (data['role']         as String? ?? 'teacher'),
        'studentClass':   (data['studentClass'] as String? ?? ''),
        'studentRoll':    (data['studentRoll']  as int?    ?? 0),
        'assignedClasses': rawClasses != null
            ? List<String>.from(rawClasses as List)
            : <String>[],
      };
    }).toList()
      ..sort((a, b) => (a['email'] as String).compareTo(b['email'] as String));
  }

  /// Returns the assigned classes for a coordinator/principal, or null if not set.
  Future<({List<String>? assignedClasses, String? schoolId})> getAssignedClasses(String email) async {
    final doc = await _allowedUsers.doc(email.toLowerCase().trim()).get();
    if (!doc.exists || doc.data() == null) return (assignedClasses: null, schoolId: null);
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
    String?       newPassword,
    String?       studentClass,
    int?          studentRoll,
    List<String>? assignedClasses,
  }) async {
    final docRef = _allowedUsers.doc(email.toLowerCase().trim());
    final data   = <String, dynamic>{'role': role};
    if (newPassword != null && newPassword.isNotEmpty) {
      data['password'] = _hashPassword(newPassword);
    }
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

  Future<void> addAllowedUser(
    String email,
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
    final data = <String, dynamic>{
      'role':     role,
      'email':    email.toLowerCase().trim(),
      'password': _hashPassword(password),
      'createdAt': FieldValue.serverTimestamp(),
      if (name           != null && name.isNotEmpty)  'name':     name,
      if (schoolId       != null && schoolId.isNotEmpty) 'schoolId': schoolId,
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
    await _allowedUsers.doc(email.toLowerCase().trim()).set(data);
  }

  /// Returns users created by the given creator email.
  Future<List<Map<String, dynamic>>> getUsersCreatedBy(String creatorEmail) async {
    final snap = await _allowedUsers
        .where('createdByEmail', isEqualTo: creatorEmail.toLowerCase().trim())
        .get();
    return snap.docs.map((d) {
      final data = Map<String, dynamic>.from(d.data());
      return <String, dynamic>{
        'email':          d.id,
        'role':           data['role']           as String?   ?? '',
        'createdAt':      data['createdAt'],
        'createdByEmail': data['createdByEmail'] as String?   ?? '',
        'createdByRole':  data['createdByRole']  as String?   ?? '',
        'studentClass':   data['studentClass']   as String?   ?? '',
        'studentRoll':    data['studentRoll']    as int?      ?? 0,
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

  /// Returns the role if the email is registered, or null if not found.
  Future<String?> getAllowedRole(String email) async {
    final doc = await _allowedUsers.doc(email.toLowerCase().trim()).get();
    if (!doc.exists || doc.data() == null) return null;
    return doc.data()!['role'] as String?;
  }

  /// Validates email + password. Returns role string on success, null on failure.
  Future<String?> validateLogin(String email, String password) async {
    final doc = await _allowedUsers.doc(email.toLowerCase().trim()).get();
    if (!doc.exists || doc.data() == null) return null;
    final data = doc.data()!;
    final storedPass = data['password'] as String? ?? '';
    if (storedPass.isEmpty || storedPass != _hashPassword(password)) return null;
    return data['role'] as String?;
  }

  // ── Leave Applications ────────────────────────────────────────────────────────

  Future<void> submitLeaveApplication({
    String? schoolId,
    required String teacherId,
    required String teacherName,
    required String teacherEmail,
    required String toRole,
    required String startDate,
    required int numberOfDays,
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
  Future<List<Map<String, dynamic>>> getLeaveApplications({String? status, String? schoolId}) async {
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

  Future<void> updateLeaveApplication(String schoolId, String id, String status,
      {String? note}) async {
    final update = <String, dynamic>{'status': status};
    if (note != null && note.isNotEmpty) update['coordinatorNote'] = note;
    await _leaveApps.doc(id).update(update);
  }

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
    required String className,
    required List<String> days,
    required int bell,
    required String? teacherId,
    String? subject,
    String? schoolId,
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
  Future<void> linkGuardianEmail({
    required String email,
    required String studentClass,
    required int    studentRoll,
    String?         studentName,
    String?         schoolId,
  }) async {
    final docRef = _allowedUsers.doc(email.toLowerCase().trim());
    final doc    = await docRef.get();
    final data   = doc.exists && doc.data() != null
        ? Map<String, dynamic>.from(doc.data()!)
        : <String, dynamic>{};

    final links = List<Map<String, dynamic>>.from(
        (data['studentLinks'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? []);

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
        (data['studentLinks'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? []);
    links.removeWhere((l) =>
        l['studentClass'] == studentClass && l['studentRoll'] == studentRoll);

    await docRef.update({'studentLinks': links});
  }

  /// Returns all coordinators, optionally filtered by schoolId field.
  Future<List<Map<String, dynamic>>> getCoordinators(String schoolId) async {
    final snap = await _allowedUsers
        .where('role', isEqualTo: 'coordinator')
        .get();
    return snap.docs.map((d) {
      final data = Map<String, dynamic>.from(d.data());
      data['email'] = d.id;
      return data;
    }).where((u) {
      // If records have a schoolId field, filter; otherwise include all
      final sid = u['schoolId'] as String?;
      return sid == null || sid.isEmpty || sid == schoolId;
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

    final allLeavesFuture  = getLeaveApplications();
    final timetableFuture  = getTimetable();
    final subsFuture       = getTodaySubstitutions();

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
      final days = (app['numberOfDays'] as num?)?.toInt() ?? 1;
      final end  = start.add(Duration(days: days - 1));
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
    final todayName = dayNames[(now.weekday - 1).clamp(0, 5)];
    var unassigned = 0;
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

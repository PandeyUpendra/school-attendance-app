import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/teacher.dart';
import '../models/timetable_entry.dart';
import 'base_firestore_service.dart';

class TimetableService extends BaseFirestoreService {
  static final TimetableService _instance = TimetableService._();
  TimetableService._();
  factory TimetableService() => _instance;

  CollectionReference<Map<String, dynamic>> _teachers(String schoolId) =>
      schoolCollection(schoolId, 'teachers');
  CollectionReference<Map<String, dynamic>> _settings(String schoolId) =>
      schoolCollection(schoolId, 'settings');
  CollectionReference<Map<String, dynamic>> _tt(String schoolId) =>
      schoolCollection(schoolId, 'timetable');
  CollectionReference<Map<String, dynamic>> _duties(String schoolId) =>
      schoolCollection(schoolId, 'duties');
  CollectionReference<Map<String, dynamic>> _allowedUsers = FirebaseFirestore.instance.collection('allowed_users');
  CollectionReference<Map<String, dynamic>> _substitutions(String schoolId) =>
      schoolCollection(schoolId, 'substitutions');
  CollectionReference<Map<String, dynamic>> _leaveApps(String schoolId) =>
      schoolCollection(schoolId, 'leave_applications');

  static Map<String, Map<String, dynamic>> _settingsCache = {};
  static Map<String, List<Teacher>> _teachersCache = {};
  static Map<String, Map<String, Map<String, Map<int, TimetableEntry>>>> _ttCache = {};

  // ── Teachers ──────────────────────────────────────────────────────────────

  Future<Teacher?> getTeacherById({String? schoolId, required String id}) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    if (_teachersCache.containsKey(sId)) {
      try {
        return _teachersCache[sId]!.firstWhere((t) => t.id == id);
      } catch (_) {}
    }
    final doc = await _teachers(sId).doc(id).get();
    if (!doc.exists || doc.data() == null) return null;
    return Teacher.fromJson(Map<String, dynamic>.from(doc.data()!));
  }

  Future<List<Teacher>> getTeachers({String? schoolId, bool refresh = false}) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    if (!refresh && _teachersCache.containsKey(sId)) return _teachersCache[sId]!;

    final snap = await _teachers(sId).get();
    final list = snap.docs
        .map((d) => Teacher.fromJson(Map<String, dynamic>.from(d.data())))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    _teachersCache[sId] = list;
    return list;
  }

  Future<void> addTeacher(String schoolId, Teacher teacher) async {
    _teachersCache.remove(schoolId);
    await _teachers(schoolId).doc(teacher.id).set(teacher.toJson());
  }

  Future<void> updateTeacher(String schoolId, Teacher teacher) async {
    _teachersCache.remove(schoolId);
    await _teachers(schoolId).doc(teacher.id).set(teacher.toJson());
  }

  Future<void> removeTeacher(String schoolId, String id) async {
    _teachersCache.remove(schoolId);
    _ttCache.remove(schoolId);
    await _teachers(schoolId).doc(id).delete();

    // Scrub teacher from every timetable slot
    final snap = await _tt(schoolId).get();
    final batch = db.batch();
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
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    if (_settingsCache.containsKey(sId)) return _settingsCache[sId]!;

    final doc = await _settings(sId).doc('main').get();
    Map<String, dynamic> result;

    if (!doc.exists || doc.data() == null) {
      result = {
        'numberOfBells': 8,
        'classes': ['Class 6', 'Class 7', 'Class 8', 'Class 9', 'Class 10'],
      };
    } else {
      result = Map<String, dynamic>.from(doc.data()!);
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
    _settingsCache[sId] = result;
    return result;
  }

  Future<void> saveSettings(String schoolId, Map<String, dynamic> settings) async {
    _settingsCache.remove(schoolId);
    await _settings(schoolId).doc('main').set(settings);
  }

  // ── Timetable ─────────────────────────────────────────────────────────────

  Future<Map<String, Map<String, Map<int, TimetableEntry>>>> getTimetable({String? schoolId, bool refresh = false}) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    if (!refresh && _ttCache.containsKey(sId)) return _ttCache[sId]!;

    final snap = await _tt(sId).get();
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
    _ttCache[sId] = result;
    return result;
  }

  Future<void> _saveTimetable(String schoolId,
      Map<String, Map<String, Map<int, TimetableEntry>>> tt) async {
    _ttCache[schoolId] = tt;
    final batch = db.batch();
    for (final clsEntry in tt.entries) {
      final data = clsEntry.value.map(
        (day, bells) => MapEntry(
          day,
          bells.map((k, e) => MapEntry(k.toString(), e.toJson())),
        ),
      );
      batch.set(_tt(schoolId).doc(clsEntry.key), {'data': data});
    }
    await batch.commit();
  }

  Future<String?> findClash({
    required String schoolId,
    required String forClass,
    required String day,
    required int bell,
    required String teacherId,
  }) async {
    final tt = await getTimetable(schoolId: schoolId);
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

  Future<Map<String, String>> getTodayDuties({String? schoolId}) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    final doc = await _duties(sId).doc(_dutyKey()).get();
    if (!doc.exists || doc.data() == null) return {};
    final raw = Map<String, dynamic>.from(
        (doc.data()!['assignments'] as Map?) ?? {});
    return raw.map((k, v) => MapEntry(k, v as String));
  }

  Future<void> saveTodayDuties(String schoolId, Map<String, String> duties) async {
    await _duties(schoolId).doc(_dutyKey()).set({
      'assignments': duties,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Allowed Users ──────────────────────────────────────────────────────────

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

  Future<List<String>?> getAssignedClasses(String email) async {
    final doc = await _allowedUsers.doc(email.toLowerCase().trim()).get();
    if (!doc.exists || doc.data() == null) return null;
    final raw = doc.data()!['assignedClasses'];
    if (raw == null) return null;
    final list = List<String>.from(raw as List);
    return list.isEmpty ? null : list;
  }

  Future<void> updateAllowedUser(
    String email, {
    required String role,
    String?       newPassword,
    String?       studentClass,
    int?          studentRoll,
    List<Map<String, dynamic>>? studentLinks,
    List<String>? assignedClasses,
  }) async {
    final docRef = _allowedUsers.doc(email.toLowerCase().trim());
    final data   = <String, dynamic>{'role': role};
    if (newPassword != null && newPassword.isNotEmpty) {
      data['password'] = newPassword;
    }
    
    if (role == 'guardian') {
      if (studentLinks != null) {
        data['studentLinks'] = studentLinks;
      } else if (studentClass != null && studentRoll != null) {
        data['studentLinks'] = [{
          'studentClass': studentClass,
          'studentRoll': studentRoll,
          'studentName': '',
        }];
      } else {
        data['studentLinks'] = null;
      }
    } else {
      data['studentLinks'] = null;
    }

    if (role == 'coordinator' || role == 'principal') {
      data['assignedClasses'] = assignedClasses ?? [];
    } else {
      data['assignedClasses'] = null;
    }
    await docRef.update(data);
  }

  Future<void> addAllowedUser(
    String email,
    String? password,
    String role, {
    String?       name,
    String?       schoolId,
    String?       studentClass,
    int?          studentRoll,
    List<Map<String, dynamic>>? studentLinks,
    List<String>? assignedClasses,
  }) async {
    final data = <String, dynamic>{
      'role':     role,
      'email':    email.toLowerCase().trim(),
      'name':     name,
      'schoolId': schoolId,
    };

    if (password != null && password.isNotEmpty) {
      data['password'] = password;
    }

    if (role == 'guardian') {
      if (studentLinks != null) {
        data['studentLinks'] = studentLinks;
      } else if (studentClass != null && studentRoll != null) {
        data['studentLinks'] = [{
          'studentClass': studentClass,
          'studentRoll': studentRoll,
          'studentName': '',
        }];
      }
    }

    if (role == 'coordinator' || role == 'principal') {
      data['assignedClasses'] = assignedClasses ?? [];
    }
    await _allowedUsers.doc(email.toLowerCase().trim()).set(data);
  }

  Future<List<Map<String, dynamic>>?> getGuardianLinks(String email) async {
    final doc = await _allowedUsers.doc(email.toLowerCase().trim()).get();
    if (!doc.exists || doc.data() == null) return null;
    final data = doc.data()!;
    if (data['role'] != 'guardian') return null;
    
    if (data['studentLinks'] == null) {
      final cls  = data['studentClass'] as String?;
      final roll = data['studentRoll']  as int?;
      if (cls == null || roll == null) return null;
      return [{'studentClass': cls, 'studentRoll': roll, 'studentName': ''}];
    }

    final rawLinks = data['studentLinks'] as List?;
    if (rawLinks == null) return null;
    return rawLinks.map((l) => Map<String, dynamic>.from(l as Map)).toList();
  }

  Future<void> removeAllowedUser(String email) async {
    await _allowedUsers.doc(email.toLowerCase().trim()).delete();
  }

  Future<String?> getAllowedRole(String email) async {
    final doc = await _allowedUsers.doc(email.toLowerCase().trim()).get();
    if (!doc.exists || doc.data() == null) return null;
    return doc.data()!['role'] as String?;
  }

  Future<String?> validateLogin(String email, [String? password]) async {
    final doc = await _allowedUsers.doc(email.toLowerCase().trim()).get();
    if (!doc.exists || doc.data() == null) return null;
    final data = doc.data()!;
    return data['role'] as String?;
  }

  Future<List<Map<String, dynamic>>> getCoordinators(String schoolId) async {
    final snap = await _allowedUsers
        .where('schoolId', isEqualTo: schoolId)
        .where('role', isEqualTo: 'coordinator')
        .get();
    return snap.docs.map((d) => Map<String, dynamic>.from(d.data())).toList();
  }

  // ── Leave Applications ────────────────────────────────────────────────────────

  Future<void> submitLeaveApplication({
    required String schoolId,
    required String teacherId,
    required String teacherName,
    required String teacherEmail,
    required String toRole,
    required String startDate,
    required int numberOfDays,
    required String reason,
  }) async {
    await _leaveApps(schoolId).add({
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

  Future<List<Map<String, dynamic>>> getLeaveApplications({String? schoolId, String? status}) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    QuerySnapshot<Map<String, dynamic>> snap;
    if (status != null) {
      snap = await _leaveApps(sId).where('status', isEqualTo: status).get();
    } else {
      snap = await _leaveApps(sId).orderBy('createdAt', descending: true).get();
    }

    final list = snap.docs.map((d) {
      final data = Map<String, dynamic>.from(d.data());
      data['id'] = d.id;
      return data;
    }).toList();

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
    await _leaveApps(schoolId).doc(id).update(update);
  }

  // ── Absent-teacher info for dashboard ────────────────────────────────────

  Future<Map<String, int>> getTodayAbsentTeachersInfo(String schoolId) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Optimize: only fetch approved leaves that could possibly be for today.
    // Fetching leaves from the last 30 days is a reasonable heuristic if we don't have better indexing.
    final thirtyDaysAgo = today.subtract(const Duration(days: 30));
    final leavesSnap = await _leaveApps(schoolId)
        .where('status', isEqualTo: 'approved')
        .where('startDate', isGreaterThanOrEqualTo: thirtyDaysAgo.toIso8601String().substring(0, 10))
        .get();

    final timetableFuture  = getTimetable(schoolId: schoolId);
    final subsFuture       = getTodaySubstitutions(schoolId: schoolId);

    final allLeaves = leavesSnap.docs.map((d) => d.data()).toList();
    final timetable = await timetableFuture;
    final subs      = await subsFuture;

    final absentIds = <String>{};
    for (final app in allLeaves) {
      final startStr = app['startDate'] as String?;
      if (startStr == null) continue;
      final start = DateTime.tryParse(startStr);
      if (start == null) continue;
      final days = (app['numberOfDays'] as num?)?.toInt() ?? 1;
      final end  = start.add(Duration(days: days - 1));

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

  // ── Substitutions ─────────────────────────────────────────────────────────

  String _subKey() {
    final d = DateTime.now();
    return '${d.year}-${d.month}-${d.day}';
  }

  Future<Map<String, String>> getTodaySubstitutions({String? schoolId}) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    final doc = await _substitutions(sId).doc(_subKey()).get();
    if (!doc.exists || doc.data() == null) return {};
    final raw = Map<String, dynamic>.from(doc.data()!);
    return raw.map((k, v) => MapEntry(k, v as String));
  }

  Future<void> setSubstitution(
      String schoolId, String className, int bell, String? teacherId) async {
    final key = '${className}_$bell';
    if (teacherId == null || teacherId.isEmpty) {
      await _substitutions(schoolId)
          .doc(_subKey())
          .set({key: FieldValue.delete()}, SetOptions(merge: true));
    } else {
      await _substitutions(schoolId).doc(_subKey()).set(
          {key: teacherId, 'updatedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true));
    }
  }

  Future<String?> assignTeacher({
    required String schoolId,
    required String className,
    required List<String> days,
    required int bell,
    required String? teacherId,
    String? subject,
  }) async {
    if (teacherId != null) {
      for (final day in days) {
        final clash = await findClash(
            schoolId: schoolId, forClass: className, day: day, bell: bell, teacherId: teacherId);
        if (clash != null) {
          return 'Clash on $day! Teacher already has Bell $bell in $clash';
        }
      }
    }
    final tt = await getTimetable(schoolId: schoolId);
    tt.putIfAbsent(className, () => {});
    for (final day in days) {
      tt[className]!.putIfAbsent(day, () => {});
      tt[className]![day]![bell] =
          TimetableEntry(teacherId: teacherId, subject: subject);
    }
    await _saveTimetable(schoolId, tt);
    return null;
  }

  Future<List<String>> getClassesTaughtByTeacher(String schoolId, String teacherId) async {
    final snap = await _tt(schoolId).get();
    final result = <String>{};
    for (final doc in snap.docs) {
      final rawData = (doc.data()['data'] as Map?) ?? {};
      bool found = false;
      rawData.forEach((day, bellsRaw) {
        if (found) return;
        final bells = Map<String, dynamic>.from(bellsRaw as Map);
        bells.forEach((bell, entryRaw) {
          if (found) return;
          final e = Map<String, dynamic>.from(entryRaw as Map);
          if (e['teacherId'] == teacherId) {
            found = true;
          }
        });
      });
      if (found) {
        result.add(doc.id);
      }
    }
    return result.toList()..sort();
  }
}

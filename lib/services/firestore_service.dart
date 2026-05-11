import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/attendance_status.dart';

/// Central Firestore service. Firestore offline persistence is enabled in
/// main.dart, so all methods work offline and auto-sync when reconnected.
class FirestoreService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Helpers ──────────────────────────────────────────────────────────────

  static CollectionReference<Map<String, dynamic>> _attendanceCol(
          String schoolId, String classId) =>
      _db
          .collection('schools').doc(schoolId)
          .collection('classes').doc(classId)
          .collection('attendance');

  static DocumentReference<Map<String, dynamic>> _classDoc(
          String schoolId, String classId) =>
      _db.collection('schools').doc(schoolId).collection('classes').doc(classId);

  // ── Attendance ───────────────────────────────────────────────────────────

  /// Saves attendance using single-letter codes: 'P', 'A', 'L'.
  static Future<void> saveAttendance({
    required String schoolId,
    required String classId,
    required String date,
    required Map<int, AttendanceStatus> attendance,
  }) async {
    final data = {
      for (final e in attendance.entries) e.key.toString(): e.value.code,
    };
    await _attendanceCol(schoolId, classId).doc(date).set(data);
  }

  /// Returns attendance with backward-compatible bool → AttendanceStatus parsing.
  static Future<Map<int, AttendanceStatus>?> loadAttendance({
    required String schoolId,
    required String classId,
    required String date,
  }) async {
    try {
      final doc = await _attendanceCol(schoolId, classId).doc(date).get();
      if (!doc.exists || doc.data() == null) return null;
      return doc.data()!.map(
          (k, v) => MapEntry(int.parse(k), AttendanceStatus.fromValue(v)));
    } catch (_) {
      return null;
    }
  }

  static Future<List<String>> getAttendanceDates({
    required String schoolId,
    required String classId,
  }) async {
    try {
      final snap = await _attendanceCol(schoolId, classId).get();
      return snap.docs.map((d) => d.id).toList()..sort();
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, dynamic>?> loadAttendanceSummary({
    required String schoolId,
    required String classId,
    required String date,
  }) async {
    final att = await loadAttendance(
        schoolId: schoolId, classId: classId, date: date);
    if (att == null) return null;
    return {
      'present': att.values.where((v) => v.isPresent).length,
      'absent': att.values.where((v) => v.isAbsent).length,
      'leave': att.values.where((v) => v.isLeave).length,
      'attendance': att,
    };
  }

  // ── Students ─────────────────────────────────────────────────────────────

  static Future<void> saveStudents({
    required String schoolId,
    required String classId,
    required List<Map<String, dynamic>> students,
  }) async {
    await _classDoc(schoolId, classId)
        .set({'students': students}, SetOptions(merge: true));
  }

  static Future<List<Map<String, dynamic>>?> loadStudents({
    required String schoolId,
    required String classId,
  }) async {
    try {
      final doc = await _classDoc(schoolId, classId).get();
      if (!doc.exists || doc.data() == null) return null;
      final list = doc.data()!['students'] as List?;
      return list?.cast<Map<String, dynamic>>();
    } catch (_) {
      return null;
    }
  }

  // ── Timetable ─────────────────────────────────────────────────────────────

  /// Returns { 'Mon': ['Math','English',...], 'Tue': [...], ... }
  static Future<Map<String, List<String>>?> loadTimetable({
    required String schoolId,
    required String classId,
  }) async {
    try {
      final doc = await _classDoc(schoolId, classId).get();
      if (!doc.exists || doc.data() == null) return null;
      final raw = doc.data()!['timetable'] as Map<String, dynamic>?;
      return raw?.map((k, v) => MapEntry(k, List<String>.from(v as List)));
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveTimetable({
    required String schoolId,
    required String classId,
    required Map<String, List<String>> timetable,
  }) async {
    await _classDoc(schoolId, classId)
        .set({'timetable': timetable}, SetOptions(merge: true));
  }

  // ── Users (admin) ─────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getUsersBySchool(
      String schoolId) async {
    try {
      final snap = await _db
          .collection('users')
          .where('schoolId', isEqualTo: schoolId)
          .get();
      return snap.docs.map((d) => {'uid': d.id, ...d.data()}).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> updateUserFields(
      String uid, Map<String, dynamic> data) async {
    await _db.collection('users').doc(uid).update(data);
  }

  static Future<void> createUserDoc(
      String uid, Map<String, dynamic> data) async {
    await _db.collection('users').doc(uid).set(data);
  }

  // ── FCM token ─────────────────────────────────────────────────────────────

  static Future<void> saveFcmToken(String uid, String token) async {
    try {
      await _db.collection('users').doc(uid).update({'fcmToken': token});
    } catch (_) {}
  }

  // ── Reports ───────────────────────────────────────────────────────────────

  /// Returns per-roll { 'present': n, 'absent': n, 'leave': n, 'total': n }
  static Future<Map<int, Map<String, int>>> getStudentAttendanceStats({
    required String schoolId,
    required String classId,
  }) async {
    final dates =
        await getAttendanceDates(schoolId: schoolId, classId: classId);
    final Map<int, int> presentCount = {};
    final Map<int, int> absentCount = {};
    final Map<int, int> leaveCount = {};

    for (final date in dates) {
      final att = await loadAttendance(
          schoolId: schoolId, classId: classId, date: date);
      if (att == null) continue;
      for (final e in att.entries) {
        if (e.value.isPresent) {
          presentCount[e.key] = (presentCount[e.key] ?? 0) + 1;
        } else if (e.value.isLeave) {
          leaveCount[e.key] = (leaveCount[e.key] ?? 0) + 1;
        } else {
          absentCount[e.key] = (absentCount[e.key] ?? 0) + 1;
        }
      }
    }

    final allRolls = {
      ...presentCount.keys,
      ...absentCount.keys,
      ...leaveCount.keys
    };
    return {
      for (final roll in allRolls)
        roll: {
          'present': presentCount[roll] ?? 0,
          'absent': absentCount[roll] ?? 0,
          'leave': leaveCount[roll] ?? 0,
          'total': dates.length,
        }
    };
  }

  // ── Analytics ─────────────────────────────────────────────────────────────

  /// Returns { 'totalDays': n, 'presentRate': 0.0-1.0 } per class.
  static Future<Map<String, dynamic>> getClassStats({
    required String schoolId,
    required String classId,
  }) async {
    try {
      final dates =
          await getAttendanceDates(schoolId: schoolId, classId: classId);
      if (dates.isEmpty) return {'totalDays': 0, 'presentRate': 0.0};

      int totalPresent = 0, totalRecords = 0;
      for (final date in dates) {
        final att = await loadAttendance(
            schoolId: schoolId, classId: classId, date: date);
        if (att == null) continue;
        totalPresent += att.values.where((v) => v.isPresent).length;
        totalRecords += att.length;
      }

      return {
        'totalDays': dates.length,
        'presentRate':
            totalRecords > 0 ? totalPresent / totalRecords : 0.0,
      };
    } catch (_) {
      return {'totalDays': 0, 'presentRate': 0.0};
    }
  }

  // ── Guardian ──────────────────────────────────────────────────────────────

  /// Returns [ { 'date': 'YYYY-MM-DD', 'status': AttendanceStatus } ]
  static Future<List<Map<String, dynamic>>> getStudentAttendanceHistory({
    required String schoolId,
    required String classId,
    required int studentRoll,
  }) async {
    final dates =
        await getAttendanceDates(schoolId: schoolId, classId: classId);
    final List<Map<String, dynamic>> history = [];

    for (final date in dates) {
      final att = await loadAttendance(
          schoolId: schoolId, classId: classId, date: date);
      if (att == null) continue;
      final status = att[studentRoll];
      if (status != null) {
        history.add({'date': date, 'status': status});
      }
    }
    return history;
  }

  // ── Student Profiles ─────────────────────────────────────────────────────

  static CollectionReference<Map<String, dynamic>> _profilesCol(
          String schoolId, String classId) =>
      _db
          .collection('schools').doc(schoolId)
          .collection('classes').doc(classId)
          .collection('studentProfiles');

  static Future<Map<String, dynamic>?> loadStudentProfile({
    required String schoolId,
    required String classId,
    required int roll,
  }) async {
    try {
      final doc =
          await _profilesCol(schoolId, classId).doc(roll.toString()).get();
      if (!doc.exists || doc.data() == null) return null;
      return doc.data();
    } catch (_) {
      return null;
    }
  }

  static Future<void> updateStudentProfile({
    required String schoolId,
    required String classId,
    required int roll,
    required Map<String, dynamic> data,
  }) async {
    await _profilesCol(schoolId, classId)
        .doc(roll.toString())
        .set(data, SetOptions(merge: true));
  }

  /// Appends [item] to an array field using arrayUnion (no duplicates).
  static Future<void> appendToStudentProfile({
    required String schoolId,
    required String classId,
    required int roll,
    required String arrayField,
    required Map<String, dynamic> item,
  }) async {
    await _profilesCol(schoolId, classId).doc(roll.toString()).set(
      {arrayField: FieldValue.arrayUnion([item])},
      SetOptions(merge: true),
    );
  }

  /// Returns a map of dateKey → AttendanceStatus? for the last [days] days.
  /// Keys are ordered oldest → newest.
  static Future<Map<String, AttendanceStatus?>> getLastNDaysAttendance({
    required String schoolId,
    required String classId,
    required int studentRoll,
    int days = 7,
  }) async {
    final now = DateTime.now();
    final result = <String, AttendanceStatus?>{};

    // Pre-populate oldest → newest with null (no data)
    for (int i = days - 1; i >= 0; i--) {
      final day = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: i));
      final key =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      result[key] = null;
    }

    // Fetch each day's attendance (cache-first due to offline persistence)
    for (final date in result.keys.toList()) {
      try {
        final att = await loadAttendance(
            schoolId: schoolId, classId: classId, date: date);
        if (att != null) result[date] = att[studentRoll];
      } catch (_) {}
    }
    return result;
  }

  // ── Tests ─────────────────────────────────────────────────────────────────

  static CollectionReference<Map<String, dynamic>> _testsCol(
          String schoolId, String classId) =>
      _db
          .collection('schools').doc(schoolId)
          .collection('classes').doc(classId)
          .collection('tests');

  static Future<List<Map<String, dynamic>>> getTests({
    required String schoolId,
    required String classId,
  }) async {
    try {
      final snap = await _testsCol(schoolId, classId)
          .orderBy('date', descending: true)
          .get();
      return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<String> createTest({
    required String schoolId,
    required String classId,
    required Map<String, dynamic> data,
  }) async {
    final ref = await _testsCol(schoolId, classId).add(data);
    return ref.id;
  }

  static Future<void> saveTestMarks({
    required String schoolId,
    required String classId,
    required String testId,
    required Map<int, int> marks,
  }) async {
    final data = {
      'marks': {
        for (final e in marks.entries) e.key.toString(): e.value,
      },
    };
    await _testsCol(schoolId, classId).doc(testId).update(data);
  }

  // ── PTM ───────────────────────────────────────────────────────────────────

  static CollectionReference<Map<String, dynamic>> _ptmCol(
          String schoolId, String classId) =>
      _db
          .collection('schools').doc(schoolId)
          .collection('classes').doc(classId)
          .collection('ptm');

  static Future<List<Map<String, dynamic>>> getPtmList({
    required String schoolId,
    required String classId,
  }) async {
    try {
      final snap = await _ptmCol(schoolId, classId)
          .orderBy('date', descending: true)
          .get();
      return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<String> addPtm({
    required String schoolId,
    required String classId,
    required Map<String, dynamic> data,
  }) async {
    final ref = await _ptmCol(schoolId, classId).add(data);
    return ref.id;
  }

  static Future<void> updatePtmStatus({
    required String schoolId,
    required String classId,
    required String ptmId,
    required String status,
  }) async {
    await _ptmCol(schoolId, classId).doc(ptmId).update({'status': status});
  }

  // ── Syllabus ──────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>?> loadSyllabus({
    required String schoolId,
    required String classId,
  }) async {
    try {
      final doc = await _classDoc(schoolId, classId).get();
      if (!doc.exists || doc.data() == null) return null;
      final list = doc.data()!['syllabus'] as List?;
      return list?.cast<Map<String, dynamic>>();
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveSyllabus({
    required String schoolId,
    required String classId,
    required List<Map<String, dynamic>> chapters,
  }) async {
    await _classDoc(schoolId, classId)
        .set({'syllabus': chapters}, SetOptions(merge: true));
  }

  // ── Class Complaints ──────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>?> loadClassComplaints({
    required String schoolId,
    required String classId,
  }) async {
    try {
      final doc = await _classDoc(schoolId, classId).get();
      if (!doc.exists || doc.data() == null) return null;
      final list = doc.data()!['classComplaints'] as List?;
      return list?.cast<Map<String, dynamic>>();
    } catch (_) {
      return null;
    }
  }

  static Future<void> addClassComplaint({
    required String schoolId,
    required String classId,
    required Map<String, dynamic> complaint,
  }) async {
    await _classDoc(schoolId, classId).set(
      {'classComplaints': FieldValue.arrayUnion([complaint])},
      SetOptions(merge: true),
    );
  }

  // ── School-level complaints (raised by subject teachers) ──────────────────

  static CollectionReference<Map<String, dynamic>> _schoolComplaintsCol(
          String schoolId) =>
      _db.collection('schools').doc(schoolId).collection('complaints');

  static Future<void> addSchoolComplaint({
    required String schoolId,
    required Map<String, dynamic> complaint,
  }) async {
    await _schoolComplaintsCol(schoolId).add({
      ...complaint,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<List<Map<String, dynamic>>> getSchoolComplaints({
    required String schoolId,
  }) async {
    try {
      final snap = await _schoolComplaintsCol(schoolId)
          .orderBy('createdAt', descending: true)
          .get();
      return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (_) {
      return [];
    }
  }

  /// Get complaints submitted by a specific guardian (for the guardian portal).
  static Future<List<Map<String, dynamic>>> getGuardianComplaints({
    required String schoolId,
    required String guardianId,
  }) async {
    try {
      final snap = await _schoolComplaintsCol(schoolId)
          .where('guardianId', isEqualTo: guardianId)
          .orderBy('createdAt', descending: true)
          .get();
      return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (_) {
      return [];
    }
  }

  // ── School Events ─────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getSchoolEvents({
    required String schoolId,
  }) async {
    try {
      final snap = await _db
          .collection('schools').doc(schoolId)
          .collection('events')
          .orderBy('date', descending: true)
          .get();
      return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Leaderboard ───────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getLeaderboardEntries({
    required String schoolId,
    required String category,
  }) async {
    try {
      final snap = await _db
          .collection('schools').doc(schoolId)
          .collection('leaderboard')
          .where('category', isEqualTo: category)
          .orderBy('score', descending: true)
          .get();
      return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (_) {
      return [];
    }
  }

  // ── School Info (subject teachers, bus) ───────────────────────────────────

  /// Subject teachers stored as array in the class document.
  static Future<List<Map<String, dynamic>>> getSubjectTeachers({
    required String schoolId,
    required String classId,
  }) async {
    try {
      final doc = await _classDoc(schoolId, classId).get();
      if (!doc.exists || doc.data() == null) return [];
      final list = doc.data()!['subjectTeachers'] as List?;
      return list?.cast<Map<String, dynamic>>() ?? [];
    } catch (_) {
      return [];
    }
  }

  /// Bus info stored in school document as 'busInfo' map.
  static Future<Map<String, dynamic>?> getBusInfo({
    required String schoolId,
  }) async {
    try {
      final doc = await _db.collection('schools').doc(schoolId).get();
      if (!doc.exists || doc.data() == null) return null;
      return doc.data()!['busInfo'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  // ── Advanced Timetable (coordinator) ──────────────────────────────────────

  /// Loads rich timetable: { day: [ { subject, teacher, room } ] }
  static Future<Map<String, List<Map<String, dynamic>>>?> loadRichTimetable({
    required String schoolId,
    required String classId,
  }) async {
    try {
      final doc = await _classDoc(schoolId, classId).get();
      if (!doc.exists || doc.data() == null) return null;
      final raw = doc.data()!['richTimetable'] as Map<String, dynamic>?;
      if (raw == null) return null;
      return raw.map((day, periods) {
        final list = (periods as List)
            .map((p) => Map<String, dynamic>.from(p as Map))
            .toList();
        return MapEntry(day, list);
      });
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveRichTimetable({
    required String schoolId,
    required String classId,
    required Map<String, List<Map<String, dynamic>>> timetable,
  }) async {
    await _classDoc(schoolId, classId)
        .set({'richTimetable': timetable}, SetOptions(merge: true));
  }

  // ── Teacher Duties ────────────────────────────────────────────────────────

  static Future<void> addTeacherDuty({
    required String teacherUid,
    required Map<String, dynamic> duty,
  }) async {
    await _db.collection('users').doc(teacherUid).update({
      'duties': FieldValue.arrayUnion([duty]),
    });
  }

  // ── Coordinator Complaints ────────────────────────────────────────────────

  /// All complaints for a set of class IDs (coordinator view).
  static Future<List<Map<String, dynamic>>> getComplaintsForClasses({
    required String schoolId,
    required List<String> classIds,
  }) async {
    try {
      final snap = await _schoolComplaintsCol(schoolId)
          .orderBy('createdAt', descending: true)
          .get();
      final all = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      if (classIds.isEmpty) return all;
      return all
          .where((c) => classIds.contains(c['className'] as String?))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Update complaint status and optional resolution note.
  static Future<void> updateComplaint({
    required String schoolId,
    required String complaintId,
    required Map<String, dynamic> data,
  }) async {
    await _schoolComplaintsCol(schoolId).doc(complaintId).update(data);
  }

  // ── Leaderboard (principal) ───────────────────────────────────────────────

  static CollectionReference<Map<String, dynamic>> _leaderboardCol(
          String schoolId) =>
      _db.collection('schools').doc(schoolId).collection('leaderboard');

  static Future<void> addLeaderboardEntry({
    required String schoolId,
    required Map<String, dynamic> entry,
  }) async {
    await _leaderboardCol(schoolId).add(entry);
  }

  static Future<void> updateLeaderboardEntry({
    required String schoolId,
    required String docId,
    required Map<String, dynamic> data,
  }) async {
    await _leaderboardCol(schoolId).doc(docId).update(data);
  }

  static Future<void> deleteLeaderboardEntry({
    required String schoolId,
    required String docId,
  }) async {
    await _leaderboardCol(schoolId).doc(docId).delete();
  }

  // ── School Events (principal) ─────────────────────────────────────────────

  static Future<String> addSchoolEvent({
    required String schoolId,
    required Map<String, dynamic> event,
  }) async {
    final ref = await _db
        .collection('schools')
        .doc(schoolId)
        .collection('events')
        .add(event);
    return ref.id;
  }

  static Future<void> deleteSchoolEvent({
    required String schoolId,
    required String eventId,
  }) async {
    await _db
        .collection('schools')
        .doc(schoolId)
        .collection('events')
        .doc(eventId)
        .delete();
  }
}

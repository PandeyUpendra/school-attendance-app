import 'dart:async';

import '../models/student.dart';
import '../models/student_remark.dart';
import 'student_repository.dart';

/// In-memory [StudentRepository] for use in unit tests.
///
/// • No Firebase / network required.
/// • Every mutation is immediately visible to subsequent reads.
/// • Streams emit a single snapshot of the current state (not live updates).
///   If you need reactive-stream behaviour, call [notifyWatchers] after writes
///   and hold references to the stream controllers.
///
/// Usage:
/// ```dart
/// final repo    = FakeStudentRepository();
/// final service = StudentService(repo);
///
/// repo.seed([Student(roll: 1, name: 'Alice', className: 'Class 6')]);
///
/// final students = await service.getStudentsByClass(className: 'Class 6');
/// expect(students.first.name, 'Alice');
/// ```
class FakeStudentRepository implements StudentRepository {
  // ── Storage ─────────────────────────────────────────────────────────────────

  final _students = <String, Student>{};
  final _remarks  = <String, List<StudentRemark>>{}; // key = docId
  final _deletionRequests = <String, Map<String, dynamic>>{};
  int _reqCounter = 0;

  // ── Helpers ─────────────────────────────────────────────────────────────────

  /// Computes the opaque document ID from student fields — mirrors the
  /// production [FirestoreStudentRepository._docId] logic exactly.
  String docId(int roll, String className, [String section = '']) {
    final base = className.replaceAll(' ', '_');
    final sec  = section.trim().replaceAll(' ', '_');
    return sec.isEmpty ? '${base}_$roll' : '${base}_${sec}_$roll';
  }

  /// Pre-populate the in-memory store with a list of students.
  /// Each student's `id` field is normalised to the computed docId.
  void seed(List<Student> students) {
    for (final s in students) {
      final id = docId(s.roll, s.className, s.section);
      _students[id] = _withId(s, id);
    }
  }

  /// Replace a student's `id` field with [id] (returns a new object).
  Student _withId(Student s, String id) =>
      s.copyWith(id: id);

  // ── Students ────────────────────────────────────────────────────────────────

  @override
  Future<List<Student>> fetchAll() async =>
      _students.values.toList()
        ..sort((a, b) => a.roll.compareTo(b.roll));

  @override
  Future<List<Student>> fetchByClass(
    String className,
    String section, {
    String? teacherId,
  }) async {
    return _students.values.where((s) {
      if (s.className != className) return false;
      if (section.trim().isNotEmpty &&
          s.section.trim() != section.trim()) { return false; }
      if (teacherId != null &&
          teacherId.isNotEmpty &&
          s.teacherId != teacherId) { return false; }
      return true;
    }).toList()
      ..sort((a, b) => a.roll.compareTo(b.roll));
  }

  @override
  Future<Student?> fetchByRoll(
          String className, String section, int roll) async =>
      _students[docId(roll, className, section)];

  @override
  Future<Student?> fetchById(String id) async => _students[id];

  @override
  Future<String?> addStudentUnique(Student s) async {
    final id = docId(s.roll, s.className, s.section);
    if (_students.containsKey(id)) {
      final sec = s.section.isNotEmpty ? ' Section ${s.section}' : '';
      return 'Roll number ${s.roll} already exists in ${s.className}$sec.';
    }
    _students[id] = _withId(s, id);
    return null;
  }

  @override
  Future<List<Student>> fetchByRolls(
    String className,
    String section,
    List<int> rolls,
  ) async {
    final futures = rolls.map((r) => fetchByRoll(className, section, r));
    final results = await Future.wait(futures);
    return results.whereType<Student>().toList();
  }

  @override
  Future<bool> existsByRoll(
          String className, String section, int roll) async =>
      _students.containsKey(docId(roll, className, section));

  @override
  Future<void> upsert(Student s) async {
    final id = docId(s.roll, s.className, s.section);
    _students[id] = _withId(s, id);
  }

  @override
  Future<void> delete(String id) async {
    _students.remove(id);
    _remarks.remove(id);
  }

  @override
  Future<void> setGuardianEmail(
    String className,
    String section,
    int roll,
    String email,
  ) async {
    final id = docId(roll, className, section);
    final existing = _students[id];
    if (existing == null) return;
    _students[id] = existing.copyWith(guardianEmail: email);
  }

  // ── Streams ─────────────────────────────────────────────────────────────────

  @override
  Stream<List<Student>> watchByClass(
    String className,
    String section, {
    String? teacherId,
  }) =>
      Stream.fromFuture(
          fetchByClass(className, section, teacherId: teacherId));

  @override
  Stream<List<Student>> watchAll() => Stream.fromFuture(fetchAll());

  // ── Remarks ─────────────────────────────────────────────────────────────────

  @override
  Future<List<StudentRemark>> fetchRemarks(
    String className,
    int roll, {
    String section = '',
  }) async {
    final key  = docId(roll, className, section);
    final list = List<StudentRemark>.from(_remarks[key] ?? []);
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  @override
  Future<void> addRemark({
    required String className,
    required int roll,
    required String createdBy,
    required String role,
    required String remark,
    String section = '',
    String? teacherId,
    String type = 'negative',
    bool whatsappSent = false,
  }) async {
    final key = docId(roll, className, section);
    final r   = StudentRemark(
      id:           '${DateTime.now().microsecondsSinceEpoch}',
      createdBy:    createdBy,
      role:         role,
      remark:       remark,
      timestamp:    DateTime.now(),
      teacherId:    teacherId,
      type:         type,
      whatsappSent: whatsappSent,
    );
    (_remarks[key] ??= []).add(r);
  }

  @override
  Future<void> deleteRemark({
    required String className,
    required int roll,
    required String remarkId,
    required String currentUserEmail,
    String section = '',
  }) async {
    final key  = docId(roll, className, section);
    final list = _remarks[key];
    if (list == null) return;
    final idx = list.indexWhere((r) => r.id == remarkId);
    if (idx == -1) return;
    if (list[idx].createdBy != currentUserEmail) {
      throw StateError('You can only delete your own remarks.');
    }
    list.removeAt(idx);
  }

  // ── Deletion requests ─────────────────────────────────────────────────────────

  @override
  Future<void> setDeletionPending(
    int roll,
    String className,
    String section,
    bool value,
  ) async {
    final id = docId(roll, className, section);
    final existing = _students[id];
    if (existing == null) return;
    _students[id] = existing.copyWith(deletionPending: value);
  }

  @override
  Future<void> submitDeletionRequest({
    required String teacherId,
    required String teacherName,
    required String teacherEmail,
    required List<Map<String, dynamic>> students,
    String reason = '',
  }) async {
    final id = 'req_${++_reqCounter}';
    _deletionRequests[id] = {
      'id':           id,
      'teacherId':    teacherId,
      'teacherName':  teacherName,
      'teacherEmail': teacherEmail,
      'students':     students,
      'reason':       reason,
      'status':       'pending',
      'requestedAt':  DateTime.now(),
    };
  }

  @override
  Stream<int> streamPendingDeletionCount() => Stream.value(
      _deletionRequests.values
          .where((r) => r['status'] == 'pending')
          .length);

  @override
  Future<List<Map<String, dynamic>>> getPendingDeletionRequests() async =>
      _deletionRequests.values
          .where((r) => r['status'] == 'pending')
          .toList()
          .reversed
          .toList();

  @override
  Future<Map<String, dynamic>?> getDeletionRequest(
          String requestId) async =>
      _deletionRequests[requestId];

  @override
  Future<void> updateDeletionRequestStatus(
    String requestId,
    String status, {
    String? rejectionNote,
  }) async {
    if (!_deletionRequests.containsKey(requestId)) return;
    _deletionRequests[requestId]!['status']      = status;
    _deletionRequests[requestId]!['resolvedAt']  = DateTime.now();
    if (rejectionNote != null) {
      _deletionRequests[requestId]!['rejectionNote'] = rejectionNote;
    }
  }

  // ── Test utilities ───────────────────────────────────────────────────────────

  /// Number of students currently stored (useful for count assertions).
  int get studentCount => _students.length;

  /// Clear all stored data (use in `tearDown`).
  void clear() {
    _students.clear();
    _remarks.clear();
    _deletionRequests.clear();
    _reqCounter = 0;
  }
}

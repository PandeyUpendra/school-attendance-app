import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/student.dart';
import '../models/student_remark.dart';
import '../services/auth_service.dart';

// ── Abstract interface ────────────────────────────────────────────────────────

/// Intent-level interface for all student-related persistence.
///
/// Callers describe *what* they want; implementations decide *how* to store it.
/// The production implementation is [FirestoreStudentRepository].
/// For unit tests use [FakeStudentRepository] from
/// `repositories/student_repository_fake.dart`.
///
/// See `docs/ARCHITECTURE.md` for the full Repository pattern guide.
abstract class StudentRepository {
  // ── Students ────────────────────────────────────────────────────────────────

  /// Fetch every student in the school (all classes), sorted by roll.
  Future<List<Student>> fetchAll();

  /// Fetch students in [className]/[section], sorted by roll.
  /// Pass [teacherId] to scope results to one class teacher's roster.
  Future<List<Student>> fetchByClass(
    String className,
    String section, {
    String? teacherId,
  });

  /// Fetch a single student by class + section + roll.
  /// Returns `null` when no matching record exists.
  Future<Student?> fetchByRoll(String className, String section, int roll);

  /// Fetch multiple students by roll list within [className]/[section].
  /// Missing rolls are silently omitted from the result.
  Future<List<Student>> fetchByRolls(
    String className,
    String section,
    List<int> rolls,
  );

  /// Returns `true` if a student with this roll already exists in the class.
  Future<bool> existsByRoll(String className, String section, int roll);

  /// Create or replace a student record (upsert semantics).
  /// The document ID is derived from `student.className`, `student.section`,
  /// and `student.roll` — the caller does not need to supply it.
  Future<void> upsert(Student s);

  /// Delete a student document identified by its opaque [id].
  ///
  /// Obtain [id] from `student.id` on any Student returned by this repository.
  /// Note: this does **not** cascade-delete attendance or revoke guardian
  /// access — that orchestration belongs in [StudentService.removeStudent].
  Future<void> delete(String id);

  /// Patch only the `guardianEmail` field on an existing student record.
  Future<void> setGuardianEmail(
    String className,
    String section,
    int roll,
    String email,
  );

  // ── Real-time streams ────────────────────────────────────────────────────────

  /// Live stream of students for [className]/[section], sorted by roll.
  /// Emits a new list on every remote add / update / delete.
  Stream<List<Student>> watchByClass(
    String className,
    String section, {
    String? teacherId,
  });

  /// Live stream of ALL students in the school, sorted by roll.
  Stream<List<Student>> watchAll();

  // ── Remarks ──────────────────────────────────────────────────────────────────

  /// Returns all remarks for a student, newest first.
  Future<List<StudentRemark>> fetchRemarks(
    String className,
    int roll, {
    String section = '',
  });

  /// Appends a new remark to the student's record.
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
  });

  /// Deletes a remark by ID.
  /// Throws [StateError] if [currentUserEmail] is not the original author.
  Future<void> deleteRemark({
    required String className,
    required int roll,
    required String remarkId,
    required String currentUserEmail,
    String section = '',
  });

  // ── Deletion requests ─────────────────────────────────────────────────────────

  /// Submit a teacher request to delete one or more students.
  Future<void> submitDeletionRequest({
    required String teacherId,
    required String teacherName,
    required String teacherEmail,
    required List<Map<String, dynamic>> students,
    String reason = '',
  });

  /// Live count of pending deletion requests (used for dashboard badges).
  Stream<int> streamPendingDeletionCount();

  /// All pending deletion requests, newest first.
  Future<List<Map<String, dynamic>>> getPendingDeletionRequests();

  /// Fetch a single deletion-request document by its ID.
  Future<Map<String, dynamic>?> getDeletionRequest(String requestId);

  /// Update the status of a deletion request (e.g. 'approved' / 'rejected').
  /// Optionally attach a [rejectionNote].
  Future<void> updateDeletionRequestStatus(
    String requestId,
    String status, {
    String? rejectionNote,
  });
}

// ── Firestore implementation ──────────────────────────────────────────────────

/// Production [StudentRepository] backed by Cloud Firestore.
///
/// All documents live under `schools/{schoolId}/students/`.
/// The school ID is read lazily from [AuthService.currentSchoolId] on every
/// call, so mid-session school switches (rare but possible) are handled
/// transparently.
class FirestoreStudentRepository implements StudentRepository {
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  String get _schoolId => AuthService.currentSchoolId;

  CollectionReference<Map<String, dynamic>> get _students =>
      _db.collection('schools').doc(_schoolId).collection('students');

  CollectionReference<Map<String, dynamic>> get _deletionRequests =>
      _db.collection('schools').doc(_schoolId).collection('student_deletion_requests');

  // ── Document-ID helpers ──────────────────────────────────────────────────────

  /// Derives the Firestore document ID from student fields.
  /// Format: `{className}_{section}_{roll}` (spaces → underscores).
  /// When section is empty: `{className}_{roll}`.
  String _docId(int roll, String className, [String section = '']) {
    final base = className.replaceAll(' ', '_');
    final sec = section.trim().replaceAll(' ', '_');
    return sec.isEmpty ? '${base}_$roll' : '${base}_${sec}_$roll';
  }

  /// Converts a Firestore document snapshot into a [Student], always setting
  /// `student.id` to the actual Firestore document ID so callers can pass it
  /// back to [delete] reliably.
  Student _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = Map<String, dynamic>.from(doc.data()!);
    data['id'] = doc.id; // override whatever the document stores in 'id'
    return Student.fromJson(data);
  }

  // ── Students ────────────────────────────────────────────────────────────────

  @override
  Future<List<Student>> fetchAll() async {
    final snap = await _students.get();
    return snap.docs
        .map(_fromDoc)
        .toList()
      ..sort((a, b) => a.roll.compareTo(b.roll));
  }

  @override
  Future<List<Student>> fetchByClass(
    String className,
    String section, {
    String? teacherId,
  }) async {
    Query<Map<String, dynamic>> q =
        _students.where('className', isEqualTo: className);
    if (section.trim().isNotEmpty) {
      q = q.where('section', isEqualTo: section.trim());
    }
    if (teacherId != null && teacherId.isNotEmpty) {
      q = q.where('teacherId', isEqualTo: teacherId);
    }
    final snap = await q.get();
    return snap.docs
        .map(_fromDoc)
        .toList()
      ..sort((a, b) => a.roll.compareTo(b.roll));
  }

  @override
  Future<Student?> fetchByRoll(
      String className, String section, int roll) async {
    final doc =
        await _students.doc(_docId(roll, className, section)).get();
    if (!doc.exists || doc.data() == null) return null;
    return _fromDoc(doc);
  }

  @override
  Future<List<Student>> fetchByRolls(
    String className,
    String section,
    List<int> rolls,
  ) async {
    if (rolls.isEmpty) return [];
    final results = await Future.wait(
      rolls.map((r) => fetchByRoll(className, section, r)),
    );
    return results.whereType<Student>().toList();
  }

  @override
  Future<bool> existsByRoll(
      String className, String section, int roll) async {
    final doc =
        await _students.doc(_docId(roll, className, section)).get();
    return doc.exists;
  }

  @override
  Future<void> upsert(Student s) async {
    final id = _docId(s.roll, s.className, s.section);
    await _students.doc(id).set(s.toJson());
  }

  @override
  Future<void> delete(String id) async {
    await _students.doc(id).delete();
  }

  @override
  Future<void> setGuardianEmail(
    String className,
    String section,
    int roll,
    String email,
  ) async {
    await _students
        .doc(_docId(roll, className, section))
        .update({'guardianEmail': email});
  }

  // ── Streams ─────────────────────────────────────────────────────────────────

  @override
  Stream<List<Student>> watchByClass(
    String className,
    String section, {
    String? teacherId,
  }) {
    Query<Map<String, dynamic>> q =
        _students.where('className', isEqualTo: className);
    if (section.trim().isNotEmpty) {
      q = q.where('section', isEqualTo: section.trim());
    }
    if (teacherId != null && teacherId.isNotEmpty) {
      q = q.where('teacherId', isEqualTo: teacherId);
    }
    return q.snapshots().map((snap) => snap.docs
        .map(_fromDoc)
        .toList()
      ..sort((a, b) => a.roll.compareTo(b.roll)));
  }

  @override
  Stream<List<Student>> watchAll() {
    return _students.snapshots().map((snap) => snap.docs
        .map(_fromDoc)
        .toList()
      ..sort((a, b) => a.roll.compareTo(b.roll)));
  }

  // ── Remarks ─────────────────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _remarksRef(
          int roll, String className, String section) =>
      _students.doc(_docId(roll, className, section)).collection('remarks');

  @override
  Future<List<StudentRemark>> fetchRemarks(
    String className,
    int roll, {
    String section = '',
  }) async {
    final snap = await _remarksRef(roll, className, section)
        .orderBy('timestamp', descending: true)
        .get();
    return snap.docs
        .map((d) => StudentRemark.fromJson(
            d.id, Map<String, dynamic>.from(d.data())))
        .toList();
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
    await _remarksRef(roll, className, section).add({
      'createdBy': createdBy,
      'role': role,
      'remark': remark,
      'timestamp': FieldValue.serverTimestamp(),
      'type': type,
      'whatsappSent': whatsappSent,
      if (teacherId != null) 'teacherId': teacherId,
    });
  }

  @override
  Future<void> deleteRemark({
    required String className,
    required int roll,
    required String remarkId,
    required String currentUserEmail,
    String section = '',
  }) async {
    final ref = _remarksRef(roll, className, section).doc(remarkId);
    final doc = await ref.get();
    if (!doc.exists) return;
    final data = Map<String, dynamic>.from(doc.data()!);
    if (data['createdBy'] != currentUserEmail) {
      throw StateError('You can only delete your own remarks.');
    }
    await ref.delete();
  }

  // ── Deletion requests ─────────────────────────────────────────────────────────

  @override
  Future<void> submitDeletionRequest({
    required String teacherId,
    required String teacherName,
    required String teacherEmail,
    required List<Map<String, dynamic>> students,
    String reason = '',
  }) async {
    await _deletionRequests.add({
      'teacherId': teacherId,
      'teacherName': teacherName,
      'teacherEmail': teacherEmail,
      'students': students,
      'reason': reason.trim(),
      'status': 'pending',
      'requestedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Stream<int> streamPendingDeletionCount() => _deletionRequests
      .where('status', isEqualTo: 'pending')
      .snapshots()
      .map((s) => s.docs.length);

  @override
  Future<List<Map<String, dynamic>>> getPendingDeletionRequests() async {
    final snap = await _deletionRequests
        .where('status', isEqualTo: 'pending')
        .orderBy('requestedAt', descending: true)
        .get();
    return snap.docs.map((d) {
      final data = Map<String, dynamic>.from(d.data());
      data['id'] = d.id;
      return data;
    }).toList();
  }

  @override
  Future<Map<String, dynamic>?> getDeletionRequest(
      String requestId) async {
    final doc = await _deletionRequests.doc(requestId).get();
    if (!doc.exists || doc.data() == null) return null;
    final data = Map<String, dynamic>.from(doc.data()!);
    data['id'] = doc.id;
    return data;
  }

  @override
  Future<void> updateDeletionRequestStatus(
    String requestId,
    String status, {
    String? rejectionNote,
  }) async {
    await _deletionRequests.doc(requestId).update({
      'status': status,
      if (rejectionNote != null) 'rejectionNote': rejectionNote.trim(),
      'resolvedAt': FieldValue.serverTimestamp(),
    });
  }
}

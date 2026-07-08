import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/student.dart';
import '../models/student_remark.dart';
import '../services/auth_service.dart';
import '../shared/utils/app_logger.dart';
import '../shared/utils/class_name_utils.dart';

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

  /// Fetch students in [className]/[section] paginated.
  Future<({List<Student> entries, dynamic cursor})> fetchByClassPaginated(
    String className,
    String section, {
    String? teacherId,
    required int limit,
    dynamic startAfter,
  });

  /// Returns `true` if a student with this roll already exists in the class.
  Future<bool> existsByRoll(String className, String section, int roll);

  /// Returns `true` if ANY student document (other than [excludeDocId]) uses
  /// this [admissionId]. Pass the current student's Firestore doc ID as
  /// [excludeDocId] so the self-document is not flagged as a collision (#40).
  Future<bool> existsByAdmissionId(String admissionId, {String excludeDocId = ''});

  /// Fetch a single student by its Firestore document [id].
  Future<Student?> fetchById(String id);

  /// Atomically inserts a student checking for duplicate roll inside a transaction.
  Future<String?> addStudentUnique(Student s);

  /// Archives a promoted student record by moving it to a non-colliding ID and moving remarks.
  Future<void> archivePromotedStudent(Student s);

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

  /// Atomically promotes a batch of students by creating new records in target
  /// class and updating old records to marked as promoted.
  Future<void> promoteStudentsAtomic(
    List<Student> newStudents,
    List<Student> oldStudents,
  );

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

  /// Flags/unflags a student record as awaiting deletion approval. A targeted
  /// field write (does not overwrite the rest of the document).
  Future<void> setDeletionPending(
    int roll,
    String className,
    String section,
    bool value,
  );

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
    return Student.buildDocId(roll, className, section);
  }

  /// Converts a Firestore document snapshot into a [Student], always setting
  /// `student.id` to the actual Firestore document ID so callers can pass it
  /// back to [delete] reliably.
  Student _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = Map<String, dynamic>.from(doc.data()!);
    data['id'] = doc.id; // override whatever the document stores in 'id'
    return Student.fromJson(data);
  }

  String _toTitleCase(String text) {
    if (text.trim().isEmpty) return text;
    return text.trim().split(RegExp(r'\s+')).map((word) {
      if (word.isEmpty) return '';
      return word.split('-').map((subWord) {
        if (subWord.isEmpty) return '';
        return subWord[0].toUpperCase() + subWord.substring(1).toLowerCase();
      }).join('-');
    }).join(' ');
  }

  // ── Students ────────────────────────────────────────────────────────────────

  /// Page size used when sweeping the whole students collection.
  static const int _fetchAllPageSize = 500;

  /// Soft ceiling: above this many students a single client-side full sweep is
  /// a scale smell (dashboards should read aggregates/rollups instead of every
  /// student doc — see SCALABILITY_REVIEW SCALE-02/04). We still return every
  /// student (no silent truncation), but log so the cost is visible.
  static const int _fetchAllWarnThreshold = 5000;

  @override
  Future<List<Student>> fetchAll() async {
    // Cursor-paginate the entire collection rather than truncating at a fixed
    // limit. The previous `.limit(500)` silently dropped every student beyond
    // the first 500, so any school larger than that showed wrong rosters and
    // dashboard totals with no error (SCALE-01).
    final all = <Student>[];
    DocumentSnapshot<Map<String, dynamic>>? cursor;
    while (true) {
      Query<Map<String, dynamic>> q = _students
          .orderBy(FieldPath.documentId)
          .limit(_fetchAllPageSize);
      if (cursor != null) q = q.startAfterDocument(cursor);
      final snap = await q.get();
      if (snap.docs.isEmpty) break;
      all.addAll(snap.docs.map(_fromDoc));
      if (snap.docs.length < _fetchAllPageSize) break;
      cursor = snap.docs.last;
    }
    if (all.length > _fetchAllWarnThreshold) {
      AppLogger.w('StudentRepository',
          'fetchAll() returned ${all.length} students for school $_schoolId — '
          'this whole-school sweep does not scale; migrate the caller to '
          'aggregate/rollup reads (SCALE-02/04).');
    }
    all.sort((a, b) => a.roll.compareTo(b.roll));
    return all;
  }

  @override
  Future<List<Student>> fetchByClass(
    String className,
    String section, {
    String? teacherId,
  }) async {
    final normalizedClassName = _toTitleCase(className);
    Query<Map<String, dynamic>> q =
        _students.where('className', isEqualTo: normalizedClassName);
    if (section.trim().isNotEmpty) {
      q = q.where('section', isEqualTo: section.trim().toUpperCase());
    }
    if (teacherId != null && teacherId.isNotEmpty) {
      q = q.where('teacherId', isEqualTo: teacherId);
    }
    final snap = await q.orderBy('roll').get();
    return snap.docs
        .map(_fromDoc)
        .toList();
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
    // Doc IDs are deterministic ({class}_{section}_{roll}), so batch the
    // lookups with whereIn on documentId — ceil(N/30) queries instead of one
    // get() per roll (SCALE-10). 30 is Firestore's whereIn limit.
    final ids = rolls.map((r) => _docId(r, className, section)).toList();
    const chunk = 30;
    final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
    for (var i = 0; i < ids.length; i += chunk) {
      final slice = ids.sublist(
          i, i + chunk > ids.length ? ids.length : i + chunk);
      futures.add(
          _students.where(FieldPath.documentId, whereIn: slice).get());
    }
    final snaps = await Future.wait(futures);
    return [
      for (final snap in snaps)
        for (final doc in snap.docs) _fromDoc(doc),
    ];
  }

  @override
  Future<({List<Student> entries, dynamic cursor})> fetchByClassPaginated(
    String className,
    String section, {
    String? teacherId,
    required int limit,
    dynamic startAfter,
  }) async {
    final normalizedClassName = _toTitleCase(className);
    Query<Map<String, dynamic>> q =
        _students.where('className', isEqualTo: normalizedClassName);
    if (section.trim().isNotEmpty) {
      q = q.where('section', isEqualTo: section.trim().toUpperCase());
    }
    if (teacherId != null && teacherId.isNotEmpty) {
      q = q.where('teacherId', isEqualTo: teacherId);
    }
    q = q.orderBy('roll').limit(limit);
    if (startAfter != null) {
      q = q.startAfterDocument(startAfter as DocumentSnapshot);
    }
    final snap = await q.get();
    final list = snap.docs.map(_fromDoc).toList();
    final cursor = snap.docs.isNotEmpty ? snap.docs.last : null;
    return (entries: list, cursor: cursor);
  }

  @override
  Future<bool> existsByRoll(
      String className, String section, int roll) async {
    final doc =
        await _students.doc(_docId(roll, className, section)).get();
    if (!doc.exists) return false;
    final data = doc.data();
    if (data == null) return false;
    return data['promoted'] != true;
  }

  @override
  Future<bool> existsByAdmissionId(
      String admissionId, {String excludeDocId = ''}) async {
    if (admissionId.isEmpty) return false;
    final snap = await _students
        .where('admissionId', isEqualTo: admissionId)
        .limit(2)  // 2 so we can detect self vs. collision
        .get();
    for (final doc in snap.docs) {
      if (doc.id != excludeDocId) return true;
    }
    return false;
  }

  @override
  Future<Student?> fetchById(String id) async {
    final doc = await _students.doc(id).get();
    if (!doc.exists || doc.data() == null) return null;
    return _fromDoc(doc);
  }

  @override
  Future<void> archivePromotedStudent(Student s) async {
    final id = _docId(s.roll, s.className, s.section);
    final docRef = _students.doc(id);
    final archiveId = '${id}_promoted_${s.admissionId}';
    final archiveRef = _students.doc(archiveId);

    final remarksSnap = await docRef.collection('remarks').get();
    final batch = _db.batch();
    batch.set(archiveRef, s.toJson());
    for (final rDoc in remarksSnap.docs) {
      batch.set(archiveRef.collection('remarks').doc(rDoc.id), rDoc.data());
      batch.delete(rDoc.reference);
    }
    batch.delete(docRef);
    await batch.commit();
  }

  @override
  Future<String?> addStudentUnique(Student s) async {
    final id = _docId(s.roll, s.className, s.section);
    final docRef = _students.doc(id);

    final initialSnap = await docRef.get();
    if (initialSnap.exists) {
      final existing = _fromDoc(initialSnap);
      if (existing.promoted) {
        await archivePromotedStudent(existing);
      }
    }

    return _db.runTransaction<String?>((tx) async {
      final doc = await tx.get(docRef);
      if (doc.exists) {
        final data = doc.data();
        if (data != null && data.containsKey('name') && data['name'].toString().isNotEmpty) {
          final classAndSec = ClassName.formatWithSectionWord(s.className, s.section, 'Section');
          return 'Roll number ${s.roll} already exists in $classAndSec.';
        }
      }
      tx.set(docRef, s.toJson(), SetOptions(merge: true));
      return null;
    });
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
  Future<void> promoteStudentsAtomic(
    List<Student> newStudents,
    List<Student> oldStudents,
  ) async {
    if (newStudents.isEmpty) return;
    assert(newStudents.length == oldStudents.length);

    // Firestore batch limit is 500 operations.
    // Each student promotion has 1 set operation (the old is archived/deleted beforehand).
    // So we can process up to 500 students per batch. Let's use a chunk size of 400.
    const chunkSize = 400;
    for (var i = 0; i < newStudents.length; i += chunkSize) {
      final end = (i + chunkSize < newStudents.length)
          ? i + chunkSize
          : newStudents.length;
      final newChunk = newStudents.sublist(i, end);

      final batch = _db.batch();
      for (var j = 0; j < newChunk.length; j++) {
        final ns = newChunk[j];

        final nextId = _docId(ns.roll, ns.className, ns.section);
        final nsWithSchool = ns.copyWith(schoolId: _schoolId);
        batch.set(_students.doc(nextId), nsWithSchool.toJson());
      }
      await batch.commit();
    }
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
    final normalizedClassName = _toTitleCase(className);
    Query<Map<String, dynamic>> q =
        _students.where('className', isEqualTo: normalizedClassName);
    if (section.trim().isNotEmpty) {
      q = q.where('section', isEqualTo: section.trim().toUpperCase());
    }
    if (teacherId != null && teacherId.isNotEmpty) {
      q = q.where('teacherId', isEqualTo: teacherId);
    }
    return q.orderBy('roll').snapshots().map((snap) => snap.docs
        .map(_fromDoc)
        .toList());
  }

  /// Deterministic upper bound on the live whole-school student stream.
  ///
  /// A real-time listener over the entire students collection does not scale
  /// (SCALE-03): it re-bills documents on every change and grows with the
  /// school. This bound keeps the stream affordable; dashboards that need
  /// school-wide figures should migrate to aggregate/rollup reads rather than
  /// raising this number. Ordered by roll so the bounded window is stable.
  ///
  /// CRITICAL: [watchAll] is a BOUNDED window, NOT a complete roster. It is for
  /// best-effort change *detection* only (dashboards re-run their aggregates
  /// when this window changes). Anything that needs EVERY student — exports,
  /// official reports, counts — MUST use the cursor-paginated [fetchAll]
  /// instead. Misusing this stream as a complete source silently dropped every
  /// student past the cap (SCALE-01).
  static const int _watchAllCap = 500;

  @override
  Stream<List<Student>> watchAll() {
    return _students
        .orderBy('roll')
        .limit(_watchAllCap)
        .snapshots()
        .map((snap) {
          // Make truncation LOUD, never silent: a school that has outgrown the
          // window must surface in logs so the caller is migrated (rollups for
          // dashboards, fetchAll for complete reads) — SCALE-01/03.
          if (snap.docs.length >= _watchAllCap) {
            AppLogger.w('StudentRepository',
                'watchAll() hit its $_watchAllCap-doc cap for school $_schoolId — '
                'this stream is a bounded change-detection window, not a complete '
                'roster. Complete reads must use fetchAll(); dashboards should '
                'move to aggregate/rollup reads (SCALE-01/02/03).');
          }
          return snap.docs.map(_fromDoc).toList();
        });
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
      // schoolId stamped so the collection-group remarks query (EOD digest) can
      // be tenant-filtered once multi-tenancy lands (Phase 1 prep).
      'schoolId': _schoolId,
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
      final session = await AuthService().getSession();
      final role = (session?['role'] as String?)?.toLowerCase();
      final isAuthorized = role == 'principal' || role == 'coordinator';
      if (!isAuthorized) {
        throw StateError('You can only delete your own remarks.');
      }
    }
    await ref.delete();
  }

  // ── Deletion requests ─────────────────────────────────────────────────────────

  @override
  Future<void> setDeletionPending(
    int roll,
    String className,
    String section,
    bool value,
  ) async {
    await _students
        .doc(_docId(roll, className, section))
        .update({'deletionPending': value});
  }

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

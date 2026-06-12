import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/exam.dart';
import 'audit_log_service.dart';
import 'auth_service.dart';
import 'base_firestore_service.dart';

/// Firestore-backed exam & marks service.
///
/// Schema (school-scoped):
///   schools/{schoolId}/exams/{examId}                        → Exam doc
///   schools/{schoolId}/exam_results/{examId}/students/{roll} → ExamResult doc
class ExamService extends BaseFirestoreService {
  static ExamService? _instance;
  ExamService._();
  factory ExamService() => _instance ??= ExamService._();
  static set mockInstance(ExamService? mock) => _instance = mock;

  static String _toTitleCase(String text) {
    if (text.trim().isEmpty) return text;
    return text.trim().split(RegExp(r'\s+')).map((word) {
      if (word.isEmpty) return '';
      return word.split('-').map((subWord) {
        if (subWord.isEmpty) return '';
        return subWord[0].toUpperCase() + subWord.substring(1).toLowerCase();
      }).join('-');
    }).join(' ');
  }

  String get _sid => AuthService.currentSchoolId;

  CollectionReference<Map<String, dynamic>> get _exams =>
      schoolCollection(_sid, 'exams');

  CollectionReference<Map<String, dynamic>> get _examResults =>
      schoolCollection(_sid, 'exam_results');

  CollectionReference _resultsCol(String examId) =>
      _examResults.doc(examId).collection('students');

  // ── Exams ──────────────────────────────────────────────────────────────────

  Future<List<Exam>> getExams({String? schoolId, String? className}) async {
    Query q = _exams;
    if (className != null) {
      q = q.where('className', isEqualTo: _toTitleCase(className));
    }
    final snap = await q.get();
    final list = snap.docs
        .map((d) =>
            Exam.fromDoc(d.id, Map<String, dynamic>.from(d.data() as Map)))
        .toList();
    // Sort newest exam date first
    list.sort((a, b) => b.examDate.compareTo(a.examDate));
    return list;
  }

  /// Guards against a 0 (or negative) maximum — a maxMarks:0 exam makes the
  /// marks validator a 0..0 range that rejects every entry (review #235).
  void _validateExam(Exam exam) {
    if (exam.maxMarks <= 0) {
      throw ArgumentError('Maximum marks must be greater than 0.');
    }
  }

  Future<String> createExam({String? schoolId, required Exam exam}) async {
    _validateExam(exam);
    final normalized = Exam(
      id: exam.id,
      name: exam.name,
      className: _toTitleCase(exam.className),
      subjects: exam.subjects,
      maxMarks: exam.maxMarks,
      examDate: exam.examDate,
      createdBy: exam.createdBy,
      publishedAt: exam.publishedAt,
    );
    final ref = await _exams.add(normalized.toJson());
    AuditService.emit(
      action:   'create',
      entity:   'exam',
      entityId: ref.id,
      after:    normalized.toJson(),
    );
    return ref.id;
  }

  Future<void> updateExam({required Exam exam}) async {
    _validateExam(exam);
    final normalized = Exam(
      id: exam.id,
      name: exam.name,
      className: _toTitleCase(exam.className),
      subjects: exam.subjects,
      maxMarks: exam.maxMarks,
      examDate: exam.examDate,
      createdBy: exam.createdBy,
      publishedAt: exam.publishedAt,
    );
    final prev   = await _exams.doc(normalized.id).get();
    final before = prev.exists && prev.data() != null
        ? Map<String, dynamic>.from(prev.data()!)
        : null;
    await _exams.doc(normalized.id).set(normalized.toJson());
    AuditService.emit(
      action:   'update',
      entity:   'exam',
      entityId: normalized.id,
      before:   before,
      after:    normalized.toJson(),
    );
  }

  Future<void> deleteExam({String? schoolId, required String examId}) async {
    final prev   = await _exams.doc(examId).get();
    final before = prev.exists && prev.data() != null
        ? Map<String, dynamic>.from(prev.data()!)
        : null;

    final resultsSnap = await _resultsCol(examId).get();
    final batch = db.batch();
    for (final doc in resultsSnap.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(_examResults.doc(examId));
    batch.delete(_exams.doc(examId));
    await batch.commit();

    AuditService.emit(
      action:   'delete',
      entity:   'exam',
      entityId: examId,
      before:   before,
    );
  }

  // ── Results ────────────────────────────────────────────────────────────────

  /// Builds a section-scoped Firestore document ID for an exam result.
  ///
  /// Using `{className}_{roll}` (e.g. `Class_9-A_1`) prevents roll-number
  /// collisions when the same exam is created for multiple sections of the same
  /// grade (e.g. Class 9-A and Class 9-B both have roll 1 — #627).
  static String _resultDocId(int roll, String className) {
    final cls = _toTitleCase(className).replaceAll(' ', '_');
    return '${cls}_$roll';
  }

  /// Get all results for an exam.
  Future<List<ExamResult>> getResults(
      {String? schoolId, required String examId}) async {
    final snap = await _resultsCol(examId).get();
    return snap.docs
        .map((d) =>
            ExamResult.fromDoc(Map<String, dynamic>.from(d.data() as Map)))
        .toList()
      ..sort((a, b) => a.roll.compareTo(b.roll));
  }

  /// Get result for a single student in an exam, scoped by [className] to
  /// prevent section collisions (#627). The doc ID is `{className}_{roll}`.
  ///
  /// Falls back to the legacy roll-only doc if the section-scoped one is
  /// absent — this keeps existing data accessible during the transition.
  Future<ExamResult?> getResult(String examId, int roll, {String className = ''}) async {
    if (className.isNotEmpty) {
      final scopedDoc = await _resultsCol(examId).doc(_resultDocId(roll, className)).get();
      if (scopedDoc.exists && scopedDoc.data() != null) {
        return ExamResult.fromDoc(
            Map<String, dynamic>.from(scopedDoc.data() as Map));
      }
    }
    // Legacy fallback: roll-only doc (written before #627 fix).
    final doc = await _resultsCol(examId).doc('$roll').get();
    if (!doc.exists || doc.data() == null) return null;
    return ExamResult.fromDoc(
        Map<String, dynamic>.from(doc.data() as Map));
  }

  /// Save / update marks for a student. Uses class-scoped doc ID to prevent
  /// section collisions (#627). Detects create vs update automatically.
  Future<void> saveResult(
      {String? schoolId,
      required String examId,
      required ExamResult result}) async {
    final docId = _resultDocId(result.roll, result.className);
    final prev  = await _resultsCol(examId).doc(docId).get();
    final before = prev.exists && prev.data() != null
        ? Map<String, dynamic>.from(prev.data()! as Map)
        : null;
    await _resultsCol(examId).doc(docId).set(result.toJson());
    AuditService.emit(
      action:   before == null ? 'create' : 'update',
      entity:   'exam_result',
      entityId: '${examId}_${result.className}_${result.roll}',
      before:   before,
      after:    result.toJson(),
    );
  }

  /// Get all results for a student across all exams in a class.
  /// Passes [className] so each result lookup uses the section-scoped doc ID.
  Future<List<ExamResult>> getStudentResults(
      {String? schoolId,
      required String className,
      required int roll}) async {
    final exams = await getExams(className: className);
    if (exams.isEmpty) return [];

    final futures = exams.map((e) => getResult(e.id, roll, className: className)).toList();
    final results = await Future.wait(futures);
    return results.whereType<ExamResult>().toList();
  }

  /// Compute class rank for each student based on total marks in an exam.
  /// Returns { roll → rank }.
  Map<int, int> computeRanks(List<ExamResult> results) {
    final sorted = List<ExamResult>.from(results)
      ..sort((a, b) => b.total.compareTo(a.total));
    final ranks = <int, int>{};
    for (int i = 0; i < sorted.length; i++) {
      ranks[sorted[i].roll] = i + 1;
    }
    return ranks;
  }
}

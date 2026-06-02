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
  static final ExamService _instance = ExamService._();
  ExamService._();
  factory ExamService() => _instance;

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
      q = q.where('className', isEqualTo: className);
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

  Future<String> createExam({String? schoolId, required Exam exam}) async {
    final ref = await _exams.add(exam.toJson());
    AuditService.emit(
      action:   'create',
      entity:   'exam',
      entityId: ref.id,
      after:    exam.toJson(),
    );
    return ref.id;
  }

  Future<void> updateExam({required Exam exam}) async {
    final prev   = await _exams.doc(exam.id).get();
    final before = prev.exists && prev.data() != null
        ? Map<String, dynamic>.from(prev.data()!)
        : null;
    await _exams.doc(exam.id).set(exam.toJson());
    AuditService.emit(
      action:   'update',
      entity:   'exam',
      entityId: exam.id,
      before:   before,
      after:    exam.toJson(),
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

  /// Get result for a single student in an exam.
  Future<ExamResult?> getResult(String examId, int roll) async {
    final doc = await _resultsCol(examId).doc('$roll').get();
    if (!doc.exists || doc.data() == null) return null;
    return ExamResult.fromDoc(
        Map<String, dynamic>.from(doc.data() as Map));
  }

  /// Save / update marks for a student. Detects create vs update automatically.
  Future<void> saveResult(
      {String? schoolId,
      required String examId,
      required ExamResult result}) async {
    final prev   = await _resultsCol(examId).doc('${result.roll}').get();
    final before = prev.exists && prev.data() != null
        ? Map<String, dynamic>.from(prev.data()! as Map)
        : null;
    await _resultsCol(examId).doc('${result.roll}').set(result.toJson());
    AuditService.emit(
      action:   before == null ? 'create' : 'update',
      entity:   'exam_result',
      entityId: '${examId}_${result.roll}',
      before:   before,
      after:    result.toJson(),
    );
  }

  /// Get all results for a student across all exams in a class.
  Future<List<ExamResult>> getStudentResults(
      {String? schoolId,
      required String className,
      required int roll}) async {
    final exams = await getExams(className: className);
    if (exams.isEmpty) return [];

    final futures = exams.map((e) => getResult(e.id, roll)).toList();
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

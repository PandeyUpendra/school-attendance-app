import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/exam.dart';

/// Firestore-backed exam & marks service.
///
/// Schema:
///   exams/{examId}                         → Exam doc
///   exam_results/{examId}/students/{roll}  → ExamResult doc
class ExamService {
  static final _db    = FirebaseFirestore.instance;
  static final _exams = _db.collection('exams');

  static final ExamService _instance = ExamService._();
  ExamService._();
  factory ExamService() => _instance;

  CollectionReference _resultsCol(String examId) =>
      _db.collection('exam_results').doc(examId).collection('students');

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
    return ref.id;
  }

  Future<void> updateExam(Exam exam) async {
    await _exams.doc(exam.id).set(exam.toJson());
  }

  Future<void> deleteExam({String? schoolId, required String examId}) async {
    // Delete exam doc — results sub-collection is left (cheap orphan)
    await _exams.doc(examId).delete();
  }

  // ── Results ────────────────────────────────────────────────────────────────

  /// Get all results for an exam.
  Future<List<ExamResult>> getResults({String? schoolId, required String examId}) async {
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

  /// Save / update marks for a student.
  Future<void> saveResult({String? schoolId, required String examId, required ExamResult result}) async {
    await _resultsCol(examId).doc('${result.roll}').set(result.toJson());
  }

  /// Get all results for a student across all exams in a class.
  Future<List<ExamResult>> getStudentResults(
      {String? schoolId, required String className, required int roll}) async {
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

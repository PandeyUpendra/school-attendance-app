import 'package:cloud_firestore/cloud_firestore.dart';

/// An exam (e.g. Unit Test 1, Half Yearly, Annual).
class Exam {
  final String   id;
  final String   name;         // e.g. 'Unit Test 1'
  final String   className;
  final List<String> subjects; // subjects included in this exam
  final int      maxMarks;     // per subject
  final DateTime examDate;
  final String   createdBy;   // coordinator email/name
  /// When the coordinator publishes the results. Null means unpublished (draft).
  /// Guardians should only see exams where [isPublished] is true.
  final DateTime? publishedAt;

  const Exam({
    required this.id,
    required this.name,
    required this.className,
    required this.subjects,
    required this.maxMarks,
    required this.examDate,
    required this.createdBy,
    this.publishedAt,
  });

  /// An exam is visible to guardians when its results have been published
  /// (publishedAt is non-null and not in the future). Exams without
  /// publishedAt (legacy data) are treated as published for backwards compat.
  bool get isPublished {
    if (publishedAt == null) return true; // legacy exams — no gate
    return !publishedAt!.isAfter(DateTime.now());
  }

  Map<String, dynamic> toJson() => {
        'name':      name,
        'className': className,
        'subjects':  subjects,
        'maxMarks':  maxMarks,
        'examDate':  Timestamp.fromDate(examDate),
        'createdBy': createdBy,
        if (publishedAt != null)
          'publishedAt': Timestamp.fromDate(publishedAt!),
      };

  factory Exam.fromDoc(String id, Map<String, dynamic> data) {
    final ts = data['examDate'];
    final pubTs = data['publishedAt'];
    return Exam(
      id:          id,
      name:        (data['name']      as String?) ?? '',
      className:   (data['className'] as String?) ?? '',
      subjects:    List<String>.from((data['subjects'] as List?) ?? const []),
      maxMarks:    (data['maxMarks']  as num?)?.toInt() ?? 100,
      examDate:    ts is Timestamp ? ts.toDate() : DateTime.now(),
      createdBy:   (data['createdBy'] as String?) ?? '',
      publishedAt: pubTs is Timestamp ? pubTs.toDate() : null,
    );
  }
}

/// Marks for one student in one exam.
/// Stored at: exam_results/{examId}/students/{roll}
class ExamResult {
  final int    roll;
  final String studentName;
  final String className;
  final String examId;
  final String examName;
  /// subject → marks obtained (null = absent/not entered)
  final Map<String, double?> marks;
  final int    maxMarks;
  final String enteredBy; // teacher email

  const ExamResult({
    required this.roll,
    required this.studentName,
    required this.className,
    required this.examId,
    required this.examName,
    required this.marks,
    required this.maxMarks,
    required this.enteredBy,
  });

  double get total => marks.values
      .where((v) => v != null && v >= 0)
      .fold(0.0, (s, v) => s + v!);

  int get subjectCount => marks.length;

  double get percentage =>
      (subjectCount * maxMarks) == 0
          ? 0
          : total / (subjectCount * maxMarks) * 100;

  String get grade {
    final p = percentage;
    if (p >= 90) return 'A+';
    if (p >= 80) return 'A';
    if (p >= 70) return 'B+';
    if (p >= 60) return 'B';
    if (p >= 50) return 'C';
    if (p >= 33) return 'D';
    return 'F';
  }

  bool get isPassed => percentage >= 33;

  Map<String, dynamic> toJson() => {
        'roll':        roll,
        'studentName': studentName,
        'className':   className,
        'examId':      examId,
        'examName':    examName,
        'marks':       marks.map((k, v) => MapEntry(k, v)),
        'maxMarks':    maxMarks,
        'enteredBy':   enteredBy,
      };

  factory ExamResult.fromDoc(Map<String, dynamic> data) {
    final rawMarks = Map<String, dynamic>.from(
        (data['marks'] as Map?) ?? {});
    return ExamResult(
      roll:        (data['roll']        as num?)?.toInt() ?? 0,
      studentName: (data['studentName'] as String?) ?? '',
      className:   (data['className']   as String?) ?? '',
      examId:      (data['examId']      as String?) ?? '',
      examName:    (data['examName']    as String?) ?? '',
      marks:       rawMarks.map(
          (k, v) => MapEntry(k, v == null ? null : (v as num).toDouble())),
      maxMarks:    (data['maxMarks']    as num?)?.toInt() ?? 100,
      enteredBy:   (data['enteredBy']   as String?) ?? '',
    );
  }
}

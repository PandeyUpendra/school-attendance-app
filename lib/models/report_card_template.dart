import 'package:cloud_firestore/cloud_firestore.dart';

// ─── SubjectColumn ────────────────────────────────────────────────────────────

/// Per-subject column configuration inside a template.
class SubjectColumn {
  final String subject;
  final int    maxMarks;
  final bool   includeGrade;
  final bool   includeRemarks;

  const SubjectColumn({
    required this.subject,
    required this.maxMarks,
    this.includeGrade   = true,
    this.includeRemarks = false,
  });

  Map<String, dynamic> toJson() => {
    'subject':        subject,
    'maxMarks':       maxMarks,
    'includeGrade':   includeGrade,
    'includeRemarks': includeRemarks,
  };

  factory SubjectColumn.fromJson(Map<String, dynamic> j) => SubjectColumn(
    subject:        (j['subject']        as String?) ?? '',
    maxMarks:       (j['maxMarks']       as num?)?.toInt() ?? 100,
    includeGrade:   (j['includeGrade']   as bool?) ?? true,
    includeRemarks: (j['includeRemarks'] as bool?) ?? false,
  );

  SubjectColumn copyWith({
    String? subject,
    int? maxMarks,
    bool? includeGrade,
    bool? includeRemarks,
  }) => SubjectColumn(
    subject:        subject        ?? this.subject,
    maxMarks:       maxMarks       ?? this.maxMarks,
    includeGrade:   includeGrade   ?? this.includeGrade,
    includeRemarks: includeRemarks ?? this.includeRemarks,
  );
}

// ─── GradeBand ────────────────────────────────────────────────────────────────

/// One row in the grading scheme (e.g. 91–100 → A1, GPA 10).
class GradeBand {
  final double minPercent;
  final double maxPercent;
  final String grade;
  final double gpa;

  const GradeBand({
    required this.minPercent,
    required this.maxPercent,
    required this.grade,
    required this.gpa,
  });

  Map<String, dynamic> toJson() => {
    'minPercent': minPercent,
    'maxPercent': maxPercent,
    'grade':      grade,
    'gpa':        gpa,
  };

  factory GradeBand.fromJson(Map<String, dynamic> j) => GradeBand(
    minPercent: (j['minPercent'] as num?)?.toDouble() ?? 0,
    maxPercent: (j['maxPercent'] as num?)?.toDouble() ?? 100,
    grade:      (j['grade']      as String?) ?? '',
    gpa:        (j['gpa']        as num?)?.toDouble() ?? 0,
  );

  GradeBand copyWith({
    double? minPercent,
    double? maxPercent,
    String? grade,
    double? gpa,
  }) => GradeBand(
    minPercent: minPercent ?? this.minPercent,
    maxPercent: maxPercent ?? this.maxPercent,
    grade:      grade      ?? this.grade,
    gpa:        gpa        ?? this.gpa,
  );
}

// ─── ReportCardBoard enum ─────────────────────────────────────────────────────

enum ReportCardBoard { cbse, icse, up, cisce, state, custom }

extension ReportCardBoardLabel on ReportCardBoard {
  String get label {
    switch (this) {
      case ReportCardBoard.cbse:   return 'CBSE';
      case ReportCardBoard.icse:   return 'ICSE';
      case ReportCardBoard.up:     return 'UP Board';
      case ReportCardBoard.cisce:  return 'CISCE';
      case ReportCardBoard.state:  return 'State Board';
      case ReportCardBoard.custom: return 'Custom';
    }
  }
}

// ─── ReportCardTemplate ───────────────────────────────────────────────────────

/// Stored at: schools/{sid}/report_card_templates/{templateId}
class ReportCardTemplate {
  final String id;
  final String name;
  final ReportCardBoard board;

  /// Firebase Storage URL for the school logo. May be empty.
  final String headerLogo;

  /// School branding text shown in the PDF header.
  /// MUST come from schools/{sid}.brandName — never hardcode school name here.
  final String headerText;

  /// Optional default per-subject configuration.
  /// When generating from a real Exam, the exam's subject list takes precedence;
  /// this list is used for per-subject overrides (includeGrade, includeRemarks)
  /// and as the preview data in the template editor.
  final List<SubjectColumn> subjects;

  final bool showRank;
  final bool showAttendance;
  final bool showCoCurricular;

  /// Sorted descending by minPercent (highest band first).
  final List<GradeBand> gradeScheme;

  /// Footer line(s) e.g. "Class Teacher: ___  Principal: ___"
  final String footerText;

  final String pageSize;    // 'A4' | 'Letter'
  final String orientation; // 'portrait' | 'landscape'

  /// System presets cannot be edited directly; clone first.
  final bool isSystemPreset;

  final DateTime createdAt;

  const ReportCardTemplate({
    required this.id,
    required this.name,
    required this.board,
    this.headerLogo   = '',
    required this.headerText,
    required this.subjects,
    this.showRank          = true,
    this.showAttendance    = false,
    this.showCoCurricular  = false,
    required this.gradeScheme,
    this.footerText   = '',
    this.pageSize     = 'A4',
    this.orientation  = 'portrait',
    this.isSystemPreset = false,
    required this.createdAt,
  });

  // ── Grade helpers ──────────────────────────────────────────────────────────

  String gradeForPercent(double pct) {
    for (final band in gradeScheme) {
      if (pct >= band.minPercent && pct <= band.maxPercent) return band.grade;
    }
    return 'F';
  }

  double gpaForPercent(double pct) {
    for (final band in gradeScheme) {
      if (pct >= band.minPercent && pct <= band.maxPercent) return band.gpa;
    }
    return 0;
  }

  // ── Config lookup ──────────────────────────────────────────────────────────

  /// Returns the SubjectColumn override for [subject], or null if none defined.
  SubjectColumn? columnFor(String subject) {
    try {
      return subjects.firstWhere((s) => s.subject == subject);
    } catch (_) {
      return null;
    }
  }

  // ── Serialisation ──────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'name':             name,
    'board':            board.name,
    'headerLogo':       headerLogo,
    'headerText':       headerText,
    'subjects':         subjects.map((s) => s.toJson()).toList(),
    'showRank':         showRank,
    'showAttendance':   showAttendance,
    'showCoCurricular': showCoCurricular,
    'gradeScheme':      gradeScheme.map((g) => g.toJson()).toList(),
    'footerText':       footerText,
    'pageSize':         pageSize,
    'orientation':      orientation,
    'isSystemPreset':   isSystemPreset,
    'createdAt':        Timestamp.fromDate(createdAt),
  };

  factory ReportCardTemplate.fromDoc(String id, Map<String, dynamic> data) {
    ReportCardBoard boardVal;
    try {
      boardVal = ReportCardBoard.values.firstWhere(
          (b) => b.name == (data['board'] as String?));
    } catch (_) {
      boardVal = ReportCardBoard.custom;
    }

    final subjectsRaw    = data['subjects']    as List? ?? [];
    final gradeSchemeRaw = data['gradeScheme'] as List? ?? [];
    final ts             = data['createdAt'];

    return ReportCardTemplate(
      id:             id,
      name:           (data['name']           as String?) ?? '',
      board:          boardVal,
      headerLogo:     (data['headerLogo']     as String?) ?? '',
      headerText:     (data['headerText']     as String?) ?? '',
      subjects:       subjectsRaw
          .map((s) => SubjectColumn.fromJson(Map<String, dynamic>.from(s as Map)))
          .toList(),
      showRank:          (data['showRank']          as bool?) ?? true,
      showAttendance:    (data['showAttendance']    as bool?) ?? false,
      showCoCurricular:  (data['showCoCurricular']  as bool?) ?? false,
      gradeScheme:    gradeSchemeRaw
          .map((g) => GradeBand.fromJson(Map<String, dynamic>.from(g as Map)))
          .toList(),
      footerText:     (data['footerText']     as String?) ?? '',
      pageSize:       (data['pageSize']       as String?) ?? 'A4',
      orientation:    (data['orientation']    as String?) ?? 'portrait',
      isSystemPreset: (data['isSystemPreset'] as bool?) ?? false,
      createdAt:      ts is Timestamp ? ts.toDate() : DateTime.now(),
    );
  }

  ReportCardTemplate copyWith({
    String?               id,
    String?               name,
    ReportCardBoard?      board,
    String?               headerLogo,
    String?               headerText,
    List<SubjectColumn>?  subjects,
    bool?                 showRank,
    bool?                 showAttendance,
    bool?                 showCoCurricular,
    List<GradeBand>?      gradeScheme,
    String?               footerText,
    String?               pageSize,
    String?               orientation,
    bool?                 isSystemPreset,
    DateTime?             createdAt,
  }) => ReportCardTemplate(
    id:             id             ?? this.id,
    name:           name           ?? this.name,
    board:          board          ?? this.board,
    headerLogo:     headerLogo     ?? this.headerLogo,
    headerText:     headerText     ?? this.headerText,
    subjects:       subjects       ?? this.subjects,
    showRank:          showRank          ?? this.showRank,
    showAttendance:    showAttendance    ?? this.showAttendance,
    showCoCurricular:  showCoCurricular  ?? this.showCoCurricular,
    gradeScheme:    gradeScheme    ?? this.gradeScheme,
    footerText:     footerText     ?? this.footerText,
    pageSize:       pageSize       ?? this.pageSize,
    orientation:    orientation    ?? this.orientation,
    isSystemPreset: isSystemPreset ?? this.isSystemPreset,
    createdAt:      createdAt      ?? this.createdAt,
  );
}

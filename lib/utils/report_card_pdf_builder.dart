import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/exam.dart';
import '../models/report_card_template.dart';
import '../models/student.dart';
import 'pdf_theme.dart';

// ─── Shared PDF constants ─────────────────────────────────────────────────────

const double _kMarginMm  = 12.0;
const double _kMargin    = _kMarginMm * PdfPageFormat.mm;

// Brand colours for the report-card PDF — the app's teal-green palette.
// Names retained to avoid churn; see [PdfTheme] for the shared source.
const _kViolet    = PdfTheme.primary;     // #003D33 brand primary
const _kVioletDk  = PdfTheme.primaryDark; // #002A24 brand dark
const _kAccent    = PdfTheme.accent;      // #2E8B74 brand accent
const _kGrey50    = PdfColor.fromInt(0xFFF5F5F5);
const _kGrey200   = PdfColor.fromInt(0xFFEEEEEE);
const _kGrey400   = PdfColor.fromInt(0xFFBDBDBD);
const _kGreen50   = PdfColor.fromInt(0xFFE8F5E9);
const _kRed50     = PdfColor.fromInt(0xFFFFEBEE);
const _kGreenDk   = PdfColor.fromInt(0xFF2E7D32);
const _kRedDk     = PdfColor.fromInt(0xFFC62828);
const _kText      = PdfColors.black;
const _kTextLight = PdfColor.fromInt(0xFF616161);
// Semi-transparent whites (PdfColors has no opacity variants)
const _kWhite70   = PdfColor(1, 1, 1, 0.70);
const _kWhite24   = PdfColor(1, 1, 1, 0.24);

// ─── Page format helper ───────────────────────────────────────────────────────

PdfPageFormat _pageFormat(ReportCardTemplate t) {
  final base = t.pageSize == 'Letter' ? PdfPageFormat.letter : PdfPageFormat.a4;
  return t.orientation == 'landscape' ? base.landscape : base;
}

// ═══════════════════════════════════════════════════════════════════════════════
// Individual student report card
// ═══════════════════════════════════════════════════════════════════════════════

/// Builds a single-student report card PDF using [template] settings.
///
/// [rank]          – class rank (null if showRank is false or rank unknown).
/// [totalPresent] / [totalDays] – attendance figures; only used when
///                               template.showAttendance is true.
Future<Uint8List> buildReportCardPdf({
  required ReportCardTemplate template,
  required ExamResult         result,
  required Student            student,
  required Exam               exam,
  int?    rank,
  int?    totalPresent,
  int?    totalDays,
}) async {
  final doc  = pw.Document();
  final fmt  = _pageFormat(template);
  final pct  = result.percentage;
  final grade = template.gradeScheme.isNotEmpty
      ? template.gradeForPercent(pct)
      : result.grade;
  final gpa = template.gradeScheme.isNotEmpty
      ? template.gpaForPercent(pct)
      : 0.0;

  doc.addPage(pw.Page(
    pageFormat: fmt,
    margin: const pw.EdgeInsets.all(_kMargin),
    build: (ctx) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        // ── Header ──────────────────────────────────────────────────────────
        _buildHeader(template, exam),
        pw.SizedBox(height: 8),

        // ── Student info ─────────────────────────────────────────────────────
        _buildStudentInfo(student, exam),
        pw.SizedBox(height: 8),

        // ── Subject table ────────────────────────────────────────────────────
        _buildSubjectTable(template, result, exam),
        pw.SizedBox(height: 8),

        // ── Summary strip ────────────────────────────────────────────────────
        _buildSummaryStrip(
          result: result,
          grade:  grade,
          gpa:    gpa,
          rank:   template.showRank ? rank : null,
          exam:   exam,
        ),

        // ── Attendance ───────────────────────────────────────────────────────
        if (template.showAttendance && totalPresent != null && totalDays != null)
          ...[
            pw.SizedBox(height: 6),
            _buildAttendanceRow(totalPresent, totalDays),
          ],

        // ── Co-curricular placeholder ─────────────────────────────────────────
        if (template.showCoCurricular) ...[
          pw.SizedBox(height: 8),
          _buildCoCurricularTable(),
        ],

        pw.Spacer(),

        // ── Footer ───────────────────────────────────────────────────────────
        _buildFooter(template),
      ],
    ),
  ));

  return doc.save();
}

// ═══════════════════════════════════════════════════════════════════════════════
// Class-wide report card (multi-page)
// ═══════════════════════════════════════════════════════════════════════════════

/// Builds a class-wide report card PDF with one row per student.
Future<Uint8List> buildClassReportCardPdf({
  required ReportCardTemplate   template,
  required List<ExamResult>     results,
  required List<Student>        students,
  required Exam                 exam,
  required Map<int, int>        ranks,
}) async {
  final doc = pw.Document();
  final fmt = _pageFormat(template);

  // Build result lookup map for O(1) access.
  final resultMap = { for (final r in results) r.roll: r };

  doc.addPage(pw.MultiPage(
    pageFormat: fmt,
    margin: const pw.EdgeInsets.all(_kMargin),
    header: (ctx) => _buildHeader(template, exam),
    footer: (ctx) => _buildFooter(template),
    build: (ctx) => [
      pw.SizedBox(height: 8),
      _buildClassStatsRow(results, exam),
      pw.SizedBox(height: 8),
      _buildClassTable(
        template: template,
        students: students,
        resultMap: resultMap,
        exam: exam,
        ranks: ranks,
      ),
    ],
  ));

  return doc.save();
}

// ─── Header ───────────────────────────────────────────────────────────────────

pw.Widget _buildHeader(ReportCardTemplate template, Exam exam) {
  final examDate = exam.examDate;
  final dateStr  =
      '${examDate.day.toString().padLeft(2, '0')}/'
      '${examDate.month.toString().padLeft(2, '0')}/'
      '${examDate.year}';

  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: const pw.BoxDecoration(
      color: _kVioletDk,
      borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (template.headerText.isNotEmpty)
                pw.Text(
                  template.headerText,
                  style: pw.TextStyle(
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
              pw.SizedBox(height: 2),
              pw.Text(
                'REPORT CARD  •  ${exam.name}',
                style: const pw.TextStyle(
                  fontSize: 10,
                  color: _kWhite70,
                ),
              ),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              exam.className,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              dateStr,
              style: const pw.TextStyle(fontSize: 9, color: _kWhite70),
            ),
            pw.SizedBox(height: 2),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: const pw.BoxDecoration(
                color: _kWhite24,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Text(
                template.board.label,
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.white),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

// ─── Student info box ─────────────────────────────────────────────────────────

pw.Widget _buildStudentInfo(Student student, Exam exam) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: pw.BoxDecoration(
      color: _kGrey50,
      border: pw.Border.all(color: _kGrey400, width: 0.5),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
    ),
    child: pw.Row(
      children: [
        _infoCell('Student Name', student.name, flex: 3),
        _infoCell('Roll No', '${student.roll}'),
        _infoCell('Class', exam.className),
        _infoCell('Max / Subject', '${exam.maxMarks}'),
      ],
    ),
  );
}

pw.Widget _infoCell(String label, String value, {int flex = 2}) =>
    pw.Expanded(
      flex: flex,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label,
              style: const pw.TextStyle(fontSize: 7, color: _kTextLight)),
          pw.SizedBox(height: 1),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );

// ─── Subject marks table ──────────────────────────────────────────────────────

pw.Widget _buildSubjectTable(
  ReportCardTemplate template,
  ExamResult         result,
  Exam               exam,
) {
  // Determine which extra columns to show (any subject needs it)
  final showGrade   = exam.subjects.any((s) =>
      template.columnFor(s)?.includeGrade ?? true);
  final showRemarks = exam.subjects.any((s) =>
      template.columnFor(s)?.includeRemarks ?? false);

  final colWidths = <int, pw.TableColumnWidth>{
    0: const pw.FlexColumnWidth(3),   // Subject
    1: const pw.FixedColumnWidth(42), // Marks
    2: const pw.FixedColumnWidth(38), // Max
    3: const pw.FixedColumnWidth(38), // %
  };
  int nextCol = 4;
  if (showGrade)   colWidths[nextCol++] = const pw.FixedColumnWidth(36);
  if (showRemarks) colWidths[nextCol]   = const pw.FlexColumnWidth(2);

  pw.Widget headerCell(String t) => _cell(t, bold: true, bg: _kGrey200);

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Text('Subject-wise Marks',
          style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: _kViolet)),
      pw.SizedBox(height: 4),
      pw.Table(
        border: pw.TableBorder.all(color: _kGrey400, width: 0.4),
        columnWidths: colWidths,
        children: [
          // Header
          pw.TableRow(children: [
            headerCell('Subject'),
            headerCell('Marks'),
            headerCell('Max'),
            headerCell('%'),
            if (showGrade)   headerCell('Grade'),
            if (showRemarks) headerCell('Remarks'),
          ]),
          // Rows
          for (final sub in exam.subjects) ...[
            _buildSubjectRow(
              subject:     sub,
              result:      result,
              maxMarks:    exam.maxMarks,
              showGrade:   showGrade,
              showRemarks: showRemarks,
              template:    template,
            ),
          ],
        ],
      ),
    ],
  );
}

pw.TableRow _buildSubjectRow({
  required String            subject,
  required ExamResult        result,
  required int               maxMarks,
  required bool              showGrade,
  required bool              showRemarks,
  required ReportCardTemplate template,
}) {
  final marks   = result.marks[subject];
  final pct     = marks != null ? (marks / maxMarks * 100) : 0.0;
  final passed  = marks != null && marks >= maxMarks * 0.33;
  final marksStr = marks != null ? marks.toStringAsFixed(0) : 'AB';
  final pctStr   = marks != null ? '${pct.toStringAsFixed(1)}%' : '—';
  final gradeStr = marks != null
      ? (template.gradeScheme.isNotEmpty
          ? template.gradeForPercent(pct)
          : result.grade)
      : '—';

  final rowBg = marks == null
      ? _kGrey50
      : passed ? _kGreen50 : _kRed50;

  return pw.TableRow(
    decoration: pw.BoxDecoration(color: rowBg),
    children: [
      _cell(subject),
      _cell(marksStr,
          color: marks == null ? _kTextLight : passed ? _kGreenDk : _kRedDk,
          bold: true),
      _cell('$maxMarks', color: _kTextLight),
      _cell(pctStr),
      if (showGrade)   _cell(gradeStr, bold: true),
      if (showRemarks) _cell(''),
    ],
  );
}

// ─── Summary strip ────────────────────────────────────────────────────────────

pw.Widget _buildSummaryStrip({
  required ExamResult result,
  required String     grade,
  required double     gpa,
  required int?       rank,
  required Exam       exam,
}) {
  final totalMax = exam.maxMarks * exam.subjects.length;
  final cols = [
    _summaryCol('Total',
        '${result.total.toStringAsFixed(0)} / $totalMax'),
    _summaryCol('Percentage',
        '${result.percentage.toStringAsFixed(1)}%'),
    _summaryCol('Grade', grade),
    if (gpa > 0) _summaryCol('GPA', gpa.toStringAsFixed(1)),
    if (rank != null) _summaryCol('Rank', '#$rank'),
    _summaryCol('Result', result.isPassed ? 'PASS' : 'FAIL',
        valueColor: result.isPassed ? _kGreenDk : _kRedDk),
  ];

  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 9, horizontal: 12),
    decoration: const pw.BoxDecoration(
      color: _kViolet,
      borderRadius: pw.BorderRadius.all(pw.Radius.circular(5)),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
      children: cols,
    ),
  );
}

pw.Widget _summaryCol(String label, String value,
    {PdfColor? valueColor}) =>
    pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(label,
            style: const pw.TextStyle(
                fontSize: 7, color: _kWhite70)),
        pw.SizedBox(height: 2),
        pw.Text(value,
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: valueColor ?? PdfColors.white,
            )),
      ],
    );

// ─── Attendance row ───────────────────────────────────────────────────────────

pw.Widget _buildAttendanceRow(int present, int total) {
  final pct  = total > 0 ? (present / total * 100).toStringAsFixed(1) : '—';
  final good = total > 0 && present / total >= 0.75;
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: pw.BoxDecoration(
      color: good ? _kGreen50 : _kRed50,
      border: pw.Border.all(color: _kGrey400, width: 0.4),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
    ),
    child: pw.Row(children: [
      pw.Text('Attendance:',
          style: pw.TextStyle(
              fontSize: 9, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(width: 6),
      pw.Text('$present / $total days  ($pct%)',
          style: const pw.TextStyle(fontSize: 9)),
      pw.Spacer(),
      pw.Text(
        good ? 'Satisfactory' : 'Short Attendance',
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          color: good ? _kGreenDk : _kRedDk,
        ),
      ),
    ]),
  );
}

// ─── Co-curricular placeholder ────────────────────────────────────────────────

pw.Widget _buildCoCurricularTable() {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Text('Co-Curricular Activities',
          style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: _kViolet)),
      pw.SizedBox(height: 4),
      pw.Table(
        border: pw.TableBorder.all(color: _kGrey400, width: 0.4),
        columnWidths: const {
          0: pw.FlexColumnWidth(3),
          1: pw.FixedColumnWidth(60),
          2: pw.FixedColumnWidth(60),
        },
        children: [
          pw.TableRow(children: [
            _cell('Activity', bold: true, bg: _kGrey200),
            _cell('Grade', bold: true, bg: _kGrey200),
            _cell('Remarks', bold: true, bg: _kGrey200),
          ]),
          for (int i = 0; i < 3; i++)
            pw.TableRow(children: [
              _cell(''),
              _cell(''),
              _cell(''),
            ]),
        ],
      ),
    ],
  );
}

// ─── Footer ───────────────────────────────────────────────────────────────────

pw.Widget _buildFooter(ReportCardTemplate template) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Divider(color: _kGrey400, thickness: 0.5),
      pw.SizedBox(height: 4),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Text(
              template.footerText,
              style: const pw.TextStyle(fontSize: 8, color: _kTextLight),
            ),
          ),
          pw.Text(
            'Generated by School App',
            style: const pw.TextStyle(fontSize: 7, color: _kGrey400),
          ),
        ],
      ),
    ],
  );
}

// ─── Class-wide stats row ─────────────────────────────────────────────────────

pw.Widget _buildClassStatsRow(List<ExamResult> results, Exam exam) {
  final passCount = results.where((r) => r.isPassed).length;
  final avgPct    = results.isEmpty
      ? 0.0
      : results.fold(0.0, (s, r) => s + r.percentage) / results.length;

  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 14),
    decoration: pw.BoxDecoration(
      color: _kGrey50,
      border: pw.Border.all(color: _kGrey400, width: 0.4),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
      children: [
        _statChip('Students',  '${results.length}',      _kViolet),
        _statChip('Passed',    '$passCount',              _kGreenDk),
        _statChip('Failed',    '${results.length - passCount}', _kRedDk),
        _statChip('Avg %',     '${avgPct.toStringAsFixed(1)}%', _kAccent),
        _statChip('Max Marks', '${exam.maxMarks}/sub',   _kTextLight),
      ],
    ),
  );
}

pw.Widget _statChip(String label, String value, PdfColor color) =>
    pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(value,
            style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: color)),
        pw.SizedBox(height: 1),
        pw.Text(label,
            style: const pw.TextStyle(
                fontSize: 7, color: _kTextLight)),
      ],
    );

// ─── Class-wide table ─────────────────────────────────────────────────────────

pw.Widget _buildClassTable({
  required ReportCardTemplate   template,
  required List<Student>        students,
  required Map<int, ExamResult> resultMap,
  required Exam                 exam,
  required Map<int, int>        ranks,
}) {
  final showRank = template.showRank;
  final subjects = exam.subjects;

  // Column widths: Roll | Name | sub*N | Total | % | Grade | [Rank]
  final colWidths = <int, pw.TableColumnWidth>{
    0: const pw.FixedColumnWidth(30), // Roll
    1: const pw.FlexColumnWidth(3),   // Name
  };
  for (int i = 0; i < subjects.length; i++) {
    colWidths[2 + i] = const pw.FlexColumnWidth(1.5);
  }
  final base = 2 + subjects.length;
  colWidths[base]     = const pw.FixedColumnWidth(40); // Total
  colWidths[base + 1] = const pw.FixedColumnWidth(38); // %
  colWidths[base + 2] = const pw.FixedColumnWidth(34); // Grade
  if (showRank) colWidths[base + 3] = const pw.FixedColumnWidth(30); // Rank

  pw.Widget h(String t) => _cell(t, bold: true, bg: _kGrey200, fontSize: 8);

  final rows = <pw.TableRow>[
    // Header
    pw.TableRow(children: [
      h('Roll'),
      h('Name'),
      ...subjects.map(h),
      h('Total'),
      h('%'),
      h('Grade'),
      if (showRank) h('Rank'),
    ]),
    // Student rows
    for (final s in students) ...[
      _buildClassRow(
        student:  s,
        result:   resultMap[s.roll],
        exam:     exam,
        rank:     showRank ? ranks[s.roll] : null,
        template: template,
      ),
    ],
  ];

  return pw.Table(
    border: pw.TableBorder.all(color: _kGrey400, width: 0.4),
    columnWidths: colWidths,
    children: rows,
  );
}

pw.TableRow _buildClassRow({
  required Student            student,
  required ExamResult?        result,
  required Exam               exam,
  required int?               rank,
  required ReportCardTemplate template,
}) {
  PdfColor bg = PdfColors.white;
  if (result != null) {
    bg = result.isPassed ? _kGreen50 : _kRed50;
  }

  final pct     = result?.percentage ?? 0;
  final grade   = result == null
      ? '—'
      : template.gradeScheme.isNotEmpty
          ? template.gradeForPercent(pct)
          : result.grade;

  return pw.TableRow(
    decoration: pw.BoxDecoration(color: bg),
    children: [
      _cell('${student.roll}', fontSize: 8),
      _cell(student.name, fontSize: 8),
      ...exam.subjects.map((sub) {
        final v = result?.marks[sub];
        return _cell(
          v != null ? v.toStringAsFixed(0) : '—',
          fontSize: 8,
          color: v == null ? _kTextLight : null,
        );
      }),
      _cell(
        result != null ? result.total.toStringAsFixed(0) : '—',
        bold: true, fontSize: 8,
      ),
      _cell(
        result != null ? '${pct.toStringAsFixed(1)}%' : '—',
        fontSize: 8,
      ),
      _cell(grade, bold: true, fontSize: 8),
      if (rank != null) _cell('#$rank', fontSize: 8),
    ],
  );
}

// ─── Shared cell builder ──────────────────────────────────────────────────────

pw.Widget _cell(
  String text, {
  bool    bold     = false,
  PdfColor? color  ,
  PdfColor? bg     ,
  double  fontSize = 9,
}) =>
    pw.Container(
      color: bg,
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color ?? _kText,
        ),
      ),
    );

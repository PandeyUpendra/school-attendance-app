import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/exam.dart';
import '../models/student.dart';
import '../services/exam_service.dart';
import '../services/student_service.dart';
import '../theme.dart';

/// Report card screen — shows all students' results for one exam.
/// Includes class rank, grade, pass/fail and a printable PDF.
class ReportCardScreen extends StatefulWidget {
  final Exam   exam;
  final String className;

  const ReportCardScreen({
    super.key,
    required this.exam,
    required this.className,
  });

  @override
  State<ReportCardScreen> createState() => _ReportCardScreenState();
}

class _ReportCardScreenState extends State<ReportCardScreen> {
  final _examService    = ExamService();
  final _studentService = StudentService();

  StreamSubscription<List<Student>>? _studentSub;

  bool _loading = true;
  List<Student>      _students = [];
  List<ExamResult>   _results  = [];
  Map<int, int>      _ranks    = {};

  @override
  void initState() {
    super.initState();
    _load();
    // Keep the student roster in sync so deletions are reflected immediately.
    _studentSub = _studentService
        .watchStudentsByClass(widget.className)
        .listen((list) {
      if (!mounted) return;
      setState(() => _students = list);
    });
  }

  @override
  void dispose() {
    _studentSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await Future.wait([
      _studentService.getStudentsByClass(widget.className),
      _examService.getResults(widget.exam.id),
    ]);
    final students = data[0] as List<Student>;
    final results  = data[1] as List<ExamResult>;
    final ranks    = _examService.computeRanks(results);

    if (!mounted) return;
    setState(() {
      _students = students;
      _results  = results;
      _ranks    = ranks;
      _loading  = false;
    });
  }

  ExamResult? _resultFor(int roll) {
    try {
      return _results.firstWhere((r) => r.roll == roll);
    } catch (_) {
      return null;
    }
  }

  Future<void> _shareStudentReport(Student s, ExamResult r) async {
    final doc  = pw.Document();
    final exam = widget.exam;

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (pw.Context ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Center(
            child: pw.Text('STUDENT REPORT CARD',
                style: pw.TextStyle(
                    fontSize: 20, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(exam.name,
                style: const pw.TextStyle(fontSize: 13)),
          ),
          pw.SizedBox(height: 20),

          // Student info box
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              border: pw.Border.all(width: 0.5),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _pdfInfoRow('Student Name', s.name),
                pw.SizedBox(height: 4),
                _pdfInfoRow('Roll No', '${s.roll}'),
                pw.SizedBox(height: 4),
                _pdfInfoRow('Class', exam.className),
                pw.SizedBox(height: 4),
                _pdfInfoRow('Exam Date',
                    '${exam.examDate.day}/${exam.examDate.month}/${exam.examDate.year}'),
              ],
            ),
          ),
          pw.SizedBox(height: 16),

          // Subject marks table
          pw.Text('Subject-wise Marks',
              style: pw.TextStyle(
                  fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FlexColumnWidth(2),
              2: const pw.FlexColumnWidth(2),
              3: const pw.FlexColumnWidth(2),
            },
            children: [
              pw.TableRow(
                decoration:
                    const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  _pdfCell('Subject', bold: true),
                  _pdfCell('Marks', bold: true),
                  _pdfCell('Max', bold: true),
                  _pdfCell('Status', bold: true),
                ],
              ),
              for (final sub in exam.subjects)
                pw.TableRow(
                  children: [
                    _pdfCell(sub),
                    _pdfCell(r.marks[sub] != null
                        ? r.marks[sub]!.toStringAsFixed(0)
                        : 'Absent'),
                    _pdfCell('${exam.maxMarks}'),
                    _pdfCell(
                      r.marks[sub] == null
                          ? 'Absent'
                          : r.marks[sub]! >= (exam.maxMarks * 0.33)
                              ? 'Pass'
                              : 'Fail',
                    ),
                  ],
                ),
            ],
          ),
          pw.SizedBox(height: 16),

          // Summary row
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(
                vertical: 10, horizontal: 12),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey200,
              border: pw.Border.all(width: 0.5),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _pdfSummaryCol('Total',
                    '${r.total.toStringAsFixed(0)}/${exam.maxMarks * exam.subjects.length}'),
                _pdfSummaryCol('Percentage',
                    '${r.percentage.toStringAsFixed(1)}%'),
                _pdfSummaryCol('Grade', r.grade),
                _pdfSummaryCol('Rank',
                    _ranks[s.roll] != null ? '#${_ranks[s.roll]}' : '—'),
                _pdfSummaryCol(
                    'Result', r.isPassed ? 'PASS' : 'FAIL'),
              ],
            ),
          ),
          pw.Spacer(),
          pw.Text(
            'Pass criteria: >= 33%  |  Generated by School App',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ],
      ),
    ));

    await Printing.sharePdf(
      bytes: await doc.save(),
      filename:
          'report_${s.name.replaceAll(' ', '_')}_${exam.name.replaceAll(' ', '_')}.pdf',
    );
  }

  pw.Widget _pdfInfoRow(String label, String value) => pw.Row(children: [
        pw.Text('$label: ',
            style: pw.TextStyle(
                fontSize: 10, fontWeight: pw.FontWeight.bold)),
        pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
      ]);

  pw.Widget _pdfSummaryCol(String label, String value) => pw.Column(
        children: [
          pw.Text(label,
              style: const pw.TextStyle(fontSize: 9)),
          pw.SizedBox(height: 2),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 13, fontWeight: pw.FontWeight.bold)),
        ],
      );

  Future<void> _shareClassReport() async {
    final doc  = pw.Document();
    final exam = widget.exam;

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (pw.Context context) => [
        pw.Center(
          child: pw.Text('REPORT CARD — ${exam.name}',
              style: pw.TextStyle(
                  fontSize: 18, fontWeight: pw.FontWeight.bold)),
        ),
        pw.SizedBox(height: 4),
        pw.Center(
          child: pw.Text(
            '${exam.className}  •  Date: '
            '${exam.examDate.day}/${exam.examDate.month}/${exam.examDate.year}  •  '
            'Max Marks: ${exam.maxMarks}/subject',
            style: const pw.TextStyle(fontSize: 10),
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Table(
          border: pw.TableBorder.all(width: 0.5),
          columnWidths: {
            0: const pw.FixedColumnWidth(35),
            1: const pw.FlexColumnWidth(3),
            ...{
              for (int i = 0; i < exam.subjects.length; i++)
                i + 2: const pw.FlexColumnWidth(2),
            },
            exam.subjects.length + 2: const pw.FixedColumnWidth(40),
            exam.subjects.length + 3: const pw.FixedColumnWidth(40),
            exam.subjects.length + 4: const pw.FixedColumnWidth(35),
            exam.subjects.length + 5: const pw.FixedColumnWidth(30),
          },
          children: [
            // Header row
            pw.TableRow(
              decoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              children: [
                _pdfCell('Roll', bold: true),
                _pdfCell('Name', bold: true),
                ...exam.subjects.map((s) => _pdfCell(s, bold: true)),
                _pdfCell('Total', bold: true),
                _pdfCell('%', bold: true),
                _pdfCell('Grade', bold: true),
                _pdfCell('Rank', bold: true),
              ],
            ),
            // Data rows
            for (final s in _students) ...[
              pw.TableRow(
                children: [
                  _pdfCell('${s.roll}'),
                  _pdfCell(s.name),
                  ...exam.subjects.map((sub) {
                    final v = _resultFor(s.roll)?.marks[sub];
                    return _pdfCell(
                        v != null ? v.toStringAsFixed(0) : '—');
                  }),
                  _pdfCell(
                    _resultFor(s.roll) != null
                        ? _resultFor(s.roll)!.total.toStringAsFixed(0)
                        : '—',
                  ),
                  _pdfCell(
                    _resultFor(s.roll) != null
                        ? '${_resultFor(s.roll)!.percentage.toStringAsFixed(1)}%'
                        : '—',
                  ),
                  _pdfCell(_resultFor(s.roll)?.grade ?? '—'),
                  _pdfCell(_ranks[s.roll] != null
                      ? '#${_ranks[s.roll]}'
                      : '—'),
                ],
              ),
            ],
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Text(
          'Pass criteria: >= 33%  |  Generated by School App',
          style: const pw.TextStyle(fontSize: 8),
        ),
      ],
    ));

    await Printing.sharePdf(
      bytes: await doc.save(),
      filename:
          'report_${exam.name.replaceAll(' ', '_')}_${widget.className}.pdf',
    );
  }

  pw.Widget _pdfCell(String text, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final exam = widget.exam;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(exam.name,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            Text(exam.className,
                style:
                    const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share PDF',
            onPressed: _loading ? null : _shareClassReport,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _students.isEmpty
              ? Center(
                  child: Text('No students in ${widget.className}.',
                      style: TextStyle(color: Colors.grey.shade500)))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppTheme.primary,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(12),
                    children: [
                      // Topper banner — pass live student map so name is never stale
                      _TopperBanner(
                        results:    _results,
                        ranks:      _ranks,
                        studentMap: {for (final s in _students) s.roll: s},
                      ),
                      const SizedBox(height: 12),

                      // Stats summary
                      _StatsSummary(
                        students: _students,
                        results:  _results,
                        maxMarks: exam.maxMarks,
                        subjectCount: exam.subjects.length,
                      ),
                      const SizedBox(height: 12),

                      // Per-student cards
                      ...List.generate(_students.length, (i) {
                        final s = _students[i];
                        final result = _resultFor(s.roll);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _StudentResultCard(
                            student:  s,
                            result:   result,
                            rank:     _ranks[s.roll],
                            subjects: exam.subjects,
                            maxMarks: exam.maxMarks,
                            onShare:  result != null
                                ? () => _shareStudentReport(s, result)
                                : null,
                          ),
                        );
                      }),
                    ],
                  ),
                ),
    );
  }
}

// ─── Topper banner ────────────────────────────────────────────────────────────

class _TopperBanner extends StatelessWidget {
  final List<ExamResult>  results;
  final Map<int, int>     ranks;
  final Map<int, Student> studentMap;

  const _TopperBanner({
    required this.results,
    required this.ranks,
    required this.studentMap,
  });

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) return const SizedBox.shrink();
    final toppers = results.where((r) => ranks[r.roll] == 1).toList();
    if (toppers.isEmpty) return const SizedBox.shrink();
    final top = toppers.first;
    // Prefer live name from students/ collection; fall back to stored name.
    final name = studentMap[top.roll]?.name ?? top.studentName;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primaryDark, AppTheme.primary],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        const Icon(Icons.emoji_events, color: Colors.amber, size: 32),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Class Topper',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 11)),
              Text(name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              Text(
                '${top.total.toStringAsFixed(0)} marks  •  '
                '${top.percentage.toStringAsFixed(1)}%  •  Grade ${top.grade}',
                style: const TextStyle(
                    color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

// ─── Stats summary ────────────────────────────────────────────────────────────

class _StatsSummary extends StatelessWidget {
  final List<Student>    students;
  final List<ExamResult> results;
  final int maxMarks, subjectCount;

  const _StatsSummary({
    required this.students,
    required this.results,
    required this.maxMarks,
    required this.subjectCount,
  });

  @override
  Widget build(BuildContext context) {
    final passCount = results.where((r) => r.isPassed).length;
    final avgPct = results.isEmpty
        ? 0.0
        : results.fold(0.0, (s, r) => s + r.percentage) / results.length;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Cell('${students.length}', 'Students', AppTheme.primary),
          _Cell('${results.length}', 'Results', AppTheme.primaryMid),
          _Cell('$passCount', 'Passed', Colors.green),
          _Cell('${results.length - passCount}', 'Failed', Colors.red),
          _Cell('${avgPct.toStringAsFixed(1)}%', 'Avg %',
              const Color(0xFFF57F17)),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final String value, label;
  final Color  color;
  const _Cell(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color)),
          const SizedBox(height: 2),
          Text(label,
              style:
                  TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        ],
      );
}

// ─── Per-student result card ──────────────────────────────────────────────────

class _StudentResultCard extends StatelessWidget {
  final Student      student;
  final ExamResult?  result;
  final int?         rank;
  final List<String> subjects;
  final int          maxMarks;
  final VoidCallback? onShare;

  const _StudentResultCard({
    required this.student,
    required this.result,
    required this.rank,
    required this.subjects,
    required this.maxMarks,
    this.onShare,
  });

  Color get _gradeColor {
    if (result == null) return Colors.grey;
    final p = result!.percentage;
    if (p >= 80) return Colors.green;
    if (p >= 50) return const Color(0xFFF57F17);
    if (p >= 33) return Colors.blue;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final s = student;
    final r = result;
    final color = _gradeColor;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: color.withOpacity(0.12),
              child: Text(
                s.name.isNotEmpty ? s.name[0].toUpperCase() : '?',
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.name,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold)),
                  Text('Roll ${s.roll}',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade500)),
                ],
              ),
            ),
            if (rank != null)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: rank == 1
                      ? Colors.amber.shade50
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: rank == 1
                          ? Colors.amber
                          : Colors.grey.shade300),
                ),
                child: Text(
                  rank == 1 ? '🥇 #$rank' : '#$rank',
                  style: TextStyle(
                      fontSize: 11,
                      color: rank == 1 ? Colors.amber.shade800 : null,
                      fontWeight: FontWeight.bold),
                ),
              ),
            if (onShare != null) ...[
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.share_outlined, size: 18),
                tooltip: 'Share PDF',
                color: AppTheme.primary,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 30, minHeight: 30),
                onPressed: onShare,
              ),
            ],
          ]),
          if (r != null) ...[
            const SizedBox(height: 10),
            // Subject marks chips
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: subjects.map((sub) {
                final marks = r.marks[sub];
                final ok = marks != null && marks >= (maxMarks * 0.33);
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: marks == null
                        ? Colors.grey.shade100
                        : ok
                            ? Colors.green.shade50
                            : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: marks == null
                          ? Colors.grey.shade300
                          : ok
                              ? Colors.green.shade200
                              : Colors.red.shade200,
                    ),
                  ),
                  child: Text(
                    '$sub: ${marks != null ? marks.toStringAsFixed(0) : 'AB'}/$maxMarks',
                    style: TextStyle(
                        fontSize: 11,
                        color: marks == null
                            ? Colors.grey
                            : ok
                                ? Colors.green.shade800
                                : Colors.red.shade800),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            Row(children: [
              // Grade badge
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Grade ${r.grade}',
                  style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${r.total.toStringAsFixed(0)} / '
                '${maxMarks * subjects.length}  •  '
                '${r.percentage.toStringAsFixed(1)}%',
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade600),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: r.isPassed
                      ? Colors.green.shade50
                      : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  r.isPassed ? 'PASS' : 'FAIL',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: r.isPassed
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                  ),
                ),
              ),
            ]),
          ] else ...[
            const SizedBox(height: 8),
            Text('Marks not entered yet',
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade400)),
          ],
        ],
      ),
    );
  }
}

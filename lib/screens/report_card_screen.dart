import 'dart:async';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../models/exam.dart';
import '../models/report_card_template.dart';
import '../models/student.dart';
import '../services/auth_service.dart';
import '../services/exam_service.dart';
import '../services/report_card_template_service.dart';
import '../services/school_service.dart';
import '../services/student_service.dart';
import '../theme.dart';
import '../utils/report_card_pdf_builder.dart';
import 'coordinator/report_card_template_editor.dart';

/// Report card screen — shows all students' results for one exam.
/// Coordinator picks a template before exporting any PDF.
class ReportCardScreen extends StatefulWidget {
  final Exam   exam;
  final String className;
  final String section;

  const ReportCardScreen({
    super.key,
    required this.exam,
    required this.className,
    this.section = '',
  });

  @override
  State<ReportCardScreen> createState() => _ReportCardScreenState();
}

class _ReportCardScreenState extends State<ReportCardScreen> {
  final _examSvc      = ExamService();
  final _studentSvc   = StudentService();
  final _templateSvc  = ReportCardTemplateService();
  final _schoolSvc    = SchoolService();

  StreamSubscription<List<Student>>? _studentSub;

  bool _loading = true;
  List<Student>    _students = [];
  List<ExamResult> _results  = [];
  Map<int, int>    _ranks    = {};

  @override
  void initState() {
    super.initState();
    _load();
    _studentSub = _studentSvc
        .watchStudentsByClass(
            className: widget.className, section: widget.section)
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
      _studentSvc.getStudentsByClass(
          className: widget.className, section: widget.section),
      _examSvc.getResults(examId: widget.exam.id),
    ]);
    final students = data[0] as List<Student>;
    final results  = data[1] as List<ExamResult>;
    final ranks    = _examSvc.computeRanks(results);

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

  // ── Template picker ────────────────────────────────────────────────────────

  /// Shows a bottom sheet to pick a template, then calls [onPicked].
  /// Auto-seeds the 3 system presets if the school has none yet.
  Future<void> _pickTemplateAndRun(
      Future<void> Function(ReportCardTemplate) onPicked) async {
    List<ReportCardTemplate> templates;
    try {
      // Idempotent seed — no-op if presets already exist.
      final sid   = AuthService.currentSchoolId;
      final brand = await _schoolSvc.getBrandName(sid);
      await _templateSvc.seedDefaultTemplates(schoolId: sid, brandName: brand);
      templates = await _templateSvc.getTemplates();
    } catch (_) {
      templates = [];
    }

    if (!mounted) return;

    if (templates.isEmpty) {
      _showSnack(
        'No templates found. Create one via Manage Templates.',
        color: Colors.orange,
      );
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _TemplatePicker(
        templates: templates,
        onPick: (t) {
          Navigator.pop(ctx);
          onPicked(t);
        },
      ),
    );
  }

  // ── Individual PDF ─────────────────────────────────────────────────────────

  Future<void> _shareStudentReport(Student s, ExamResult r) async {
    await _pickTemplateAndRun((template) async {
      try {
        final bytes = await buildReportCardPdf(
          template: template,
          result:   r,
          student:  s,
          exam:     widget.exam,
          rank:     template.showRank ? _ranks[s.roll] : null,
        );
        await Printing.sharePdf(
          bytes: bytes,
          filename:
              'report_${s.name.replaceAll(' ', '_')}'
              '_${widget.exam.name.replaceAll(' ', '_')}.pdf',
        );
      } catch (e) {
        _showSnack('PDF error: $e', color: Colors.red);
      }
    });
  }

  // ── Class-wide PDF ─────────────────────────────────────────────────────────

  Future<void> _shareClassReport() async {
    await _pickTemplateAndRun((template) async {
      try {
        final bytes = await buildClassReportCardPdf(
          template:  template,
          results:   _results,
          students:  _students,
          exam:      widget.exam,
          ranks:     _ranks,
        );
        await Printing.sharePdf(
          bytes: bytes,
          filename:
              'report_${widget.exam.name.replaceAll(' ', '_')}'
              '_${widget.className}.pdf',
        );
      } catch (e) {
        _showSnack('PDF error: $e', color: Colors.red);
      }
    });
  }

  // ── Manage templates nav ───────────────────────────────────────────────────

  Future<void> _openTemplates() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => const ReportCardTemplateListScreen()),
    );
  }

  void _showSnack(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

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
                style: const TextStyle(
                    fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.description_outlined),
            tooltip: 'Manage Templates',
            onPressed: _openTemplates,
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share Class PDF',
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
                      _TopperBanner(
                        results:    _results,
                        ranks:      _ranks,
                        studentMap: {for (final s in _students) s.roll: s},
                      ),
                      const SizedBox(height: 12),
                      _StatsSummary(
                        students:     _students,
                        results:      _results,
                        maxMarks:     exam.maxMarks,
                        subjectCount: exam.subjects.length,
                      ),
                      const SizedBox(height: 12),
                      ...List.generate(_students.length, (i) {
                        final s      = _students[i];
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

// ─── Template picker bottom sheet ─────────────────────────────────────────────

class _TemplatePicker extends StatelessWidget {
  final List<ReportCardTemplate>          templates;
  final void Function(ReportCardTemplate) onPick;

  const _TemplatePicker({
    required this.templates,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.85,
      builder: (_, ctrl) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text('Choose Report Card Template',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: ListView.separated(
              controller: ctrl,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              itemCount: templates.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final t = templates[i];
                return InkWell(
                  onTap: () => onPick(t),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(t.board.label,
                            style: const TextStyle(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 11)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14)),
                            const SizedBox(height: 3),
                            Text(
                              [
                                t.pageSize,
                                t.orientation,
                                if (t.showRank) 'Rank',
                                if (t.showAttendance) 'Attendance',
                              ].join(' · '),
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),
                      if (t.isSystemPreset)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border:
                                Border.all(color: Colors.amber.shade200),
                          ),
                          child: Text('System',
                              style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.amber.shade800)),
                        ),
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right,
                          color: AppTheme.primary),
                    ]),
                  ),
                );
              },
            ),
          ),
        ],
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
    final top  = toppers.first;
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
                  style: TextStyle(color: Colors.white70, fontSize: 11)),
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
    final avgPct    = results.isEmpty
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
          _Cell('${students.length}', 'Students',  AppTheme.primary),
          _Cell('${results.length}',  'Results',   AppTheme.primaryMid),
          _Cell('$passCount',         'Passed',    Colors.green),
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
          style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
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
    final s     = student;
    final r     = result;
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
              backgroundColor: color.withValues(alpha: 0.12),
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
                        : Colors.grey.shade300,
                  ),
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
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
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

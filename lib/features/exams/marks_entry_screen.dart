import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../l10n/app_strings.dart';
import '../../models/exam.dart';
import '../../models/student.dart';
import '../../services/auth_service.dart';
import '../../services/exam_service.dart';
import '../../services/student_service.dart';
import '../../services/offline_queue_service.dart';
import '../../theme.dart';
import '../../shared/utils/app_logger.dart';

/// Teacher/Coordinator enters marks per student per subject for an exam.
class MarksEntryScreen extends StatefulWidget {
  final Exam   exam;
  final String section;

  const MarksEntryScreen({super.key, required this.exam, this.section = ''});

  @override
  State<MarksEntryScreen> createState() => _MarksEntryScreenState();
}

class _MarksEntryScreenState extends State<MarksEntryScreen> {
  final _examService    = ExamService();
  final _studentService = StudentService.instance;

  bool _loading = true;
  bool _saving  = false;

  List<Student>    _students = [];
  // roll → subject → marks controller
  Map<int, Map<String, TextEditingController>> _controllers = {};

  // Email of the staff member entering marks — stamped on each result so grade
  // changes are attributable (previously saved as an empty string).
  String _enteredBy = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final exam = widget.exam;
    final results = await Future.wait([
      _studentService.getStudentsByClass(className: exam.className, section: widget.section),
      _examService.getResults(examId: exam.id),
    ]);
    final students    = results[0] as List<Student>;
    final examResults = results[1] as List<ExamResult>;

    final session = await AuthService().getSession();
    _enteredBy = (session?['email'] as String?) ?? '';

    assert(students.length == {for (final s in students) s.roll: s}.length,
        'Duplicate rolls detected in class ${exam.className}');
    AppLogger.d('StudentList', '[${exam.className}] count=${students.length}');

    // Map results by roll
    final savedMap = <int, ExamResult>{};
    for (final r in examResults) {
      savedMap[r.roll] = r;
    }

    // Build controllers
    final ctrlMap = <int, Map<String, TextEditingController>>{};
    for (final s in students) {
      final subjectCtrls = <String, TextEditingController>{};
      for (final sub in exam.subjects) {
        final saved = savedMap[s.roll]?.marks[sub];
        subjectCtrls[sub] = TextEditingController(
          text: saved == -1.0 ? 'AB' : (saved != null ? saved.toStringAsFixed(0) : ''),
        );
      }
      ctrlMap[s.roll] = subjectCtrls;
    }

    if (!mounted) return;
    setState(() {
      _students      = students;
      _controllers   = ctrlMap;
      _loading       = false;
    });
  }

  Future<void> _saveAll() async {
    final exam = widget.exam;
    for (final s in _students) {
      final ctrls = _controllers[s.roll]!;
      for (final sub in exam.subjects) {
        final txt = ctrls[sub]!.text.trim().toUpperCase();
        if (txt.isNotEmpty && txt != 'AB' && txt != 'A') {
          final v = double.tryParse(txt);
          if (v == null || v < 0 || v > exam.maxMarks) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  '${s.name} ("$sub"): ${context.tr('marksMustBe')} 0–${exam.maxMarks}'),
              backgroundColor: Colors.red.shade700,
            ));
            return;
          }
        }
      }
    }
    setState(() => _saving = true);

    bool isOnline = true;
    try {
      final results = await Connectivity().checkConnectivity();
      isOnline = results.any((r) => r != ConnectivityResult.none);
    } catch (_) {}

    final futures = <Future>[];
    for (final s in _students) {
      final ctrls = _controllers[s.roll]!;
      final marks = <String, double?>{};
      for (final sub in exam.subjects) {
        final txt = ctrls[sub]!.text.trim().toUpperCase();
        if (txt == 'AB' || txt == 'A') {
          marks[sub] = -1.0;
        } else {
          marks[sub] = txt.isEmpty ? null : double.tryParse(txt);
        }
      }
      final result = ExamResult(
        roll:        s.roll,
        studentName: s.name,
        className:   s.className,
        examId:      exam.id,
        examName:    exam.name,
        marks:       marks,
        maxMarks:    exam.maxMarks,
        enteredBy:   _enteredBy,
      );
      if (isOnline) {
        futures.add(_examService.saveResult(examId: exam.id, result: result));
      } else {
        futures.add(OfflineQueueService().enqueueExamResult(examId: exam.id, result: result));
      }
    }
    await Future.wait(futures);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isOnline ? context.tr('marksSavedSuccess') : 'Saved offline! Marks will sync automatically when network returns.'),
        backgroundColor: isOnline ? Colors.green : Colors.orange,
      ),
    );
  }

  @override
  void dispose() {
    for (final subMap in _controllers.values) {
      for (final ctrl in subMap.values) {
        ctrl.dispose();
      }
    }
    super.dispose();
  }

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
            Text('${exam.className}  •  ${context.tr('maxLabel')} ${exam.maxMarks}${context.tr('perSubjectSuffix')}',
                style:
                    const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              ),
            )
          else
            TextButton.icon(
              onPressed: _saveAll,
              icon: const Icon(Icons.save_outlined,
                  color: Colors.white, size: 18),
              label: Text(context.tr('saveAll'),
                  style: const TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _students.isEmpty
              ? Center(
                  child: Text('${context.tr('noStudentsIn')} ${exam.className}.',
                      style: TextStyle(color: Colors.grey.shade500)),
                )
              : Column(
                  children: [
                    // Subject header row
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Row(children: [
                        const SizedBox(width: 110),
                        ...exam.subjects.map((sub) => Expanded(
                              child: Text(
                                sub,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primary),
                              ),
                            )),
                        const SizedBox(width: 50), // total column
                      ]),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.separated(
                        itemCount: _students.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final s = _students[i];
                          return _StudentMarksRow(
                            student:    s,
                            exam:       exam,
                            controllers: _controllers[s.roll] ?? {},
                          );
                        },
                      ),
                    ),
                    // Save button
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _saving ? null : _saveAll,
                            icon: const Icon(Icons.save_outlined),
                            label: Text(context.tr('saveAllMarks')),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

// ─── One row per student ──────────────────────────────────────────────────────

class _StudentMarksRow extends StatefulWidget {
  final Student  student;
  final Exam     exam;
  final Map<String, TextEditingController> controllers;

  const _StudentMarksRow({
    required this.student,
    required this.exam,
    required this.controllers,
  });

  @override
  State<_StudentMarksRow> createState() => _StudentMarksRowState();
}

class _StudentMarksRowState extends State<_StudentMarksRow> {
  double _total = 0;

  @override
  void initState() {
    super.initState();
    _recalc();
    for (final ctrl in widget.controllers.values) {
      ctrl.addListener(_recalc);
    }
  }

  void _recalc() {
    double t = 0;
    for (final ctrl in widget.controllers.values) {
      final txt = ctrl.text.trim().toUpperCase();
      if (txt != 'AB' && txt != 'A') {
        t += double.tryParse(txt) ?? 0;
      }
    }
    if (mounted) setState(() => _total = t);
  }

  bool _isInvalid(String sub) {
    final txt = widget.controllers[sub]?.text.trim().toUpperCase() ?? '';
    if (txt.isEmpty || txt == 'AB' || txt == 'A') return false;
    final v = double.tryParse(txt);
    return v == null || v < 0 || v > widget.exam.maxMarks;
  }

  @override
  void dispose() {
    for (final ctrl in widget.controllers.values) {
      ctrl.removeListener(_recalc);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s    = widget.student;
    final exam = widget.exam;
    final maxTotal = exam.maxMarks * exam.subjects.length;
    final pct  = maxTotal == 0 ? 0.0 : _total / maxTotal * 100;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Student name + roll
          SizedBox(
            width: 110,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.name.length > 12
                      ? '${s.name.substring(0, 12)}…'
                      : s.name,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Text('${context.tr('roll')} ${s.roll}',
                    style: TextStyle(
                        fontSize: 10, color: Colors.grey.shade500)),
              ],
            ),
          ),
          // Per-subject fields
          ...exam.subjects.map((sub) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: TextField(
                    controller: widget.controllers[sub],
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9.aAbB]')),
                    ],
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 8),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: _isInvalid(sub)
                              ? Colors.red
                              : Colors.grey.shade300,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: _isInvalid(sub)
                              ? Colors.red
                              : AppTheme.primary,
                        ),
                      ),
                      hintText: '—',
                      hintStyle:
                          TextStyle(color: Colors.grey.shade300),
                    ),
                  ),
                ),
              )),
          // Total + %
          SizedBox(
            width: 50,
            child: Column(
              children: [
                Text(
                  _total.toStringAsFixed(0),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: pct >= 33
                        ? Colors.green.shade700
                        : Colors.red,
                  ),
                ),
                Text(
                  '${pct.toStringAsFixed(0)}%',
                  style: TextStyle(
                      fontSize: 10, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

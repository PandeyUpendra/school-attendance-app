import 'package:flutter/material.dart';
import '../models/exam.dart';
import '../models/student.dart';
import '../services/exam_service.dart';
import '../services/student_service.dart';
import '../theme.dart';
import '../theme.dart';

/// Teacher/Coordinator enters marks per student per subject for an exam.
class MarksEntryScreen extends StatefulWidget {
  final Exam exam;

  const MarksEntryScreen({super.key, required this.exam});

  @override
  State<MarksEntryScreen> createState() => _MarksEntryScreenState();
}

class _MarksEntryScreenState extends State<MarksEntryScreen> {
  final _examService    = ExamService();
  final _studentService = StudentService();

  bool _loading = true;
  bool _saving  = false;

  List<Student>    _students = [];
  // roll → subject → marks controller
  Map<int, Map<String, TextEditingController>> _controllers = {};
  // Previously saved results
  Map<int, ExamResult> _savedResults = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final exam = widget.exam;
    final results = await Future.wait([
      _studentService.getStudentsByClass(exam.className),
      _examService.getResults(exam.id),
    ]);
    final students    = results[0] as List<Student>;
    final examResults = results[1] as List<ExamResult>;

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
          text: saved != null ? saved.toStringAsFixed(0) : '',
        );
      }
      ctrlMap[s.roll] = subjectCtrls;
    }

    if (!mounted) return;
    setState(() {
      _students      = students;
      _controllers   = ctrlMap;
      _savedResults  = savedMap;
      _loading       = false;
    });
  }

  Future<void> _saveAll() async {
    setState(() => _saving = true);
    final exam = widget.exam;

    final futures = <Future>[];
    for (final s in _students) {
      final ctrls = _controllers[s.roll]!;
      final marks = <String, double?>{};
      for (final sub in exam.subjects) {
        final txt = ctrls[sub]!.text.trim();
        marks[sub] = txt.isEmpty ? null : double.tryParse(txt);
      }
      final result = ExamResult(
        roll:        s.roll,
        studentName: s.name,
        className:   s.className,
        examId:      exam.id,
        examName:    exam.name,
        marks:       marks,
        maxMarks:    exam.maxMarks,
        enteredBy:   '',
      );
      futures.add(_examService.saveResult(exam.id, result));
    }
    await Future.wait(futures);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Marks saved successfully ✓'),
        backgroundColor: Colors.green,
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
            Text('${exam.className}  •  Max ${exam.maxMarks}/subject',
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
              label: const Text('Save All',
                  style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _students.isEmpty
              ? Center(
                  child: Text('No students in ${exam.className}.',
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
                            label: const Text('Save All Marks'),
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
      t += double.tryParse(ctrl.text.trim()) ?? 0;
    }
    if (mounted) setState(() => _total = t);
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
                Text('Roll ${s.roll}',
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
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 8),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      hintText: '—',
                      hintStyle: TextStyle(color: Colors.grey.shade300),
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

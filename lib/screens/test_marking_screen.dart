import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../models/student.dart';
import '../models/student_profile_data.dart';
import '../services/firestore_service.dart';

class TestMarkingScreen extends StatefulWidget {
  final String className;
  final String schoolId;
  final String testId;
  final String testName;
  final String subject;
  final int totalMarks;
  final List<Student> students;

  const TestMarkingScreen({
    super.key,
    required this.className,
    required this.schoolId,
    required this.testId,
    required this.testName,
    required this.subject,
    required this.totalMarks,
    required this.students,
  });

  @override
  State<TestMarkingScreen> createState() => _TestMarkingScreenState();
}

class _TestMarkingScreenState extends State<TestMarkingScreen> {
  late final List<TextEditingController> _ctrls;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(
        widget.students.length, (_) => TextEditingController());
  }

  @override
  void dispose() {
    for (final c in _ctrls) c.dispose();
    super.dispose();
  }

  int? _parsedMark(int index) => int.tryParse(_ctrls[index].text.trim());

  double get _classAverage {
    final valid = List.generate(widget.students.length, (i) => _parsedMark(i))
        .whereType<int>()
        .toList();
    if (valid.isEmpty) return 0;
    return valid.reduce((a, b) => a + b) / valid.length;
  }

  Future<void> _save() async {
    // Validate
    for (int i = 0; i < widget.students.length; i++) {
      final raw = _ctrls[i].text.trim();
      if (raw.isEmpty) continue; // allow empty (absent)
      final v = int.tryParse(raw);
      if (v == null || v < 0 || v > widget.totalMarks) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${widget.students[i].name}: marks must be 0–${widget.totalMarks}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    setState(() => _saving = true);

    // Build marks map
    final marks = <int, int>{};
    for (int i = 0; i < widget.students.length; i++) {
      final v = int.tryParse(_ctrls[i].text.trim());
      if (v != null) marks[widget.students[i].roll] = v;
    }

    try {
      // Save marks to the test document
      await FirestoreService.saveTestMarks(
        schoolId: widget.schoolId,
        classId: widget.className,
        testId: widget.testId,
        marks: marks,
      );

      // Mirror to each student's profile
      if (widget.schoolId.isNotEmpty) {
        final futures = marks.entries.map((e) {
          final student =
              widget.students.firstWhere((s) => s.roll == e.key);
          final testResult = TestResult(
            name: widget.testName,
            subject: widget.subject,
            marksObtained: e.value,
            totalMarks: widget.totalMarks,
            date: DateTime.now(),
          );
          return FirestoreService.appendToStudentProfile(
            schoolId: widget.schoolId,
            classId: widget.className,
            roll: student.roll,
            arrayField: 'tests',
            item: testResult.toMap(),
          );
        });
        await Future.wait(futures);
      }

      if (!mounted) return;
      // Show result dialog
      final avg = _classAverage;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Marks Saved!'),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ResultRow('Test', widget.testName),
              _ResultRow('Subject', widget.subject),
              _ResultRow('Total Marks', '${widget.totalMarks}'),
              _ResultRow('Marked', '${marks.length}/${widget.students.length} students'),
              const Divider(),
              _ResultRow('Class Average',
                  '${avg.toStringAsFixed(1)} / ${widget.totalMarks}',
                  highlight: true),
              _ResultRow('Average %',
                  '${(avg / widget.totalMarks * 100).toStringAsFixed(1)}%',
                  highlight: true),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // close dialog
                Navigator.pop(context); // go back to class management
              },
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      setState(() => _saving = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving marks: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.testName),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Container(
            color: const AppTheme.primary,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(children: [
              _Chip(widget.subject, Icons.menu_book_outlined),
              const SizedBox(width: 10),
              _Chip('Max: ${widget.totalMarks}', Icons.numbers_rounded),
              const Spacer(),
              _Chip(
                  '${widget.students.length} students', Icons.people_outline),
            ]),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
              itemCount: widget.students.length,
              itemBuilder: (ctx, i) {
                final student = widget.students[i];
                return _MarkRow(
                  student: student,
                  controller: _ctrls[i],
                  totalMarks: widget.totalMarks,
                  onChanged: (_) => setState(() {}),
                );
              },
            ),
          ),

          // Bottom save bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: const [
                BoxShadow(
                    color: Colors.black12,
                    blurRadius: 8,
                    offset: Offset(0, -2))
              ],
            ),
            child: Row(children: [
              // Live class average
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Class Avg: ${_classAverage.toStringAsFixed(1)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    Text(
                      '${(_classAverage / widget.totalMarks * 100).toStringAsFixed(1)}%',
                      style: TextStyle(
                          color: Colors.grey.shade500, fontSize: 12),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.save_rounded),
                label: Text(_saving ? 'Saving…' : 'Save Marks'),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

// ── Mark entry row ────────────────────────────────────────────────────────────

class _MarkRow extends StatefulWidget {
  final Student student;
  final TextEditingController controller;
  final int totalMarks;
  final ValueChanged<String> onChanged;

  const _MarkRow({
    required this.student,
    required this.controller,
    required this.totalMarks,
    required this.onChanged,
  });

  @override
  State<_MarkRow> createState() => _MarkRowState();
}

class _MarkRowState extends State<_MarkRow> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(() => setState(() {}));
  }

  double? get _pct {
    final v = int.tryParse(widget.controller.text.trim());
    if (v == null) return null;
    return v / widget.totalMarks;
  }

  Color _pctColor(double p) {
    if (p >= 0.75) return Colors.green.shade600;
    if (p >= 0.5) return Colors.orange.shade700;
    return Colors.red.shade600;
  }

  @override
  Widget build(BuildContext context) {
    final pct = _pct;
    final color =
        pct != null ? _pctColor(pct) : Colors.grey.shade400;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color ?? Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))
        ],
      ),
      child: Row(children: [
        // Roll avatar
        CircleAvatar(
          radius: 18,
          backgroundColor: color.withOpacity(0.12),
          child: Text(
            '${widget.student.roll}',
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
        const SizedBox(width: 12),

        // Name
        Expanded(
          child: Text(widget.student.name,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 14)),
        ),

        // Percentage
        if (pct != null) ...[
          Text(
            '${(pct * 100).toStringAsFixed(0)}%',
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(width: 8),
        ],

        // Marks input
        SizedBox(
          width: 72,
          child: TextField(
            controller: widget.controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            onChanged: widget.onChanged,
            decoration: InputDecoration(
              hintText: '—',
              hintStyle: TextStyle(color: Colors.grey.shade400),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 10),
              suffixText: '/${widget.totalMarks}',
              suffixStyle: TextStyle(
                  fontSize: 10, color: Colors.grey.shade500),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Small widgets ─────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final IconData icon;
  const _Chip(this.label, this.icon);

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: Colors.white70, size: 13),
      const SizedBox(width: 4),
      Text(label,
          style: const TextStyle(color: Colors.white70, fontSize: 12)),
    ]);
  }
}

class _ResultRow extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const _ResultRow(this.label, this.value, {this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Text(label,
            style: TextStyle(
                color: Colors.grey.shade600, fontSize: 13)),
        const Spacer(),
        Text(value,
            style: TextStyle(
                fontWeight: highlight
                    ? FontWeight.bold
                    : FontWeight.w500,
                fontSize: highlight ? 15 : 13,
                color: highlight
                    ? const AppTheme.primary
                    : null)),
      ]),
    );
  }
}

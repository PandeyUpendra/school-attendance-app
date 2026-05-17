import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../theme.dart';
import 'package:flutter/services.dart';
import '../models/student.dart';
import '../services/firestore_service.dart';
import 'test_marking_screen.dart';

class TestCreationScreen extends StatefulWidget {
  final String className;
  final String schoolId;
  final List<Student> students;

  const TestCreationScreen({
    super.key,
    required this.className,
    required this.schoolId,
    required this.students,
  });

  @override
  State<TestCreationScreen> createState() => _TestCreationScreenState();
}

class _TestCreationScreenState extends State<TestCreationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _marksCtrl = TextEditingController(text: '100');

  String _subject = 'Math';
  DateTime _date = DateTime.now();
  TimeOfDay _time = const TimeOfDay(hour: 10, minute: 0);
  bool _saving = false;

  static const _subjects = [
    'Math', 'English', 'Science', 'Hindi',
    'Social Studies', 'Computer', 'Other',
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _marksCtrl.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime d) {
    const m = ['', 'Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${m[d.month]} ${d.year}';
  }

  String _fmtTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final min = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$min $period';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final data = {
      'name': _nameCtrl.text.trim(),
      'subject': _subject,
      'totalMarks': int.parse(_marksCtrl.text.trim()),
      'date': Timestamp.fromDate(_date),
      'time': _fmtTime(_time),
      'createdAt': FieldValue.serverTimestamp(),
      'marks': <String, int>{},
    };

    try {
      final testId = await FirestoreService.createTest(
        schoolId: widget.schoolId,
        classId: widget.className,
        data: data,
      );

      if (!mounted) return;
      // Replace this screen with TestMarkingScreen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => TestMarkingScreen(
            className: widget.className,
            schoolId: widget.schoolId,
            testId: testId,
            testName: _nameCtrl.text.trim(),
            subject: _subject,
            totalMarks: int.parse(_marksCtrl.text.trim()),
            students: widget.students,
          ),
        ),
      );
    } catch (e) {
      setState(() => _saving = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create test: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Test'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const AppTheme.primary.withOpacity(0.07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const AppTheme.primary.withOpacity(0.2)),
              ),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const AppTheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.quiz_outlined,
                      color: AppTheme.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('New Test',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(widget.className,
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ]),
            ),
            const SizedBox(height: 24),

            _label('Test Name'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'e.g. Unit Test 1, Mid Term…',
                prefixIcon: Icon(Icons.edit_note_rounded),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Test name is required' : null,
            ),
            const SizedBox(height: 20),

            _label('Subject'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _subject,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.menu_book_outlined),
              ),
              items: _subjects
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) => setState(() => _subject = v!),
            ),
            const SizedBox(height: 20),

            _label('Total Marks'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _marksCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                hintText: '100',
                prefixIcon: Icon(Icons.numbers_rounded),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                final n = int.tryParse(v);
                if (n == null || n <= 0) return 'Enter a valid number';
                return null;
              },
            ),
            const SizedBox(height: 20),

            _label('Date'),
            const SizedBox(height: 8),
            _PickerTile(
              icon: Icons.calendar_today_outlined,
              value: _fmtDate(_date),
              label: 'Test Date',
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2024),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setState(() => _date = picked);
              },
            ),
            const SizedBox(height: 12),

            _label('Time'),
            const SizedBox(height: 8),
            _PickerTile(
              icon: Icons.access_time_rounded,
              value: _fmtTime(_time),
              label: 'Test Time',
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: _time,
                );
                if (picked != null) setState(() => _time = picked);
              },
            ),
            const SizedBox(height: 36),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.arrow_forward_rounded),
                label: Text(_saving
                    ? 'Creating…'
                    : 'Create & Enter Marks'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Text(text,
        style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.black54,
            letterSpacing: 0.3));
  }
}

// ── Picker tile ───────────────────────────────────────────────────────────────

class _PickerTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final VoidCallback onTap;

  const _PickerTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).inputDecorationTheme.fillColor ??
          Colors.grey.shade100,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Icon(icon, color: Colors.grey.shade500, size: 20),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: Colors.grey.shade500, fontSize: 11)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
              ],
            ),
            const Spacer(),
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ]),
        ),
      ),
    );
  }
}

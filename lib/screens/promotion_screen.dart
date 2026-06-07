import 'package:flutter/material.dart';
import '../theme.dart';
import '../models/student.dart';
import '../services/student_service.dart';
import '../services/timetable_service.dart';
import '../services/promotion_service.dart';

/// Academic-year promotion / rollover (#70).
///
/// Lets a coordinator/principal promote a source class roster into the next
/// class. Source students keep their attendance/fee history (the old record is
/// archived, not deleted) and carry a stable admission id into the new class.
class PromotionScreen extends StatefulWidget {
  const PromotionScreen({super.key});

  @override
  State<PromotionScreen> createState() => _PromotionScreenState();
}

class _PromotionScreenState extends State<PromotionScreen> {
  final _studentSvc = StudentService();

  List<String> _classes = [];
  bool _loadingClasses = true;

  String? _fromClass;
  String? _toClass;
  final _fromSection = TextEditingController();
  final _toSection = TextEditingController();

  List<Student> _loaded = [];
  bool _loadingStudents = false;
  bool _promoting = false;

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  @override
  void dispose() {
    _fromSection.dispose();
    _toSection.dispose();
    super.dispose();
  }

  Future<void> _loadClasses() async {
    try {
      final settings = await TimetableService().getSettings();
      final classes =
          (settings['classes'] as List?)?.map((e) => e.toString()).toList() ??
              [];
      if (!mounted) return;
      setState(() {
        _classes = classes;
        _loadingClasses = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingClasses = false);
    }
  }

  Future<void> _loadStudents() async {
    final from = _fromClass;
    if (from == null) return;
    setState(() {
      _loadingStudents = true;
      _loaded = [];
    });
    final list = await _studentSvc.getStudentsByClass(
      className: from,
      section: _fromSection.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _loaded = list;
      _loadingStudents = false;
    });
  }

  Future<void> _promote() async {
    final to = _toClass;
    if (to == null || _loaded.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm promotion'),
        content: Text(
          'Promote ${_loaded.length} student(s) from '
          '$_fromClass${_fromSection.text.trim().isEmpty ? '' : ' ${_fromSection.text.trim()}'} '
          'to $to${_toSection.text.trim().isEmpty ? '' : ' ${_toSection.text.trim()}'}?\n\n'
          'Their current records are archived (history is kept) and new records '
          'are created in the target class with fees reset to Pending.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(_, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(_, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white),
            child: const Text('Promote'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _promoting = true);
    PromotionResult result;
    try {
      result = await PromotionService().promoteStudents(
        students: _loaded,
        targetClass: to,
        targetSection: _toSection.text.trim(),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _promoting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Promotion failed: $e')));
      return;
    }
    if (!mounted) return;
    setState(() {
      _promoting = false;
      _loaded = [];
    });
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Promotion complete'),
        content: SingleChildScrollView(
          child: Text(
            'Promoted: ${result.promoted}\n'
            'Skipped: ${result.skipped.length}'
            '${result.skipped.isEmpty ? '' : '\n\n${result.skipped.join('\n')}'}',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(_), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryDark,
        foregroundColor: Colors.white,
        title: const Text('Promote Class'),
      ),
      body: _loadingClasses
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _card(
                  'From (current class)',
                  _fromClass,
                  (v) => setState(() {
                    _fromClass = v;
                    _loaded = [];
                  }),
                  _fromSection,
                ),
                const SizedBox(height: 12),
                Center(
                  child: OutlinedButton.icon(
                    onPressed: _fromClass == null || _loadingStudents
                        ? null
                        : _loadStudents,
                    icon: const Icon(Icons.search),
                    label: Text(_loadingStudents
                        ? 'Loading…'
                        : 'Load students'),
                  ),
                ),
                if (_loaded.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('${_loaded.length} student(s) found',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
                const SizedBox(height: 16),
                _card(
                  'To (next class)',
                  _toClass,
                  (v) => setState(() => _toClass = v),
                  _toSection,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: (_loaded.isEmpty ||
                          _toClass == null ||
                          _toClass == _fromClass &&
                              _toSection.text.trim() ==
                                  _fromSection.text.trim() ||
                          _promoting)
                      ? null
                      : _promote,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: _promoting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.upgrade),
                  label: Text(_promoting ? 'Promoting…' : 'Promote students'),
                ),
                const SizedBox(height: 12),
                Text(
                  'Old records are archived (attendance & fee history kept). '
                  'New records start with fees Pending. Rolls are carried over; '
                  'a roll already taken in the target class is skipped.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
    );
  }

  Widget _card(String label, String? value, ValueChanged<String?> onChanged,
      TextEditingController sectionCtrl) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: AppTheme.primary)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: value,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Class',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: _classes
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: onChanged,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: sectionCtrl,
              decoration: const InputDecoration(
                labelText: 'Section (optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/exam.dart';
import '../services/exam_service.dart';
import '../services/timetable_service.dart';
import '../theme.dart';
import 'marks_entry_screen.dart';
import 'report_card_screen.dart';

/// Coordinator screen: create & manage exams per class,
/// and navigate to marks entry / report cards.
class ExamManagementScreen extends StatefulWidget {
  final String role;    // 'coordinator' | 'teacher' | 'principal'
  final String section; // teacher's section — passed down to MarksEntryScreen
  /// When non-empty, only these classes are shown. Empty means show all.
  final List<String> allowedClasses;

  const ExamManagementScreen({
    super.key,
    required this.role,
    this.section = '',
    this.allowedClasses = const [],
  });

  @override
  State<ExamManagementScreen> createState() => _ExamManagementScreenState();
}

class _ExamManagementScreenState extends State<ExamManagementScreen> {
  final _examService = ExamService();

  bool _loading = true;
  List<String> _classes = [];
  String? _selectedClass;
  List<Exam> _exams = [];

  bool get _canManage => widget.role == 'coordinator';

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    final settings = await TimetableService().getSettings();
    final all = List<String>.from(settings['classes'] as List? ?? []);
    final classes = widget.allowedClasses.isEmpty
        ? all
        : all.where((c) => widget.allowedClasses.contains(c)).toList();
    if (!mounted) return;
    setState(() { _classes = classes; });
    if (classes.isNotEmpty) await _selectClass(classes.first);
    setState(() => _loading = false);
  }

  Future<void> _selectClass(String cls) async {
    setState(() { _selectedClass = cls; _loading = true; });
    final exams = await _examService.getExams(className: cls);
    if (!mounted) return;
    setState(() { _exams = exams; _loading = false; });
  }

  Future<void> _createOrEditExam({Exam? editing}) async {
    if (_selectedClass == null) return;

    final formKey      = GlobalKey<FormState>();
    final nameCtrl     = TextEditingController(text: editing?.name ?? '');
    final maxMarksCtrl = TextEditingController(
        text: editing?.maxMarks.toString() ?? '100');

    // Subject list
    final subjectCtrls = editing != null
        ? editing.subjects.map((s) => TextEditingController(text: s)).toList()
        : [TextEditingController()];

    DateTime examDate = editing?.examDate ?? DateTime.now();
    bool saving = false;

    // Multi-class selection (only for new exams; editing locks to existing class)
    final Set<String> selectedClasses =
        editing != null ? {editing.className} : {_selectedClass!};

    Future<void> pickDate(StateSetter setS) async {
      final picked = await showDatePicker(
        context: context,
        initialDate: examDate,
        firstDate: DateTime(2020),
        lastDate: DateTime(2030),
      );
      if (picked != null) setS(() => examDate = picked);
    }

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(
            left: 18, right: 18, top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 18,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(editing == null ? 'New Exam' : 'Edit Exam',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),
                TextFormField(
                  controller: nameCtrl,
                  maxLength: 60,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  decoration: InputDecoration(
                    labelText: 'Exam Name (e.g. Unit Test 1)',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    counterText: '',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Exam name is required' : null,
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: maxMarksCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: 'Max Marks per Subject',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        final n = int.tryParse(v.trim());
                        if (n == null || n < 1 || n > 200) return '1–200';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      onTap: () => pickDate(setS),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Exam Date',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(
                          '${examDate.day}/${examDate.month}/${examDate.year}',
                        ),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                // Class selection (multi for new, locked for edit)
                if (editing == null) ...[
                  const Text('Classes',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  StatefulBuilder(
                    builder: (_, setChips) => Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: _classes.map((cls) {
                        final sel = selectedClasses.contains(cls);
                        return FilterChip(
                          label: Text(cls),
                          selected: sel,
                          selectedColor: AppTheme.primary.withOpacity(0.15),
                          checkmarkColor: AppTheme.primary,
                          labelStyle: TextStyle(
                            color: sel ? AppTheme.primary : null,
                            fontWeight: sel
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                          onSelected: (v) {
                            setChips(() {
                              if (v) {
                                selectedClasses.add(cls);
                              } else if (selectedClasses.length > 1) {
                                selectedClasses.remove(cls);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Subjects',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    TextButton.icon(
                      onPressed: () =>
                          setS(() => subjectCtrls.add(TextEditingController())),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add'),
                      style: TextButton.styleFrom(
                          foregroundColor: AppTheme.primary),
                    ),
                  ],
                ),
                for (int i = 0; i < subjectCtrls.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Expanded(
                        child: TextFormField(
                          controller: subjectCtrls[i],
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[a-zA-Z ]')),
                          ],
                          maxLength: 30,
                          maxLengthEnforcement: MaxLengthEnforcement.enforced,
                          decoration: InputDecoration(
                            labelText: 'Subject ${i + 1}',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 10),
                            counterText: '',
                          ),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? 'Required' : null,
                        ),
                      ),
                      if (subjectCtrls.length > 1)
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline,
                              color: Colors.red, size: 20),
                          onPressed: () =>
                              setS(() => subjectCtrls.removeAt(i)),
                          padding: EdgeInsets.zero,
                        ),
                    ]),
                  ),
                const SizedBox(height: 12),
                Row(children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: saving
                        ? null
                        : () async {
                            if (!formKey.currentState!.validate()) return;
                            final name = nameCtrl.text.trim();
                            final subjects = subjectCtrls
                                .map((c) => c.text.trim())
                                .where((s) => s.isNotEmpty)
                                .toList();
                            setS(() => saving = true);
                            final maxMarksVal = int.tryParse(
                                    maxMarksCtrl.text.trim()) ??
                                100;
                            if (editing == null) {
                              await Future.wait(
                                selectedClasses.map((cls) =>
                                  _examService.createExam(exam: Exam(
                                    id:        '',
                                    name:      name,
                                    className: cls,
                                    subjects:  subjects,
                                    maxMarks:  maxMarksVal,
                                    examDate:  examDate,
                                    createdBy: '',
                                  )),
                                ),
                              );
                            } else {
                              await _examService.updateExam(exam: Exam(
                                id:        editing.id,
                                name:      name,
                                className: editing.className,
                                subjects:  subjects,
                                maxMarks:  maxMarksVal,
                                examDate:  examDate,
                                createdBy: '',
                              ));
                            }
                            if (ctx.mounted) Navigator.pop(ctx, true);
                          },
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: Text(editing == null ? 'Create' : 'Save'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ]),
              ],
            ),
            ),
          ),
        ),
      ),
    );

    if (saved == true && _selectedClass != null) {
      _selectClass(_selectedClass!);
    }
  }

  Future<void> _deleteExam(Exam exam) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
        title: const Text('Delete Exam?'),
        content: Text('Delete "${exam.name}"? All marks will be lost.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _examService.deleteExam(examId: exam.id);
    if (_selectedClass != null) _selectClass(_selectedClass!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Exams & Marks',
                style:
                    TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text('Manage exams and results',
                style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
      ),
      floatingActionButton: _canManage && _selectedClass != null
          ? FloatingActionButton.extended(
              onPressed: () => _createOrEditExam(),
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('New Exam'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _classes.isEmpty
              ? Center(
                  child: Text('No classes configured.',
                      style: TextStyle(color: Colors.grey.shade500)))
              : Column(
                  children: [
                    // Class chips
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _classes.map((cls) {
                            final selected = cls == _selectedClass;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(cls),
                                selected: selected,
                                selectedColor: AppTheme.primary,
                                labelStyle: TextStyle(
                                  color: selected ? Colors.white : null,
                                  fontWeight: selected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                                onSelected: (_) => _selectClass(cls),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const Divider(height: 1),

                    Expanded(
                      child: _exams.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.quiz_outlined,
                                      size: 56,
                                      color: Colors.grey.shade300),
                                  const SizedBox(height: 12),
                                  Text(
                                    _canManage
                                        ? 'No exams yet.\nTap + to create one.'
                                        : 'No exams created yet.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: Colors.grey.shade500),
                                  ),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: () =>
                                  _selectClass(_selectedClass!),
                              color: AppTheme.primary,
                              child: ListView.separated(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.all(12),
                                itemCount: _exams.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (_, i) => _ExamCard(
                                  exam:       _exams[i],
                                  canManage:  _canManage,
                                  onEdit:     () =>
                                      _createOrEditExam(editing: _exams[i]),
                                  onDelete:   () => _deleteExam(_exams[i]),
                                  onMarks: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => MarksEntryScreen(
                                            exam:    _exams[i],
                                            section: widget.section),
                                      ),
                                    );
                                  },
                                  onReport: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ReportCardScreen(
                                          exam:      _exams[i],
                                          className: _selectedClass!,
                                          section:   widget.section,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }
}

// ─── Exam card ────────────────────────────────────────────────────────────────

class _ExamCard extends StatelessWidget {
  final Exam         exam;
  final bool         canManage;
  final VoidCallback onEdit, onDelete, onMarks, onReport;

  const _ExamCard({
    required this.exam,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
    required this.onMarks,
    required this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    final e = exam;
    final date =
        '${e.examDate.day}/${e.examDate.month}/${e.examDate.year}';
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
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.quiz_outlined,
                  color: AppTheme.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.name,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold)),
                  Text(
                    '${e.className}  •  $date  •  Max ${e.maxMarks}/sub',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            if (canManage) ...[
              IconButton(
                icon: const Icon(Icons.edit_outlined,
                    size: 18, color: Colors.grey),
                onPressed: onEdit,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 30, minHeight: 30),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: Colors.redAccent),
                onPressed: onDelete,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 30, minHeight: 30),
              ),
            ],
          ]),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: e.subjects
                .map((s) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(s,
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.primary)),
                    ))
                .toList(),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onMarks,
                icon: const Icon(Icons.edit_note_outlined, size: 16),
                label: const Text('Enter Marks'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side:
                      const BorderSide(color: AppTheme.primary),
                  padding:
                      const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: onReport,
                icon: const Icon(Icons.assessment_outlined, size: 16),
                label: const Text('Report Card'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

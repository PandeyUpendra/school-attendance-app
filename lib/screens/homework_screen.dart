import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_strings.dart';
import '../models/homework.dart';
import '../models/teacher.dart';
import '../services/homework_service.dart';
import '../services/copy_check_service.dart'; // for getClassesForTeacher
import '../services/base_firestore_service.dart';
import '../theme.dart';
import '../widgets/refreshable_data.dart';

class HomeworkScreen extends StatefulWidget {
  final Teacher teacher;
  const HomeworkScreen({super.key, required this.teacher});

  @override
  State<HomeworkScreen> createState() => _HomeworkScreenState();
}

class _HomeworkScreenState extends State<HomeworkScreen> {
  final _service = HomeworkService();

  bool    _loading = true;
  List<Homework> _list = [];

  // classes this teacher teaches: {className → subject}
  Map<String, String> _classSubjectMap = {};
  String?             _selectedClass;

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    final assignments =
        await CopyCheckService().getTeacherAssignments(widget.teacher.id);
    if (!mounted) return;
    final map = <String, String>{};
    for (final a in assignments) {
      final key = a.section.isEmpty ? a.className : '${a.className} ${a.section}';
      map[key] = a.subject;
    }
    setState(() {
      _classSubjectMap = map;
      _selectedClass   = map.keys.isNotEmpty ? map.keys.first : null;
    });
    await _loadHomework();
  }

  Future<void> _loadHomework() async {
    setState(() => _loading = true);
    final list = await _service.getHomeworkForTeacher(BaseFirestoreService.currentSchoolId ?? 'default_school', widget.teacher.id);
    if (!mounted) return;
    setState(() {
      _list    = list;
      _loading = false;
    });
  }

  List<Homework> get _filteredList {
    if (_selectedClass == null) return _list;
    return _list.where((h) => h.className == _selectedClass).toList();
  }

  Future<void> _showPostDialog() async {
    if (_classSubjectMap.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('noClassesInTimetable'))),
      );
      return;
    }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.background,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _PostHomeworkSheet(
        teacher:        widget.teacher,
        classSubjectMap: _classSubjectMap,
        onPosted: _loadHomework,
      ),
    );
  }

  Future<void> _markReviewed(Homework hw) async {
    await _service.markReviewed(BaseFirestoreService.currentSchoolId ?? 'default_school', hw.id);
    _loadHomework();
  }

  Future<void> _delete(Homework hw) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.tr('deleteHomeworkQ')),
        content: Text('${context.tr('delete')} "${hw.title}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr('cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child:
                  Text(context.tr('delete'), style: const TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      await _service.deleteHomework(BaseFirestoreService.currentSchoolId ?? 'default_school', hw.id);
      _loadHomework();
    }
  }

  @override
  Widget build(BuildContext context) {
    final classes = _classSubjectMap.keys.toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('homework'),
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold)),
            Text(context.tr('postManageAssignments'),
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadHomework,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(context.tr('postHomework')),
        onPressed: _showPostDialog,
      ),
      body: Column(
        children: [
          // Class filter chips
          if (classes.isNotEmpty)
            Container(
              color: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // "All" chip
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(context.tr('allCount')),
                        selected: _selectedClass == null,
                        selectedColor: Colors.red,
                        labelStyle: TextStyle(
                          color: _selectedClass == null
                              ? Colors.white
                              : null,
                          fontWeight: _selectedClass == null
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                        onSelected: (_) =>
                            setState(() => _selectedClass = null),
                      ),
                    ),
                    ...classes.map((cls) {
                      final sel = cls == _selectedClass;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(cls),
                          selected: sel,
                          selectedColor: Colors.red,
                          labelStyle: TextStyle(
                            color: sel ? Colors.white : null,
                            fontWeight:
                                sel ? FontWeight.bold : FontWeight.normal,
                          ),
                          onSelected: (_) =>
                              setState(() => _selectedClass = cls),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const LoadingState()
                : _filteredList.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.assignment_outlined,
                                size: 56, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            Text(
                              context.tr('noHomeworkPosted'),
                              textAlign: TextAlign.center,
                              style:
                                  TextStyle(color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadHomework,
                        color: Colors.red,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _filteredList.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) =>
                              _HomeworkCard(
                            hw: _filteredList[i],
                            onMarkReviewed: () =>
                                _markReviewed(_filteredList[i]),
                            onDelete: () => _delete(_filteredList[i]),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// ─── Homework card ────────────────────────────────────────────────────────────

class _HomeworkCard extends StatelessWidget {
  final Homework hw;
  final VoidCallback onMarkReviewed;
  final VoidCallback onDelete;

  const _HomeworkCard({
    required this.hw,
    required this.onMarkReviewed,
    required this.onDelete,
  });

  Color get _statusColor {
    if (hw.isReviewed) return Colors.green;
    if (hw.isOverdue)  return Colors.red;
    return Colors.orange;
  }

  String _statusLabel(BuildContext context) {
    if (hw.isReviewed) return context.tr('hwReviewed');
    if (hw.isOverdue)  return context.tr('hwOverdue');
    final d = hw.daysUntilDue;
    if (d == 0) return context.tr('dueToday');
    if (d == 1) return context.tr('dueTomorrow');
    return '${context.tr('dueInPrefix')} $d ${context.tr('daysSuffix')}';
  }

  @override
  Widget build(BuildContext context) {
    final due =
        '${hw.dueDate.day}/${hw.dueDate.month}/${hw.dueDate.year}';
    final posted =
        '${hw.postedAt.day}/${hw.postedAt.month}/${hw.postedAt.year}';

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
          Row(
            children: [
              Expanded(
                child: Text(hw.title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(_statusLabel(context),
                    style: TextStyle(
                        fontSize: 11,
                        color: _statusColor,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _Chip(Icons.class_outlined, hw.className),
              const SizedBox(width: 6),
              _Chip(Icons.book_outlined, hw.subject),
            ],
          ),
          const SizedBox(height: 8),
          Text(hw.description,
              style: TextStyle(
                  fontSize: 13, color: Colors.grey.shade700),
              maxLines: 3,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.event_outlined,
                  size: 13, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text('${context.tr('dueColon')} $due',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade500)),
              const Spacer(),
              Text('${context.tr('postedColon')} $posted',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade400)),
            ],
          ),
          const Divider(height: 16),
          Row(
            children: [
              if (!hw.isReviewed)
                TextButton.icon(
                  icon: const Icon(Icons.check_circle_outline,
                      size: 16),
                  label: Text(context.tr('markReviewed')),
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.green,
                      padding: EdgeInsets.zero),
                  onPressed: onMarkReviewed,
                ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: Colors.red, size: 20),
                onPressed: onDelete,
                tooltip: context.tr('delete'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String   label;
  const _Chip(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.grey.shade500),
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      ],
    );
  }
}

// ─── Common homework titles + default description templates ───────────────────

/// Most-common homework titles, each mapped to a starter description the
/// teacher can edit before posting. `{class}` / `{subject}` are filled in with
/// the selected class & subject when a title is picked.
const Map<String, String> _kHomeworkTemplates = {
  'Complete exercises':
      'Complete the exercises from today\'s {subject} lesson. Show all working '
          'in your notebook and bring it for checking tomorrow.',
  'Read chapter':
      'Read the assigned chapter from your {subject} textbook. Underline key '
          'points and be ready to answer questions in the next class.',
  'Practice sums':
      'Practise the sums covered in class today. Attempt all problems and revise '
          'the formulas before the next {subject} period.',
  'Learn & memorise':
      'Learn and memorise the topic taught today. You will be asked to recite / '
          'write it from memory in the next class.',
  'Write an essay / paragraph':
      'Write a well-structured essay/paragraph on the given topic. Pay attention '
          'to handwriting, spelling and neatness.',
  'Worksheet':
      'Complete the {subject} worksheet handed out in class. Answer every '
          'question and submit it tomorrow.',
  'Project / activity work':
      'Work on the assigned {subject} project/activity. Bring the required '
          'materials and your progress to the next class.',
  'Revise for test':
      'Revise the topics covered so far in {subject} for the upcoming class '
          'test. Clear any doubts before the test day.',
  'Other (custom)': '',
};

// ─── Post homework bottom sheet ───────────────────────────────────────────────

class _PostHomeworkSheet extends StatefulWidget {
  final Teacher               teacher;
  final Map<String, String>   classSubjectMap;
  final VoidCallback          onPosted;

  const _PostHomeworkSheet({
    required this.teacher,
    required this.classSubjectMap,
    required this.onPosted,
  });

  @override
  State<_PostHomeworkSheet> createState() => _PostHomeworkSheetState();
}

class _PostHomeworkSheetState extends State<_PostHomeworkSheet> {
  final _service   = HomeworkService();
  final _formKey   = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController(); // custom title ("Other")
  final _descCtrl  = TextEditingController();

  late String _selectedClass;
  late String _selectedSubject;
  String?     _selectedTitle;   // chosen from the common-title dropdown
  DateTime    _dueDate = DateTime.now().add(const Duration(days: 1));
  bool        _saving  = false;

  bool get _isOtherTitle => _selectedTitle == 'Other (custom)';

  @override
  void initState() {
    super.initState();
    _selectedClass   = widget.classSubjectMap.keys.first;
    _selectedSubject = widget.classSubjectMap[_selectedClass]!;
  }

  /// Fill in {subject} / {class} placeholders in a template.
  String _fillTemplate(String tpl) => tpl
      .replaceAll('{subject}', _selectedSubject)
      .replaceAll('{class}', _selectedClass);

  /// When a common title is picked, pre-fill the description with its template
  /// unless the teacher has already typed their own custom text.
  void _onTitleSelected(String? title) {
    if (title == null) return;
    final tpl = _kHomeworkTemplates[title] ?? '';
    final filled = _fillTemplate(tpl);

    // Only overwrite if the current text is empty or still matches a previous
    // template (i.e. the teacher hasn't customised it) — never clobber edits.
    final current = _descCtrl.text.trim();
    final isUntouchedTemplate = current.isEmpty ||
        _kHomeworkTemplates.values
            .any((t) => t.isNotEmpty && _fillTemplate(t).trim() == current);

    setState(() {
      _selectedTitle = title;
      if (isUntouchedTemplate) {
        _descCtrl.text = filled;
        _descCtrl.selection =
            TextSelection.collapsed(offset: _descCtrl.text.length);
      }
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _dueDate = d);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final title = _isOtherTitle
        ? _titleCtrl.text.trim()
        : (_selectedTitle ?? '');
    final desc  = _descCtrl.text.trim();
    setState(() => _saving = true);
    final hw = Homework(
      id:          '',
      teacherId:   widget.teacher.id,
      teacherName: widget.teacher.name,
      className:   _selectedClass,
      subject:     _selectedSubject,
      title:       title,
      description: desc,
      dueDate:     _dueDate,
      postedAt:    DateTime.now(),
    );
    await _service.postHomework(BaseFirestoreService.currentSchoolId ?? 'default_school', hw);
    if (!mounted) return;
    Navigator.pop(context);
    widget.onPosted();
  }

  @override
  Widget build(BuildContext context) {
    final classes = widget.classSubjectMap.keys.toList();
    final due     = '${_dueDate.day}/${_dueDate.month}/${_dueDate.year}';

    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(context.tr('postHomework'),
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),

            // Class selector
            Text(context.tr('classLabel'),
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: classes.map((cls) {
                  final sel = cls == _selectedClass;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(cls),
                      selected: sel,
                      selectedColor: Colors.red,
                      labelStyle: TextStyle(
                          color: sel ? Colors.white : null,
                          fontWeight: sel
                              ? FontWeight.bold
                              : FontWeight.normal),
                      onSelected: (_) => setState(() {
                        _selectedClass   = cls;
                        _selectedSubject =
                            widget.classSubjectMap[cls]!;
                      }),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 4),
            Text('${context.tr('subjectColon')} $_selectedSubject',
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade500)),
            const SizedBox(height: 16),

            // Title — pick from common titles
            DropdownButtonFormField<String>(
              value: _selectedTitle,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: context.tr('homeworkTitle'),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
              ),
              hint: Text(context.tr('selectHomeworkTitle')),
              items: _kHomeworkTemplates.keys
                  .map((t) => DropdownMenuItem(
                        value: t,
                        child: Text(t, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: _onTitleSelected,
              validator: (v) =>
                  v == null ? context.tr('pleaseSelectTitle') : null,
            ),
            // Custom title field shown only for "Other (custom)"
            if (_isOtherTitle) ...[
              const SizedBox(height: 10),
              TextFormField(
                controller: _titleCtrl,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 80,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: context.tr('customTitle'),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  counterText: '',
                ),
                validator: (v) => _isOtherTitle &&
                        (v == null || v.trim().isEmpty)
                    ? context.tr('titleRequired')
                    : null,
              ),
            ],
            const SizedBox(height: 14),

            // Description
            TextFormField(
              controller: _descCtrl,
              maxLines: 4,
              maxLength: 500,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: context.tr('descriptionMessageEditable'),
                helperText: context.tr('prefilledFromTitle'),
                alignLabelWithHint: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return context.tr('descriptionRequired');
                if (v.trim().length < 10) return context.tr('atLeast10Chars');
                return null;
              },
            ),
            const SizedBox(height: 14),

            // Due date
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.event_outlined,
                        color: Colors.red, size: 20),
                    const SizedBox(width: 10),
                    Text('${context.tr('dueDateColon')} $due',
                        style: const TextStyle(fontSize: 14)),
                    const Spacer(),
                    Icon(Icons.edit_outlined,
                        size: 16, color: Colors.grey.shade500),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white))
                    : Text(context.tr('postHomework'),
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

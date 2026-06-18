import 'package:flutter/material.dart';
import '../../models/class_diary.dart';
import '../../models/teacher.dart';
import '../../services/class_diary_service.dart';
import '../../services/copy_check_service.dart';
import '../../theme.dart';
import '../../l10n/app_strings.dart';
import '../../shared/utils/class_name_utils.dart';

class ClassDiaryScreen extends StatefulWidget {
  final Teacher? teacher; // Null for Guardian view
  final String? guardianClass; // Passed for Guardian view
  final String? guardianSection; // Passed for Guardian view

  const ClassDiaryScreen({
    super.key,
    this.teacher,
    this.guardianClass,
    this.guardianSection,
  });

  @override
  State<ClassDiaryScreen> createState() => _ClassDiaryScreenState();
}

class _ClassDiaryScreenState extends State<ClassDiaryScreen> {
  final _diaryService = ClassDiaryService();
  DateTime _selectedDate = DateTime.now();
  bool _loading = false;
  List<ClassDiaryEntry> _entries = [];

  // Teacher specific state
  Map<String, String> _teacherClassSubjectMap = {}; // "ClassName Section" -> Subject
  String? _selectedClass; // Active class selected by teacher
  bool _loadingClasses = false;

  @override
  void initState() {
    super.initState();
    if (widget.teacher != null) {
      _loadTeacherClasses();
    } else {
      _loadDiaryEntries();
    }
  }

  String get _activeClass {
    if (widget.teacher != null) {
      return _selectedClass ?? '';
    } else {
      return widget.guardianClass ?? '';
    }
  }

  String get _activeSection {
    if (widget.teacher != null) {
      return ''; // Teacher selects full class key including section
    } else {
      return widget.guardianSection ?? '';
    }
  }

  String get _dateKey {
    return '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadTeacherClasses() async {
    setState(() => _loadingClasses = true);
    try {
      final assignments = await CopyCheckService().getTeacherAssignments(widget.teacher!.id);
      final map = <String, String>{};
      for (final a in assignments) {
        final key = a.section.isEmpty ? a.className : '${a.className} ${a.section}';
        map[key] = a.subject;
      }
      if (mounted) {
        setState(() {
          _teacherClassSubjectMap = map;
          _selectedClass = map.keys.isNotEmpty ? map.keys.first : null;
          _loadingClasses = false;
        });
        _loadDiaryEntries();
      }
    } catch (e) {
      if (mounted) setState(() => _loadingClasses = false);
    }
  }

  Future<void> _loadDiaryEntries() async {
    if (_activeClass.isEmpty) return;
    setState(() => _loading = true);
    try {
      // Normalize class query name
      final targetClass = _activeClass;
      final list = await _diaryService.getDiaryForDateRange(targetClass, _dateKey, _dateKey);
      if (mounted) {
        setState(() {
          _entries = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _adjustDate(int days) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: days));
    });
    _loadDiaryEntries();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 7)), // Allow logging slightly ahead if needed
      builder: (context, child) {
        return Theme(
          data: AppTheme.light.copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primary,
              onPrimary: Colors.white,
              onSurface: AppTheme.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _loadDiaryEntries();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTeacher = widget.teacher != null;
    final formattedDate = '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(context.tr('dailyClassDiary')),
        backgroundColor: AppTheme.primaryDark,
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildHeaderSection(isTeacher),
          _buildDateSelector(formattedDate),
          Expanded(
            child: _loadingClasses || _loading
                ? const Center(child: CircularProgressIndicator())
                : _entries.isEmpty
                    ? _buildEmptyState(isTeacher)
                    : _buildTimelineList(isTeacher),
          ),
        ],
      ),
      floatingActionButton: isTeacher && _selectedClass != null
          ? FloatingActionButton.extended(
              onPressed: () => _showAddEntrySheet(),
              backgroundColor: AppTheme.primary,
              icon: const Icon(Icons.rate_review),
              label: Text(context.tr('logDailyLesson')),
            )
          : null,
    );
  }

  Widget _buildHeaderSection(bool isTeacher) {
    if (isTeacher) {
      if (_teacherClassSubjectMap.isEmpty) {
        return const SizedBox();
      }
      return Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: DropdownButtonFormField<String>(
          value: _selectedClass,
          decoration: const InputDecoration(
            labelText: 'Active Class / Section',
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: _teacherClassSubjectMap.keys.map((cls) {
            return DropdownMenuItem(
              value: cls,
              child: Text(cls, style: const TextStyle(fontWeight: FontWeight.bold)),
            );
          }).toList(),
          onChanged: (v) {
            if (v != null) {
              setState(() {
                _selectedClass = v;
              });
              _loadDiaryEntries();
            }
          },
        ),
      );
    } else {
      return Container(
        width: double.infinity,
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppTheme.primaryLight.withValues(alpha: 0.2),
              child: const Icon(Icons.school, color: AppTheme.primary),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Class ${ClassName.format(_activeClass, _activeSection)}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
                const Text(
                  'Timeline of topics taught & assignments',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ],
        ),
      );
    }
  }

  Widget _buildDateSelector(String formattedDate) {
    return Container(
      color: Colors.grey.shade50,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: AppTheme.primary),
            onPressed: () => _adjustDate(-1),
          ),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, size: 16, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    formattedDate,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textPrimary),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: AppTheme.primary),
            onPressed: () => _adjustDate(1),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isTeacher) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_note, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'No diary entries logged',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            isTeacher ? 'Log topics taught & homework for today.' : 'Ask teachers to log today\'s class diary updates.',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineList(bool isTeacher) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _entries.length,
      itemBuilder: (context, index) {
        final entry = _entries[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: AppTheme.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryLight.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        entry.subject.toUpperCase(),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primary),
                      ),
                    ),
                    if (isTeacher && entry.recordedBy == widget.teacher?.email)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 20),
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                        onPressed: () => _confirmDelete(entry),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'TOPICS TAUGHT:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 10, color: AppTheme.textSecondary, letterSpacing: 0.8),
                ),
                const SizedBox(height: 4),
                Text(
                  entry.topicsTaught,
                  style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                ),
                const Divider(height: 20),
                const Text(
                  'HOMEWORK ASSIGNED:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 10, color: AppTheme.textSecondary, letterSpacing: 0.8),
                ),
                const SizedBox(height: 4),
                Text(
                  entry.homeworkSummary.isNotEmpty ? entry.homeworkSummary : 'None',
                  style: TextStyle(fontSize: 14, color: entry.homeworkSummary.isNotEmpty ? AppTheme.textPrimary : Colors.grey.shade500),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'Logged by: ${entry.recordedBy.split('@')[0]}',
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(ClassDiaryEntry entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('deleteEntryQuestion')),
        content: Text(context.tr('deleteDiaryConfirm').replaceAll('{subject}', entry.subject)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _loading = true);
      try {
        await _diaryService.deleteDiaryEntry(entry.id);
        _loadDiaryEntries();
      } catch (e) {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  void _showAddEntrySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddDiaryEntryBottomSheet(
        className: _activeClass,
        subject: _teacherClassSubjectMap[_activeClass] ?? 'General',
        teacherEmail: widget.teacher!.email,
        dateKey: _dateKey,
        onSaved: () {
          _loadDiaryEntries();
        },
      ),
    );
  }
}

class _AddDiaryEntryBottomSheet extends StatefulWidget {
  final String className;
  final String subject;
  final String teacherEmail;
  final String dateKey;
  final VoidCallback onSaved;

  const _AddDiaryEntryBottomSheet({
    required this.className,
    required this.subject,
    required this.teacherEmail,
    required this.dateKey,
    required this.onSaved,
  });

  @override
  State<_AddDiaryEntryBottomSheet> createState() => _AddDiaryEntryBottomSheetState();
}

class _AddDiaryEntryBottomSheetState extends State<_AddDiaryEntryBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  final _topicsController = TextEditingController();
  final _homeworkController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _topicsController.dispose();
    _homeworkController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final entry = ClassDiaryEntry(
        id: '',
        className: widget.className,
        dateKey: widget.dateKey,
        subject: widget.subject,
        topicsTaught: _topicsController.text.trim(),
        homeworkSummary: _homeworkController.text.trim(),
        recordedBy: widget.teacherEmail,
      );
      await ClassDiaryService().saveDiaryEntry(entry);
      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + viewInsets.bottom),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Log ${widget.subject} Lesson',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 12),
              TextFormField(
                controller: _topicsController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: context.tr('topicsCoveredLabel'),
                  border: const OutlineInputBorder(),
                  hintText: context.tr('diaryLessonHint'),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return context.tr('specifyTopicsError');
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _homeworkController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: context.tr('homeworkAssignedLabel'),
                  border: const OutlineInputBorder(),
                  hintText: context.tr('diaryHomeworkHint'),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Text(
                        context.tr('saveDiaryEntry'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

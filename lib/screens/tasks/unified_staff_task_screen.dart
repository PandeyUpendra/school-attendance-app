import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../theme.dart';
import '../../models/staff_task.dart';
import '../../models/teacher.dart';
import '../../services/staff_task_service.dart';
import '../../services/timetable_service.dart';
import '../../services/notification_service.dart';
import '../task_badge_widgets.dart';

const String _kAllTeachers = 'ALL_TEACHERS';

const Map<String, String> _kTemplates = {
  'PTM Preparation':
      'Please prepare a detailed student-wise summary including attendance '
      'percentage, latest test marks, and behavior notes for the upcoming '
      'Parent-Teacher Meeting.',
  'Check and Return Copies':
      'Please collect, check, and return all student copies/notebooks for your '
      'subject. Ensure feedback is written on each copy before returning.',
  'Submit Marks':
      'Please submit the marks for the recent exam/test in the app under your '
      'class and subject by the due date.',
  'Prepare Question Paper':
      'Please prepare a question paper for the upcoming exam. Include MCQ, '
      'short answer, and long answer sections as per the standard pattern.',
  'Update Syllabus':
      'Please update the syllabus completion status in the app for all chapters '
      'covered so far this month.',
  'Duty Assignment':
      'You have been assigned duty for the upcoming school event/exam. Please '
      'report to your assigned location on time in proper uniform.',
  'Parent Call':
      'Please call the parents of the students listed and update the call '
      'status and reason in the Daily Calls section.',
  'Prepare Notes':
      'Please prepare chapter-wise notes for your subject and upload them to '
      'the study material section for students.',
  'Attendance Report':
      'Please review and verify the attendance records for your class for this '
      'month and report any discrepancies.',
  'Meeting Attendance':
      'Your presence is required at the staff meeting. Please ensure you attend '
      'on time and bring any relevant documents.',
  'Custom Task': '',
};

/// Single unified Staff Task screen — role-aware tabs.
///
/// Coordinator / Principal → Assign Task | All Tasks | Analytics
/// Teacher                 → My Tasks   | Done & Overdue
class UnifiedStaffTaskScreen extends StatelessWidget {
  /// 'coordinator', 'principal', or 'teacher'
  final String role;

  /// Email of the logged-in user (coordinator / principal / teacher).
  final String userEmail;

  /// Teacher's Firestore document ID — required when [role] == 'teacher'.
  final String? teacherId;

  /// Display name (used in notifications).
  final String userName;

  const UnifiedStaffTaskScreen({
    super.key,
    required this.role,
    required this.userEmail,
    this.teacherId,
    this.userName = '',
  });

  bool get _isAdmin => role == 'coordinator' || role == 'principal';

  @override
  Widget build(BuildContext context) {
    if (_isAdmin) {
      return DefaultTabController(
        length: 3,
        child: Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(
            title: const Text('Staff Tasks'),
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            bottom: const TabBar(
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              tabs: [
                Tab(icon: Icon(Icons.add_task_outlined),    text: 'Assign Task'),
                Tab(icon: Icon(Icons.list_alt_outlined),    text: 'All Tasks'),
                Tab(icon: Icon(Icons.bar_chart_outlined),   text: 'Analytics'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _AssignTab(assignerEmail: userEmail, assignerName: userName),
              _AllTasksTab(assignerEmail: userEmail),
              _AnalyticsTab(),
            ],
          ),
        ),
      );
    }

    // Teacher view
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text('My Tasks'),
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            tabs: [
              Tab(icon: Icon(Icons.pending_actions_outlined), text: 'Active'),
              Tab(icon: Icon(Icons.done_all_outlined),        text: 'Done & Overdue'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _TeacherTaskTab(
              teacherId: teacherId ?? '',
              showCompleted: false,
            ),
            _TeacherTaskTab(
              teacherId: teacherId ?? '',
              showCompleted: true,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab: Assign Task (coordinator / principal)
// ─────────────────────────────────────────────────────────────────────────────

class _AssignTab extends StatefulWidget {
  final String assignerEmail;
  final String assignerName;
  const _AssignTab({required this.assignerEmail, required this.assignerName});

  @override
  State<_AssignTab> createState() => _AssignTabState();
}

class _AssignTabState extends State<_AssignTab> {
  final _descCtrl        = TextEditingController();
  final _customTitleCtrl = TextEditingController();

  String?       _selectedTaskTitle;
  List<Teacher> _teachers          = [];
  String?       _selectedTeacherId;
  String        _selectedTeacherName = '';
  TaskPriority  _priority             = TaskPriority.medium;
  DateTime?     _dueDate;
  bool          _loadingPeople        = true;
  bool          _saving               = false;

  @override
  void initState() {
    super.initState();
    _loadTeachers();
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _customTitleCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTeachers() async {
    final teachers = await TimetableService().getTeachers();
    if (!mounted) return;
    setState(() {
      _teachers      = teachers..sort((a, b) => a.name.compareTo(b.name));
      _loadingPeople = false;
    });
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now().add(const Duration(days: 3)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
              primary: AppTheme.primary, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  String get _actualTitle =>
      _selectedTaskTitle == 'Custom Task'
          ? _customTitleCtrl.text.trim()
          : _selectedTaskTitle ?? '';

  Future<void> _submit() async {
    if (_selectedTaskTitle == null) {
      _snack('Please select a task title');
      return;
    }
    if (_selectedTaskTitle == 'Custom Task' &&
        _customTitleCtrl.text.trim().isEmpty) {
      _snack('Please enter a custom task title');
      return;
    }
    if (_selectedTeacherId == null) {
      _snack('Please select a teacher');
      return;
    }
    if (_selectedTeacherId == _kAllTeachers) {
      await _submitToAllTeachers();
      return;
    }

    setState(() => _saving = true);

    final title = _actualTitle;
    final task = StaffTask(
      id:             '',
      title:          title,
      description:    _descCtrl.text.trim(),
      assignedTo:     _selectedTeacherId!,
      assignedToName: _selectedTeacherName,
      assignedBy:     widget.assignerEmail,
      assignedByRole: 'coordinator',
      dueDate:        _dueDate,
      status:         TaskStatus.pending,
      priority:       _priority,
      createdAt:      DateTime.now(),
    );

    await StaffTaskService().createTask(task);

    await NotificationService().addStaffTaskNotice(
      taskTitle:         title,
      assignedTeacherId: _selectedTeacherId!,
      assignedByName:    widget.assignerName.isNotEmpty
                             ? widget.assignerName
                             : widget.assignerEmail,
      dueDateStr:        _dueDate != null ? _fmtDate(_dueDate!) : null,
      priority:          _priority.label,
    );

    if (!mounted) return;
    setState(() => _saving = false);
    _resetForm();
    _snack('Task assigned successfully');
  }

  Future<void> _submitToAllTeachers() async {
    final count = _teachers.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Assign to All Teachers?'),
        content: Text('This will create $count individual tasks, '
            'one for each teacher.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _saving = true);
    final title       = _actualTitle;
    final description = _descCtrl.text.trim();
    final groupId     = DateTime.now().millisecondsSinceEpoch.toString();
    final now         = DateTime.now();

    final tasks = _teachers
        .map((t) => StaffTask(
              id:             '',
              title:          title,
              description:    description,
              assignedTo:     t.id,
              assignedToName: t.name,
              assignedBy:     widget.assignerEmail,
              assignedByRole: 'coordinator',
              dueDate:        _dueDate,
              status:         TaskStatus.pending,
              priority:       _priority,
              createdAt:      now,
              isGroupTask:    true,
              groupTaskId:    groupId,
            ))
        .toList();

    await StaffTaskService().createTasksBatch(tasks);

    for (final t in _teachers) {
      await NotificationService().addStaffTaskNotice(
        taskTitle:         title,
        assignedTeacherId: t.id,
        assignedByName:    widget.assignerName.isNotEmpty
                               ? widget.assignerName
                               : widget.assignerEmail,
        dueDateStr:        _dueDate != null ? _fmtDate(_dueDate!) : null,
        priority:          _priority.label,
      );
    }

    if (!mounted) return;
    setState(() => _saving = false);
    _resetForm();
    _snack('Task assigned to all $count teachers');
  }

  void _resetForm() {
    _descCtrl.clear();
    _customTitleCtrl.clear();
    setState(() {
      _selectedTaskTitle   = null;
      _selectedTeacherId   = null;
      _selectedTeacherName = '';
      _priority            = TaskPriority.medium;
      _dueDate             = null;
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Task Title Dropdown ──────────────────────────────────────────
          _Label('Task Title'),
          DropdownButtonFormField<String>(
            decoration: InputDecoration(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              filled: true,
              fillColor: AppTheme.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              prefixIcon: const Icon(Icons.task_alt,
                  color: AppTheme.primary, size: 20),
            ),
            isExpanded: true,
            value: _selectedTaskTitle,
            hint: const Text('Select or choose custom'),
            items: _kTemplates.keys
                .map((t) => DropdownMenuItem<String>(
                      value: t,
                      child: Text(t, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (selected) {
              setState(() {
                _selectedTaskTitle = selected;
                _descCtrl.text = (selected != null && selected != 'Custom Task')
                    ? _kTemplates[selected] ?? ''
                    : '';
              });
            },
          ),

          // ── Custom Task Title field ───────────────────────────────────────
          if (_selectedTaskTitle == 'Custom Task') ...[
            const SizedBox(height: 10),
            TextField(
              controller: _customTitleCtrl,
              decoration: _inputDec(hint: 'e.g. Prepare Annual Report').copyWith(
                labelText: 'Enter Custom Task Title',
                floatingLabelBehavior: FloatingLabelBehavior.always,
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
          ],

          const SizedBox(height: 14),

          // ── Description ───────────────────────────────────────────────────
          _Label('Description (auto-filled, editable)'),
          TextField(
            controller: _descCtrl,
            maxLines: 4,
            decoration:
                _inputDec(hint: 'Describe what needs to be done'),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 4),
          Text('You can edit this message',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),

          const SizedBox(height: 14),

          // ── Assign To ─────────────────────────────────────────────────────
          _Label('Assign To'),
          _loadingPeople
              ? const Center(
                  child: CircularProgressIndicator(
                      color: AppTheme.primary, strokeWidth: 2))
              : DropdownButtonFormField<String>(
                  value: _selectedTeacherId,
                  hint: const Text('Select a teacher'),
                  isExpanded: true,
                  decoration: _inputDec(),
                  items: [
                    DropdownMenuItem<String>(
                      value: _kAllTeachers,
                      child: Row(children: [
                        const Icon(Icons.groups,
                            color: AppTheme.primary, size: 18),
                        const SizedBox(width: 8),
                        const Text('All Teachers',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary)),
                      ]),
                    ),
                    ..._teachers.map((t) => DropdownMenuItem<String>(
                          value: t.id,
                          child: Text(t.name,
                              overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _selectedTeacherId   = v;
                      _selectedTeacherName = v == _kAllTeachers
                          ? 'All Teachers'
                          : _teachers.firstWhere((t) => t.id == v).name;
                    });
                  },
                ),

          // ── All Teachers banner ───────────────────────────────────────────
          if (_selectedTeacherId == _kAllTeachers) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppTheme.primary.withOpacity(0.2)),
              ),
              child: Row(children: [
                const Icon(Icons.groups,
                    color: AppTheme.primary, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Task will be assigned to all ${_teachers.length} '
                    'teachers in the school',
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ]),
            ),
          ],

          const SizedBox(height: 14),

          // ── Priority ──────────────────────────────────────────────────────
          _Label('Priority'),
          Row(children: [
            for (final p in TaskPriority.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(p.label),
                  selected: _priority == p,
                  selectedColor: _priorityColor(p).withOpacity(0.15),
                  labelStyle: TextStyle(
                    color: _priority == p
                        ? _priorityColor(p)
                        : Colors.grey.shade600,
                    fontWeight: _priority == p
                        ? FontWeight.w700
                        : FontWeight.normal,
                  ),
                  side: BorderSide(
                    color: _priority == p
                        ? _priorityColor(p)
                        : Colors.grey.shade300,
                  ),
                  onSelected: (_) => setState(() => _priority = p),
                ),
              ),
          ]),

          const SizedBox(height: 14),

          // ── Due Date ──────────────────────────────────────────────────────
          _Label('Due Date'),
          GestureDetector(
            onTap: _pickDueDate,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                Icon(Icons.event_outlined,
                    size: 18, color: Colors.grey.shade500),
                const SizedBox(width: 8),
                Text(
                  _dueDate != null
                      ? _fmtDate(_dueDate!)
                      : 'Select due date (optional)',
                  style: TextStyle(
                      fontSize: 13,
                      color: _dueDate != null
                          ? Colors.grey.shade800
                          : Colors.grey.shade400),
                ),
                const Spacer(),
                if (_dueDate != null)
                  GestureDetector(
                    onTap: () => setState(() => _dueDate = null),
                    child: Icon(Icons.clear,
                        size: 16, color: Colors.grey.shade400),
                  ),
              ]),
            ),
          ),

          const SizedBox(height: 28),

          // ── Submit ────────────────────────────────────────────────────────
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
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Assign Task',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Color _priorityColor(TaskPriority p) {
    switch (p) {
      case TaskPriority.high:   return AppTheme.danger;
      case TaskPriority.medium: return AppTheme.warning;
      case TaskPriority.low:    return AppTheme.success;
    }
  }

  InputDecoration _inputDec({String? hint}) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        filled: true,
        fillColor: AppTheme.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      );

  String _fmtDate(DateTime dt) {
    const mo = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec',
    ];
    return '${dt.day} ${mo[dt.month - 1]} ${dt.year}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab: All Tasks (coordinator / principal)
// ─────────────────────────────────────────────────────────────────────────────

class _AllTasksTab extends StatefulWidget {
  final String assignerEmail;
  const _AllTasksTab({required this.assignerEmail});

  @override
  State<_AllTasksTab> createState() => _AllTasksTabState();
}

class _AllTasksTabState extends State<_AllTasksTab> {
  TaskStatus? _filterStatus;
  int         _refreshTick = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Status filter bar ────────────────────────────────────────────
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _FilterChip(
                  label: 'All',
                  selected: _filterStatus == null,
                  onTap: () => setState(() => _filterStatus = null)),
              const SizedBox(width: 6),
              for (final s in TaskStatus.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _FilterChip(
                      label: s.label,
                      selected: _filterStatus == s,
                      onTap: () => setState(() => _filterStatus = s)),
                ),
            ]),
          ),
        ),

        // ── Task list ────────────────────────────────────────────────────
        Expanded(
          child: StreamBuilder<List<StaffTask>>(
            key: ValueKey(_refreshTick),
            stream: StaffTaskService()
                .getTasksByAssignerStream(widget.assignerEmail),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData) {
                return const Center(
                    child: CircularProgressIndicator(
                        color: AppTheme.primary));
              }
              var tasks = snap.data ?? [];
              if (_filterStatus != null) {
                tasks = tasks
                    .where((t) => t.status == _filterStatus)
                    .toList();
              }
              if (tasks.isEmpty) {
                return Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.task_outlined,
                        size: 56, color: Colors.grey.shade300),
                    const SizedBox(height: 10),
                    Text('No tasks yet',
                        style: TextStyle(
                            fontSize: 15, color: Colors.grey.shade500)),
                    const SizedBox(height: 6),
                    Text('Tap "Assign Task" to create one',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade400)),
                  ]),
                );
              }
              return RefreshIndicator(
                onRefresh: () async =>
                    setState(() => _refreshTick++),
                color: AppTheme.primary,
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: tasks.length,
                  itemBuilder: (_, i) => _AdminTaskCard(
                    task: tasks[i],
                    onDelete: () => _deleteTask(tasks[i]),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _deleteTask(StaffTask task) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Task'),
        content: Text('Delete "${task.title}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child:
                  Text('Delete', style: TextStyle(color: AppTheme.danger))),
        ],
      ),
    );
    if (ok == true) await StaffTaskService().deleteTaskById(task.id);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab: Analytics (coordinator / principal)
// ─────────────────────────────────────────────────────────────────────────────

class _AnalyticsTab extends StatelessWidget {
  const _AnalyticsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<StaffTask>>(
      stream: StaffTaskService().getAllTasksStream(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: AppTheme.primary));
        }
        final tasks = snap.data ?? [];
        if (tasks.isEmpty) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.bar_chart_outlined,
                  size: 56, color: Colors.grey.shade300),
              const SizedBox(height: 10),
              Text('No task data yet',
                  style: TextStyle(
                      fontSize: 15, color: Colors.grey.shade500)),
            ]),
          );
        }

        final total      = tasks.length;
        final pending    = tasks.where((t) => t.status == TaskStatus.pending).length;
        final inProgress = tasks.where((t) => t.status == TaskStatus.inProgress).length;
        final completed  = tasks.where((t) => t.status == TaskStatus.completed).length;
        final overdue    = tasks.where((t) => t.isOverdue).length;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary grid
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 2.2,
                children: [
                  _StatCard('Total',       '$total',      Colors.indigo),
                  _StatCard('Completed',   '$completed',  AppTheme.success),
                  _StatCard('In Progress', '$inProgress', AppTheme.warning),
                  _StatCard('Overdue',     '$overdue',    AppTheme.danger),
                ],
              ),
              const SizedBox(height: 20),

              // Pie chart
              const Text('Completion Breakdown',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Container(
                height: 160,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14)),
                child: total == 0
                    ? const Center(child: Text('No data'))
                    : Row(children: [
                        Expanded(
                          child: PieChart(PieChartData(
                            sections: [
                              if (completed > 0)
                                PieChartSectionData(
                                    value: completed.toDouble(),
                                    color: AppTheme.success,
                                    title: '',
                                    radius: 45),
                              if (inProgress > 0)
                                PieChartSectionData(
                                    value: inProgress.toDouble(),
                                    color: AppTheme.warning,
                                    title: '',
                                    radius: 45),
                              if (pending > 0)
                                PieChartSectionData(
                                    value: pending.toDouble(),
                                    color: Colors.blue,
                                    title: '',
                                    radius: 45),
                              if (overdue > 0)
                                PieChartSectionData(
                                    value: overdue.toDouble(),
                                    color: AppTheme.danger,
                                    title: '',
                                    radius: 45),
                            ],
                            sectionsSpace: 2,
                          )),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _LegendRow('Completed',   AppTheme.success, completed),
                            _LegendRow('In Progress', AppTheme.warning, inProgress),
                            _LegendRow('Pending',     Colors.blue,     pending),
                            _LegendRow('Overdue',     AppTheme.danger, overdue),
                          ],
                        ),
                      ]),
              ),
              const SizedBox(height: 20),

              // Teacher-wise breakdown
              const Text('By Teacher',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              ..._teacherStats(tasks).map((entry) {
                final name      = entry['name'] as String;
                final tTotal    = entry['total'] as int;
                final tDone     = entry['done']  as int;
                final pct       = tTotal > 0 ? tDone / tTotal : 0.0;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(name,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                        Text('$tDone / $tTotal done',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade500)),
                      ]),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 5,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              pct == 1.0 ? AppTheme.success : AppTheme.primary),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  List<Map<String, dynamic>> _teacherStats(List<StaffTask> tasks) {
    final map = <String, Map<String, dynamic>>{};
    for (final t in tasks) {
      final name = t.assignedToName.isNotEmpty ? t.assignedToName : t.assignedTo;
      if (name.isEmpty) continue;
      map.putIfAbsent(name, () => {'name': name, 'total': 0, 'done': 0});
      map[name]!['total'] = (map[name]!['total'] as int) + 1;
      if (t.status == TaskStatus.completed) {
        map[name]!['done'] = (map[name]!['done'] as int) + 1;
      }
    }
    final list = map.values.toList();
    list.sort((a, b) => (b['total'] as int).compareTo(a['total'] as int));
    return list;
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  const _StatCard(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(value,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: color)),
          Text(label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ]),
      );
}

class _LegendRow extends StatelessWidget {
  final String label;
  final Color  color;
  final int    count;
  const _LegendRow(this.label, this.color, this.count);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(children: [
          Container(
              width: 9, height: 9,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 5),
          Text('$label ($count)',
              style: const TextStyle(fontSize: 10)),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab: Teacher tasks (active OR done/overdue)
// ─────────────────────────────────────────────────────────────────────────────

class _TeacherTaskTab extends StatefulWidget {
  final String teacherId;
  final bool   showCompleted;
  const _TeacherTaskTab(
      {required this.teacherId, required this.showCompleted});

  @override
  State<_TeacherTaskTab> createState() => _TeacherTaskTabState();
}

class _TeacherTaskTabState extends State<_TeacherTaskTab> {
  int _refreshTick = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.teacherId.isEmpty) {
      return Center(
        child: Text('Teacher ID not found',
            style: TextStyle(color: Colors.grey.shade500)),
      );
    }

    return StreamBuilder<List<StaffTask>>(
      key: ValueKey(_refreshTick),
      stream:
          StaffTaskService().getTasksForTeacherStream(widget.teacherId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting &&
            !snap.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: AppTheme.primary));
        }
        final all = snap.data ?? [];
        final tasks = widget.showCompleted
            ? all
                .where((t) =>
                    t.status == TaskStatus.completed || t.isOverdue)
                .toList()
            : all
                .where((t) =>
                    t.status != TaskStatus.completed && !t.isOverdue)
                .toList();

        if (tasks.isEmpty) {
          return RefreshIndicator(
            onRefresh: () async => setState(() => _refreshTick++),
            color: AppTheme.primary,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.5,
                  child: Center(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                              widget.showCompleted
                                  ? Icons.done_all_outlined
                                  : Icons.task_alt_outlined,
                              size: 56,
                              color: Colors.grey.shade300),
                          const SizedBox(height: 10),
                          Text(
                              widget.showCompleted
                                  ? 'No completed tasks yet'
                                  : 'No active tasks',
                              style: TextStyle(
                                  fontSize: 15,
                                  color: Colors.grey.shade500)),
                          if (!widget.showCompleted) ...[
                            const SizedBox(height: 6),
                            Text('You\'re all caught up!',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade400)),
                          ],
                        ]),
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async => setState(() => _refreshTick++),
          color: AppTheme.primary,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: tasks.length,
            itemBuilder: (_, i) => _TeacherTaskCard(
              task: tasks[i],
              onStatusChange: (s) async =>
                  StaffTaskService().updateTaskStatus(tasks[i].id, s),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Cards
// ─────────────────────────────────────────────────────────────────────────────

class _AdminTaskCard extends StatelessWidget {
  final StaffTask    task;
  final VoidCallback onDelete;
  const _AdminTaskCard({required this.task, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final overdue = task.isOverdue;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: overdue
            ? Border.all(
                color: AppTheme.danger.withOpacity(0.4), width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(task.title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              TaskPriorityBadge(priority: task.priority),
              const SizedBox(width: 6),
              TaskStatusChip(status: task.status),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onDelete,
                child: Icon(Icons.delete_outline,
                    size: 18, color: Colors.grey.shade400),
              ),
            ]),
            if (task.assignedToName.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.person_outline,
                    size: 12, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Text(task.assignedToName,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500)),
              ]),
            ],
            if (task.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(task.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade600)),
            ],
            if (task.dueDate != null) ...[
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.event_outlined,
                    size: 12,
                    color: overdue
                        ? AppTheme.danger
                        : Colors.grey.shade400),
                const SizedBox(width: 4),
                Text(
                  overdue
                      ? 'OVERDUE by ${task.overdueDays}d'
                      : 'Due ${_fmtDate(task.dueDate!)}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        overdue ? FontWeight.w700 : FontWeight.normal,
                    color: overdue
                        ? AppTheme.danger
                        : Colors.grey.shade500,
                  ),
                ),
              ]),
            ],
            if (task.isGroupTask) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: AppTheme.primary.withOpacity(0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.groups,
                      size: 12, color: AppTheme.primary),
                  const SizedBox(width: 4),
                  const Text('Group Task',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary)),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime dt) {
    const mo = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec',
    ];
    return '${dt.day} ${mo[dt.month - 1]} ${dt.year}';
  }
}

class _TeacherTaskCard extends StatelessWidget {
  final StaffTask                task;
  final ValueChanged<TaskStatus> onStatusChange;
  const _TeacherTaskCard(
      {required this.task, required this.onStatusChange});

  @override
  Widget build(BuildContext context) {
    final overdue = task.isOverdue;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: overdue
            ? Border.all(
                color: AppTheme.danger.withOpacity(0.4), width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(task.title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              TaskPriorityBadge(priority: task.priority),
              const SizedBox(width: 6),
              TaskStatusChip(status: task.status),
            ]),
            if (task.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(task.description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey.shade600)),
            ],
            if (task.dueDate != null) ...[
              const SizedBox(height: 6),
              Row(children: [
                Icon(Icons.event_outlined,
                    size: 12,
                    color: overdue
                        ? AppTheme.danger
                        : Colors.grey.shade400),
                const SizedBox(width: 4),
                Text(
                  overdue
                      ? 'OVERDUE by ${task.overdueDays}d'
                      : 'Due ${_fmtDate(task.dueDate!)}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        overdue ? FontWeight.w700 : FontWeight.normal,
                    color: overdue
                        ? AppTheme.danger
                        : Colors.grey.shade500,
                  ),
                ),
              ]),
            ],
            const SizedBox(height: 10),
            // Status update row
            if (task.status != TaskStatus.completed)
              Row(children: [
                if (task.status == TaskStatus.pending)
                  _StatusBtn(
                      label: 'Mark In Progress',
                      color: AppTheme.warning,
                      onTap: () =>
                          onStatusChange(TaskStatus.inProgress)),
                if (task.status == TaskStatus.inProgress) ...[
                  _StatusBtn(
                      label: 'Mark Done',
                      color: AppTheme.success,
                      onTap: () =>
                          onStatusChange(TaskStatus.completed)),
                  const SizedBox(width: 8),
                  _StatusBtn(
                      label: 'Back to Pending',
                      color: Colors.grey,
                      onTap: () =>
                          onStatusChange(TaskStatus.pending)),
                ],
              ]),
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime dt) {
    const mo = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec',
    ];
    return '${dt.day} ${mo[dt.month - 1]} ${dt.year}';
  }
}

class _StatusBtn extends StatelessWidget {
  final String       label;
  final Color        color;
  final VoidCallback onTap;
  const _StatusBtn(
      {required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String       label;
  final bool         selected;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : Colors.grey.shade600)),
        ),
      );
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600)),
      );
}

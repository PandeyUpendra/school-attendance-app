import 'package:flutter/material.dart';
import '../theme.dart';
import '../models/staff_task.dart';
import '../models/teacher.dart';
import '../services/staff_task_service.dart';
import '../services/timetable_service.dart';
import '../services/notification_service.dart';
import 'task_badge_widgets.dart';

/// Coordinator's staff-task management screen.
/// Tab 1 — Assign Task (create form).
/// Tab 2 — All Tasks (created by this coordinator).
class CoordinatorStaffTasksScreen extends StatelessWidget {
  final String coordinatorEmail;

  const CoordinatorStaffTasksScreen({
    super.key,
    required this.coordinatorEmail,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
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
              Tab(icon: Icon(Icons.add_task_outlined), text: 'Assign Task'),
              Tab(icon: Icon(Icons.list_alt_outlined),  text: 'All Tasks'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _AssignTab(coordinatorEmail: coordinatorEmail),
            _AllTasksTab(coordinatorEmail: coordinatorEmail),
          ],
        ),
      ),
    );
  }
}

// ── Tab 1: Assign Task ────────────────────────────────────────────────────────

class _AssignTab extends StatefulWidget {
  final String coordinatorEmail;
  const _AssignTab({required this.coordinatorEmail});

  @override
  State<_AssignTab> createState() => _AssignTabState();
}

class _AssignTabState extends State<_AssignTab> {
  final _titleCtrl = TextEditingController();
  final _descCtrl  = TextEditingController();

  List<Teacher>  _teachers      = [];
  String?        _selectedTeacherId;
  String         _selectedTeacherName = '';
  TaskPriority   _priority      = TaskPriority.medium;
  DateTime?      _dueDate;
  bool           _loadingPeople = true;
  bool           _saving        = false;

  @override
  void initState() {
    super.initState();
    _loadTeachers();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTeachers() async {
    final teachers = await TimetableService().getTeachers();
    if (!mounted) return;
    setState(() {
      _teachers     = teachers..sort((a, b) => a.name.compareTo(b.name));
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

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      _snack('Please enter a task title');
      return;
    }
    if (_selectedTeacherId == null) {
      _snack('Please select a teacher');
      return;
    }

    setState(() => _saving = true);

    final task = StaffTask(
      id:             '',
      title:          title,
      description:    _descCtrl.text.trim(),
      assignedTo:     _selectedTeacherId!,
      assignedToName: _selectedTeacherName,
      assignedBy:     widget.coordinatorEmail,
      assignedByRole: 'coordinator',
      dueDate:        _dueDate,
      status:         TaskStatus.pending,
      priority:       _priority,
      createdAt:      DateTime.now(),
    );

    await StaffTaskService().createTask(task);

    // Notify the assigned teacher.
    await NotificationService().addStaffTaskNotice(
      taskTitle:         title,
      assignedTeacherId: _selectedTeacherId!,
      assignedByName:    widget.coordinatorEmail,
      dueDateStr:        _dueDate != null ? _fmtDate(_dueDate!) : null,
      priority:          _priority.label,
    );

    if (!mounted) return;
    setState(() => _saving = false);
    _titleCtrl.clear();
    _descCtrl.clear();
    setState(() {
      _selectedTeacherId   = null;
      _selectedTeacherName = '';
      _priority            = TaskPriority.medium;
      _dueDate             = null;
    });
    _snack('Task assigned successfully');
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
          // ── Title ──────────────────────────────────────────────────────
          _Label('Task Title'),
          TextField(
            controller: _titleCtrl,
            decoration: _inputDec(hint: 'e.g. PTM Preparation'),
            textCapitalization: TextCapitalization.sentences,
          ),

          const SizedBox(height: 14),

          // ── Description ────────────────────────────────────────────────
          _Label('Description'),
          TextField(
            controller: _descCtrl,
            maxLines: 4,
            decoration: _inputDec(hint: 'Describe what needs to be done'),
            textCapitalization: TextCapitalization.sentences,
          ),

          const SizedBox(height: 14),

          // ── Assign To ──────────────────────────────────────────────────
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
                  items: _teachers.map((t) {
                    return DropdownMenuItem(
                      value: t.id,
                      child: Text(t.name,
                          overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    final teacher =
                        _teachers.firstWhere((t) => t.id == v);
                    setState(() {
                      _selectedTeacherId   = v;
                      _selectedTeacherName = teacher.name;
                    });
                  },
                ),

          const SizedBox(height: 14),

          // ── Priority ───────────────────────────────────────────────────
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
                  onSelected: (_) =>
                      setState(() => _priority = p),
                ),
              ),
          ]),

          const SizedBox(height: 14),

          // ── Due Date ───────────────────────────────────────────────────
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

          // ── Submit ─────────────────────────────────────────────────────
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
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${dt.day} ${mo[dt.month - 1]} ${dt.year}';
  }
}

// ── Tab 2: All Tasks (created by coordinator) ─────────────────────────────────

class _AllTasksTab extends StatefulWidget {
  final String coordinatorEmail;
  const _AllTasksTab({required this.coordinatorEmail});

  @override
  State<_AllTasksTab> createState() => _AllTasksTabState();
}

class _AllTasksTabState extends State<_AllTasksTab> {
  int         _refreshTick   = 0;
  TaskStatus? _filterStatus;   // null = All
  String?     _filterTeacher; // null = All teachers

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Filter bar ────────────────────────────────────────────────
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

        // ── Task list ─────────────────────────────────────────────────
        Expanded(
          child: StreamBuilder<List<StaffTask>>(
            key: ValueKey(_refreshTick),
            stream: StaffTaskService()
                .getTasksByAssignerStream(widget.coordinatorEmail),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData) {
                return const Center(
                    child: CircularProgressIndicator(
                        color: AppTheme.primary));
              }
              var tasks = snap.data ?? [];

              // Apply filters
              if (_filterStatus != null) {
                tasks = tasks
                    .where((t) => t.status == _filterStatus)
                    .toList();
              }
              if (_filterTeacher != null) {
                tasks = tasks
                    .where((t) => t.assignedTo == _filterTeacher)
                    .toList();
              }

              if (tasks.isEmpty) {
                return Center(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.task_outlined,
                            size: 56, color: Colors.grey.shade300),
                        const SizedBox(height: 10),
                        Text('No tasks yet',
                            style: TextStyle(
                                fontSize: 15,
                                color: Colors.grey.shade500)),
                        const SizedBox(height: 6),
                        Text('Tap "Assign Task" to create one',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade400)),
                      ]),
                );
              }

              return RefreshIndicator(
                onRefresh: () async =>
                    setState(() => _refreshTick++),
                color: AppTheme.primary,
                child: ListView.builder(
                  padding:
                      const EdgeInsets.fromLTRB(12, 12, 12, 32),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: tasks.length,
                  itemBuilder: (_, i) => _CoordTaskCard(
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
              child: Text('Delete',
                  style: TextStyle(color: AppTheme.danger))),
        ],
      ),
    );
    if (ok == true) await StaffTaskService().deleteTaskById(task.id);
  }
}

class _CoordTaskCard extends StatelessWidget {
  final StaffTask    task;
  final VoidCallback onDelete;
  const _CoordTaskCard({required this.task, required this.onDelete});

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
                    fontWeight: overdue
                        ? FontWeight.w700
                        : FontWeight.normal,
                    color: overdue
                        ? AppTheme.danger
                        : Colors.grey.shade500,
                  ),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime dt) {
    const mo = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${dt.day} ${mo[dt.month - 1]} ${dt.year}';
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String       label;
  final bool         selected;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primary
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color:
                  selected ? Colors.white : Colors.grey.shade600,
            ),
          ),
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

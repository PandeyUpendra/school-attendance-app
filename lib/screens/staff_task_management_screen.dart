import 'package:flutter/material.dart';
import '../theme.dart';
import '../models/staff_task.dart';
import '../models/teacher.dart';
import '../services/staff_task_service.dart';
import '../services/timetable_service.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import 'task_badge_widgets.dart';

/// Principal's school-wide task overview.
/// Shows stats, all tasks with filters, and a FAB to create new tasks.
class StaffTaskManagementScreen extends StatefulWidget {
  const StaffTaskManagementScreen({super.key});

  @override
  State<StaffTaskManagementScreen> createState() =>
      _StaffTaskManagementScreenState();
}

class _StaffTaskManagementScreenState
    extends State<StaffTaskManagementScreen> {
  int         _refreshTick    = 0;
  TaskStatus? _filterStatus;        // null = All
  String?     _filterAssignedTo;    // teacher id filter
  String?     _filterAssignedBy;    // assigner email filter
  String      _principalEmail = '';

  @override
  void initState() {
    super.initState();
    _loadEmail();
  }

  Future<void> _loadEmail() async {
    final session = await AuthService().getSession();
    if (!mounted) return;
    setState(() => _principalEmail =
        (session?['email'] as String?) ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('All Staff Tasks'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateSheet,
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Assign Task'),
      ),
      body: StreamBuilder<List<StaffTask>>(
        key: ValueKey(_refreshTick),
        stream: StaffTaskService().getAllTasksStream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(
                    color: AppTheme.primary));
          }
          final allTasks = snap.data ?? [];
          var filtered   = _applyFilters(allTasks);

          return RefreshIndicator(
            onRefresh: () async => setState(() => _refreshTick++),
            color: AppTheme.primary,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // ── Stats row ────────────────────────────────────────
                SliverToBoxAdapter(
                  child: _StatsRow(tasks: allTasks),
                ),

                // ── Filter bar ───────────────────────────────────────
                SliverToBoxAdapter(
                  child: _buildFilterBar(allTasks),
                ),

                // ── Task list ────────────────────────────────────────
                filtered.isEmpty
                    ? SliverFillRemaining(
                        hasScrollBody: false,
                        child: _emptyState(allTasks.isEmpty),
                      )
                    : SliverPadding(
                        padding: const EdgeInsets.fromLTRB(
                            12, 8, 12, 100),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (_, i) => _PrincipalTaskCard(
                              task: filtered[i],
                              onDelete: () =>
                                  _deleteTask(filtered[i]),
                            ),
                            childCount: filtered.length,
                          ),
                        ),
                      ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<StaffTask> _applyFilters(List<StaffTask> tasks) {
    var result = tasks;
    if (_filterStatus != null) {
      result = result.where((t) => t.status == _filterStatus).toList();
    }
    if (_filterAssignedTo != null) {
      result = result
          .where((t) => t.assignedTo == _filterAssignedTo)
          .toList();
    }
    if (_filterAssignedBy != null) {
      result = result
          .where((t) => t.assignedBy == _filterAssignedBy)
          .toList();
    }
    return result;
  }

  Widget _buildFilterBar(List<StaffTask> allTasks) {
    // Unique assigners
    final assigners = allTasks.map((t) => t.assignedBy).toSet().toList()
      ..sort();
    // Unique teachers
    final teachers = <String, String>{};
    for (final t in allTasks) {
      if (t.assignedTo.isNotEmpty) {
        teachers[t.assignedTo] = t.assignedToName;
      }
    }

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _FChip(
                  label: 'All',
                  selected: _filterStatus == null,
                  onTap: () =>
                      setState(() => _filterStatus = null)),
              const SizedBox(width: 6),
              for (final s in TaskStatus.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _FChip(
                      label: s.label,
                      selected: _filterStatus == s,
                      onTap: () =>
                          setState(() => _filterStatus = s)),
                ),
            ]),
          ),

          // Teacher + assigner dropdowns (only if data available)
          if (teachers.isNotEmpty || assigners.isNotEmpty)
            const SizedBox(height: 8),
          if (teachers.isNotEmpty)
            DropdownButtonFormField<String?>(
              value: _filterAssignedTo,
              isExpanded: true,
              decoration: InputDecoration(
                hintText: 'Filter by teacher',
                hintStyle: TextStyle(
                    fontSize: 12, color: Colors.grey.shade400),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                filled: true,
                fillColor: AppTheme.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('All Teachers')),
                ...teachers.entries.map((e) => DropdownMenuItem<String?>(
                    value: e.key,
                    child: Text(e.value.isNotEmpty ? e.value : e.key,
                        overflow: TextOverflow.ellipsis))),
              ],
              onChanged: (v) =>
                  setState(() => _filterAssignedTo = v),
            ),

          if (assigners.length > 1) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              value: _filterAssignedBy,
              isExpanded: true,
              decoration: InputDecoration(
                hintText: 'Filter by assigned by',
                hintStyle: TextStyle(
                    fontSize: 12, color: Colors.grey.shade400),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                filled: true,
                fillColor: AppTheme.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('All Assigners')),
                ...assigners.map((e) => DropdownMenuItem<String?>(
                    value: e,
                    child: Text(e,
                        overflow: TextOverflow.ellipsis))),
              ],
              onChanged: (v) =>
                  setState(() => _filterAssignedBy = v),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openCreateSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateTaskSheet(
        assignedBy:     _principalEmail,
        assignedByRole: 'principal',
      ),
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
    if (ok == true) await StaffTaskService().deleteTask(task.id);
  }

  Widget _emptyState(bool noTasksAtAll) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.task_outlined,
              size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(noTasksAtAll ? 'No tasks yet' : 'No matching tasks',
              style:
                  TextStyle(fontSize: 16, color: Colors.grey.shade500)),
          const SizedBox(height: 6),
          Text(
            noTasksAtAll
                ? 'Tap + Assign Task to get started'
                : 'Try changing the filters',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          ),
        ]),
      );
}

// ── Stats row ─────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final List<StaffTask> tasks;
  const _StatsRow({required this.tasks});

  @override
  Widget build(BuildContext context) {
    final total     = tasks.length;
    final pending   = tasks.where((t) => t.status == TaskStatus.pending).length;
    final completed = tasks.where((t) => t.status == TaskStatus.completed).length;
    final overdue   = tasks.where((t) => t.isOverdue).length;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(children: [
        _Stat(value: '$total',     label: 'Total',     color: AppTheme.primary),
        _StatDivider(),
        _Stat(value: '$pending',   label: 'Pending',   color: AppTheme.warning),
        _StatDivider(),
        _Stat(value: '$completed', label: 'Completed', color: AppTheme.success),
        _StatDivider(),
        _Stat(value: '$overdue',   label: 'Overdue',   color: AppTheme.danger),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final Color  color;
  const _Stat(
      {required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: color,
                  height: 1.1)),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 10.5,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w500)),
        ]),
      );
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        height: 30,
        width: 1,
        color: Colors.grey.shade100,
      );
}

// ── Principal task card ───────────────────────────────────────────────────────

class _PrincipalTaskCard extends StatelessWidget {
  final StaffTask    task;
  final VoidCallback onDelete;
  const _PrincipalTaskCard(
      {required this.task, required this.onDelete});

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
            // Title row
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

            // Teacher name
            if (task.assignedToName.isNotEmpty) ...[
              const SizedBox(height: 5),
              Row(children: [
                Icon(Icons.person_outline,
                    size: 13, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Text(task.assignedToName,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500)),
                const Spacer(),
                Text('by ${task.assignedBy}',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade400,
                        fontStyle: FontStyle.italic),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ]),
            ],

            // Due date
            if (task.dueDate != null) ...[
              const SizedBox(height: 5),
              Row(children: [
                Icon(Icons.event_outlined,
                    size: 13,
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

// ── Create task sheet (shared by principal) ───────────────────────────────────

class _CreateTaskSheet extends StatefulWidget {
  final String assignedBy;
  final String assignedByRole;

  const _CreateTaskSheet({
    required this.assignedBy,
    required this.assignedByRole,
  });

  @override
  State<_CreateTaskSheet> createState() => _CreateTaskSheetState();
}

class _CreateTaskSheetState extends State<_CreateTaskSheet> {
  final _titleCtrl = TextEditingController();
  final _descCtrl  = TextEditingController();

  List<Teacher>  _teachers             = [];
  String?        _selectedTeacherId;
  String         _selectedTeacherName  = '';
  TaskPriority   _priority             = TaskPriority.medium;
  DateTime?      _dueDate;
  bool           _loadingPeople        = true;
  bool           _saving               = false;

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
      assignedBy:     widget.assignedBy,
      assignedByRole: widget.assignedByRole,
      dueDate:        _dueDate,
      status:         TaskStatus.pending,
      priority:       _priority,
      createdAt:      DateTime.now(),
    );

    await StaffTaskService().createTask(task);

    await NotificationService().addStaffTaskNotice(
      taskTitle:         title,
      assignedTeacherId: _selectedTeacherId!,
      assignedByName:    widget.assignedBy,
      dueDateStr:        _dueDate != null ? _fmtDate(_dueDate!) : null,
      priority:          _priority.label,
    );

    if (!mounted) return;
    Navigator.pop(context);
    _snack('Task assigned to $_selectedTeacherName');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: EdgeInsets.only(bottom: bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Assign Task',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),

                  // Title
                  _SheetLabel('Task Title'),
                  TextField(
                    controller: _titleCtrl,
                    decoration: _dec(hint: 'e.g. PTM Preparation'),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 12),

                  // Description
                  _SheetLabel('Description'),
                  TextField(
                    controller: _descCtrl,
                    maxLines: 3,
                    decoration:
                        _dec(hint: 'Describe what needs to be done'),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 12),

                  // Assign to teacher
                  _SheetLabel('Assign To'),
                  _loadingPeople
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: AppTheme.primary,
                              strokeWidth: 2))
                      : DropdownButtonFormField<String>(
                          value: _selectedTeacherId,
                          hint: const Text('Select a teacher'),
                          isExpanded: true,
                          decoration: _dec(),
                          items: _teachers.map((t) {
                            return DropdownMenuItem(
                              value: t.id,
                              child: Text(t.name,
                                  overflow: TextOverflow.ellipsis),
                            );
                          }).toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            final teacher = _teachers
                                .firstWhere((t) => t.id == v);
                            setState(() {
                              _selectedTeacherId   = v;
                              _selectedTeacherName = teacher.name;
                            });
                          },
                        ),
                  const SizedBox(height: 12),

                  // Priority
                  _SheetLabel('Priority'),
                  Row(children: [
                    for (final p in TaskPriority.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(p.label),
                          selected: _priority == p,
                          selectedColor:
                              _pColor(p).withOpacity(0.15),
                          labelStyle: TextStyle(
                            color: _priority == p
                                ? _pColor(p)
                                : Colors.grey.shade600,
                            fontWeight: _priority == p
                                ? FontWeight.w700
                                : FontWeight.normal,
                          ),
                          side: BorderSide(
                            color: _priority == p
                                ? _pColor(p)
                                : Colors.grey.shade300,
                          ),
                          onSelected: (_) =>
                              setState(() => _priority = p),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 12),

                  // Due date
                  _SheetLabel('Due Date (optional)'),
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
                            size: 18,
                            color: Colors.grey.shade500),
                        const SizedBox(width: 8),
                        Text(
                          _dueDate != null
                              ? _fmtDate(_dueDate!)
                              : 'Tap to select',
                          style: TextStyle(
                              fontSize: 13,
                              color: _dueDate != null
                                  ? Colors.grey.shade800
                                  : Colors.grey.shade400),
                        ),
                        const Spacer(),
                        if (_dueDate != null)
                          GestureDetector(
                            onTap: () =>
                                setState(() => _dueDate = null),
                            child: Icon(Icons.clear,
                                size: 16,
                                color: Colors.grey.shade400),
                          ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Submit
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(12)),
                      ),
                      child: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2))
                          : const Text('Assign Task',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _pColor(TaskPriority p) {
    switch (p) {
      case TaskPriority.high:   return AppTheme.danger;
      case TaskPriority.medium: return AppTheme.warning;
      case TaskPriority.low:    return AppTheme.success;
    }
  }

  InputDecoration _dec({String? hint}) => InputDecoration(
        hintText: hint,
        hintStyle:
            TextStyle(fontSize: 13, color: Colors.grey.shade400),
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

// ── Shared helpers ────────────────────────────────────────────────────────────

class _FChip extends StatelessWidget {
  final String       label;
  final bool         selected;
  final VoidCallback onTap;
  const _FChip(
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
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? Colors.white
                      : Colors.grey.shade600)),
        ),
      );
}

class _SheetLabel extends StatelessWidget {
  final String text;
  const _SheetLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600)),
      );
}

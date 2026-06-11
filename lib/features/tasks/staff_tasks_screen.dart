import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../l10n/app_strings.dart';
import '../../models/staff_task.dart';
import '../../services/auth_service.dart';
import '../../services/staff_task_service.dart';
import '../../shared/widgets/index_building_notice.dart';
import './task_badge_widgets.dart';
import './create_staff_task_screen.dart';

/// Teacher's personal task list — shows tasks assigned to this teacher only.
class StaffTasksScreen extends StatefulWidget {
  final String? teacherId;

  const StaffTasksScreen({super.key, this.teacherId});

  @override
  State<StaffTasksScreen> createState() => _StaffTasksScreenState();
}

class _StaffTasksScreenState extends State<StaffTasksScreen> {
  // Incrementing this key forces the StreamBuilder to re-subscribe on refresh.
  int _refreshTick = 0;
  String _email = '';
  String _role  = '';
  String _name  = '';

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final session = await AuthService().getSession();
    if (session != null && mounted) {
      setState(() {
        _email = (session['email'] as String? ?? '').toLowerCase();
        _role  = session['role'] as String? ?? '';
        _name  = session['name'] as String? ?? _email;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tid = widget.teacherId ?? '';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(context.tr('myTasks')),
        backgroundColor: AppTheme.primaryDark,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: tid.isEmpty
          ? _emptyState()
          : StreamBuilder<List<StaffTask>>(
              key: ValueKey(_refreshTick),
              stream: StaffTaskService().getTasksForTeacherStream(tid),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.primary));
                }
                if (snap.hasError && isIndexBuildingError(snap.error)) {
                  return IndexBuildingNotice(
                      onRetry: () => setState(() => _refreshTick++));
                }
                if (snap.hasError) {
                  return Center(
                      child: Text('Error: ${snap.error}',
                          style: TextStyle(color: Colors.grey.shade500)));
                }
                final tasks = snap.data ?? [];
                if (tasks.isEmpty) return _emptyState();
                return RefreshIndicator(
                  onRefresh: () async =>
                      setState(() => _refreshTick++),
                  color: AppTheme.primary,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: tasks.length,
                    itemBuilder: (_, i) => _TaskCard(
                      task: tasks[i],
                      currentEmail: _email,
                      currentRole: _role,
                      currentName: _name,
                      onStatusChange: (s) async {
                        await StaffTaskService()
                            .updateTaskStatus(tasks[i].id, s);
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _emptyState() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.task_alt_outlined,
              size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(context.tr('noTasksAssigned'),
              style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
          const SizedBox(height: 6),
          Text(context.tr('allCaughtUp'),
              style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
        ]),
      );
}

// ── Task card ─────────────────────────────────────────────────────────────────

class _TaskCard extends StatelessWidget {
  final StaffTask                task;
  final ValueChanged<TaskStatus> onStatusChange;
  final String                   currentEmail;
  final String                   currentRole;
  final String                   currentName;

  const _TaskCard({
    required this.task,
    required this.onStatusChange,
    this.currentEmail = '',
    this.currentRole = '',
    this.currentName = '',
  });

  @override
  Widget build(BuildContext context) {
    final overdue = task.isOverdue;

    return GestureDetector(
      onTap: () => _showDetail(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: overdue
              ? Border.all(color: AppTheme.danger.withValues(alpha: 0.5), width: 1.5)
              : null,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top row: title + priority badge + status chip ──
              Row(children: [
                Expanded(
                  child: Text(task.title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 6),
                TaskPriorityBadge(priority: task.priority),
                const SizedBox(width: 6),
                TaskStatusChip(status: task.status),
              ]),

              // ── Description ──
              if (task.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(task.description,
                    style: TextStyle(
                        fontSize: 12.5, color: Colors.grey.shade600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],

              const SizedBox(height: 10),
              Divider(height: 1, color: Colors.grey.shade100),
              const SizedBox(height: 8),

              // ── Bottom row: due date + assigned by ──
              Row(children: [
                if (task.dueDate != null) ...[
                  Icon(
                    Icons.event_outlined,
                    size: 13,
                    color: overdue ? AppTheme.danger : Colors.grey.shade400,
                  ),
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
                ] else ...[
                  Icon(Icons.event_outlined,
                      size: 13, color: Colors.grey.shade300),
                  const SizedBox(width: 4),
                  Text(context.tr('noDueDate'),
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade400)),
                ],
                const Spacer(),
                Icon(Icons.person_outline,
                    size: 12, color: Colors.grey.shade400),
                const SizedBox(width: 3),
                Text(task.assignedBy,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade400),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TaskDetailSheet(
        task: task,
        onStatusChange: onStatusChange,
        currentEmail: currentEmail,
        currentRole: currentRole,
        currentName: currentName,
      ),
    );
  }

  String _fmtDate(DateTime dt) {
    const mo = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${dt.day} ${mo[dt.month - 1]}';
  }
}

// ── Detail bottom sheet ───────────────────────────────────────────────────────

class _TaskDetailSheet extends StatelessWidget {
  final StaffTask                task;
  final ValueChanged<TaskStatus> onStatusChange;
  final String                   currentEmail;
  final String                   currentRole;
  final String                   currentName;

  const _TaskDetailSheet({
    required this.task,
    required this.onStatusChange,
    this.currentEmail = '',
    this.currentRole = '',
    this.currentName = '',
  });

  @override
  Widget build(BuildContext context) {
    final overdue = task.isOverdue;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(bottom: 14),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),

          // Title + badges
          Row(children: [
            Expanded(
              child: Text(task.title,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            TaskPriorityBadge(priority: task.priority),
            const SizedBox(width: 6),
            TaskStatusChip(status: task.status),
          ]),

          if (overdue) ...[
            const SizedBox(height: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppTheme.danger.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.warning_amber_outlined,
                    size: 15, color: AppTheme.danger),
                const SizedBox(width: 6),
                Text('OVERDUE by ${task.overdueDays} day(s)',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.danger)),
              ]),
            ),
          ],

          const SizedBox(height: 14),

          // Description
          if (task.description.isNotEmpty) ...[
            Text(task.description,
                style: TextStyle(
                    fontSize: 13.5, color: Colors.grey.shade700,
                    height: 1.5)),
            const SizedBox(height: 14),
          ],

          Divider(color: Colors.grey.shade100),
          const SizedBox(height: 10),

          // Meta info
          _MetaRow(
              icon: Icons.event_outlined,
              label: 'Due date',
              value: task.dueDate != null
                  ? _fmtDateFull(task.dueDate!)
                  : 'No due date'),
          const SizedBox(height: 6),
          _MetaRow(
              icon: Icons.person_outline,
              label: 'Assigned by',
              value: '${task.assignedBy} (${task.assignedByRole})'),
          const SizedBox(height: 6),
          _MetaRow(
              icon: Icons.calendar_today_outlined,
              label: 'Created',
              value: _fmtDateFull(task.createdAt)),
          if (task.classId.isNotEmpty) ...[
            const SizedBox(height: 6),
            _MetaRow(
                icon: Icons.class_outlined,
                label: 'Class',
                value: task.classId),
          ],

          const SizedBox(height: 20),

          // Creator-only: edit / delete the task you created (any role).
          if (currentEmail.isNotEmpty && task.createdBy == currentEmail) ...[
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CreateStaffTaskScreen(
                          schoolId: task.schoolId,
                          creatorEmail: currentEmail,
                          creatorRole: currentRole,
                          creatorName: currentName,
                          existing: task,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: const BorderSide(color: AppTheme.primary),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: Text(context.tr('deleteTaskTitle')),
                        content: Text(context.tr('deleteTaskPermanently')),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: Text(context.tr('cancel'))),
                          TextButton(
                            onPressed: () => Navigator.pop(c, true),
                            style: TextButton.styleFrom(
                                foregroundColor: AppTheme.danger),
                            child: Text(context.tr('delete')),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await StaffTaskService().deleteTask(task);
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Delete'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.danger,
                    side: BorderSide(
                        color: AppTheme.danger.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),
          ],

          // Status buttons
          if (task.status != TaskStatus.completed) ...[
            Row(children: [
              if (task.status == TaskStatus.pending)
                Expanded(
                  child: _ActionBtn(
                    label: 'Mark In Progress',
                    color: AppTheme.warning,
                    onTap: () {
                      Navigator.pop(context);
                      onStatusChange(TaskStatus.inProgress);
                    },
                  ),
                ),
              if (task.status == TaskStatus.pending)
                const SizedBox(width: 10),
              Expanded(
                child: _ActionBtn(
                  label: 'Mark Complete',
                  color: AppTheme.success,
                  onTap: () {
                    Navigator.pop(context);
                    onStatusChange(TaskStatus.completed);
                  },
                ),
              ),
            ]),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: _ActionBtn(
                label: 'Reopen',
                color: Colors.grey,
                onTap: () {
                  Navigator.pop(context);
                  onStatusChange(TaskStatus.pending);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _fmtDateFull(DateTime dt) {
    const mo = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${dt.day} ${mo[dt.month - 1]} ${dt.year}';
  }
}

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  const _MetaRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade400),
          const SizedBox(width: 6),
          Text('$label: ',
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w600)),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade700)),
          ),
        ],
      );
}

// TaskPriorityBadge and TaskStatusChip are in task_badge_widgets.dart

class _ActionBtn extends StatelessWidget {
  final String       label;
  final Color        color;
  final VoidCallback onTap;
  const _ActionBtn(
      {required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
        child: Text(label,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600)),
      );
}

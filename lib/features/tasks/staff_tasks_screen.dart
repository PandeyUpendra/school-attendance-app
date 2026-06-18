import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../theme.dart';
import '../../l10n/app_strings.dart';
import '../../models/staff_task.dart';
import '../../models/meeting.dart';
import '../../services/auth_service.dart';
import '../../services/staff_task_service.dart';
import '../../services/meeting_service.dart';
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
  late Stream<List<StaffTask>> _tasksStream;

  String _meetingFilter = 'All'; // All | Pending | Completed
  static const _meetingFilters = ['All', 'Pending', 'Completed'];

  @override
  void initState() {
    super.initState();
    _initStream();
    _loadUser();
  }

  void _initStream() {
    _tasksStream = StaffTaskService().getTasksForTeacherStream(widget.teacherId ?? '');
  }

  @override
  void didUpdateWidget(StaffTasksScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.teacherId != widget.teacherId) {
      _initStream();
    }
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

  List<MeetingTask> _applyMeetingFilter(List<MeetingTask> tasks) {
    if (_meetingFilter == 'Pending')   return tasks.where((t) => !t.isCompleted).toList();
    if (_meetingFilter == 'Completed') return tasks.where((t) =>  t.isCompleted).toList();
    return tasks;
  }

  String _fmtMeetingDate(DateTime d) {
    const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${mo[d.month - 1]} ${d.year}';
  }

  Future<void> _markMeetingTaskDone(MeetingTask task) async {
    await MeetingService().completeMeetingTask(
      meetingTaskId: task.id,
      staffTaskId:   task.staffTaskId,
      meetingId:     task.meetingId,
      pointTaskId:   task.id,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('taskMarkedComplete'))));
    }
  }

  Widget _buildStaffTasksTab(String tid) {
    if (tid.isEmpty) return _emptyState();
    return StreamBuilder<List<StaffTask>>(
      key: ValueKey(_refreshTick),
      stream: _tasksStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting &&
            !snap.hasData) {
          return const Center(
              child: CircularProgressIndicator(
                  color: AppTheme.primary));
        }
        if (snap.hasError && isIndexBuildingError(snap.error)) {
          return IndexBuildingNotice(
              onRetry: () => setState(() {
                _initStream();
                _refreshTick++;
              }));
        }
        if (snap.hasError) {
          return Center(
              child: Text(context.tr('errorWithDetailsSnap').replaceAll('{error}', snap.error.toString()),
                  style: TextStyle(color: Colors.grey.shade500)));
        }
        final tasks = snap.data ?? [];
        if (tasks.isEmpty) return _emptyState();
        return RefreshIndicator(
          onRefresh: () async {
            setState(() {
              _initStream();
              _refreshTick++;
            });
          },
          color: AppTheme.primary,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: tasks.length,
            itemBuilder: (_, i) => _StaffTaskCard(
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
    );
  }

  Widget _buildMeetingTasksTab(String tid) {
    if (tid.isEmpty) return _noMeetingsState();
    return Column(
      children: [
        // Filter chips
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: _meetingFilters.map((f) {
              final active = _meetingFilter == f;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(_localizedFilter(context, f)),
                  selected: active,
                  onSelected: (_) => setState(() => _meetingFilter = f),
                  selectedColor: AppTheme.primary,
                  labelStyle: TextStyle(
                      color: active ? Colors.white : Colors.black87,
                      fontSize: 12),
                  backgroundColor: Colors.white,
                  checkmarkColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: active ? AppTheme.primary : AppTheme.border,
                      width: 1,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        // Task list
        Expanded(
          child: StreamBuilder<List<MeetingTask>>(
            stream: MeetingService().streamTasksForTeacher(tid),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData) {
                return _buildMeetingShimmer();
              }
              if (snap.hasError && isIndexBuildingError(snap.error)) {
                return IndexBuildingNotice(onRetry: () => setState(() {}));
              }
              if (snap.hasError) {
                return _noMeetingsState();
              }

              final tasks    = _applyMeetingFilter(snap.data ?? []);
              final pending  = (snap.data ?? []).where((t) => !t.isCompleted).length;
              final total    = (snap.data ?? []).length;

              return RefreshIndicator(
                onRefresh: () async => setState(() {}),
                color: AppTheme.primary,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    if (total > 0) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: pending > 0
                              ? AppTheme.warning.withValues(alpha: 0.1)
                              : AppTheme.success.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: pending > 0
                                  ? AppTheme.warning.withValues(alpha: 0.3)
                                  : AppTheme.success.withValues(alpha: 0.2)),
                        ),
                        child: Row(children: [
                          Icon(
                            pending > 0
                                ? Icons.pending_outlined
                                : Icons.task_alt,
                            color: pending > 0
                                ? AppTheme.warning
                                : AppTheme.success,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            pending > 0
                                ? '$pending ${context.tr('pendingLower')} · ${total - pending} ${context.tr('completedLower')}'
                                : '${context.tr('filterAll')} $total ${context.tr('tasksCompletedLower')}',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: pending > 0
                                    ? AppTheme.warning
                                    : AppTheme.success),
                          ),
                        ]),
                      ),
                    ],

                    if (tasks.isEmpty)
                      _emptyMeetingState(pending, total)
                    else
                      ...tasks.map((t) => _MeetingTaskCard(
                            task:    t,
                            fmtDate: _fmtMeetingDate,
                            onMarkDone: t.isCompleted
                                ? null
                                : () => _markMeetingTaskDone(t),
                            meetingStream:
                                MeetingService().streamMeeting(t.meetingId),
                          )),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _localizedFilter(BuildContext c, String f) => switch (f) {
        'Pending' => c.tr('statusPending'),
        'Completed' => c.tr('completedLabel'),
        _ => c.tr('filterAll'),
      };

  Widget _buildMeetingShimmer() => Shimmer.fromColors(
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: 4,
          itemBuilder: (_, __) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            height: 130,
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(14)),
          ),
        ),
      );

  Widget _noMeetingsState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.event_busy_outlined,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              context.tr('noMeetingsAvailable'),
              style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
          ]),
        ),
      );

  Widget _emptyMeetingState(int pending, int total) => Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 80),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.assignment_outlined,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              _meetingFilter == 'Pending' && total > 0
                  ? context.tr('noPendingTasks')
                  : _meetingFilter == 'Completed' && total > 0
                      ? context.tr('noCompletedTasks')
                      : context.tr('noMeetingTasksAssigned'),
              style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 6),
            Text(
              context.tr('meetingTaskWillAppear'),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
              textAlign: TextAlign.center,
            ),
          ]),
        ),
      );


  @override
  Widget build(BuildContext context) {
    final tid = widget.teacherId ?? '';

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Text(context.tr('myTasks')),
          backgroundColor: AppTheme.primaryDark,
          foregroundColor: Colors.white,
          elevation: 0,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Staff Duties'),
              Tab(text: 'Meeting Decisions'),
            ],
            indicatorColor: Colors.white,
          ),
        ),
        body: TabBarView(
          children: [
            _buildStaffTasksTab(tid),
            _buildMeetingTasksTab(tid),
          ],
        ),
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

class _StaffTaskCard extends StatelessWidget {
  final StaffTask                task;
  final ValueChanged<TaskStatus> onStatusChange;
  final String                   currentEmail;
  final String                   currentRole;
  final String                   currentName;

  const _StaffTaskCard({
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

class _MeetingTaskCard extends StatefulWidget {
  final MeetingTask        task;
  final String Function(DateTime) fmtDate;
  final Future<void> Function()? onMarkDone;
  final Stream<Meeting?>   meetingStream;

  const _MeetingTaskCard({
    required this.task,
    required this.fmtDate,
    required this.onMarkDone,
    required this.meetingStream,
  });

  @override
  State<_MeetingTaskCard> createState() => _MeetingTaskCardState();
}

class _MeetingTaskCardState extends State<_MeetingTaskCard> {
  bool _expanded = false;
  bool _marking  = false;

  Color get _borderColor =>
      widget.task.isCompleted ? AppTheme.success : AppTheme.warning;

  @override
  Widget build(BuildContext context) {
    final t = widget.task;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: _borderColor, width: 4)),
      ),
      child: Column(children: [
        // ── Main content ──────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Title row
            Row(children: [
              Expanded(
                child: Text(t.meetingTitle,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(widget.fmtDate(t.meetingDate),
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary)),
              ),
            ]),
            const SizedBox(height: 4),
            Text('${context.tr('assignedByLabel')}: ${t.assignedBy}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),

            const SizedBox(height: 10),
            // Task text
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('"${t.pointText}"',
                  style: const TextStyle(
                      fontSize: 13.5, fontStyle: FontStyle.italic)),
            ),

            const SizedBox(height: 10),
            Row(children: [
              // Status chip
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: t.isCompleted
                      ? AppTheme.success.withValues(alpha: 0.1)
                      : AppTheme.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    t.isCompleted ? Icons.check_circle : Icons.pending_outlined,
                    size: 14,
                    color: t.isCompleted ? AppTheme.success : AppTheme.warning,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    t.isCompleted ? context.tr('completedLabel') : context.tr('statusPending'),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: t.isCompleted
                            ? AppTheme.success
                            : AppTheme.warning),
                  ),
                ]),
              ),
              const Spacer(),

              // Mark done button
              if (!t.isCompleted)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.success,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: _marking
                      ? const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.check, size: 15),
                  label: Text(context.tr('markAsDone'),
                      style: const TextStyle(fontSize: 12)),
                  onPressed: _marking
                      ? null
                      : () async {
                          setState(() => _marking = true);
                          try {
                            await widget.onMarkDone?.call();
                          } finally {
                            if (mounted) setState(() => _marking = false);
                          }
                        },
                ),
            ]),

            // ── Expand toggle ─────────────────────────────────────────────
            const SizedBox(height: 8),
            Divider(height: 1, color: Colors.grey.shade100),
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  Icon(Icons.info_outline,
                      size: 14, color: Colors.grey.shade400),
                  const SizedBox(width: 6),
                  Text(context.tr('meetingContext'),
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade500)),
                  const Spacer(),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                    color: Colors.grey.shade400,
                  ),
                ]),
              ),
            ),
          ]),
        ),

        // ── Expanded meeting context ───────────────────────────────────────
        if (_expanded)
          StreamBuilder<Meeting?>(
            stream: widget.meetingStream,
            builder: (context, snap) {
              if (snap.hasError && isIndexBuildingError(snap.error)) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: IndexBuildingNotice(onRetry: () => setState(() {})),
                );
              }
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                      child: SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppTheme.primary))),
                );
              }
              final m = snap.data;
              if (m == null) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(context.tr('meetingNotFound'),
                      style: TextStyle(color: Colors.grey.shade400)),
                );
              }

              return Container(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Divider(height: 1, color: Colors.grey.shade100),
                    const SizedBox(height: 10),
                    Text('${context.tr('fromMeeting')}: ${m.title}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    Text('${context.tr('dateLabel')}: ${widget.fmtDate(m.date)}',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500)),
                    const SizedBox(height: 10),
                    Text(context.tr('allAgendaPoints'),
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600)),
                    const SizedBox(height: 6),
                    ...m.points.asMap().entries.map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                e.value.isChecked
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                size: 15,
                                color: e.value.isChecked
                                    ? AppTheme.success
                                    : Colors.grey.shade400,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${e.key + 1}. ${e.value.text}',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: e.value.isChecked
                                        ? Colors.grey.shade400
                                        : Colors.black87,
                                    decoration: e.value.isChecked
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                              ),
                              if (e.value.convertedToTask)
                                const Icon(Icons.task_alt,
                                    size: 13, color: AppTheme.warning),
                            ],
                          ),
                        )),
                  ],
                ),
              );
            },
          ),
      ]),
    );
  }
}

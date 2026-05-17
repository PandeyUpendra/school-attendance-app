import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../models/meeting.dart';
import '../../services/meeting_service.dart';
import '../../theme.dart';

class TeacherMeetingTasksScreen extends StatefulWidget {
  final String teacherId;
  final String teacherName;

  const TeacherMeetingTasksScreen({
    super.key,
    required this.teacherId,
    required this.teacherName,
  });

  @override
  State<TeacherMeetingTasksScreen> createState() =>
      _TeacherMeetingTasksScreenState();
}

class _TeacherMeetingTasksScreenState
    extends State<TeacherMeetingTasksScreen> {
  final _svc = MeetingService();

  String _filter = 'All'; // All | Pending | Completed
  static const _filters = ['All', 'Pending', 'Completed'];

  List<MeetingTask> _applyFilter(List<MeetingTask> tasks) {
    if (_filter == 'Pending')   return tasks.where((t) => !t.isCompleted).toList();
    if (_filter == 'Completed') return tasks.where((t) =>  t.isCompleted).toList();
    return tasks;
  }

  String _fmtDate(DateTime d) {
    const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${mo[d.month - 1]} ${d.year}';
  }

  Future<void> _markDone(MeetingTask task) async {
    await _svc.completeMeetingTask(
      meetingTaskId: task.id,
      staffTaskId:   task.staffTaskId,
      meetingId:     task.meetingId,
      pointTaskId:   task.id, // meeting point stores the meetingTask ID as taskId
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task marked complete')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Meeting Tasks'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // ── Filter chips ─────────────────────────────────────────────────
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: _filters.map((f) {
                final active = _filter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(f),
                    selected: active,
                    onSelected: (_) => setState(() => _filter = f),
                    selectedColor: AppTheme.primary,
                    labelStyle: TextStyle(
                        color: active ? Colors.white : Colors.black87,
                        fontSize: 12),
                    backgroundColor: Colors.white,
                    checkmarkColor: Colors.white,
                  ),
                );
              }).toList(),
            ),
          ),

          // ── Task list ─────────────────────────────────────────────────────
          Expanded(
            child: StreamBuilder<List<MeetingTask>>(
              stream: _svc.streamTasksForTeacher(widget.teacherId),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return _buildShimmer();
                }
                if (snap.hasError) {
                  return Center(
                      child: Text('Error: ${snap.error}',
                          style: TextStyle(color: Colors.grey.shade500)));
                }

                final tasks    = _applyFilter(snap.data ?? []);
                final pending  = (snap.data ?? []).where((t) => !t.isCompleted).length;
                final total    = (snap.data ?? []).length;

                return RefreshIndicator(
                  onRefresh: () async => setState(() {}),
                  color: AppTheme.primary,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      // Summary chip
                      if (total > 0) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: pending > 0
                                ? AppTheme.warning.withOpacity(0.1)
                                : AppTheme.success.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: pending > 0
                                    ? AppTheme.warning.withOpacity(0.3)
                                    : AppTheme.success.withOpacity(0.2)),
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
                                  ? '$pending pending · ${total - pending} completed'
                                  : 'All $total tasks completed',
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
                        _emptyState(pending, total)
                      else
                        ...tasks.map((t) => _TaskCard(
                              task:    t,
                              fmtDate: _fmtDate,
                              onMarkDone: t.isCompleted
                                  ? null
                                  : () => _markDone(t),
                              meetingStream:
                                  _svc.streamMeeting(t.meetingId),
                            )),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmer() => Shimmer.fromColors(
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

  Widget _emptyState(int pending, int total) => Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 80),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.assignment_outlined,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              _filter != 'All' && total > 0
                  ? 'No ${_filter.toLowerCase()} tasks'
                  : 'No meeting tasks assigned',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 6),
            Text(
              'When a coordinator assigns a meeting task to you, it will appear here.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
              textAlign: TextAlign.center,
            ),
          ]),
        ),
      );
}

// ── Task card ─────────────────────────────────────────────────────────────────

class _TaskCard extends StatefulWidget {
  final MeetingTask        task;
  final String Function(DateTime) fmtDate;
  final Future<void> Function()? onMarkDone;
  final Stream<Meeting?>   meetingStream;

  const _TaskCard({
    required this.task,
    required this.fmtDate,
    required this.onMarkDone,
    required this.meetingStream,
  });

  @override
  State<_TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<_TaskCard> {
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
                  color: AppTheme.primaryLight.withOpacity(0.3),
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
            Text('Assigned by: ${t.assignedBy}',
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
                      ? AppTheme.success.withOpacity(0.1)
                      : AppTheme.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    t.isCompleted ? Icons.check_circle : Icons.pending_outlined,
                    size: 14,
                    color: t.isCompleted ? AppTheme.success : AppTheme.warning,
                  ),
                  const SizedBox(width: 4),
                  Text(t.status,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: t.isCompleted
                              ? AppTheme.success
                              : AppTheme.warning)),
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
                  label: const Text('Mark as Done',
                      style: TextStyle(fontSize: 12)),
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
                  Text('Meeting context',
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
                  child: Text('Meeting not found',
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
                    Text('From Meeting: ${m.title}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    Text('Date: ${widget.fmtDate(m.date)}',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500)),
                    const SizedBox(height: 10),
                    Text('All agenda points:',
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

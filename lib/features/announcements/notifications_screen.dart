import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/teacher.dart';
import '../../models/student.dart';
import '../../services/notification_service.dart';
import '../../services/student_service.dart';
import '../../theme.dart';
import '../../l10n/app_strings.dart';
import './announcements_screen.dart';
import '../leave/leave_application_screen.dart';
import '../leave/leave_requests_screen.dart';
import '../tasks/staff_tasks_screen.dart';
import '../substitution/substitution_history_screen.dart';
import '../meeting/teacher_meeting_tasks_screen.dart';
import '../leave/guardian_leave_application_screen.dart';
import '../students/staff_remarks_screen.dart';

class NotificationsScreen extends StatefulWidget {
  final String   role;
  final String?  teacherId;
  final String?  studentClass;
  final int?     studentRoll;
  final String?  studentAdmissionId;
  final Student? student;
  final Teacher? teacher;

  const NotificationsScreen({
    super.key,
    required this.role,
    this.teacherId,
    this.studentClass,
    this.studentRoll,
    this.studentAdmissionId,
    this.student,
    this.teacher,
  });

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _service = NotificationService();
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];
  StreamSubscription? _sub;
  int _lastSeenMs = 0;
  String? _myEmail;
  String? _myName;
  String? _myTeacherId;

  // ── Multi-select state ────────────────────────────────────────────────────
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _lastSeenMs = prefs.getInt('notif_last_seen_ms') ?? 0;
    _myEmail = prefs.getString('auth_email');
    _myName = prefs.getString('auth_name');
    _myTeacherId = prefs.getString('auth_teacher_id');

    _sub = _service
        .streamFor(
          role:               widget.role,
          teacherId:          widget.teacherId,
          studentClass:       widget.studentClass,
          studentRoll:        widget.studentRoll,
          studentAdmissionId: widget.studentAdmissionId,
        )
        .listen((items) {
      if (!mounted) return;
      setState(() {
        _items   = items;
        _loading = false;
        // Drop any selected IDs that no longer exist.
        final liveIds = items.map((n) => n['id'] as String? ?? '').toSet();
        _selectedIds.removeWhere((id) => !liveIds.contains(id));
        if (_selectedIds.isEmpty) _selectionMode = false;
      });
    }, onError: (_) {
      if (mounted) setState(() => _loading = false);
    });

    await _service.markAllSeen();
  }

  bool _isUnread(Map<String, dynamic> n) {
    final ts = n['createdAt'];
    if (ts is! Timestamp) return false;
    return ts.toDate().millisecondsSinceEpoch > _lastSeenMs;
  }

  // ── Selection helpers ─────────────────────────────────────────────────────

  void _enterSelectionMode(String id) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(id);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll() {
    setState(() {
      for (final n in _items) {
        final id = n['id'] as String?;
        if (id != null) _selectedIds.add(id);
      }
    });
  }

  bool get _allSelected =>
      _items.isNotEmpty &&
      _items.every((n) => _selectedIds.contains(n['id'] as String? ?? ''));

  // ── Delete actions ────────────────────────────────────────────────────────

  Future<void> _deleteOne(Map<String, dynamic> n) async {
    final id = n['id'] as String?;
    if (id == null) return;
    await _service.deleteNotification(id: id);
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete $count Notification${count > 1 ? 's' : ''}'),
        content: Text(
            'Remove $count selected notification${count > 1 ? 's' : ''}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr('cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _service.deleteAll(_selectedIds.toList());
    if (mounted) _exitSelectionMode();
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.tr('clearAllNotifications')),
        content: const Text(
            'Delete all notifications? This removes them for everyone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr('cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(context.tr('clearAll')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final ids = _items
        .map((n) => n['id'] as String?)
        .whereType<String>()
        .toList();
    await _service.deleteAll(ids);
    if (mounted) _exitSelectionMode();
  }

  Future<void> _markAllRead() async {
    await _service.markAllSeen();
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _lastSeenMs = prefs.getInt('notif_last_seen_ms') ?? 0);
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  bool _hasRoute(String type) {
    switch (type) {
      case 'leave_submitted':
        return widget.role == 'coordinator' || widget.role == 'principal';
      case 'leave_resolved':
        return widget.teacher != null;
      case 'announcement':
        return true;
      case 'staff_task':
      case 'task':
        return widget.teacherId != null;
      case 'staff_remark':
        return true;
      case 'substitution_assigned':
      case 'meeting_task':
        return widget.role == 'teacher';
      case 'absent':
        return widget.role == 'guardian';
      default:
        return false;
    }
  }

  Future<void> _handleTap(Map<String, dynamic> n) async {
    if (!mounted) return;
    final type = (n['type'] as String?) ?? '';

    switch (type) {
      case 'leave_submitted':
        if (widget.role == 'coordinator' || widget.role == 'principal') {
          await Navigator.push(context, MaterialPageRoute(
            builder: (_) => LeaveRequestsScreen(viewerRole: widget.role),
          ));
        }
        break;

      case 'leave_resolved':
        final t = widget.teacher;
        if (t != null) {
          await Navigator.push(context, MaterialPageRoute(
            builder: (_) => LeaveApplicationScreen(teacher: t),
          ));
        }
        break;

      case 'announcement':
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => AnnouncementsScreen(
            viewerRole: widget.role,
            posterName: widget.teacher?.email,
          ),
        ));
        break;

      case 'staff_task':
      case 'task':
        if (widget.teacherId != null) {
          await Navigator.push(context, MaterialPageRoute(
            builder: (_) => StaffTasksScreen(teacherId: widget.teacherId),
          ));
        }
        break;

      case 'staff_remark':
        final email = _myEmail ?? widget.teacher?.email ?? '';
        final name = _myName ?? widget.teacher?.name ?? '';
        final tid = widget.teacherId ?? widget.teacher?.id ?? _myTeacherId;
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => StaffRemarksScreen(
            role: widget.role,
            userEmail: email,
            userName: name,
            teacherId: tid,
          ),
        ));
        break;

      case 'substitution_assigned':
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => SubstitutionHistoryScreen(
            teacherId:   widget.teacherId,
            teacherName: widget.teacher?.name,
          ),
        ));
        break;

      case 'meeting_task':
        final tid = widget.teacherId;
        if (tid != null && tid.isNotEmpty) {
          await Navigator.push(context, MaterialPageRoute(
            builder: (_) => TeacherMeetingTasksScreen(
              teacherId:   tid,
              teacherName: widget.teacher?.name ?? '',
            ),
          ));
        }
        break;

      case 'absent':
        if (widget.role == 'guardian') {
          var s = widget.student;
          if (s == null && widget.studentClass != null && widget.studentRoll != null) {
            s = await StudentService.instance.getStudentByRoll(
              widget.studentClass!,
              widget.studentRoll!,
            );
          }
          if (s != null && mounted) {
            await Navigator.push(context, MaterialPageRoute(
              builder: (_) => GuardianLeaveApplicationScreen(student: s!),
            ));
          }
        }
        break;
    }
  }

  // ── Display helpers ───────────────────────────────────────────────────────

  IconData _iconFor(Map<String, dynamic> n) {
    final type   = (n['type'] as String?) ?? '';
    final status = (n['status'] as String?) ?? '';
    switch (type) {
      case 'absent':                return Icons.cancel_outlined;
      case 'leave_submitted':       return Icons.event_busy_outlined;
      case 'leave_resolved':
        return status == 'rejected'
            ? Icons.cancel_outlined
            : Icons.task_alt_outlined;
      case 'announcement':          return Icons.campaign_outlined;
      case 'staff_task':            return Icons.assignment_outlined;
      case 'substitution_assigned': return Icons.swap_horiz_outlined;
      case 'meeting_task':          return Icons.groups_outlined;
      case 'staff_remark':          return Icons.rate_review_outlined;
      default:                      return Icons.notifications_outlined;
    }
  }

  Color _colorFor(Map<String, dynamic> n) {
    final type   = (n['type'] as String?) ?? '';
    final status = (n['status'] as String?) ?? '';
    switch (type) {
      case 'absent':                return Colors.red;
      case 'leave_submitted':       return Colors.orange;
      case 'leave_resolved':
        return status == 'rejected' ? Colors.red : Colors.green;
      case 'announcement':          return Colors.deepOrange;
      case 'staff_task':            return AppTheme.primary;
      case 'substitution_assigned': return AppTheme.primaryMid;
      case 'meeting_task':          return AppTheme.primary;
      case 'staff_remark':          return Colors.purple;
      default:                      return AppTheme.primary;
    }
  }

  String _when(dynamic ts) {
    if (ts is! Timestamp) return '';
    final d    = ts.toDate();
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours   < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays    < 1) return '${diff.inHours}h ago';
    if (diff.inDays    < 7) return '${diff.inDays}d ago';
    return '${d.day}/${d.month}/${d.year}';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasUnread = _items.any(_isUnread);

    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectionMode) _exitSelectionMode();
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: _selectionMode
            ? _buildSelectionAppBar()
            : _buildNormalAppBar(hasUnread),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? _buildEmpty()
                : _buildList(),
      ),
    );
  }

  AppBar _buildNormalAppBar(bool hasUnread) => AppBar(
        title: Text(context.tr('notifications'),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: _markAllRead,
              child: Text(context.tr('markAllRead'),
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ),
          if (_items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.checklist_outlined),
              tooltip: 'Select notifications',
              onPressed: () {
                final firstId = _items.first['id'] as String?;
                if (firstId != null) _enterSelectionMode(firstId);
              },
            ),
          if (_items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Clear all',
              onPressed: _clearAll,
            ),
        ],
      );

  AppBar _buildSelectionAppBar() {
    final count = _selectedIds.length;
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _exitSelectionMode,
      ),
      title: Text(
        count == 0 ? 'Select notifications' : '$count selected',
        style:
            const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
      ),
      actions: [
        // Select / deselect all
        TextButton(
          onPressed: _allSelected ? _exitSelectionMode : _selectAll,
          child: Text(
            _allSelected ? context.tr('deselectAll') : context.tr('selectAll'),
            style:
                const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        // Delete selected
        if (count > 0)
          IconButton(
            icon: const Icon(Icons.delete_outlined),
            tooltip: 'Delete selected',
            onPressed: _deleteSelected,
          ),
      ],
    );
  }

  Widget _buildEmpty() => ListView(children: [
        const SizedBox(height: 100),
        Icon(Icons.notifications_none,
            size: 64, color: Colors.grey.shade300),
        const SizedBox(height: 14),
        Center(
          child: Text(context.tr('noNotificationsYet'),
              style:
                  TextStyle(fontSize: 14, color: Colors.grey.shade500)),
        ),
      ]);

  Widget _buildList() => ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final n      = _items[i];
          final id     = (n['id'] as String?) ?? '';
          final type   = (n['type'] as String?) ?? '';
          final color  = _colorFor(n);
          final unread = _isUnread(n);
          final routed = _hasRoute(type);
          final selected = _selectedIds.contains(id);

          // NOTE: a coloured left border (unread/selected accent) makes the
          // Border NON-uniform. Flutter forbids `borderRadius` on a non-uniform
          // border and throws "A borderRadius can only be given on borders with
          // uniform colors." during paint — which blanked the whole list the
          // moment any unread notification appeared. Fix: round the corners with
          // an outer ClipRRect and keep the BoxDecoration border radius-free.
          final card = ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Ink(
            decoration: BoxDecoration(
              color: selected
                  ? AppTheme.primary.withValues(alpha: 0.08)
                  : unread
                      ? AppTheme.primary.withValues(alpha: 0.05)
                      : Colors.white,
              border: Border(
                left: BorderSide(
                  color: selected
                      ? AppTheme.primary
                      : unread
                          ? AppTheme.accent
                          : Colors.grey.shade200,
                  width: (selected || unread) ? 3.5 : 1,
                ),
                top:    BorderSide(color: Colors.grey.shade200),
                right:  BorderSide(color: Colors.grey.shade200),
                bottom: BorderSide(color: Colors.grey.shade200),
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onLongPress: id.isEmpty
                  ? null
                  : () => _selectionMode
                      ? _toggleSelection(id)
                      : _enterSelectionMode(id),
              onTap: _selectionMode
                  ? (id.isEmpty ? null : () => _toggleSelection(id))
                  : (routed ? () => _handleTap(n) : null),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Leading: checkbox in select mode, icon otherwise
                    if (_selectionMode)
                      Padding(
                        padding: const EdgeInsets.only(right: 12, top: 2),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: selected
                              ? const Icon(Icons.check_circle,
                                  key: ValueKey(true),
                                  color: AppTheme.primary,
                                  size: 24)
                              : Icon(Icons.radio_button_unchecked,
                                  key: const ValueKey(false),
                                  color: Colors.grey.shade400,
                                  size: 24),
                        ),
                      )
                    else
                      Container(
                        width: 40, height: 40,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(_iconFor(n), color: color, size: 22),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                              child: Text(
                                (n['title'] as String?) ?? '',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: unread
                                        ? FontWeight.w700
                                        : FontWeight.w600),
                              ),
                            ),
                            if (unread && !_selectionMode)
                              Container(
                                width: 8, height: 8,
                                decoration: const BoxDecoration(
                                  color: AppTheme.accent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ]),
                          const SizedBox(height: 3),
                          Text(
                            (n['body'] as String?) ?? '',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700),
                          ),
                          const SizedBox(height: 6),
                          Text(_when(n['createdAt']),
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade500)),
                        ],
                      ),
                    ),
                    if (routed && !_selectionMode) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right,
                          color: Colors.grey.shade300, size: 20),
                    ],
                  ],
                ),
              ),
            ),
          ),
          );

          // Swipe-to-dismiss only when not in selection mode
          if (_selectionMode) return card;

          return Dismissible(
            key: ValueKey(n['id'] ?? i),
            direction: DismissDirection.endToStart,
            // Notification docs are shared across an audience, so a swipe deletes
            // it for everyone — confirm before dismissing (#69).
            confirmDismiss: (_) async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(context.tr('deleteNotificationQ')),
                  content: Text(context.tr('deleteNotificationBody')),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(context.tr('cancel'))),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: Text(context.tr('delete')),
                    ),
                  ],
                ),
              );
              return ok == true;
            },
            onDismissed: (_) => _deleteOne(n),
            background: Container(
              margin: const EdgeInsets.only(left: 40),
              decoration: BoxDecoration(
                color: Colors.red.shade400,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              child: const Icon(Icons.delete_outline,
                  color: Colors.white, size: 26),
            ),
            child: card,
          );
        },
      );
}

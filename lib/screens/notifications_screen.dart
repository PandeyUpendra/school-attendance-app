import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import '../services/auth_service.dart';
import '../services/timetable_service.dart';
import '../theme.dart';
import 'leave_requests_screen.dart';
import 'announcements_screen.dart';
import 'task_status_screen.dart';
import 'teacher_tasks_screen.dart';
import 'daily_calls_screen.dart';
import 'leave_application_screen.dart';
import 'class_picker_screen.dart';
import 'tasks/staff_task_detail_screen.dart';
import 'tasks/staff_task_management_screen.dart';

class NotificationsScreen extends StatefulWidget {
  final String  role;
  final String? teacherId;
  final String? studentClass;
  final int?    studentRoll;

  const NotificationsScreen({
    super.key,
    required this.role,
    this.teacherId,
    this.studentClass,
    this.studentRoll,
  });

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _service = NotificationService();
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];
  String? _userEmail;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _canDelete => widget.role == 'principal';

  Future<void> _deleteOne(Map<String, dynamic> n) async {
    final id = n['id'] as String?;
    if (id == null) return;
    setState(() => _items.remove(n));
    await _service.deleteNotification(id: id);
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear All Notifications'),
        content: const Text(
            'Delete all notifications? This removes them for everyone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final ids = _items
        .map((n) => n['id'] as String?)
        .whereType<String>()
        .toList();
    setState(() => _items.clear());
    for (final id in ids) {
      await _service.deleteNotification(id: id);
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final session = await AuthService().getSession();
    _userEmail = session?['email'];

    final items = await _service.getFor(
      role: widget.role,
      teacherId: widget.teacherId,
      studentClass: widget.studentClass,
      studentRoll: widget.studentRoll,
      userEmail: _userEmail,
    );
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
    // Mark "all seen" so the dashboard badge clears.
    await _service.markAllSeen();
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'absent':          return Icons.cancel_outlined;
      case 'leave_submitted': return Icons.event_busy_outlined;
      case 'leave_resolved':  return Icons.task_alt_outlined;
      case 'announcement':    return Icons.campaign_outlined;
      case 'task':            return Icons.assignment_outlined;
      case 'staff_task':      return Icons.assignment_turned_in_outlined;
      case 'staff_task_reminder': return Icons.alarm;
      default:                return Icons.notifications_outlined;
    }
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'absent':          return Colors.red;
      case 'leave_submitted': return Colors.orange;
      case 'leave_resolved':  return Colors.green;
      case 'announcement':    return Colors.deepOrange;
      case 'task':            return Colors.blue;
      case 'staff_task':      return AppTheme.primary;
      case 'staff_task_reminder': return Colors.red;
      default:                return AppTheme.primary;
    }
  }

  String _when(dynamic ts) {
    if (ts is! Timestamp) return '';
    final d = ts.toDate();
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours   < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays    < 1) return '${diff.inHours}h ago';
    if (diff.inDays    < 7) return '${diff.inDays}d ago';
    return '${d.day}/${d.month}/${d.year}';
  }

  Future<void> _handleTap(Map<String, dynamic> n) async {
    final type = (n['type'] as String?) ?? '';
    if (!mounted) return;

    switch (type) {
      case 'leave_submitted':
        if (widget.role == 'coordinator' || widget.role == 'principal') {
          Navigator.push(context, MaterialPageRoute(builder: (_) =>
              LeaveRequestsScreen(viewerRole: widget.role)));
        }
        break;

      case 'announcement':
        Navigator.push(context, MaterialPageRoute(builder: (_) =>
            AnnouncementsScreen(
              viewerRole:  widget.role,
              viewerClass: widget.studentClass,
            )));
        break;

      case 'task':
        if (widget.role == 'coordinator' || widget.role == 'principal') {
          final session = await AuthService().getSession();
          if (!mounted) return;
          Navigator.push(context, MaterialPageRoute(builder: (_) =>
              TaskStatusScreen(
                createdByEmail: session?['email'] ?? '',
                isAdmin: true,
              )));
        } else if (widget.role == 'teacher') {
          if (widget.teacherId != null) {
            final t = await TimetableService().getTeacherById(id: widget.teacherId!);
            if (t != null && t.classTeacherOf != null && mounted) {
              Navigator.push(context, MaterialPageRoute(builder: (_) =>
                  TeacherTasksScreen(
                    className: t.classTeacherOf!,
                    section:   t.section,
                  )));
            } else if (mounted) {
              // Subject teacher — need to pick a class
              final pick = await Navigator.push<ClassSectionPick>(
                context,
                MaterialPageRoute(
                    builder: (_) => const ClassPickerScreen(
                        mode: ClassPickerMode.studentList)),
              );
              if (pick != null && mounted) {
                Navigator.push(context, MaterialPageRoute(builder: (_) =>
                    TeacherTasksScreen(
                      className: pick.className,
                      section:   pick.section,
                    )));
              }
            }
          }
        }
        break;

      case 'absent':
        if (widget.role == 'teacher' && widget.teacherId != null) {
          final t = await TimetableService().getTeacherById(id: widget.teacherId!);
          if (t != null && t.isClassTeacher && mounted) {
            Navigator.push(context, MaterialPageRoute(builder: (_) =>
                DailyCallsScreen(teacher: t)));
          }
        }
        break;

      case 'leave_resolved':
        if (widget.role == 'teacher' && widget.teacherId != null) {
          final t = await TimetableService().getTeacherById(id: widget.teacherId!);
          if (t != null && mounted) {
            Navigator.push(context, MaterialPageRoute(builder: (_) =>
                LeaveApplicationScreen(teacher: t)));
          }
        }
        break;

      case 'staff_task':
      case 'staff_task_reminder':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const StaffTaskManagementScreen()));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Notifications',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        actions: _canDelete && _items.isNotEmpty
            ? [
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined),
                  tooltip: 'Clear all',
                  onPressed: _clearAll,
                ),
              ]
            : null,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppTheme.primary,
        child: _loading
            ? ListView(children: const [
                SizedBox(height: 120),
                Center(child: CircularProgressIndicator()),
              ])
            : _items.isEmpty
                ? ListView(children: [
                    const SizedBox(height: 100),
                    Icon(Icons.notifications_none,
                        size: 64, color: Colors.grey.shade300),
                    const SizedBox(height: 14),
                    Center(
                      child: Text('No notifications yet',
                          style: TextStyle(
                              fontSize: 14, color: Colors.grey.shade500)),
                    ),
                  ])
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(12),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final n     = _items[i];
                      final type  = (n['type'] as String?) ?? '';
                      final color = _colorFor(type);
                      final card  = InkWell(
                        onTap: () => _handleTap(n),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 40, height: 40,
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(_iconFor(type),
                                    color: color, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (n['title'] as String?) ?? '',
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600),
                                    ),
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
                            ],
                          ),
                        ),
                      );

                      if (!_canDelete) return card;

                      return Dismissible(
                        key: ValueKey(n['id'] ?? i),
                        direction: DismissDirection.endToStart,
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
                  ),
      ),
    );
  }
}

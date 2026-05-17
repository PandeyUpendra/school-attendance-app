import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';
import '../theme.dart';

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
  StreamSubscription? _sub;
  int _lastSeenMs = 0;

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

    _sub = _service
        .streamFor(
          role:         widget.role,
          teacherId:    widget.teacherId,
          studentClass: widget.studentClass,
          studentRoll:  widget.studentRoll,
        )
        .listen((items) {
      if (!mounted) return;
      setState(() {
        _items   = items;
        _loading = false;
      });
    }, onError: (_) {
      if (mounted) setState(() => _loading = false);
    });

    // Mark all seen so the badge on the calling screen clears on pop.
    await _service.markAllSeen();
  }

  bool get _canDelete => widget.role == 'principal' ||
      widget.role == 'owner' || widget.role == 'ownerPrincipal';

  bool _isUnread(Map<String, dynamic> n) {
    final ts = n['createdAt'];
    if (ts is! Timestamp) return false;
    return ts.toDate().millisecondsSinceEpoch > _lastSeenMs;
  }

  Future<void> _deleteOne(Map<String, dynamic> n) async {
    final id = n['id'] as String?;
    if (id == null) return;
    await _service.deleteNotification(id: id);
    // Stream auto-updates _items.
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
    await _service.deleteAll(ids);
    // Stream auto-updates _items.
  }

  Future<void> _markAllRead() async {
    await _service.markAllSeen();
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _lastSeenMs = prefs.getInt('notif_last_seen_ms') ?? 0);
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'absent':           return Icons.cancel_outlined;
      case 'leave_submitted':  return Icons.event_busy_outlined;
      case 'leave_resolved':   return Icons.task_alt_outlined;
      case 'announcement':     return Icons.campaign_outlined;
      case 'staff_task':       return Icons.assignment_outlined;
      case 'substitution_assigned': return Icons.swap_horiz_outlined;
      default:                 return Icons.notifications_outlined;
    }
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'absent':           return Colors.red;
      case 'leave_submitted':  return Colors.orange;
      case 'leave_resolved':   return Colors.green;
      case 'announcement':     return Colors.deepOrange;
      case 'staff_task':       return AppTheme.primary;
      case 'substitution_assigned': return AppTheme.primaryMid;
      default:                 return AppTheme.primary;
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

  @override
  Widget build(BuildContext context) {
    final hasUnread = _items.any(_isUnread);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Notifications',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
            ),
          if (_canDelete && _items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Clear all',
              onPressed: _clearAll,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
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
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final n      = _items[i];
                    final type   = (n['type'] as String?) ?? '';
                    final color  = _colorFor(type);
                    final unread = _isUnread(n);

                    final card = Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: unread
                            ? AppTheme.primary.withOpacity(0.05)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border(
                          left: BorderSide(
                            color: unread
                                ? AppTheme.accent
                                : Colors.grey.shade200,
                            width: unread ? 3.5 : 1,
                          ),
                          top:    BorderSide(color: Colors.grey.shade200),
                          right:  BorderSide(color: Colors.grey.shade200),
                          bottom: BorderSide(color: Colors.grey.shade200),
                        ),
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
                                  if (unread)
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
                        ],
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
    );
  }
}

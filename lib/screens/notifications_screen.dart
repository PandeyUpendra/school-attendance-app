import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/notification_service.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await _service.getFor(
      role: widget.role,
      teacherId: widget.teacherId,
      studentClass: widget.studentClass,
      studentRoll: widget.studentRoll,
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
      default:                return Icons.notifications_outlined;
    }
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'absent':          return Colors.red;
      case 'leave_submitted': return Colors.orange;
      case 'leave_resolved':  return Colors.green;
      case 'announcement':    return Colors.deepOrange;
      default:                return Colors.indigo;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Notifications',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: Colors.indigo,
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
                      final n = _items[i];
                      final type = (n['type'] as String?) ?? '';
                      final color = _colorFor(type);
                      return Container(
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
                      );
                    },
                  ),
      ),
    );
  }
}

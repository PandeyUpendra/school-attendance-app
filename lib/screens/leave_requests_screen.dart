import 'package:flutter/material.dart';
import '../services/timetable_service.dart';
import '../services/notification_service.dart';
import '../services/base_firestore_service.dart';
import 'free_bells_screen.dart';
import 'substitution_plan_screen.dart';
import '../theme.dart';

class LeaveRequestsScreen extends StatefulWidget {
  /// 'principal' | 'coordinator'
  final String viewerRole;

  const LeaveRequestsScreen({
    super.key,
    this.viewerRole = 'coordinator',
  });

  @override
  State<LeaveRequestsScreen> createState() => _LeaveRequestsScreenState();
}

class _LeaveRequestsScreenState extends State<LeaveRequestsScreen>
    with SingleTickerProviderStateMixin {
  final _service = TimetableService();
  late final TabController _tabCtrl;
  List<Map<String, dynamic>> _pending  = [];
  List<Map<String, dynamic>> _resolved = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final all = await _service.getLeaveApplications();
    if (!mounted) return;
    setState(() {
      _pending  = all.where((a) => a['status'] == 'pending').toList();
      _resolved = all.where((a) => a['status'] != 'pending').toList();
      _loading  = false;
    });
  }

  Future<void> _act(Map<String, dynamic> app, String status) async {
    final id          = app['id']          as String;
    final teacherId   = app['teacherId']   as String? ?? '';
    final teacherName = app['teacherName'] as String? ?? '';
    await _service.updateLeaveApplication(BaseFirestoreService.currentSchoolId ?? 'default_school', id, status);
    if (teacherId.isNotEmpty &&
        (status == 'approved' || status == 'rejected')) {
      NotificationService().addLeaveResolved(
        teacherId:   teacherId,
        teacherName: teacherName,
        status:      status,
      );
    }
    _load();
    if (!mounted) return;
    if (status == 'approved') {
      // Jump straight into the smart substitution plan for this leave.
      final startStr = app['startDate'] as String? ?? '';
      final start    = DateTime.tryParse(startStr);
      final days     = (app['numberOfDays'] as num?)?.toInt() ?? 1;

      if (teacherId.isNotEmpty && start != null) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SubstitutionPlanScreen(
              teacherId:    teacherId,
              teacherName:  teacherName,
              startDate:    start,
              numberOfDays: days,
            ),
          ),
        );
      } else {
        // Fallback when teacher/start is missing — fall back to Free Bells.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text(
              'Leave approved. Use Free Bells screen to assign substitutes.'),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Free Bells',
            textColor: Colors.white,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FreeBellsScreen()),
            ),
          ),
        ));
      }
    } else if (status == 'forwarded_to_principal') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Leave request forwarded to Principal.'),
        backgroundColor: Colors.indigo,
        duration: Duration(seconds: 3),
      ));
    }
  }

  Future<void> _showDetail(Map<String, dynamic> app) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _LeaveDetailSheet(
        app:        app,
        viewerRole: widget.viewerRole,
        onAction: (id, status) async {
          await _act(app, status);
          if (mounted) Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Leave Requests',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text('Teacher leave applications',
                style: TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: [
            Tab(
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text('Pending'),
                if (_pending.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${_pending.length}',
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ]),
            ),
            const Tab(text: 'Resolved'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _buildList(_pending, showActions: true),
                _buildList(_resolved, showActions: false),
              ],
            ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> apps, {required bool showActions}) {
    if (apps.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.event_available_outlined,
              size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(showActions ? 'No pending requests' : 'No resolved requests',
              style: TextStyle(
                  fontSize: 15, color: Colors.grey.shade400)),
        ]),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: apps.length,
        itemBuilder: (_, i) => _LeaveCard(
          app: apps[i],
          statusLabel: _fmtStatus(apps[i]['status'] as String? ?? 'pending', widget.viewerRole),
          onTap: () => _showDetail(apps[i]),
          onAccept: showActions ? () => _act(apps[i], 'approved')  : null,
          onReject: showActions ? () => _act(apps[i], 'rejected')  : null,
          onForward: showActions
              ? () => _act(apps[i], 'forwarded_to_principal')
              : null,
        ),
      ),
    );
  }
}

// ── Leave card ────────────────────────────────────────────────────────────────

class _LeaveCard extends StatelessWidget {
  final Map<String, dynamic> app;
  final String statusLabel;
  final VoidCallback onTap;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onForward;

  const _LeaveCard({
    required this.app,
    required this.statusLabel,
    required this.onTap,
    this.onAccept,
    this.onReject,
    this.onForward,
  });

  @override
  Widget build(BuildContext context) {
    final status = app['status'] as String? ?? 'pending';
    final statusColor = switch (status) {
      'approved' => Colors.green,
      'rejected' => Colors.red,
      _           => Colors.orange,
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: statusColor.withOpacity(0.25)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.deepPurple.shade50,
              child: Text(
                (app['teacherName'] as String? ?? 'T')[0].toUpperCase(),
                style: TextStyle(
                    color: Colors.deepPurple.shade700,
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(app['teacherName'] as String? ?? '—',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold)),
                Text(app['teacherEmail'] as String? ?? '',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500)),
              ],
            )),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: statusColor.withOpacity(0.4)),
              ),
              child: Text(statusLabel,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: statusColor)),
            ),
          ]),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(children: [
            _chip(Icons.calendar_today_outlined,
                _formatDate(app['startDate'] as String? ?? ''),
                AppTheme.primary),
            const SizedBox(width: 8),
            _chip(Icons.access_time_outlined,
                '${app['numberOfDays']} day${(app['numberOfDays'] as int? ?? 1) > 1 ? 's' : ''}',
                AppTheme.primaryMid),
            const SizedBox(width: 8),
            _chip(Icons.send_outlined,
                'To: ${(app['toRole'] as String? ?? '').capitalize()}',
                Colors.purple),
          ]),
          const SizedBox(height: 8),
          Text('Reason: ${app['reason'] ?? '—'}',
              style: TextStyle(
                  fontSize: 12, color: Colors.grey.shade600)),
          if (onAccept != null || onReject != null || onForward != null) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: _ActionButton(
                  label: 'Accept',
                  icon: Icons.check,
                  color: Colors.green,
                  onPressed: onAccept,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  label: 'Reject',
                  icon: Icons.close,
                  color: Colors.red,
                  onPressed: onReject,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _ActionButton(
                  label: 'Forward to Principal',
                  icon: Icons.forward_to_inbox_outlined,
                  color: Colors.indigo,
                  onPressed: onForward,
                ),
              ),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color)),
      ]),
    );
  }

  String _formatDate(String d) {
    if (d.isEmpty) return '—';
    final parts = d.split('-');
    if (parts.length < 3) return d;
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final m = int.tryParse(parts[1]) ?? 0;
    return '${parts[2]} ${months[m]} ${parts[0]}';
  }
}

// ── Inline action button ──────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withOpacity(0.6)),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        minimumSize: const Size(0, 34),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

// ── Detail bottom sheet ───────────────────────────────────────────────────────

class _LeaveDetailSheet extends StatefulWidget {
  final Map<String, dynamic> app;
  final String viewerRole;
  final void Function(String id, String status) onAction;

  const _LeaveDetailSheet({
    required this.app,
    required this.viewerRole,
    required this.onAction,
  });

  @override
  State<_LeaveDetailSheet> createState() => _LeaveDetailSheetState();
}

class _LeaveDetailSheetState extends State<_LeaveDetailSheet> {
  bool _acting = false;

  Future<void> _act(String status) async {
    setState(() => _acting = true);
    widget.onAction(widget.app['id'] as String, status);
  }

  @override
  Widget build(BuildContext context) {
    final app    = widget.app;
    final status = app['status'] as String? ?? 'pending';
    final isPending = status == 'pending';
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];

    String formatDate(String d) {
      if (d.isEmpty) return '—';
      final p = d.split('-');
      if (p.length < 3) return d;
      final m = int.tryParse(p[1]) ?? 0;
      return '${p[2]} ${months[m]} ${p[0]}';
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (ctx, sc) => Column(children: [
        Center(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
          ),
        ),
        Expanded(
          child: ListView(
            controller: sc,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              const Text('Leave Application',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),

              _detailRow(Icons.person_outline, 'Teacher',
                  app['teacherName'] as String? ?? '—'),
              _detailRow(Icons.email_outlined, 'Email',
                  app['teacherEmail'] as String? ?? '—'),
              _detailRow(Icons.calendar_today_outlined, 'Start Date',
                  formatDate(app['startDate'] as String? ?? '')),
              _detailRow(Icons.access_time_outlined, 'Duration',
                  '${app['numberOfDays']} day(s)'),
              _detailRow(Icons.send_outlined, 'Addressed To',
                  (app['toRole'] as String? ?? '').capitalize()),
              _detailRow(Icons.notes_outlined, 'Reason',
                  app['reason'] as String? ?? '—'),
              if (app['coordinatorNote'] != null)
                _detailRow(Icons.comment_outlined, 'Note',
                    app['coordinatorNote'] as String),
              const SizedBox(height: 8),

              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: status == 'approved'
                      ? Colors.green.shade50
                      : status == 'rejected'
                          ? Colors.red.shade50
                          : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: status == 'approved'
                          ? Colors.green.shade200
                          : status == 'rejected'
                              ? Colors.red.shade200
                              : Colors.orange.shade200),
                ),
                child: Row(children: [
                  Icon(
                    status == 'approved'
                        ? Icons.check_circle_outline
                        : status == 'rejected'
                            ? Icons.cancel_outlined
                            : Icons.pending_outlined,
                    size: 16,
                    color: status == 'approved'
                        ? Colors.green
                        : status == 'rejected'
                            ? Colors.red
                            : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Status: ${_fmtStatus(status, widget.viewerRole)}',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: status == 'approved'
                            ? Colors.green.shade800
                            : status == 'rejected'
                                ? Colors.red.shade800
                                : Colors.orange.shade800),
                  ),
                ]),
              ),

              if (isPending) ...[
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _acting ? null : () => _act('rejected'),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _acting ? null : () => _act('approved'),
                      icon: _acting
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check, size: 16),
                      label: Text(_acting ? 'Processing…' : 'Approve'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ]),
              ],
            ],
          ),
        ),
      ]),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: Colors.grey.shade500),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            Text(value,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w500)),
          ],
        )),
      ]),
    );
  }
}

String _fmtStatus(String status, String viewerRole) {
  switch (status) {
    case 'approved': return 'Approved';
    case 'rejected': return 'Rejected';
    case 'pending':  return 'Pending';
    case 'forwarded_to_principal':
      return (viewerRole == 'principal' || viewerRole == 'owner')
          ? 'Forwarded to You' : 'Forwarded to Principal';
    default:
      return status[0].toUpperCase() + status.substring(1);
  }
}

extension _StringCapExtension on String {
  String capitalize() =>
      isEmpty ? this : this[0].toUpperCase() + substring(1);
}

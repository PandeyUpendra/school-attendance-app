import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/timetable_service.dart';
import '../services/student_service.dart';
import '../services/notification_service.dart';
import '../services/base_firestore_service.dart';
import '../widgets/refreshable_data.dart';

/// Shown to the class teacher — lists leave applications submitted by guardians.
/// Teacher can Approve (auto-marks attendance), Reject, or Forward to Coordinator/Principal.
class StudentLeaveRequestsScreen extends StatefulWidget {
  final String studentClass;  // teacher.classTeacherOf

  const StudentLeaveRequestsScreen({
    super.key,
    required this.studentClass,
  });

  @override
  State<StudentLeaveRequestsScreen> createState() =>
      _StudentLeaveRequestsScreenState();
}

class _StudentLeaveRequestsScreenState
    extends State<StudentLeaveRequestsScreen>
    with SingleTickerProviderStateMixin {
  final _ttService = TimetableService();
  final _stuService = StudentService();

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
    final all =
        await _ttService.getStudentLeaveApplications(
            studentClass: widget.studentClass);
    if (!mounted) return;
    setState(() {
      _pending  = all.where((a) => a['status'] == 'pending').toList();
      _resolved = all.where((a) => a['status'] != 'pending').toList();
      _loading  = false;
    });
  }

  // ── Act on a leave ────────────────────────────────────────────────────────

  Future<void> _act(Map<String, dynamic> app, String status) async {
    final id     = app['id']          as String;
    final roll   = (app['studentRoll'] as int?) ?? 0;
    final name   = (app['studentName'] as String?) ?? '';
    final cls    = (app['studentClass'] as String?) ?? widget.studentClass;

    await _ttService.updateLeaveApplication(
        BaseFirestoreService.currentSchoolId ?? 'default_school', id, status);

    if (status == 'approved') {
      // Auto-mark attendance as 'Leave' for every day in the range
      final startStr = app['startDate'] as String? ?? '';
      final days     = (app['numberOfDays'] as num?)?.toInt() ?? 1;
      try {
        final parts  = startStr.split('-');
        final start  = DateTime(
            int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
        await _stuService.markLeaveForDateRange(
          className:    cls,
          roll:         roll,
          startDate:    start,
          numberOfDays: days,
        );
      } catch (_) {}

      // Notify guardian
      NotificationService().addStudentLeaveResolved(
        studentClass: cls,
        studentRoll:  roll,
        studentName:  name,
        status:       'approved',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Leave approved — attendance updated for $name'),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 3),
        ));
      }
    } else if (status == 'rejected') {
      NotificationService().addStudentLeaveResolved(
        studentClass: cls,
        studentRoll:  roll,
        studentName:  name,
        status:       'rejected',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Leave rejected for $name'),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 2),
        ));
      }
    } else if (status == 'forwarded_to_coordinator') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Leave request forwarded to Coordinator.'),
          backgroundColor: AppTheme.primary,
          duration: Duration(seconds: 3),
        ));
      }
    } else if (status == 'forwarded_to_principal') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Leave request forwarded to Principal.'),
          backgroundColor: AppTheme.primaryDark,
          duration: Duration(seconds: 3),
        ));
      }
    }

    _load();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Student Leave Requests',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text('Class ${widget.studentClass}',
                style: const TextStyle(
                    fontSize: 11, color: Colors.white70)),
          ],
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: [
            Tab(child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
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
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            )),
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
          ? const LoadingState()
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _buildList(_pending, showActions: true),
                _buildList(_resolved, showActions: false),
              ],
            ),
    );
  }

  Widget _buildList(
      List<Map<String, dynamic>> apps, {required bool showActions}) {
    if (apps.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.event_available_outlined,
              size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(showActions
                  ? 'No pending requests'
                  : 'No resolved requests',
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
        itemBuilder: (_, i) => _StudentLeaveCard(
          app:       apps[i],
          showActions: showActions,
          onAccept:  showActions ? () => _act(apps[i], 'approved')               : null,
          onReject:  showActions ? () => _act(apps[i], 'rejected')               : null,
          onFwdCoord:showActions ? () => _act(apps[i], 'forwarded_to_coordinator'): null,
          onFwdPrinc:showActions ? () => _act(apps[i], 'forwarded_to_principal') : null,
          onTap: () => _showDetail(apps[i], showActions: showActions),
        ),
      ),
    );
  }

  Future<void> _showDetail(
      Map<String, dynamic> app, {required bool showActions}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _StudentLeaveDetailSheet(
        app:        app,
        showActions: showActions,
        onAction: (status) async {
          await _act(app, status);
          if (mounted) Navigator.pop(context);
        },
      ),
    );
  }
}

// ── Leave card ────────────────────────────────────────────────────────────────

class _StudentLeaveCard extends StatelessWidget {
  final Map<String, dynamic> app;
  final bool        showActions;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onFwdCoord;
  final VoidCallback? onFwdPrinc;
  final VoidCallback  onTap;

  const _StudentLeaveCard({
    required this.app,
    required this.showActions,
    required this.onTap,
    this.onAccept,
    this.onReject,
    this.onFwdCoord,
    this.onFwdPrinc,
  });

  @override
  Widget build(BuildContext context) {
    final status = app['status'] as String? ?? 'pending';
    final statusColor = switch (status) {
      'approved' => Colors.green,
      'rejected' => Colors.red,
      _           => Colors.orange,
    };
    final name    = app['studentName']  as String? ?? '—';
    final roll    = app['studentRoll']  as int?    ?? 0;
    final cls     = app['studentClass'] as String? ?? '';
    final days    = app['numberOfDays'] as int?    ?? 1;
    final start   = app['startDate']    as String? ?? '';
    final reason  = app['reason']       as String? ?? '';
    final guardian= app['guardianName'] as String? ?? '';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: statusColor.withValues(alpha: 0.25)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold)),
                Text(
                  'Roll $roll  •  $cls'
                  '${guardian.isNotEmpty ? '  •  $guardian' : ''}',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade500)),
              ],
            )),
            _statusBadge(status, statusColor),
          ]),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            _chip(Icons.calendar_today_outlined, _fmtDate(start), AppTheme.primary),
            _chip(Icons.access_time_outlined,
                '$days day${days > 1 ? 's' : ''}', AppTheme.primaryMid),
          ]),
          const SizedBox(height: 8),
          Text('Reason: $reason',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          if (showActions) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _ActionBtn(
                label: 'Approve',
                icon: Icons.check,
                color: Colors.green,
                onPressed: onAccept,
              )),
              const SizedBox(width: 6),
              Expanded(child: _ActionBtn(
                label: 'Reject',
                icon: Icons.close,
                color: Colors.red,
                onPressed: onReject,
              )),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: _ActionBtn(
                label: 'Fwd Coordinator',
                icon: Icons.forward_to_inbox_outlined,
                color: AppTheme.primaryMid,
                onPressed: onFwdCoord,
              )),
              const SizedBox(width: 6),
              Expanded(child: _ActionBtn(
                label: 'Fwd Principal',
                icon: Icons.forward_to_inbox_outlined,
                color: AppTheme.primaryDark,
                onPressed: onFwdPrinc,
              )),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _statusBadge(String status, Color color) {
    final label = switch (status) {
      'approved'               => 'Approved',
      'rejected'               => 'Rejected',
      'forwarded_to_coordinator' => 'Fwd Coord',
      'forwarded_to_principal' => 'Fwd Principal',
      _                        => 'Pending',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color)),
    );
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
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

  String _fmtDate(String d) {
    if (d.isEmpty) return '—';
    final p = d.split('-');
    if (p.length < 3) return d;
    const months = ['','Jan','Feb','Mar','Apr','May','Jun',
                       'Jul','Aug','Sep','Oct','Nov','Dec'];
    final m = int.tryParse(p[1]) ?? 0;
    return '${p[2]} ${months[m]} ${p[0]}';
  }
}

// ── Inline action button ──────────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final String    label;
  final IconData  icon;
  final Color     color;
  final VoidCallback? onPressed;

  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 13),
      label: Text(label, style: const TextStyle(fontSize: 10)),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.6)),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8)),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

// ── Detail bottom sheet ───────────────────────────────────────────────────────

class _StudentLeaveDetailSheet extends StatefulWidget {
  final Map<String, dynamic> app;
  final bool showActions;
  final void Function(String status) onAction;

  const _StudentLeaveDetailSheet({
    required this.app,
    required this.showActions,
    required this.onAction,
  });

  @override
  State<_StudentLeaveDetailSheet> createState() =>
      _StudentLeaveDetailSheetState();
}

class _StudentLeaveDetailSheetState extends State<_StudentLeaveDetailSheet> {
  bool _acting = false;

  Future<void> _act(String status) async {
    setState(() => _acting = true);
    widget.onAction(status);
  }

  @override
  Widget build(BuildContext context) {
    final app    = widget.app;
    final status = app['status'] as String? ?? 'pending';
    const months = ['','Jan','Feb','Mar','Apr','May','Jun',
                       'Jul','Aug','Sep','Oct','Nov','Dec'];

    String fmtDate(String d) {
      if (d.isEmpty) return '—';
      final p = d.split('-');
      if (p.length < 3) return d;
      final m = int.tryParse(p[1]) ?? 0;
      return '${p[2]} ${months[m]} ${p[0]}';
    }

    final statusColor = switch (status) {
      'approved' => Colors.green,
      'rejected' => Colors.red,
      _           => Colors.orange,
    };

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
        Expanded(child: ListView(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            const Text('Student Leave Application',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            _row(Icons.person_outline, 'Student',
                '${app['studentName'] ?? '—'}  •  Roll ${app['studentRoll'] ?? ''}'),
            _row(Icons.school_outlined, 'Class',
                app['studentClass'] as String? ?? '—'),
            if ((app['guardianName'] as String? ?? '').isNotEmpty)
              _row(Icons.family_restroom_outlined, 'Guardian',
                  app['guardianName'] as String),
            _row(Icons.calendar_today_outlined, 'Start Date',
                fmtDate(app['startDate'] as String? ?? '')),
            _row(Icons.access_time_outlined, 'Duration',
                '${app['numberOfDays']} day(s)'),
            _row(Icons.notes_outlined, 'Reason',
                app['reason'] as String? ?? '—'),
            const SizedBox(height: 8),

            // Status badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: statusColor.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                Icon(
                  status == 'approved'
                      ? Icons.check_circle_outline
                      : status == 'rejected'
                          ? Icons.cancel_outlined
                          : Icons.pending_outlined,
                  size: 16,
                  color: statusColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'Status: ${_fmtStatus(status)}',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: statusColor.shade800),
                ),
              ]),
            ),

            if (widget.showActions && status == 'pending') ...[
              const SizedBox(height: 20),
              // Approve / Reject row
              Row(children: [
                Expanded(child: OutlinedButton.icon(
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
                )),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: ElevatedButton.icon(
                  onPressed: _acting ? null : () => _act('approved'),
                  icon: _acting
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white))
                      : const Icon(Icons.check, size: 16),
                  label: Text(_acting ? 'Processing…' : 'Approve & Mark Leave'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                )),
              ]),
              const SizedBox(height: 10),
              // Forward row
              Row(children: [
                Expanded(child: OutlinedButton.icon(
                  onPressed: _acting
                      ? null
                      : () => _act('forwarded_to_coordinator'),
                  icon: const Icon(Icons.forward_to_inbox_outlined, size: 15),
                  label: const Text('Fwd Coordinator',
                      style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryMid,
                    side: BorderSide(
                        color: AppTheme.primaryMid.withValues(alpha: 0.6)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                )),
                const SizedBox(width: 10),
                Expanded(child: OutlinedButton.icon(
                  onPressed: _acting
                      ? null
                      : () => _act('forwarded_to_principal'),
                  icon: const Icon(Icons.forward_to_inbox_outlined, size: 15),
                  label: const Text('Fwd Principal',
                      style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryDark,
                    side: BorderSide(
                        color: AppTheme.primaryDark.withValues(alpha: 0.6)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                )),
              ]),
            ],
          ],
        )),
      ]),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: Colors.grey.shade500),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 11, color: Colors.grey.shade500)),
            Text(value,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w500)),
          ],
        )),
      ]),
    );
  }

  String _fmtStatus(String s) => switch (s) {
    'approved'               => 'Approved',
    'rejected'               => 'Rejected',
    'forwarded_to_coordinator' => 'Forwarded to Coordinator',
    'forwarded_to_principal' => 'Forwarded to Principal',
    _                        => 'Pending',
  };
}


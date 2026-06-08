import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../models/teacher.dart';
import '../services/timetable_service.dart';
import '../services/notification_service.dart';
import '../services/base_firestore_service.dart';
import 'free_bells_screen.dart';
import 'substitution_plan_screen.dart';
import '../theme.dart';
import '../widgets/refreshable_data.dart';

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

  /// Assigning a substitute is a coordinator-only action. The principal can
  /// review and resolve leave, but substitution planning belongs to the
  /// coordinator, so the option is hidden from the principal's view.
  bool get _canAssignSubstitution => widget.viewerRole == 'coordinator';

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
    final results = await Future.wait([
      _service.getLeaveApplications(),
      _service.getTeachers(),
    ]);

    final all      = results[0] as List<Map<String, dynamic>>;
    final teachers = results[1] as List<Teacher>;
    // Build a set of currently-existing teacher IDs so we can filter out
    // orphaned applications from teachers whose accounts have been deleted.
    final validIds = {for (final t in teachers) t.id};

    if (!mounted) return;
    setState(() {
      final valid   = all.where(
        (a) => validIds.contains(a['teacherId'] as String? ?? ''),
      ).toList();
      _pending  = valid.where((a) => a['status'] == 'pending').toList();
      _resolved = valid.where((a) => a['status'] != 'pending').toList();
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
      // Do NOT jump straight into substitution — approving and assigning a
      // substitute are separate steps. Offer it as an option instead (the
      // approved card also carries an "Assign Substitution" button), but only
      // to the coordinator — the principal does not assign substitutions.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr('leaveApprovedCheck')),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 5),
        action: _canAssignSubstitution
            ? SnackBarAction(
                label: context.tr('assignSubstitution'),
                textColor: Colors.white,
                onPressed: () => _openSubstitution(app),
              )
            : null,
      ));
    } else if (status == 'forwarded_to_principal') {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr('leaveForwardedToPrincipal')),
        backgroundColor: AppTheme.primary,
        duration: const Duration(seconds: 3),
      ));
    }
  }

  /// Opens the smart substitution plan for a leave (or Free Bells as a
  /// fallback when the teacher/start date can't be resolved).
  Future<void> _openSubstitution(Map<String, dynamic> app) async {
    final teacherId   = app['teacherId']   as String? ?? '';
    final teacherName = app['teacherName'] as String? ?? '';
    final start       = DateTime.tryParse(app['startDate'] as String? ?? '');
    final days        = (app['numberOfDays'] as num?)?.toInt() ?? 1;

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
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const FreeBellsScreen()),
      );
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
        onAssignSubstitution: _canAssignSubstitution
            ? () {
                Navigator.pop(context);
                _openSubstitution(app);
              }
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('leaveRequests'),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text(context.tr('teacherLeaveApplications'),
                style: const TextStyle(fontSize: 11, color: Colors.white70)),
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
                Text(context.tr('statusPending')),
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
            Tab(text: context.tr('resolvedTab')),
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

  Widget _buildList(List<Map<String, dynamic>> apps, {required bool showActions}) {
    if (apps.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.event_available_outlined,
              size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(showActions ? context.tr('noPendingRequests') : context.tr('noResolvedRequests'),
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
          statusLabel: _fmtStatus(context, apps[i]['status'] as String? ?? 'pending', widget.viewerRole),
          onTap: () => _showDetail(apps[i]),
          onAccept: showActions ? () => _act(apps[i], 'approved')  : null,
          onReject: showActions ? () => _act(apps[i], 'rejected')  : null,
          onForward: showActions && widget.viewerRole == 'coordinator'
              ? () => _act(apps[i], 'forwarded_to_principal')
              : null,
          // Substitution is an explicit follow-up action, available on any
          // approved leave (not triggered automatically on approval) — and only
          // to the coordinator; the principal does not assign substitutions.
          onAssignSubstitution:
              _canAssignSubstitution && apps[i]['status'] == 'approved'
                  ? () => _openSubstitution(apps[i])
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
  final VoidCallback? onAssignSubstitution;

  const _LeaveCard({
    required this.app,
    required this.statusLabel,
    required this.onTap,
    this.onAccept,
    this.onReject,
    this.onForward,
    this.onAssignSubstitution,
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
          border: Border.all(color: statusColor.withValues(alpha: 0.25)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
              child: Text(
                (app['teacherName'] as String? ?? 'T')[0].toUpperCase(),
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
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: statusColor.withValues(alpha: 0.4)),
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
                '${app['numberOfDays']} ${(app['numberOfDays'] as int? ?? 1) > 1 ? context.tr('daysShort') : context.tr('dayShort')}',
                AppTheme.primaryMid),
            const SizedBox(width: 8),
            _chip(Icons.send_outlined,
                '${context.tr('toColon')} ${_roleLabel(context, app['toRole'] as String? ?? '')}',
                AppTheme.primaryMid),
          ]),
          const SizedBox(height: 8),
          Text('${context.tr('reasonColon')} ${app['reason'] ?? '—'}',
              style: TextStyle(
                  fontSize: 12, color: Colors.grey.shade600)),
          if (onAccept != null || onReject != null || onForward != null) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: _ActionButton(
                  label: context.tr('acceptAction'),
                  icon: Icons.check,
                  color: Colors.green,
                  onPressed: onAccept,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  label: context.tr('rejectAction'),
                  icon: Icons.close,
                  color: Colors.red,
                  onPressed: onReject,
                ),
              ),
              if (onForward != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: _ActionButton(
                    label: context.tr('forwardToPrincipal'),
                    icon: Icons.forward_to_inbox_outlined,
                    color: AppTheme.primaryDark,
                    onPressed: onForward,
                  ),
                ),
              ],
            ]),
          ],
          // Approved leaves: optional substitution assignment.
          if (onAssignSubstitution != null) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: _ActionButton(
                label: context.tr('assignSubstitution'),
                icon: Icons.swap_horiz_outlined,
                color: AppTheme.primary,
                onPressed: onAssignSubstitution,
              ),
            ),
          ],
        ]),
      ),
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
        side: BorderSide(color: color.withValues(alpha: 0.6)),
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
  /// Null when the viewer may not assign substitutions (e.g. principal).
  final VoidCallback? onAssignSubstitution;

  const _LeaveDetailSheet({
    required this.app,
    required this.viewerRole,
    required this.onAction,
    required this.onAssignSubstitution,
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
              Text(context.tr('leaveApplication'),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),

              _detailRow(Icons.person_outline, context.tr('teacherLabel'),
                  app['teacherName'] as String? ?? '—'),
              _detailRow(Icons.email_outlined, context.tr('email'),
                  app['teacherEmail'] as String? ?? '—'),
              _detailRow(Icons.calendar_today_outlined, context.tr('startDate'),
                  formatDate(app['startDate'] as String? ?? '')),
              _detailRow(Icons.access_time_outlined, context.tr('durationLabel'),
                  '${app['numberOfDays']} ${(app['numberOfDays'] as int? ?? 1) > 1 ? context.tr('daysShort') : context.tr('dayShort')}'),
              _detailRow(Icons.send_outlined, context.tr('addressedTo'),
                  _roleLabel(context, app['toRole'] as String? ?? '')),
              _detailRow(Icons.notes_outlined, context.tr('reasonLabel'),
                  app['reason'] as String? ?? '—'),
              if (app['coordinatorNote'] != null)
                _detailRow(Icons.comment_outlined, context.tr('noteLabel'),
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
                    '${context.tr('statusColonPrefix')} ${_fmtStatus(context, status, widget.viewerRole)}',
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

              if (status == 'approved' &&
                  widget.onAssignSubstitution != null) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: widget.onAssignSubstitution,
                    icon: const Icon(Icons.swap_horiz_outlined, size: 18),
                    label: Text(context.tr('assignSubstitution')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],

              if (isPending) ...[
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _acting ? null : () => _act('rejected'),
                      icon: const Icon(Icons.close, size: 16),
                      label: Text(context.tr('rejectAction')),
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
                      label: Text(_acting ? context.tr('processingEllipsis') : context.tr('approveAction')),
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

/// Localised role name for an addressed-to role (e.g. 'principal'), falling
/// back to a capitalised form for any unmapped value.
String _roleLabel(BuildContext context, String role) {
  if (role.isEmpty) return '';
  final localized = context.trRole(role);
  return localized == 'role_$role'
      ? role[0].toUpperCase() + role.substring(1)
      : localized;
}

String _fmtStatus(BuildContext context, String status, String viewerRole) {
  switch (status) {
    case 'approved': return context.tr('statusApproved');
    case 'rejected': return context.tr('statusRejected');
    case 'pending':  return context.tr('statusPending');
    case 'forwarded_to_principal':
      return (viewerRole == 'principal' || viewerRole == 'owner')
          ? context.tr('forwardedToYou') : context.tr('forwardedToPrincipalStatus');
    default:
      return status[0].toUpperCase() + status.substring(1);
  }
}

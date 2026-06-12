import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../l10n/app_strings.dart';
import '../../theme.dart';
import '../../services/timetable_service.dart';
import '../../services/student_service.dart';
import '../../services/notification_service.dart';
import '../../services/base_firestore_service.dart';
import '../../shared/widgets/refreshable_data.dart';
import '../../shared/utils/app_logger.dart';
/// Shown to the class teacher — lists leave applications submitted by guardians.
/// Teacher can Approve (auto-marks attendance), Reject, or Forward to Coordinator/Principal.
class StudentLeaveRequestsScreen extends StatefulWidget {
  final String studentClass;  // teacher.classTeacherOf
  final String studentSection;

  const StudentLeaveRequestsScreen({
    super.key,
    required this.studentClass,
    this.studentSection = '',
  });

  @override
  State<StudentLeaveRequestsScreen> createState() =>
      _StudentLeaveRequestsScreenState();
}

class _StudentLeaveRequestsScreenState
    extends State<StudentLeaveRequestsScreen>
    with SingleTickerProviderStateMixin {
  final _ttService = TimetableService.instance;
  final _stuService = StudentService.instance;

  late final TabController _tabCtrl;
  List<Map<String, dynamic>> _pending  = [];
  List<Map<String, dynamic>> _resolved = [];
  bool _loading = true;

  bool _bulkMode = false;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      if (_tabCtrl.indexIsChanging || _tabCtrl.index != 0) {
        setState(() {
          _bulkMode = false;
          _selectedIds.clear();
        });
      }
    });
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
            studentClass: widget.studentClass,
            studentSection: widget.studentSection);
    if (!mounted) return;
    setState(() {
      _pending  = all.where((a) => a['status'] == 'pending').toList();
      _resolved = all.where((a) => a['status'] != 'pending').toList();
      _loading  = false;
    });
  }

  // ── Act on a leave ────────────────────────────────────────────────────────

  Future<String?> _showRemarksDialog(String action) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(action == 'approved' ? context.tr('remarksForApproval') : context.tr('remarksForRejection')),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(
            hintText: context.tr('enterRemarksOptional'),
            border: const OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(context.tr('confirmAction')),
          ),
        ],
      ),
    );
  }

  Future<void> _act(Map<String, dynamic> app, String status, {String? bulkRemarks, bool reload = true}) async {
    final id     = app['id']          as String;
    final roll   = (app['studentRoll'] as int?) ?? 0;
    final name   = (app['studentName'] as String?) ?? '';
    final cls    = (app['studentClass'] as String?) ?? widget.studentClass;
    // Stable guardian identity stored at submission time (#39) — may be null
    // for applications that predate the admissionId field.
    final admId  = app['admissionId']  as String?;

    String remarks = '';
    if (status == 'approved' || status == 'rejected') {
      if (bulkRemarks != null) {
        remarks = bulkRemarks;
      } else {
        final res = await _showRemarksDialog(status);
        if (res == null) return; // user cancelled
        remarks = res;
      }
    }

    await _ttService.updateLeaveApplication(
        BaseFirestoreService.currentSchoolId ?? 'default_school', id, status,
        note: remarks);

    if (status == 'approved') {
      // Auto-mark attendance as 'Leave' for every day in the range
      final startStr = app['startDate'] as String? ?? '';
      final days     = (app['numberOfDays'] as num?)?.toInt() ?? 1;
      try {
        final parts  = startStr.split('-');
        if (parts.length == 3) {
          final year = int.tryParse(parts[0]);
          final month = int.tryParse(parts[1]);
          final day = int.tryParse(parts[2]);
          if (year != null && month != null && day != null) {
            final start  = DateTime(year, month, day);
            await _stuService.markLeaveForDateRange(
              className:    cls,
              roll:         roll,
              startDate:    start,
              numberOfDays: days,
            );
          } else {
            AppLogger.e('StudentLeaveRequestsScreen', 'Invalid date components in student leave approval: $startStr');
          }
        } else {
          AppLogger.e('StudentLeaveRequestsScreen', 'Malformed date string in student leave approval: $startStr');
        }
      } catch (e, st) {
        AppLogger.e('StudentLeaveRequestsScreen', 'Failed to mark leave range', e, st);
      }

      // Notify guardian
      NotificationService().addStudentLeaveResolved(
        studentClass: cls,
        studentRoll:  roll,
        studentName:  name,
        status:       'approved',
        admissionId:  admId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${context.tr('leaveApprovedAttendanceUpdated')} $name'),
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
        admissionId:  admId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${context.tr('leaveRejectedFor')} $name'),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 2),
        ));
      }
    } else if (status == 'forwarded_to_coordinator') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr('leaveForwardedToCoordinator')),
          backgroundColor: AppTheme.primary,
          duration: const Duration(seconds: 3),
        ));
      }
    } else if (status == 'forwarded_to_principal') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr('leaveForwardedToPrincipal')),
          backgroundColor: AppTheme.primaryDark,
          duration: const Duration(seconds: 3),
        ));
      }
    }

    if (reload) {
      _load();
    }
  }

  Future<void> _bulkAct(String status) async {
    String? remarks;
    if (status == 'approved' || status == 'rejected') {
      remarks = await _showRemarksDialog(status);
      if (remarks == null) return; // user cancelled
    }

    setState(() => _loading = true);
    final ids = _selectedIds.toList();
    for (final id in ids) {
      final app = _pending.firstWhere((a) => a['id'] == id, orElse: () => {});
      if (app.isNotEmpty) {
        await _act(app, status, bulkRemarks: remarks, reload: false);
      }
    }
    setState(() {
      _selectedIds.clear();
      _bulkMode = false;
    });
    await _load();
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
            Text(context.tr('studentLeaveRequests'),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text(
              '${context.tr('classLabel')} ${widget.studentClass}${widget.studentSection.isNotEmpty ? ' — ${context.tr('sectionWord')} ${widget.studentSection}' : ''}',
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
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            )),
            Tab(text: context.tr('resolvedTab')),
          ],
        ),
        actions: [
          if (_tabCtrl.index == 0 && _pending.isNotEmpty)
            IconButton(
              icon: Icon(_bulkMode ? Icons.check_box : Icons.check_box_outline_blank),
              onPressed: () {
                setState(() {
                  _bulkMode = !_bulkMode;
                  if (!_bulkMode) _selectedIds.clear();
                });
              },
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      bottomNavigationBar: _bulkMode && _selectedIds.isNotEmpty
          ? Container(
              padding: const EdgeInsets.all(12),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _bulkAct('rejected'),
                      icon: const Icon(Icons.close, color: Colors.red),
                      label: Text('Reject (${_selectedIds.length})', style: const TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _bulkAct('approved'),
                      icon: const Icon(Icons.check, color: Colors.white),
                      label: Text('Approve (${_selectedIds.length})'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : null,
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
                  ? context.tr('noPendingRequests')
                  : context.tr('noResolvedRequests'),
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
        itemBuilder: (_, i) {
          final app = apps[i];
          final id = app['id'] as String;
          return _StudentLeaveCard(
            app:       app,
            showActions: showActions,
            bulkMode:  _bulkMode,
            isSelected: _selectedIds.contains(id),
            onSelectedChanged: (val) {
              setState(() {
                if (val == true) {
                  _selectedIds.add(id);
                } else {
                  _selectedIds.remove(id);
                }
              });
            },
            onAccept:  showActions ? () => _act(app, 'approved')               : null,
            onReject:  showActions ? () => _act(app, 'rejected')               : null,
            onFwdCoord:showActions ? () => _act(app, 'forwarded_to_coordinator'): null,
            onFwdPrinc:showActions ? () => _act(app, 'forwarded_to_principal') : null,
            onTap: _bulkMode
                ? () {
                    setState(() {
                      if (_selectedIds.contains(id)) {
                        _selectedIds.remove(id);
                      } else {
                        _selectedIds.add(id);
                      }
                    });
                  }
                : () => _showDetail(app, showActions: showActions),
          );
        },
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
  final bool          bulkMode;
  final bool          isSelected;
  final ValueChanged<bool?>? onSelectedChanged;

  const _StudentLeaveCard({
    required this.app,
    required this.showActions,
    required this.onTap,
    this.onAccept,
    this.onReject,
    this.onFwdCoord,
    this.onFwdPrinc,
    this.bulkMode = false,
    this.isSelected = false,
    this.onSelectedChanged,
  });

  String _fmtSubmissionTime(dynamic createdAt) {
    if (createdAt == null) return '—';
    if (createdAt is Timestamp) {
      final dt = createdAt.toDate();
      const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      final min = dt.minute.toString().padLeft(2, '0');
      return '${dt.day.toString().padLeft(2, '0')} ${months[dt.month]} ${dt.year}, ${hour.toString().padLeft(2, '0')}:$min $ampm';
    }
    return createdAt.toString();
  }

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
            if (bulkMode) ...[
              Checkbox(
                value: isSelected,
                onChanged: onSelectedChanged,
                activeColor: AppTheme.primary,
              ),
              const SizedBox(width: 4),
            ],
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
                  '${context.tr('roll')} $roll  •  $cls${app['studentSection'] != null && app['studentSection'].toString().isNotEmpty ? ' — ${context.tr('secPrefix')} ${app['studentSection']}' : ''}'
                  '${guardian.isNotEmpty ? '  •  $guardian' : ''}\n'
                  '${context.tr('submittedPrefix')} ${_fmtSubmissionTime(app['createdAt'])}',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade500)),
              ],
            )),
            _statusBadge(context, status, statusColor),
          ]),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            _chip(Icons.calendar_today_outlined, _fmtDate(start), AppTheme.primary),
            _chip(Icons.access_time_outlined,
                '$days ${days > 1 ? context.tr('daysShort') : context.tr('dayShort')}', AppTheme.primaryMid),
          ]),
          Text('${context.tr('reasonColon')} $reason',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          if (app['coordinatorNote'] != null && app['coordinatorNote'].toString().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '${context.tr('remarksColon')} ${app['coordinatorNote']}',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.orange.shade800),
            ),
          ],
          if (showActions && !bulkMode) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _ActionBtn(
                label: context.tr('approveAction'),
                icon: Icons.check,
                color: Colors.green,
                onPressed: onAccept,
              )),
              const SizedBox(width: 6),
              Expanded(child: _ActionBtn(
                label: context.tr('rejectAction'),
                icon: Icons.close,
                color: Colors.red,
                onPressed: onReject,
              )),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: _ActionBtn(
                label: context.tr('fwdCoordinator'),
                icon: Icons.forward_to_inbox_outlined,
                color: AppTheme.primaryMid,
                onPressed: onFwdCoord,
              )),
              const SizedBox(width: 6),
              Expanded(child: _ActionBtn(
                label: context.tr('fwdPrincipal'),
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

  Widget _statusBadge(BuildContext context, String status, Color color) {
    final label = switch (status) {
      'approved'               => context.tr('statusApproved'),
      'rejected'               => context.tr('statusRejected'),
      'forwarded_to_coordinator' => context.tr('fwdCoordShort'),
      'forwarded_to_principal' => context.tr('fwdPrincipal'),
      _                        => context.tr('statusPending'),
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

    String fmtSubmissionTime(dynamic createdAt) {
      if (createdAt == null) return '—';
      if (createdAt is Timestamp) {
        final dt = createdAt.toDate();
        const monthsSub = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
        final ampm = dt.hour >= 12 ? 'PM' : 'AM';
        final min = dt.minute.toString().padLeft(2, '0');
        return '${dt.day.toString().padLeft(2, '0')} ${monthsSub[dt.month]} ${dt.year}, ${hour.toString().padLeft(2, '0')}:$min $ampm';
      }
      return createdAt.toString();
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
            Text(context.tr('studentLeaveApplication'),
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            _row(Icons.person_outline, context.tr('studentLabelField'),
                '${app['studentName'] ?? '—'}  •  ${context.tr('roll')} ${app['studentRoll'] ?? ''}'),
            _row(Icons.school_outlined, context.tr('classLabel'),
                '${app['studentClass'] ?? '—'}${app['studentSection'] != null && app['studentSection'].toString().isNotEmpty ? ' — ${context.tr('sectionWord')} ${app['studentSection']}' : ''}'),
            if ((app['guardianName'] as String? ?? '').isNotEmpty)
              _row(Icons.family_restroom_outlined, context.tr('guardianLabel'),
                  app['guardianName'] as String),
            _row(Icons.calendar_today_outlined, context.tr('startDate'),
                fmtDate(app['startDate'] as String? ?? '')),
            _row(Icons.access_time_outlined, context.tr('durationLabel'),
                '${app['numberOfDays']} ${(app['numberOfDays'] as int? ?? 1) > 1 ? context.tr('daysShort') : context.tr('dayShort')}'),
            _row(Icons.notes_outlined, context.tr('reasonLabel'),
                app['reason'] as String? ?? '—'),
            _row(Icons.watch_later_outlined, context.tr('submittedAt'),
                fmtSubmissionTime(app['createdAt'])),
            if (app['coordinatorNote'] != null && app['coordinatorNote'].toString().isNotEmpty)
              _row(Icons.comment_outlined, context.tr('noteLabel'),
                  app['coordinatorNote'] as String),
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
                  '${context.tr('statusColonPrefix')} ${_fmtStatus(context, status)}',
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
                  label: Text(context.tr('rejectAction')),
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
                  label: Text(_acting ? context.tr('processingEllipsis') : context.tr('approveAndMarkLeave')),
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
                  label: Text(context.tr('fwdCoordinator'),
                      style: const TextStyle(fontSize: 12)),
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
                  label: Text(context.tr('fwdPrincipal'),
                      style: const TextStyle(fontSize: 12)),
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

  String _fmtStatus(BuildContext context, String s) => switch (s) {
    'approved'               => context.tr('statusApproved'),
    'rejected'               => context.tr('statusRejected'),
    'forwarded_to_coordinator' => context.tr('forwardedToCoordinatorStatus'),
    'forwarded_to_principal' => context.tr('forwardedToPrincipalStatus'),
    _                        => context.tr('statusPending'),
  };
}


import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/base_firestore_service.dart';
import '../services/teacher_deletion_service.dart';
import '../theme.dart';

/// Principal / Owner review screen for coordinator-submitted teacher
/// deletion requests. Approve = actually delete the teacher (record +
/// timetable scrub + login revoke). Reject = stamp a rejection note.
class TeacherDeletionRequestsScreen extends StatefulWidget {
  const TeacherDeletionRequestsScreen({super.key});

  @override
  State<TeacherDeletionRequestsScreen> createState() =>
      _TeacherDeletionRequestsScreenState();
}

class _TeacherDeletionRequestsScreenState
    extends State<TeacherDeletionRequestsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _svc = TeacherDeletionService();

  String _role  = '';
  String _email = '';
  String _name  = '';

  String get _schoolId =>
      BaseFirestoreService.currentSchoolId ?? 'default_school';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadSession();
  }

  Future<void> _loadSession() async {
    final s = await TeacherDeletionService.sessionUser();
    if (!mounted) return;
    setState(() {
      _role  = s['role']  ?? '';
      _email = s['email'] ?? '';
      _name  = s['name']  ?? '';
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _approve(Map<String, dynamic> req) async {
    final teacher = req['teacherName'] ?? req['teacherEmail'] ?? 'this teacher';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.check_circle_outline, color: Colors.green),
          SizedBox(width: 8),
          Text('Approve Deletion', style: TextStyle(fontSize: 17)),
        ]),
        content: Text(
          'Permanently remove $teacher?\n\n'
          'This deletes their teacher record, scrubs them from every '
          'timetable slot, and revokes their login. This cannot be undone.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Approve & Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await _svc.approve(
        schoolId:      _schoolId,
        requestId:     req['id'] as String,
        reviewerEmail: _email,
        reviewerRole:  _role,
        reviewerName:  _name,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$teacher removed.'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _reject(Map<String, dynamic> req) async {
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.cancel_outlined, color: Colors.red),
          SizedBox(width: 8),
          Text('Reject Request', style: TextStyle(fontSize: 17)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Optionally provide a reason for rejection:',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 10),
            TextField(
              controller: noteCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'e.g. teacher is still active this term',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.all(10),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    final note = noteCtrl.text.trim();
    noteCtrl.dispose();
    if (ok != true || !mounted) return;

    try {
      await _svc.reject(
        schoolId:      _schoolId,
        requestId:     req['id'] as String,
        reviewerEmail: _email,
        reviewerRole:  _role,
        reviewerName:  _name,
        note:          note,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Request rejected.'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        title: const Text('Teacher Deletion Requests'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Resolved'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _RequestList(
            stream: _svc.streamPending(_schoolId),
            onApprove: _approve,
            onReject: _reject,
            isPending: true,
          ),
          _RequestList(
            stream: _svc.streamResolved(_schoolId),
            isPending: false,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Request list
// ─────────────────────────────────────────────────────────────────────────────

class _RequestList extends StatelessWidget {
  final Stream<List<Map<String, dynamic>>> stream;
  final Future<void> Function(Map<String, dynamic>)? onApprove;
  final Future<void> Function(Map<String, dynamic>)? onReject;
  final bool isPending;

  const _RequestList({
    required this.stream,
    this.onApprove,
    this.onReject,
    required this.isPending,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snap.data ?? [];
        if (items.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(isPending ? Icons.inbox_outlined : Icons.history_outlined,
                    size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                Text(
                  isPending
                      ? 'No pending deletion requests'
                      : 'No resolved requests yet',
                  style:
                      TextStyle(fontSize: 16, color: Colors.grey.shade400),
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          itemBuilder: (_, i) => _RequestCard(
            request:   items[i],
            onApprove: onApprove,
            onReject:  onReject,
            isPending: isPending,
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Individual request card
// ─────────────────────────────────────────────────────────────────────────────

class _RequestCard extends StatefulWidget {
  final Map<String, dynamic> request;
  final Future<void> Function(Map<String, dynamic>)? onApprove;
  final Future<void> Function(Map<String, dynamic>)? onReject;
  final bool isPending;

  const _RequestCard({
    required this.request,
    this.onApprove,
    this.onReject,
    required this.isPending,
  });

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  bool _busy = false;

  String _fmtDate(dynamic ts) {
    if (ts == null) return '—';
    if (ts is Timestamp) {
      final d = ts.toDate();
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${d.day} ${months[d.month - 1]} ${d.year}, '
          '${d.hour.toString().padLeft(2, '0')}:'
          '${d.minute.toString().padLeft(2, '0')}';
    }
    return ts.toString();
  }

  Color get _statusColor {
    switch (widget.request['status']) {
      case 'approved': return Colors.green;
      case 'rejected': return Colors.red;
      default:         return AppTheme.warning;
    }
  }

  IconData get _statusIcon {
    switch (widget.request['status']) {
      case 'approved': return Icons.check_circle_outline;
      case 'rejected': return Icons.cancel_outlined;
      default:         return Icons.hourglass_top_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final req      = widget.request;
    final teacher  = (req['teacherName'] as String?)?.trim().isNotEmpty == true
        ? req['teacherName'] as String
        : (req['teacherEmail'] as String? ?? 'Unknown');
    final tEmail   = (req['teacherEmail'] as String?) ?? '';
    final reqBy    = (req['requestedByName'] as String?)?.trim().isNotEmpty == true
        ? req['requestedByName'] as String
        : (req['requestedBy'] as String? ?? '—');
    final reason   = (req['reason'] as String?) ?? '';
    final note     = (req['rejectionNote'] as String?) ?? '';
    final status   = (req['status'] as String?) ?? 'pending';
    final revBy    = (req['reviewedByName'] as String?)?.trim().isNotEmpty == true
        ? req['reviewedByName'] as String
        : (req['reviewedBy'] as String? ?? '');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ───────────────────────────────────────────────────
            Row(
              children: [
                Icon(_statusIcon, color: _statusColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(teacher,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _statusColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _statusColor),
                  ),
                ),
              ],
            ),

            if (tEmail.isNotEmpty) ...[
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: Text(tEmail,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500)),
              ),
            ],

            const SizedBox(height: 10),
            // ── Meta: requested by + when ───────────────────────────────
            Row(children: [
              Icon(Icons.person_outline,
                  size: 14, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Expanded(
                child: Text('Requested by $reqBy',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade700)),
              ),
            ]),
            const SizedBox(height: 2),
            Row(children: [
              Icon(Icons.schedule_outlined,
                  size: 14, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text(_fmtDate(req['requestedAt']),
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade600)),
            ]),

            // ── Reason ──────────────────────────────────────────────────
            if (reason.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.notes_outlined,
                        size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(reason,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade700)),
                    ),
                  ],
                ),
              ),
            ],

            // ── Rejection note ──────────────────────────────────────────
            if (note.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline,
                        size: 14, color: Colors.red),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('Rejection note: $note',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.red)),
                    ),
                  ],
                ),
              ),
            ],

            // ── Resolution attribution (resolved tab) ───────────────────
            if (!widget.isPending && revBy.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${status == 'approved' ? 'Approved' : 'Rejected'} by '
                '$revBy · ${_fmtDate(req['reviewedAt'])}',
                style: TextStyle(
                    fontSize: 11, color: Colors.grey.shade500),
              ),
            ],

            // ── Action buttons (pending only) ───────────────────────────
            if (widget.isPending) ...[
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            setState(() => _busy = true);
                            await widget.onReject?.call(req);
                            if (mounted) setState(() => _busy = false);
                          },
                    icon: const Icon(Icons.close, size: 16, color: Colors.red),
                    label: const Text('Reject',
                        style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            setState(() => _busy = true);
                            await widget.onApprove?.call(req);
                            if (mounted) setState(() => _busy = false);
                          },
                    icon: _busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(
                                    Colors.white)),
                          )
                        : const Icon(Icons.check, size: 16,
                            color: Colors.white),
                    label: Text(_busy ? 'Processing…' : 'Approve & Delete',
                        style: const TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 10),
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
    );
  }
}

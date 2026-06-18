import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../l10n/app_strings.dart';
import '../../services/base_firestore_service.dart';
import '../../services/coordinator_deletion_service.dart';
import '../../services/teacher_deletion_service.dart'; // For sessionUser helper
import '../../theme.dart';
import '../../shared/utils/app_transitions.dart';

/// Owner review screen for principal-submitted coordinator deletion requests.
/// Approve = delete coordinator's allowed_users doc & Firebase Auth login.
/// Reject = stamp a rejection note.
class CoordinatorDeletionRequestsScreen extends StatefulWidget {
  const CoordinatorDeletionRequestsScreen({super.key});

  @override
  State<CoordinatorDeletionRequestsScreen> createState() =>
      _CoordinatorDeletionRequestsScreenState();
}

class _CoordinatorDeletionRequestsScreenState
    extends State<CoordinatorDeletionRequestsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _svc = CoordinatorDeletionService();

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
    final coordinator = req['coordinatorName'] ?? req['coordinatorEmail'] ?? 'this coordinator';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.check_circle_outline, color: Colors.green),
          const SizedBox(width: 8),
          Text(context.tr('approveDeletion'), style: const TextStyle(fontSize: 17)),
        ]),
        content: Text(
          '${context.tr('permanentlyRemovePrefix')} $coordinator?\n\n'
          '${context.tr('coordinatorDeletionWarning')}',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.tr('cancel'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('approveAndDelete')),
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
        content: Text('$coordinator ${context.tr('removedSuffix')}'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${context.tr('errorPrefix')} $e'),
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
        title: Row(children: [
          const Icon(Icons.cancel_outlined, color: Colors.red),
          const SizedBox(width: 8),
          Text(context.tr('rejectRequest'), style: const TextStyle(fontSize: 17)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.tr('optionalRejectionReason'),
                style: const TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 10),
            TextField(
              controller: noteCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Provide rejection feedback',
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
              child: Text(context.tr('cancel'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('rejectAction')),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr('requestRejected')),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${context.tr('errorPrefix')} $e'),
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
        backgroundColor: AppTheme.primaryDark,
        foregroundColor: Colors.white,
        title: Text(context.tr('coordinatorDeletionRequests')),
        bottom: TabBar(
          controller: _tabs,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          tabs: [
            Tab(text: context.tr('statusPending')),
            Tab(text: context.tr('resolvedTab')),
          ],
        ),
      ),
      body: PremiumTabBarView(
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
                      ? context.tr('noPendingDeletionRequests')
                      : context.tr('noResolvedRequestsYet'),
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
    final coordName = (req['coordinatorName'] as String?)?.trim().isNotEmpty == true
        ? req['coordinatorName'] as String
        : (req['coordinatorEmail'] as String? ?? context.tr('unknownLabel'));
    final cEmail   = (req['coordinatorEmail'] as String?) ?? '';
    final reqBy    = (req['requestedByName'] as String?)?.trim().isNotEmpty == true
        ? req['requestedByName'] as String
        : (req['requestedBy'] as String? ?? '—');
    final reason   = (req['reason'] as String?) ?? '';
    final note     = (req['rejectionNote'] as String?) ?? '';
    final status   = (req['status'] as String?) ?? 'pending';
    final revBy    = (req['reviewedByName'] as String?)?.trim().isNotEmpty == true
        ? req['reviewedByName'] as String
        : (req['reviewedBy'] as String? ?? '');
    final statusText = switch (status) {
      'approved' => context.tr('statusApproved'),
      'rejected' => context.tr('statusRejected'),
      _          => context.tr('statusPending'),
    };

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
                  child: Text(coordName,
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
                    statusText.toUpperCase(),
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _statusColor),
                  ),
                ),
              ],
            ),

            if (cEmail.isNotEmpty) ...[
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: Text(cEmail,
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
                child: Text('${context.tr('requestedByPrefix')} $reqBy',
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
                      child: Text('${context.tr('rejectionNotePrefix')} $note',
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
                '$statusText ${context.tr('by')} '
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
                    label: Text(context.tr('rejectAction'),
                        style: const TextStyle(color: Colors.red)),
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
                    label: Text(_busy ? context.tr('processingEllipsis') : context.tr('approveAndDelete'),
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

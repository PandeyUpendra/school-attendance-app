import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/student_service.dart';
import '../theme.dart';
import '../widgets/index_building_notice.dart';

/// Principal-only screen to review, approve or reject teacher-submitted
/// student deletion requests.
class StudentDeletionRequestsScreen extends StatefulWidget {
  const StudentDeletionRequestsScreen({super.key});

  @override
  State<StudentDeletionRequestsScreen> createState() =>
      _StudentDeletionRequestsScreenState();
}

class _StudentDeletionRequestsScreenState
    extends State<StudentDeletionRequestsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _svc = StudentService();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // ── Data helpers ──────────────────────────────────────────────────────────

  Stream<List<Map<String, dynamic>>> _stream(String status) =>
      FirebaseFirestore.instance
          .collection('student_deletion_requests')
          .where('status', isEqualTo: status)
          .orderBy('requestedAt', descending: true)
          .snapshots()
          .map((snap) => snap.docs.map((d) {
                final data = Map<String, dynamic>.from(d.data());
                data['id'] = d.id;
                return data;
              }).toList());

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _approve(Map<String, dynamic> req) async {
    final students = (req['students'] as List?) ?? [];
    final count    = students.length;
    final teacher  = req['teacherName'] ?? req['teacherEmail'] ?? 'Teacher';

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
          'Allow $teacher to delete $count '
          'student${count == 1 ? '' : 's'}?\n\n'
          'This will permanently remove their records and revoke '
          'any guardian login access.',
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
      await _svc.approveDeletionRequest(req['id'] as String);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '$count student${count == 1 ? '' : 's'} deleted successfully.'),
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
                hintText: 'e.g. Provide transfer certificate first',
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
    if (ok != true || !mounted) return;
    final note = noteCtrl.text.trim();
    noteCtrl.dispose();

    await _svc.rejectDeletionRequest(req['id'] as String,
        rejectionNote: note);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Request rejected.'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Student Deletion Requests'),
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
            stream: _stream('pending'),
            onApprove: _approve,
            onReject: _reject,
            isPending: true,
          ),
          _RequestList(
            stream: _stream('approved'),
            isPending: false,
            secondaryStream: _stream('rejected'),
          ),
        ],
      ),
    );
  }
}

// ── Request list ───────────────────────────────────────────────────────────────

class _RequestList extends StatelessWidget {
  final Stream<List<Map<String, dynamic>>> stream;
  final Stream<List<Map<String, dynamic>>>? secondaryStream;
  final Future<void> Function(Map<String, dynamic>)? onApprove;
  final Future<void> Function(Map<String, dynamic>)? onReject;
  final bool isPending;

  const _RequestList({
    required this.stream,
    this.secondaryStream,
    this.onApprove,
    this.onReject,
    required this.isPending,
  });

  @override
  Widget build(BuildContext context) {
    if (!isPending && secondaryStream != null) {
      // Merge approved + rejected for the resolved tab
      return _MergedList(
        stream1: stream,
        stream2: secondaryStream!,
      );
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError && isIndexBuildingError(snap.error)) {
          return const IndexBuildingNotice();
        }
        final items = snap.data ?? [];
        if (items.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inbox_outlined,
                    size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                Text(
                  isPending
                      ? 'No pending deletion requests'
                      : 'No resolved requests',
                  style: TextStyle(
                      fontSize: 16, color: Colors.grey.shade400),
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          itemBuilder: (_, i) => _RequestCard(
            request: items[i],
            onApprove: onApprove,
            onReject: onReject,
            isPending: isPending,
          ),
        );
      },
    );
  }
}

class _MergedList extends StatelessWidget {
  final Stream<List<Map<String, dynamic>>> stream1;
  final Stream<List<Map<String, dynamic>>> stream2;

  const _MergedList({required this.stream1, required this.stream2});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream1,
      builder: (_, snap1) {
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: stream2,
          builder: (_, snap2) {
            if ((snap1.hasError && isIndexBuildingError(snap1.error)) ||
                (snap2.hasError && isIndexBuildingError(snap2.error))) {
              return const IndexBuildingNotice();
            }
            final list1 = snap1.data ?? [];
            final list2 = snap2.data ?? [];
            final combined = [...list1, ...list2]
              ..sort((a, b) {
                final ta = a['resolvedAt'];
                final tb = b['resolvedAt'];
                if (ta == null && tb == null) return 0;
                if (ta == null) return 1;
                if (tb == null) return -1;
                return (tb as dynamic).compareTo(ta as dynamic);
              });

            if (combined.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.history_outlined,
                        size: 64, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    Text('No resolved requests yet',
                        style: TextStyle(
                            fontSize: 16, color: Colors.grey.shade400)),
                  ],
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: combined.length,
              itemBuilder: (_, i) => _RequestCard(
                  request: combined[i], isPending: false),
            );
          },
        );
      },
    );
  }
}

// ── Individual request card ────────────────────────────────────────────────────

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
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
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
    final students = (req['students'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        [];
    final teacher  = req['teacherName'] ?? req['teacherEmail'] ?? 'Unknown';
    final reason   = (req['reason'] as String?) ?? '';
    final note     = (req['rejectionNote'] as String?) ?? '';

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
            // ── Header row ──────────────────────────────────────────────────
            Row(
              children: [
                Icon(_statusIcon, color: _statusColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${students.length} student${students.length == 1 ? '' : 's'} '
                    '· requested by $teacher',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
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
                    (req['status'] as String).toUpperCase(),
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _statusColor),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 4),
            Text(
              _fmtDate(req['requestedAt']),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),

            // ── Student list ─────────────────────────────────────────────────
            const SizedBox(height: 10),
            ...students.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    Container(
                      width: 28, height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${s['roll'] ?? '?'}',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${s['name'] ?? 'Unknown'} · ${s['className'] ?? ''}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    if ((s['guardianEmail'] as String?)?.isNotEmpty == true)
                      const Icon(Icons.shield_outlined,
                          size: 14, color: AppTheme.accent),
                  ]),
                )),

            // ── Reason ──────────────────────────────────────────────────────
            if (reason.isNotEmpty) ...[
              const SizedBox(height: 8),
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

            // ── Rejection note ───────────────────────────────────────────────
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

            // ── Action buttons (pending only) ────────────────────────────────
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

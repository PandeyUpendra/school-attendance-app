import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/meeting.dart';
import '../../services/meeting_service.dart';
import '../../theme.dart';
import 'meeting_detail_screen.dart';

class CoordinatorMeetingRecordsScreen extends StatefulWidget {
  final String coordinatorEmail;
  final String coordinatorName;

  const CoordinatorMeetingRecordsScreen({
    super.key,
    required this.coordinatorEmail,
    required this.coordinatorName,
  });

  @override
  State<CoordinatorMeetingRecordsScreen> createState() =>
      _CoordinatorMeetingRecordsScreenState();
}

class _CoordinatorMeetingRecordsScreenState
    extends State<CoordinatorMeetingRecordsScreen> {
  final _svc = MeetingService();

  String _filter = 'All';
  String _search = '';
  final _searchCtrl = TextEditingController();

  static const _filters = ['All', 'This Month', 'Completed', 'Draft'];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Meeting> _applyFilter(List<Meeting> meetings) {
    var list = meetings;
    if (_filter == 'This Month') {
      final now = DateTime.now();
      list = list.where((m) =>
          m.createdAt.year == now.year && m.createdAt.month == now.month).toList();
    } else if (_filter == 'Completed') {
      list = list.where((m) => m.status == MeetingStatus.completed).toList();
    } else if (_filter == 'Draft') {
      list = list.where((m) => m.status == MeetingStatus.draft).toList();
    }
    if (_search.isNotEmpty) {
      list = list
          .where((m) => m.title.toLowerCase().contains(_search.toLowerCase()))
          .toList();
    }
    return list;
  }

  String _fmtDate(DateTime d) {
    const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${mo[d.month - 1]} ${d.year}';
  }

  Future<void> _sendReminder(Meeting m) async {
    final dateStr = _fmtDate(m.date);
    final msg = Uri.encodeComponent(
        'Reminder: Tasks from "${m.title}" on $dateStr are pending completion. '
        'Please complete your assigned tasks at your earliest convenience.');
    final uri = Uri.parse('whatsapp://send?text=$msg');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WhatsApp not available')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('My Meeting Records'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // ── Search ───────────────────────────────────────────────────────
          Container(
            color: AppTheme.primary,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _search = v),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search meetings...',
                hintStyle: const TextStyle(color: Colors.white60),
                prefixIcon: const Icon(Icons.search, color: Colors.white60),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, color: Colors.white60),
                        onPressed: () => setState(() {
                          _search = '';
                          _searchCtrl.clear();
                        }),
                      )
                    : null,
                filled: true,
                fillColor: Colors.white.withOpacity(0.15),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),

          // ── Filters ──────────────────────────────────────────────────────
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: _filters.map((f) {
                final active = _filter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(f),
                    selected: active,
                    onSelected: (_) => setState(() => _filter = f),
                    selectedColor: AppTheme.primary,
                    labelStyle: TextStyle(
                        color: active ? Colors.white : Colors.black87,
                        fontSize: 12),
                    backgroundColor: Colors.white,
                    checkmarkColor: Colors.white,
                  ),
                );
              }).toList(),
            ),
          ),

          // ── List ─────────────────────────────────────────────────────────
          Expanded(
            child: StreamBuilder<List<Meeting>>(
              stream: _svc.streamMeetingsByCreator(widget.coordinatorEmail),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return _buildShimmer();
                }
                if (snap.hasError) {
                  return Center(
                      child: Text('Error: ${snap.error}',
                          style: TextStyle(color: Colors.grey.shade500)));
                }

                final all      = snap.data ?? [];
                final filtered = _applyFilter(all);
                final now      = DateTime.now();
                final thisMonth = all.where((m) =>
                    m.createdAt.year == now.year &&
                    m.createdAt.month == now.month).length;
                final pendingTasks = all.fold<int>(
                    0, (acc, m) => acc + m.tasksCreated - m.discussedCount);

                return RefreshIndicator(
                  onRefresh: () async => setState(() {}),
                  color: AppTheme.primary,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      _SummaryCard(
                          thisMonth: thisMonth, pendingTasks: pendingTasks),
                      const SizedBox(height: 12),

                      if (filtered.isEmpty)
                        _emptyState()
                      else
                        ...filtered.map((m) => _CoordMeetingCard(
                              meeting:    m,
                              fmtDate:    _fmtDate,
                              onViewDetails: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MeetingDetailScreen(
                                    meetingId:     m.id,
                                    createdBy:     widget.coordinatorEmail,
                                    createdByName: widget.coordinatorName,
                                    createdByRole: 'coordinator',
                                    readOnly:      m.isReadOnly,
                                  ),
                                ),
                              ),
                              onDownloadPdf: () => _sharePdf(m),
                              onSendReminder: m.tasksCreated > 0 && !m.isCompleted
                                  ? () => _sendReminder(m)
                                  : null,
                            )),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.add),
        label: const Text('New Meeting'),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MeetingDetailScreen(
              createdBy:     widget.coordinatorEmail,
              createdByName: widget.coordinatorName,
              createdByRole: 'coordinator',
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _sharePdf(Meeting m) async {
    try {
      await shareMeetingPdf(m);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF error: $e')),
        );
      }
    }
  }

  Widget _buildShimmer() => Shimmer.fromColors(
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: 4,
          itemBuilder: (_, __) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            height: 160,
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(14)),
          ),
        ),
      );

  Widget _emptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 80),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.history_edu_outlined,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              _search.isNotEmpty
                  ? 'No meetings match "$_search"'
                  : 'No meetings yet',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 6),
            Text('Tap + to create a new meeting',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
          ]),
        ),
      );
}

// ── Summary card ──────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final int thisMonth;
  final int pendingTasks;
  const _SummaryCard({required this.thisMonth, required this.pendingTasks});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppTheme.primaryDark, Color(0xFF880E4F)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          const Icon(Icons.history_edu, color: Colors.white70, size: 28),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('My Meetings: $thisMonth this month',
                style: const TextStyle(color: Colors.white,
                    fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('Pending tasks from meetings: $pendingTasks',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
        ]),
      );
}

// ── Coordinator meeting card ──────────────────────────────────────────────────

class _CoordMeetingCard extends StatefulWidget {
  final Meeting  meeting;
  final String Function(DateTime) fmtDate;
  final VoidCallback  onViewDetails;
  final VoidCallback? onDownloadPdf;
  final VoidCallback? onSendReminder;

  const _CoordMeetingCard({
    required this.meeting,
    required this.fmtDate,
    required this.onViewDetails,
    this.onDownloadPdf,
    this.onSendReminder,
  });

  @override
  State<_CoordMeetingCard> createState() => _CoordMeetingCardState();
}

class _CoordMeetingCardState extends State<_CoordMeetingCard> {
  Color get _statusColor => switch (widget.meeting.status) {
        MeetingStatus.active    => AppTheme.primary,
        MeetingStatus.completed => AppTheme.success,
        MeetingStatus.draft     => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    final m   = widget.meeting;
    final pct = m.points.isEmpty ? 0.0 : m.discussedCount / m.points.length;
    final completedTasks = m.discussedCount;
    final totalTasks     = m.tasksCreated;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.primaryLight.withOpacity(0.3),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(widget.fmtDate(m.date),
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primary)),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(m.status.label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _statusColor)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(m.title,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),

          // Task counts
          Row(children: [
            _CountBadge(
                label: 'Tasks created',
                value: totalTasks,
                color: AppTheme.warning),
            const SizedBox(width: 10),
            _CountBadge(
                label: 'Tasks completed',
                value: completedTasks,
                color: AppTheme.success),
          ]),

          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: Colors.grey.shade100,
              color: AppTheme.primary,
              minHeight: 5,
            ),
          ),
          const SizedBox(height: 2),
          Text('${m.points.length} points · ${m.discussedCount} discussed',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),

          const SizedBox(height: 12),

          // Action buttons
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.visibility_outlined, size: 15),
                label: const Text('Details', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: const BorderSide(color: AppTheme.primary),
                    padding: const EdgeInsets.symmetric(vertical: 6)),
                onPressed: widget.onViewDetails,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.share_outlined, size: 15),
                label: const Text('Share PDF', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.danger,
                    side: const BorderSide(color: AppTheme.danger),
                    padding: const EdgeInsets.symmetric(vertical: 6)),
                onPressed: widget.onDownloadPdf,
              ),
            ),
            if (widget.onSendReminder != null) ...[
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.send_outlined, size: 15),
                  label: const Text('Remind', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF25D366),
                      side: const BorderSide(color: Color(0xFF25D366)),
                      padding: const EdgeInsets.symmetric(vertical: 6)),
                  onPressed: widget.onSendReminder,
                ),
              ),
            ],
          ]),
        ]),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final String label;
  final int    value;
  final Color  color;
  const _CountBadge({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(6),
        ),
        child: RichText(
          text: TextSpan(children: [
            TextSpan(
                text: '$value ',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: 13)),
            TextSpan(
                text: label,
                style: TextStyle(color: color.withOpacity(0.8), fontSize: 11)),
          ]),
        ),
      );
}

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../models/meeting.dart';
import '../../services/meeting_service.dart';
import '../../theme.dart';
import 'meeting_detail_screen.dart';

class PrincipalMeetingRecordsScreen extends StatefulWidget {
  final String principalEmail;
  final String principalName;

  const PrincipalMeetingRecordsScreen({
    super.key,
    required this.principalEmail,
    required this.principalName,
  });

  @override
  State<PrincipalMeetingRecordsScreen> createState() =>
      _PrincipalMeetingRecordsScreenState();
}

class _PrincipalMeetingRecordsScreenState
    extends State<PrincipalMeetingRecordsScreen> {
  final _svc = MeetingService();

  String _filter = 'All'; // All | This Month | Completed | Draft
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
          .where((m) =>
              m.title.toLowerCase().contains(_search.toLowerCase()))
          .toList();
    }

    return list;
  }

  String _fmtDate(DateTime d) {
    const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${mo[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Meeting Records'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: const [],
      ),
      body: Column(
        children: [
          // ── Search bar ───────────────────────────────────────────────────
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

          // ── Filter chips ─────────────────────────────────────────────────
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

          // ── Meeting list ─────────────────────────────────────────────────
          Expanded(
            child: StreamBuilder<List<Meeting>>(
              stream: _svc.streamAllMeetings(),
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

                final all       = snap.data ?? [];
                final filtered  = _applyFilter(all);
                final thisMonth = all.where((m) {
                  final now = DateTime.now();
                  return m.createdAt.year == now.year &&
                      m.createdAt.month == now.month;
                }).length;

                return RefreshIndicator(
                  onRefresh: () async => setState(() {}),
                  color: AppTheme.primary,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      // Monthly summary
                      _MonthlySummaryCard(
                        meetingsThisMonth: thisMonth,
                        totalMeetings:     all.length,
                      ),
                      const SizedBox(height: 12),

                      if (filtered.isEmpty)
                        _emptyState()
                      else
                        ...filtered.map((m) => _MeetingCard(
                              meeting:    m,
                              fmtDate:    _fmtDate,
                              onViewDetails: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MeetingDetailScreen(
                                    meetingId:     m.id,
                                    createdBy:     widget.principalEmail,
                                    createdByName: widget.principalName,
                                    createdByRole: 'principal',
                                    readOnly: m.isReadOnly &&
                                        m.createdBy != widget.principalEmail,
                                  ),
                                ),
                              ),
                              onDownloadPdf: () => _sharePdf(m),
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
              createdBy:     widget.principalEmail,
              createdByName: widget.principalName,
              createdByRole: 'principal',
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

  Widget _buildShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: 5,
        itemBuilder: (_, __) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          height: 140,
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

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
            Text(
              'Tap + to create the first meeting',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
            ),
          ]),
        ),
      );
}

// ── Meeting summary card ──────────────────────────────────────────────────────

class _MonthlySummaryCard extends StatelessWidget {
  final int meetingsThisMonth;
  final int totalMeetings;
  const _MonthlySummaryCard({
    required this.meetingsThisMonth,
    required this.totalMeetings,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppTheme.primaryDark, AppTheme.primaryMid],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          const Icon(Icons.history_edu, color: Colors.white70, size: 28),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('This month: $meetingsThisMonth meetings held',
                style: const TextStyle(color: Colors.white, fontSize: 14,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('All-time: $totalMeetings total meetings',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
        ]),
      );
}

// ── Per-meeting card ──────────────────────────────────────────────────────────

class _MeetingCard extends StatelessWidget {
  final Meeting  meeting;
  final String Function(DateTime) fmtDate;
  final VoidCallback  onViewDetails;
  final VoidCallback? onDownloadPdf;

  const _MeetingCard({
    required this.meeting,
    required this.fmtDate,
    required this.onViewDetails,
    this.onDownloadPdf,
  });

  Color get _statusColor => switch (meeting.status) {
        MeetingStatus.active    => AppTheme.primary,
        MeetingStatus.completed => AppTheme.success,
        MeetingStatus.draft     => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    final pct = meeting.points.isEmpty
        ? 0.0
        : meeting.discussedCount / meeting.points.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Top row
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.primaryLight.withOpacity(0.3),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(fmtDate(meeting.date),
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
              child: Text(meeting.status.label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _statusColor)),
            ),
          ]),
          const SizedBox(height: 8),

          Text(meeting.title,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text('By: ${meeting.createdByName} · ${meeting.createdByRole}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 10),

          // Points progress
          Row(children: [
            Text('${meeting.points.length} points · '
                '${meeting.discussedCount} discussed',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: Colors.grey.shade100,
              color: AppTheme.primary,
              minHeight: 5,
            ),
          ),

          // Teacher avatars
          if (meeting.assignedTeacherNames.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.people_outline,
                  size: 14, color: AppTheme.primary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  meeting.assignedTeacherNames.take(3).join(', ') +
                      (meeting.assignedTeacherNames.length > 3
                          ? ' +${meeting.assignedTeacherNames.length - 3} more'
                          : ''),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ],

          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.visibility_outlined, size: 16),
                label: const Text('View Details', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: const BorderSide(color: AppTheme.primary),
                    padding: const EdgeInsets.symmetric(vertical: 6)),
                onPressed: onViewDetails,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.share_outlined, size: 16),
                label: const Text('Share PDF', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.danger,
                    side: const BorderSide(color: AppTheme.danger),
                    padding: const EdgeInsets.symmetric(vertical: 6)),
                onPressed: onDownloadPdf,
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

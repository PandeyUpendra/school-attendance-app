import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../l10n/app_strings.dart';
import '../../models/meeting.dart';
import '../../services/meeting_service.dart';
import '../../theme.dart';
import '../../shared/widgets/index_building_notice.dart';
import './meeting_detail_screen.dart';
import 'package:provider/provider.dart';
import '../../shared/providers/school_settings_provider.dart';

/// Localised label for a meeting filter (filter values stay English).
String _localizedFilter(BuildContext c, String f) => switch (f) {
      'This Month' => c.tr('filterThisMonth'),
      'Completed' => c.tr('completedLabel'),
      'Draft' => c.tr('draft'),
      _ => c.tr('filterAll'),
    };

/// Localised label for a meeting status (stored status stays English).
String _localizedStatus(BuildContext c, MeetingStatus s) => switch (s) {
      MeetingStatus.draft => c.tr('draft'),
      MeetingStatus.active => c.tr('statusActive'),
      MeetingStatus.completed => c.tr('completedLabel'),
    };

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
  bool _isSearching = false;

  static const _filters = ['All', 'This Month', 'Completed', 'Draft'];

  // ── Swipe support ───────────────────────────────────────────────────

  void _onHorizontalDragEnd(DragEndDetails d) {
    final dx = d.primaryVelocity ?? 0;
    final idx = _filters.indexOf(_filter);
    if (dx < -200 && idx < _filters.length - 1) {
      // Swipe left → next tab
      setState(() => _filter = _filters[idx + 1]);
    } else if (dx > 200 && idx > 0) {
      // Swipe right → previous tab
      setState(() => _filter = _filters[idx - 1]);
    }
  }

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
        title: _isSearching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: context.tr('searchMeetings'),
                  hintStyle: const TextStyle(color: Colors.white60),
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _search = v),
              )
            : Text(context.tr('meetingRecords')),
        backgroundColor: AppTheme.primaryDark,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: _isSearching
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _isSearching = false;
                    _search = '';
                    _searchCtrl.clear();
                  });
                },
              )
            : null,
        actions: [
          if (!_isSearching)
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () {
                setState(() {
                  _isSearching = true;
                });
              },
            )
          else if (_search.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                setState(() {
                  _search = '';
                  _searchCtrl.clear();
                });
              },
            ),
        ],
      ),
      body: Column(
        children: [

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
                    label: Text(_localizedFilter(context, f)),
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

          // ── Meeting list (swipeable) ────────────────────────────────────
          Expanded(
            child: GestureDetector(
              onHorizontalDragEnd: _onHorizontalDragEnd,
              behavior: HitTestBehavior.translucent,
              child: StreamBuilder<List<Meeting>>(
              stream: _svc.streamAllMeetings(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return _buildShimmer();
                }
                if (snap.hasError && isIndexBuildingError(snap.error)) {
                  return IndexBuildingNotice(onRetry: () => setState(() {}));
                }
                if (snap.hasError) {
                  return Center(
                      child: Text(context.tr('errorWithDetailsSnap').replaceAll('{error}', snap.error.toString()),
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
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.add),
        label: Text(context.tr('newMeeting')),
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
      final settings = Provider.of<SchoolSettingsProvider>(context, listen: false);
      await shareMeetingPdf(
        m,
        schoolName: settings.schoolName,
        schoolLogoUrl: settings.schoolLogo,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.tr('pdfError')} $e')),
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
                  ? '${context.tr('noMeetingsMatch')} "$_search"'
                  : context.tr('noMeetingsYet'),
              style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 6),
            Text(
              context.tr('tapPlusFirstMeeting'),
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
          color: AppTheme.primaryDark,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          const Icon(Icons.history_edu, color: Colors.white70, size: 28),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${context.tr('thisMonthLabel')}: $meetingsThisMonth ${context.tr('meetingsHeld')}',
                style: const TextStyle(color: Colors.white, fontSize: 14,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('${context.tr('allTime')}: $totalMeetings ${context.tr('totalMeetings')}',
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
                color: AppTheme.primaryLight.withValues(alpha: 0.3),
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
                color: _statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(_localizedStatus(context, meeting.status),
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
          Text('${context.tr('byLabel')}: ${meeting.createdByName} · ${context.trRole(meeting.createdByRole)}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 10),

          // Points progress
          Row(children: [
            Text('${meeting.points.length} ${context.tr('pointsLower')} · '
                '${meeting.discussedCount} ${context.tr('discussedLower')}',
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
                          ? ' +${meeting.assignedTeacherNames.length - 3} ${context.tr('moreSuffix')}'
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
                label: Text(context.tr('viewDetails'), style: const TextStyle(fontSize: 12)),
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
                label: Text(context.tr('sharePdf'), style: const TextStyle(fontSize: 12)),
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

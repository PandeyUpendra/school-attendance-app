import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/auth_service.dart';
import '../services/student_service.dart';
import '../services/timetable_service.dart';
import '../services/notification_service.dart';
import 'attendance_class_detail_screen.dart';
import 'attendance_history_screen.dart';
import 'class_picker_screen.dart';
import 'leave_requests_screen.dart';
import 'my_timetable_screen.dart';
import 'role_selection_screen.dart';
import 'announcements_screen.dart';
import 'notifications_screen.dart';
import 'analytics_screen.dart';

/// The Principal Portal — a school-wide read-only analytics dashboard.
/// Principal can approve/reject leave applications (same as coordinator).
class PrincipalDashboard extends StatefulWidget {
  const PrincipalDashboard({super.key});

  @override
  State<PrincipalDashboard> createState() => _PrincipalDashboardState();
}

class _PrincipalDashboardState extends State<PrincipalDashboard> {
  bool _loading = true;

  List<ClassSummary> _summaries = [];
  int  _pendingLeaveCount    = 0;
  int  _teachersOnLeaveToday = 0;
  int  _unreadNotifCount     = 0;
  String _principalEmail     = '';

  int  _totalStudents = 0;
  int  _totalPresent = 0;
  int  _totalAbsent = 0;
  int  _totalLeave  = 0;
  int  _classesMarked = 0;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);

    final session = await AuthService().getSession();
    final email   = (session?['email'] as String?) ?? '';

    // getSettings is cached in memory after the first call → near-zero cost.
    final settings = await TimetableService().getSettings();
    final classes  = List<String>.from(settings['classes'] as List);

    // Fire all heavy reads in parallel.
    final summariesFuture = StudentService().loadTodayFullSummary(classes);
    final leavesFuture    =
        TimetableService().getLeaveApplications(status: 'pending');
    final allLeavesFuture = TimetableService().getLeaveApplications();
    final notifFuture     =
        NotificationService().unreadCount(role: 'principal');

    final summaries  = await summariesFuture;
    final pending    = await leavesFuture;
    final allLeaves  = await allLeavesFuture;
    final notifCount = await notifFuture;

    // How many teachers have an approved leave that covers today?
    int onLeaveToday = 0;
    final now = DateTime.now();
    for (final app in allLeaves) {
      if (app['status'] != 'approved') continue;
      final startStr = app['startDate'] as String?;
      if (startStr == null) continue;
      final start = DateTime.tryParse(startStr);
      if (start == null) continue;
      final days = (app['numberOfDays'] as num?)?.toInt() ?? 1;
      final end  = start.add(Duration(days: days - 1));
      final today = DateTime(now.year, now.month, now.day);
      if (!today.isBefore(DateTime(start.year, start.month, start.day)) &&
          !today.isAfter (DateTime(end.year,   end.month,   end.day))) {
        onLeaveToday++;
      }
    }

    if (!mounted) return;

    int ts = 0, tp = 0, ta = 0, tl = 0, cm = 0;
    for (final s in summaries) {
      ts += s.total;
      tp += s.present;
      ta += s.absent;
      tl += s.leave;
      if (s.marked) cm++;
    }

    setState(() {
      _principalEmail       = email;
      _summaries            = summaries;
      _pendingLeaveCount    = pending.length;
      _teachersOnLeaveToday = onLeaveToday;
      _totalStudents        = ts;
      _totalPresent         = tp;
      _totalAbsent          = ta;
      _totalLeave           = tl;
      _classesMarked        = cm;
      _unreadNotifCount     = notifCount;
      _loading              = false;
    });
  }

  Future<void> _logout() async {
    await AuthService().clearSession();
    if (!mounted) return;
    Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => const RoleSelectionScreen()));
  }

  Future<void> _navigate(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  double get _schoolPresentPct {
    final marked = _summaries.where((s) => s.marked).toList();
    final denom  = marked.fold(0, (t, s) => t + s.total);
    if (denom == 0) return 0;
    final num = marked.fold(0, (t, s) => t + s.present);
    return num / denom * 100;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Principal',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('School-wide overview',
                style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                tooltip: 'Notifications',
                onPressed: () async {
                  await _navigate(const NotificationsScreen(role: 'principal'));
                  _loadAll();
                },
              ),
              if (_unreadNotifCount > 0)
                Positioned(
                  right: 8, top: 8,
                  child: Container(
                    width: 14, height: 14,
                    decoration: const BoxDecoration(
                      color: Colors.red, shape: BoxShape.circle),
                    child: Center(
                      child: Text(
                        _unreadNotifCount > 9 ? '9+' : '$_unreadNotifCount',
                        style: const TextStyle(
                            fontSize: 8,
                            color: Colors.white,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _logout,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        color: AppTheme.primary,
        child: _loading
            ? ListView(children: const [
                SizedBox(height: 120),
                Center(child: CircularProgressIndicator(color: AppTheme.primary)),
              ])
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  // ── Today's hero card ───────────────────────────────
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: _SchoolTodayCard(
                      totalStudents: _totalStudents,
                      present: _totalPresent,
                      absent:  _totalAbsent,
                      leave:   _totalLeave,
                      classesMarked: _classesMarked,
                      totalClasses:  _summaries.length,
                      pct: _schoolPresentPct,
                    ),
                  ),

                  // ── Staff overview row ──────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                    child: Row(children: [
                      Expanded(
                        child: _MiniStatCard(
                          icon: Icons.event_busy_outlined,
                          color: Colors.orange,
                          value: '$_teachersOnLeaveToday',
                          label: 'Teachers on leave today',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _MiniStatCard(
                          icon: Icons.hourglass_top_outlined,
                          color: Colors.deepPurple,
                          value: '$_pendingLeaveCount',
                          label: 'Pending leave requests',
                        ),
                      ),
                    ]),
                  ),

                  // ── Class-wise attendance ───────────────────────────
                  _SectionHeader("TODAY'S ATTENDANCE BY CLASS"),
                  if (_summaries.isEmpty)
                    _emptyInfo('No classes configured yet')
                  else
                    for (int i = 0; i < _summaries.length; i++) ...[
                      _AttendanceTile(
                        summary: _summaries[i],
                        onTap: _summaries[i].marked
                            ? () => _navigate(
                                AttendanceClassDetailScreen(
                                    summary: _summaries[i]))
                            : null,
                      ),
                      if (i < _summaries.length - 1)
                        const Divider(height: 1, indent: 72),
                    ],

                  // ── Tools ───────────────────────────────────────────
                  _SectionHeader('ANALYTICS'),
                  _FeatureTile(
                    icon: Icons.analytics_outlined,
                    color: AppTheme.primary,
                    title: 'Analytics Dashboard',
                    subtitle:
                        'Attendance trends, absences, fee progress & charts',
                    onTap: () => _navigate(const AnalyticsScreen()),
                  ),
                  const Divider(height: 1, indent: 72),
                  _SectionHeader('TOOLS'),
                  _FeatureTile(
                    icon: Icons.campaign_outlined,
                    color: AppTheme.primary,
                    title: 'Announcements',
                    subtitle: 'Post and view school notices',
                    onTap: () => _navigate(AnnouncementsScreen(
                      viewerRole: 'principal',
                      posterName: _principalEmail,
                    )),
                  ),
                  const Divider(height: 1, indent: 72),
                  _FeatureTile(
                    icon: Icons.hourglass_top_outlined,
                    color: AppTheme.warning,
                    title: 'Leave Requests',
                    subtitle:
                        'Review & approve pending applications from teachers',
                    badge: _pendingLeaveCount > 0
                        ? '$_pendingLeaveCount'
                        : null,
                    onTap: () async {
                      await _navigate(const LeaveRequestsScreen());
                      _loadAll();
                    },
                  ),
                  const Divider(height: 1, indent: 72),
                  _FeatureTile(
                    icon: Icons.bar_chart_outlined,
                    color: AppTheme.primary,
                    title: 'Attendance Reports',
                    subtitle:
                        'Monthly history, % per student & low-attendance flags',
                    onTap: () async {
                      final cls = await Navigator.push<String>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ClassPickerScreen(
                              mode: ClassPickerMode.reports),
                        ),
                      );
                      if (cls != null && mounted) {
                        _navigate(AttendanceHistoryScreen(className: cls));
                      }
                    },
                  ),
                  const Divider(height: 1, indent: 72),
                  _FeatureTile(
                    icon: Icons.table_chart_outlined,
                    color: AppTheme.primary,
                    title: 'School Timetable',
                    subtitle: 'View & share class timetables as PDF',
                    onTap: () => _navigate(const MyTimetableScreen()),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
      ),
    );
  }

  Widget _emptyInfo(String msg) => Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Icon(Icons.info_outline,
              color: Colors.grey.shade400, size: 20),
          const SizedBox(width: 10),
          Text(msg,
              style:
                  TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        ]),
      );
}

// ─── Hero card — today's school summary ──────────────────────────────────────

class _SchoolTodayCard extends StatelessWidget {
  final int totalStudents, present, absent, leave;
  final int classesMarked, totalClasses;
  final double pct;

  const _SchoolTodayCard({
    required this.totalStudents,
    required this.present,
    required this.absent,
    required this.leave,
    required this.classesMarked,
    required this.totalClasses,
    required this.pct,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primaryDark, AppTheme.primaryMid],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.today_outlined, color: Colors.white, size: 20),
            const SizedBox(width: 6),
            const Text('TODAY',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1)),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$classesMarked / $totalClasses classes marked',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                totalStudents == 0 ? '—' : '${pct.toStringAsFixed(1)}%',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    height: 1),
              ),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text('Present',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _HeroStat(value: '$present', label: 'Present'),
              _HeroStat(value: '$absent',  label: 'Absent'),
              _HeroStat(value: '$leave',   label: 'Leave'),
              _HeroStat(value: '$totalStudents', label: 'Total'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String value, label;
  const _HeroStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ]);
}

// ─── Mini stat card ──────────────────────────────────────────────────────────

class _MiniStatCard extends StatelessWidget {
  final IconData icon;
  final Color    color;
  final String   value, label;

  const _MiniStatCard({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: color)),
              Text(label,
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ]),
    );
  }
}

// ─── Attendance tile ─────────────────────────────────────────────────────────

class _AttendanceTile extends StatelessWidget {
  final ClassSummary summary;
  final VoidCallback? onTap;
  const _AttendanceTile({required this.summary, this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final markedColor = s.absent > 0
        ? const Color(0xFFC62828)
        : s.leave > 0
            ? const Color(0xFFF57F17)
            : const Color(0xFF2E7D32);

    return InkWell(
      onTap: onTap,
      child: Container(
        color: Colors.white,
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: s.marked
                  ? markedColor.withOpacity(0.12)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              s.marked
                  ? Icons.fact_check_outlined
                  : Icons.pending_outlined,
              color: s.marked ? markedColor : Colors.grey.shade400,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.className,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                if (s.marked)
                  Text(
                    'Present ${s.present}/${s.total}  ·  '
                    'Absent ${s.absent}  ·  Leave ${s.leave}',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500),
                  )
                else
                  Text('Not marked yet',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade400,
                          fontStyle: FontStyle.italic)),
              ],
            ),
          ),
          if (s.marked)
            Icon(Icons.chevron_right,
                color: Colors.grey.shade400, size: 20),
        ]),
      ),
    );
  }
}

// ─── Shared small widgets ────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(title,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500,
              letterSpacing: 0.8)),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  final IconData     icon;
  final Color        color;
  final String       title, subtitle;
  final VoidCallback onTap;
  final String?      badge;

  const _FeatureTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500)),
              ],
            ),
          ),
          if (badge != null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(badge!,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            )
          else
            Icon(Icons.chevron_right,
                color: Colors.grey.shade400, size: 20),
        ]),
      ),
    );
  }
}

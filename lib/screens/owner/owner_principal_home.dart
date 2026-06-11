import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/exam.dart';
import '../../models/student.dart';
import '../../providers/school_settings_provider.dart';
import '../../services/announcement_service.dart';
import '../../services/auth_service.dart';
import '../../services/exam_service.dart';
import '../../services/role_permission_service.dart';
import '../../services/school_settings_service.dart';
import '../../services/student_service.dart';
import '../../services/timetable_service.dart';
import '../../theme.dart';
import '../profile_screen.dart';
import '../../widgets/announcement_composer.dart';
import '../../widgets/email_text_form_field.dart';
import '../../utils/role_guard.dart';
import '../onboarding/school_onboarding_screen.dart';
import '../principal_dashboard.dart';
import 'staff_directory_helpers.dart';
import '../../widgets/refreshable_data.dart';
import '../../utils/app_logger.dart';
import '../../utils/phone_utils.dart';
import '../../utils/currency_utils.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Owner-Principal Home — menu-list entry point
// ══════════════════════════════════════════════════════════════════════════════

class OwnerPrincipalHome extends StatefulWidget {
  const OwnerPrincipalHome({super.key});

  @override
  State<OwnerPrincipalHome> createState() => _OwnerPrincipalHomeState();
}

class _OwnerPrincipalHomeState extends State<OwnerPrincipalHome> {
  String _myEmail = '';
  String _myRole = 'ownerPrincipal';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      RoleGuard.verify(context, ['ownerPrincipal']);
    });
    _init();
  }

  Future<void> _init() async {
    final session = await AuthService().getSession();
    if (!mounted) return;
    final email = session?['email'] as String? ?? '';
    final role = session?['role'] as String? ?? 'ownerPrincipal';

    // Check onboarding completion
    try {
      final onboarding = await SchoolSettingsService().getOnboardingStatus();
      final isCompleted = onboarding['isCompleted'] as bool? ?? false;
      if (!isCompleted && mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (_) => const SchoolOnboardingScreen(destination: OwnerPrincipalHome()),
        ));
        return;
      }
    } catch (e, st) { AppLogger.e('OwnerPrincipalHome', 'Best-effort op failed', e, st); }

    if (!mounted) return;
    setState(() {
      _myEmail = email;
      _myRole = role;
      _loaded = true;
    });
  }



  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: LoadingState());
    }
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: ListView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom,
        ),
        children: [
          _buildHero(),
          const SizedBox(height: 4),

          const _SectionHeader('OVERVIEW'),
          _FeatureTile(
            icon: Icons.dashboard_outlined,
            color: AppTheme.primary,
            title: 'School Dashboard',
            subtitle: 'Today\'s health, attendance & weekly trend',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _OPDashPage())),
          ),

          const _SectionHeader('STAFF'),
          _FeatureTile(
            icon: Icons.people_outline,
            color: AppTheme.primary,
            title: 'Staff Overview',
            subtitle: 'Teachers, leave requests & activity',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _OPStaffPage())),
          ),

          const _SectionHeader('ACADEMICS'),
          _FeatureTile(
            icon: Icons.menu_book_outlined,
            color: AppTheme.primary,
            title: 'Academics',
            subtitle: 'Recent tests & upcoming exam calendar',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _OPAcademicsPage())),
          ),

          const _SectionHeader('FINANCE'),
          _FeatureTile(
            icon: Icons.currency_rupee_outlined,
            color: AppTheme.primary,
            title: 'Fee Collection',
            subtitle: 'Collected, pending, overdue & defaulters',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _OPFinancePage())),
          ),

          const _SectionHeader('PRINCIPAL VIEW'),
          _FeatureTile(
            icon: Icons.admin_panel_settings_outlined,
            color: AppTheme.primary,
            title: 'Principal Dashboard',
            subtitle: 'Attendance, tasks, digest, leave requests, analytics & more',
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => const PrincipalDashboard(),
            )),
          ),

          const _SectionHeader('MANAGE'),
          _FeatureTile(
            icon: Icons.settings_outlined,
            color: AppTheme.primary,
            title: 'Manage School',
            subtitle: 'Accounts, school settings & announcements',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _OPManagePage(email: _myEmail, role: _myRole))),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildHero() {
    final now = DateTime.now();
    const wdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final dateStr = '${wdays[now.weekday - 1]}, ${now.day} ${months[now.month - 1]}';
    final settingsProvider = context.watch<SchoolSettingsProvider>();
    final displayName = settingsProvider.schoolName;
    final logoUrl = settingsProvider.schoolLogo;

    return ClipPath(
      clipper: _OPWaveClipper(),
      child: Container(
        decoration: const BoxDecoration(
          color: AppTheme.primaryDark,
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 8, 52),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.business_center_outlined, color: Colors.white60, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'OWNER-PRINCIPAL  ·  $dateStr',
                      style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.9),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.account_circle_outlined, color: Colors.white, size: 22),
                    tooltip: 'My Profile',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ProfileScreen()),
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  if (logoUrl.isNotEmpty) ...[
                    CircleAvatar(
                      radius: 18,
                      backgroundImage: CachedNetworkImageProvider(logoUrl),
                      backgroundColor: Colors.white24,
                    ),
                    const SizedBox(width: 10),
                  ] else ...[
                    const CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.white24,
                      child: Icon(Icons.school, color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      displayName,
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, height: 1.1),
                    ),
                  ),
                ]),
                const SizedBox(height: 3),
                Text(_myEmail, style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Sub-page: Dashboard
// ══════════════════════════════════════════════════════════════════════════════

class _OPDashPage extends StatefulWidget {
  const _OPDashPage();

  @override
  State<_OPDashPage> createState() => _OPDashPageState();
}

class _OPDashPageState extends State<_OPDashPage> {
  static const _primary = AppTheme.primary;
  bool _loading = true;
  int _total = 0, _present = 0, _absent = 0, _activeTeachers = 0;
  List<Map<String, dynamic>> _classAtt = [];
  List<String> _alerts = [];
  List<FlSpot> _trend = [];
  List<String> _trendLabels = [];

  final _svc = TimetableService.instance;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final settings = await _svc.getSettings();
      final classes = List<String>.from(settings['classes'] as List? ?? []);
      final summaries = await StudentService.instance.loadTodayFullSummary(classes: classes);
      int tot = 0, pre = 0, abs = 0;
      final classAtt = <Map<String, dynamic>>[];
      for (final s in summaries) {
        tot += s.total; pre += s.present; abs += s.absent + s.leave;
        classAtt.add({'className': s.className, 'total': s.total, 'present': s.present, 'marked': s.marked, 'pct': s.total > 0 ? s.present / s.total * 100 : 0.0});
      }
      final alerts = <String>[];
      for (final c in classAtt) {
        if ((c['marked'] as bool) && (c['pct'] as double) < 70) {
          alerts.add('Low attendance in ${c['className']}: ${(c['pct'] as double).toStringAsFixed(0)}%');
        }
      }
      final leaves = await _svc.getLeaveApplications(status: 'pending');
      if (leaves.length > 3) alerts.add('${leaves.length} leave requests pending approval');

      final byClass = {for (final s in summaries) s.className: s.total};
      final spots = <FlSpot>[];
      final labels = <String>[];
      final db = FirebaseFirestore.instance;
      final days = List.generate(7, (i) => DateTime.now().subtract(Duration(days: 6 - i)));
      final futures = <Future<DocumentSnapshot<Map<String, dynamic>>>>[];
      // Fail loud instead of defaulting to 'school_1': an owner session always
      // has a resolved school, and a silent fallback would read/write another
      // tenant's data (SCALE-06).
      final sid = AuthService.currentSchoolId;
      for (final day in days) {
        for (final cls in classes) {
          futures.add(db.collection('schools').doc(sid).collection('attendance').doc('${cls.replaceAll(' ', '_')}_${day.year}-${day.month}-${day.day}').get());
        }
      }
      final results = await Future.wait(futures);
      for (int d = 0; d < 7; d++) {
        final day = days[d];
        int dP = 0, dT = 0;
        for (int c = 0; c < classes.length; c++) {
          final doc = results[d * classes.length + c];
          if (doc.exists && doc.data() != null) {
            dP += (Map<String, dynamic>.from((doc.data()!['rolls'] as Map?) ?? {})).values.where((v) => v == 'Present').length;
          }
          dT += byClass[classes[c]] ?? 0;
        }
        spots.add(FlSpot(d.toDouble(), dT > 0 ? dP / dT * 100 : 0.0));
        labels.add('${day.day}/${day.month}');
      }
      if (!mounted) return;
      setState(() {
        _total = tot; _present = pre; _absent = abs;
        _activeTeachers = summaries.where((s) => s.marked).length;
        _classAtt = classAtt; _alerts = alerts; _trend = spots; _trendLabels = labels;
        _loading = false;
      });
    } catch (e, st) { AppLogger.e('OwnerPrincipalHome', 'Load failed', e, st); if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(backgroundColor: _primary, foregroundColor: Colors.white, elevation: 0, title: const Text('School Dashboard')),
      body: RefreshIndicator(
        onRefresh: _load, color: _primary,
        child: _loading ? _opShimmer() : CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _opHeader('TODAY\'S SCHOOL HEALTH')),
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: GridView.count(
                crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.6,
                children: [
                  _OPStatCard(label: 'Total Students', value: '$_total', icon: Icons.people_outline, color: _primary),
                  _OPStatCard(label: 'Present Today', value: '$_present', icon: Icons.check_circle_outline, color: AppTheme.success),
                  _OPStatCard(label: 'Teachers Active', value: '$_activeTeachers', icon: Icons.person_outline, color: AppTheme.primaryMid),
                  _OPStatCard(label: 'Absent Today', value: '$_absent', icon: Icons.cancel_outlined, color: AppTheme.danger),
                ],
              ),
            )),
            SliverToBoxAdapter(child: _opHeader('ATTENDANCE OVERVIEW')),
            SliverToBoxAdapter(child: _buildAttendance()),
            SliverToBoxAdapter(child: _opHeader('QUICK ALERTS')),
            SliverToBoxAdapter(child: _buildAlerts()),
            SliverToBoxAdapter(child: _opHeader('WEEKLY TREND')),
            SliverToBoxAdapter(child: _buildTrend()),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendance() {
    if (_classAtt.isEmpty) return _opEmpty(Icons.bar_chart_outlined, 'No attendance data yet');
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Column(
      children: _classAtt.map((c) {
        final marked = c['marked'] as bool;
        final pct = c['pct'] as double;
        final col = !marked ? Colors.grey.shade400 : pct >= 90 ? AppTheme.success : pct >= 75 ? AppTheme.warning : AppTheme.danger;
        return _OPCard(margin: const EdgeInsets.only(bottom: 8), child: Row(children: [
          SizedBox(width: 80, child: Text(c['className'] as String, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
          Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: marked ? pct / 100 : 0, minHeight: 10, backgroundColor: Colors.grey.shade200, valueColor: AlwaysStoppedAnimation<Color>(col)))),
          const SizedBox(width: 8),
          SizedBox(width: 56, child: Text(marked ? '${pct.toStringAsFixed(0)}%' : 'Not marked', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: marked ? col : Colors.grey))),
        ]));
      }).toList(),
    ));
  }

  Widget _buildAlerts() {
    if (_alerts.isEmpty) {
      return const Padding(padding: EdgeInsets.symmetric(horizontal: 14, vertical: 4), child: _OPCard(child: Row(children: [
        Icon(Icons.check_circle_outline, color: AppTheme.success, size: 20), SizedBox(width: 10),
        Text('All good today', style: TextStyle(color: AppTheme.success, fontWeight: FontWeight.w600)),
      ])));
    }
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Column(
      children: _alerts.map((a) => _OPCard(margin: const EdgeInsets.only(bottom: 8), borderColor: AppTheme.accent, child: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: AppTheme.accent, size: 18), const SizedBox(width: 10),
        Expanded(child: Text(a, style: const TextStyle(fontSize: 13))),
      ]))).toList(),
    ));
  }

  Widget _buildTrend() {
    if (_trend.isEmpty) return _opEmpty(Icons.show_chart, 'Loading trend data…');
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: _OPCard(child: SizedBox(height: 160, child: LineChart(LineChartData(
      gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey.shade200, strokeWidth: 1)),
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 22,
          getTitlesWidget: (v, _) { final i = v.toInt(); if (i < 0 || i >= _trendLabels.length) return const SizedBox.shrink(); return Padding(padding: const EdgeInsets.only(top: 4), child: Text(_trendLabels[i], style: const TextStyle(fontSize: 9, color: Colors.grey))); })),
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32, getTitlesWidget: (v, _) => Text('${v.toInt()}%', style: const TextStyle(fontSize: 9, color: Colors.grey)))),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false), minX: 0, maxX: 6, minY: 0, maxY: 100,
      lineBarsData: [LineChartBarData(spots: _trend, isCurved: true, color: _primary, barWidth: 2.5, isStrokeCapRound: true, dotData: const FlDotData(show: true), belowBarData: BarAreaData(show: true, color: _primary.withValues(alpha: 0.08)))],
    )))));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Sub-page: Staff
// ══════════════════════════════════════════════════════════════════════════════

class _OPStaffPage extends StatefulWidget {
  const _OPStaffPage();

  @override
  State<_OPStaffPage> createState() => _OPStaffPageState();
}

class _OPStaffPageState extends State<_OPStaffPage> {
  static const _primary = AppTheme.primary;
  bool _loading = true;
  List<Map<String, dynamic>> _teachers = [], _leaves = [];
  String _search = '';

  final _svc = TimetableService.instance;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final all = await _svc.getAllowedUsers();
      final session = await AuthService().getSession();
      final myEmail = (session?['email'] as String? ?? '').toLowerCase();
      // All staff roles (teachers, coordinators, principals, …), excluding
      // guardians and the owner's own account (no need to list yourself).
      final staff = all.where((u) =>
              u['role'] != 'guardian' &&
              (u['email'] as String? ?? '').toLowerCase() != myEmail)
          .toList()
        ..sort(staffByRoleThenName);
      final leaves = await _svc.getLeaveApplications(status: 'pending');
      if (!mounted) return;
      setState(() { _teachers = staff; _leaves = leaves; _loading = false; });
    } catch (e, st) { AppLogger.e('OwnerPrincipalHome', 'Load failed', e, st); if (mounted) setState(() => _loading = false); }
  }

  Future<void> _updateLeave(String id, String status) async {
    try {
      await _svc.updateLeaveApplication('', id, status);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(backgroundColor: AppTheme.background,
        appBar: AppBar(backgroundColor: _primary, foregroundColor: Colors.white, elevation: 0, title: const Text('Staff')),
        body: _opShimmer());
    }
    final activeCount  = _teachers.where((t) => staffStatusOf(t) == 'active').length;
    final pendingCount = _teachers.where((t) => staffStatusOf(t) == 'pending').length;
    final filtered = _teachers.where((t) {
      if (_search.isEmpty) return true;
      return (t['email'] as String? ?? '').toLowerCase().contains(_search) || (t['name'] as String? ?? '').toLowerCase().contains(_search);
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(backgroundColor: _primary, foregroundColor: Colors.white, elevation: 0, title: const Text('Staff')),
      body: RefreshIndicator(onRefresh: _load, color: _primary, child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _opHeader('STAFF OVERVIEW')),
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Row(children: [
            Expanded(child: _OPStatCard(label: 'Total', value: '${_teachers.length}', icon: Icons.people_outline, color: _primary, compact: true)),
            const SizedBox(width: 10),
            Expanded(child: _OPStatCard(label: 'Active', value: '$activeCount', icon: Icons.check_circle_outline, color: AppTheme.success, compact: true)),
            const SizedBox(width: 10),
            Expanded(child: _OPStatCard(label: 'Pending', value: '$pendingCount', icon: Icons.hourglass_empty_outlined, color: AppTheme.warning, compact: true)),
          ]))),
          if (_leaves.isNotEmpty) ...[
            SliverToBoxAdapter(child: _opHeader('PENDING LEAVES', trailing: _opBadge(_leaves.length))),
            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Column(
              children: _leaves.map((leave) {
                final name = leave['teacherName'] as String? ?? leave['teacherId'] as String? ?? '—';
                final id = leave['id'] as String? ?? '';
                return _OPCard(margin: const EdgeInsets.only(bottom: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    CircleAvatar(radius: 16, backgroundColor: _primary.withValues(alpha: 0.12), child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'T', style: const TextStyle(color: _primary, fontWeight: FontWeight.bold, fontSize: 12))),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      Text('${leave['fromDate'] ?? ''} → ${leave['toDate'] ?? ''}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ])),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: AppTheme.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: const Text('Pending', style: TextStyle(fontSize: 11, color: AppTheme.warning, fontWeight: FontWeight.w600))),
                  ]),
                  if ((leave['reason'] as String? ?? '').isNotEmpty) ...[const SizedBox(height: 6), Text(leave['reason'] as String, style: const TextStyle(fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis)],
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: OutlinedButton(style: OutlinedButton.styleFrom(foregroundColor: AppTheme.danger, side: const BorderSide(color: AppTheme.danger), padding: const EdgeInsets.symmetric(vertical: 6)), onPressed: () => _updateLeave(id, 'rejected'), child: const Text('Reject', style: TextStyle(fontSize: 12)))),
                    const SizedBox(width: 8),
                    Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success, padding: const EdgeInsets.symmetric(vertical: 6)), onPressed: () => _updateLeave(id, 'approved'), child: const Text('Approve', style: TextStyle(fontSize: 12)))),
                  ]),
                ]));
              }).toList(),
            ))),
          ],
          SliverToBoxAdapter(child: _opHeader('STAFF LIST')),
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 8), child: TextField(
            decoration: const InputDecoration(hintText: 'Search staff…', prefixIcon: Icon(Icons.search, color: Colors.grey), isDense: true),
            onChanged: (v) => setState(() => _search = v.toLowerCase()),
          ))),
          SliverToBoxAdapter(child: filtered.isEmpty
              ? _opEmpty(Icons.people_outline, 'No staff found')
              : Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Column(
                  children: filtered.map((t) {
                    final email = t['email'] as String? ?? '';
                    final name = (t['name'] as String? ?? '').isNotEmpty ? t['name'] as String : email;
                    final role = t['role'] as String? ?? 'teacher';
                    final classes = List<String>.from(t['assignedClasses'] as List? ?? []);
                    final isOnLeave = _leaves.any((l) => (l['teacherId'] as String? ?? '') == email);
                    final status = staffStatusOf(t);
                    return _OPCard(margin: const EdgeInsets.only(bottom: 8), child: Row(children: [
                      CircleAvatar(radius: 20, backgroundColor: staffRoleColor(role).withValues(alpha: 0.12), child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'S', style: TextStyle(color: staffRoleColor(role), fontWeight: FontWeight.bold))),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Flexible(child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: 6),
                          StaffRolePill(role: role),
                        ]),
                        Text(email, style: const TextStyle(color: Colors.grey, fontSize: 11), overflow: TextOverflow.ellipsis),
                        if (classes.isNotEmpty) Text(classes.join(', '), style: TextStyle(color: _primary.withValues(alpha: 0.7), fontSize: 11)),
                      ])),
                      const SizedBox(width: 6),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                        StaffStatusPill(status: status),
                        if (isOnLeave) ...[
                          const SizedBox(height: 4),
                          const Text('On Leave', style: TextStyle(fontSize: 9, color: AppTheme.warning, fontWeight: FontWeight.w600)),
                        ],
                      ]),
                    ]));
                  }).toList(),
                ))),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      )),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Sub-page: Academics
// ══════════════════════════════════════════════════════════════════════════════

class _OPAcademicsPage extends StatefulWidget {
  const _OPAcademicsPage();

  @override
  State<_OPAcademicsPage> createState() => _OPAcademicsPageState();
}

class _OPAcademicsPageState extends State<_OPAcademicsPage> {
  static const _primary = AppTheme.primary;
  bool _loading = true;
  List<Exam> _recent = [], _upcoming = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final all = await ExamService().getExams();
      final now = DateTime.now();
      final upcoming = all.where((e) => e.examDate.isAfter(now) && e.examDate.isBefore(now.add(const Duration(days: 30)))).toList()
        ..sort((a, b) => a.examDate.compareTo(b.examDate));
      if (!mounted) return;
      setState(() { _recent = all.take(5).toList(); _upcoming = upcoming; _loading = false; });
    } catch (e, st) { AppLogger.e('OwnerPrincipalHome', 'Load failed', e, st); if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(backgroundColor: _primary, foregroundColor: Colors.white, elevation: 0, title: const Text('Academics')),
      body: RefreshIndicator(onRefresh: _load, color: _primary, child: _loading ? _opShimmer() : CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _opHeader('RECENT TESTS')),
          SliverToBoxAdapter(child: _recent.isEmpty ? _opEmpty(Icons.quiz_outlined, 'No tests recorded yet') : Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Column(
            children: _recent.map((exam) {
              final dt = exam.examDate;
              return _OPCard(margin: const EdgeInsets.only(bottom: 8), child: Row(children: [
                Container(width: 44, height: 44, decoration: BoxDecoration(color: _primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.quiz_outlined, color: _primary, size: 22)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(exam.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  Text('${exam.className}  ·  ${dt.day}/${dt.month}/${dt.year}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ])),
              ]));
            }).toList(),
          ))),
          SliverToBoxAdapter(child: _opHeader('EXAM CALENDAR (NEXT 30 DAYS)')),
          SliverToBoxAdapter(child: _upcoming.isEmpty ? _opEmpty(Icons.event_note_outlined, 'No upcoming exams in the next 30 days') : Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Column(
            children: _upcoming.map((exam) {
              final dt = exam.examDate;
              final daysLeft = dt.difference(DateTime.now()).inDays;
              final dColor = daysLeft <= 3 ? AppTheme.danger : daysLeft <= 7 ? AppTheme.warning : _primary;
              return _OPCard(margin: const EdgeInsets.only(bottom: 8), child: Row(children: [
                Column(children: [
                  Text('${dt.day}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _primary)),
                  Text(['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][dt.month - 1], style: const TextStyle(fontSize: 11, color: _primary)),
                ]),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(exam.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(exam.className, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ])),
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: dColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(daysLeft == 0 ? 'Today' : '${daysLeft}d left', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: dColor))),
              ]));
            }).toList(),
          ))),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      )),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Sub-page: Finance
// ══════════════════════════════════════════════════════════════════════════════

class _OPFinancePage extends StatefulWidget {
  const _OPFinancePage();

  @override
  State<_OPFinancePage> createState() => _OPFinancePageState();
}

class _OPFinancePageState extends State<_OPFinancePage> {
  static const _primary = AppTheme.primary;
  bool _loading = true;
  double _collected = 0, _pending = 0, _overdue = 0;
  List<Map<String, dynamic>> _defaulters = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      // Fail loud instead of defaulting to 'school_1': an owner session always
      // has a resolved school, and a silent fallback would read/write another
      // tenant's data (SCALE-06).
      final sid = AuthService.currentSchoolId;
      final snap = await FirebaseFirestore.instance.collection('schools').doc(sid).collection('students').get();
      final students = snap.docs.map((d) => Student.fromJson(Map<String, dynamic>.from(d.data()))).toList();
      double col = 0, pen = 0, ov = 0;
      final defaulters = <Map<String, dynamic>>[];
      final now = DateTime.now();
      for (final s in students) {
        final amount = s.feeAmount ?? 5000.0;
        if (s.feeStatus == 'Paid') {
          col += amount;
        } else {
          final due = s.feeDueDate != null ? DateTime.tryParse(s.feeDueDate!) ?? now : now;
          if (due.isBefore(now)) { ov += amount; defaulters.add({'name': s.name, 'className': s.className, 'amount': amount, 'daysOverdue': now.difference(due).inDays, 'phone': s.parentPhone ?? s.phone}); }
          else { pen += amount; }
        }
      }
      defaulters.sort((a, b) => (b['daysOverdue'] as int).compareTo(a['daysOverdue'] as int));
      if (!mounted) return;
      setState(() { _collected = col; _pending = pen; _overdue = ov; _defaulters = defaulters.take(10).toList(); _loading = false; });
    } catch (e, st) { AppLogger.e('OwnerPrincipalHome', 'Load failed', e, st); if (mounted) setState(() => _loading = false); }
  }

  Future<void> _sendReminders() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Send Fee Reminders?'),
      content: Text('Send WhatsApp reminders to ${_defaulters.length} overdue guardians?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success), onPressed: () => Navigator.pop(context, true), child: const Text('Send All')),
      ],
    ));
    if (ok != true) return;
    for (final d in _defaulters) {
      final phone = d['phone'] as String;
      if (phone.replaceAll(RegExp(r'\D'), '').isEmpty) continue;
      final msg = 'Dear Parent of ${d['name']}, your fee of ${CurrencyUtils.formatRupees(d['amount'] as double)} is overdue.';
      final url = PhoneUtils.whatsAppUri(phone, text: msg);
      await launchUrl(url, mode: LaunchMode.externalApplication);
      await Future.delayed(const Duration(milliseconds: 800));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(backgroundColor: _primary, foregroundColor: Colors.white, elevation: 0, title: const Text('Fee Collection')),
      body: RefreshIndicator(onRefresh: _load, color: _primary, child: _loading ? _opShimmer() : CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _opHeader('FEE COLLECTION OVERVIEW')),
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Row(children: [
            Expanded(child: _OPFeeCard(label: 'Collected', amount: _collected, color: AppTheme.success, icon: Icons.check_circle_outline)),
            const SizedBox(width: 10),
            Expanded(child: _OPFeeCard(label: 'Pending', amount: _pending, color: AppTheme.warning, icon: Icons.hourglass_bottom_outlined)),
            const SizedBox(width: 10),
            Expanded(child: _OPFeeCard(label: 'Overdue', amount: _overdue, color: AppTheme.danger, icon: Icons.warning_amber_outlined)),
          ]))),
          SliverToBoxAdapter(child: _opHeader('TOP DEFAULTERS')),
          SliverToBoxAdapter(child: _defaulters.isEmpty ? _opEmpty(Icons.mood_outlined, 'No overdue fees — great!') : Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Column(
            children: _defaulters.map((d) => _OPCard(margin: const EdgeInsets.only(bottom: 8), child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text('${d['className']}  ·  ${CurrencyUtils.formatRupees(d['amount'] as double)}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                Text('${d['daysOverdue']} days overdue', style: const TextStyle(color: AppTheme.danger, fontSize: 11)),
              ])),
              if ((d['phone'] as String).isNotEmpty) IconButton(
                icon: const Icon(Icons.chat_bubble_outline, color: AppTheme.whatsapp),
                onPressed: () {
                  final phone = d['phone'] as String;
                  final msg = 'Dear Parent of ${d['name']}, your fee is overdue.';
                  final url = PhoneUtils.whatsAppUri(phone, text: msg);
                  launchUrl(url, mode: LaunchMode.externalApplication);
                },
              ),
            ]))).toList(),
          ))),
          if (_defaulters.isNotEmpty)
            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), child: ElevatedButton.icon(
              icon: const Icon(Icons.chat_outlined),
              label: const Text('Send WhatsApp Reminder to All Overdue'),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.whatsapp, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: _sendReminders,
            ))),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      )),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Sub-page: Manage
// ══════════════════════════════════════════════════════════════════════════════

class _OPManagePage extends StatefulWidget {
  final String email;
  final String role;

  const _OPManagePage({required this.email, required this.role});

  @override
  State<_OPManagePage> createState() => _OPManagePageState();
}

class _OPManagePageState extends State<_OPManagePage> {
  static const _primary = AppTheme.primary;

  final _svc = TimetableService.instance;
  final _perm = RolePermissionService();

  List<Map<String, dynamic>> _users = [];
  bool _usersLoading = true;

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  bool _saving = false;
  late String _createRole;

  final _schoolNameCtrl = TextEditingController();
  final _schoolPhoneCtrl = TextEditingController();
  final _schoolAddressCtrl = TextEditingController();
  final _academicYearCtrl = TextEditingController();
  bool _settingsSaving = false, _settingsLoaded = false;

  List<Map<String, dynamic>> _announcements = [];

  @override
  void initState() {
    super.initState();
    final allowed = _perm.getAllowedToCreate(widget.role);
    _createRole = allowed.isNotEmpty ? allowed.first : 'principal';
    _loadAll();
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _emailCtrl.dispose();
    _schoolNameCtrl.dispose(); _schoolPhoneCtrl.dispose();
    _schoolAddressCtrl.dispose(); _academicYearCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async => Future.wait([_loadUsers(), _loadSchoolSettings(), _loadAnnouncements()]);

  Future<void> _loadUsers() async {
    if (mounted) setState(() => _usersLoading = true);
    try {
      final users = await _svc.getUsersCreatedBy(widget.email);
      if (!mounted) return;
      setState(() { _users = users; _usersLoading = false; });
    } catch (e) {
      // Don't leave the list stuck on "Loading…" if the query fails.
      if (!mounted) return;
      setState(() { _users = []; _usersLoading = false; });
      _snack('Could not load accounts: $e');
    }
  }

  Future<void> _loadSchoolSettings() async {
    if (_settingsLoaded) return;
    try {
      // Fail loud instead of defaulting to 'school_1': an owner session always
      // has a resolved school, and a silent fallback would read/write another
      // tenant's data (SCALE-06).
      final sid = AuthService.currentSchoolId;
      final doc = await FirebaseFirestore.instance.collection('schools').doc(sid).collection('settings').doc('school').get();
      if (doc.exists && doc.data() != null) {
        final d = doc.data()!;
        _schoolNameCtrl.text = d['name'] as String? ?? '';
        _schoolPhoneCtrl.text = d['phone'] as String? ?? '';
        _schoolAddressCtrl.text = d['address'] as String? ?? '';
        _academicYearCtrl.text = d['academicYear'] as String? ?? '';
      }
      if (mounted) setState(() => _settingsLoaded = true);
    } catch (e, st) { AppLogger.e('OwnerPrincipalHome', 'Best-effort op failed', e, st); }
  }

  Future<void> _saveSchoolSettings() async {
    final phone = _schoolPhoneCtrl.text.trim();
    if (phone.isNotEmpty) {
      final digits = phone.replaceAll(RegExp(r'\D'), '');
      if (digits.length != 10) {
        _snack('Phone number must be exactly 10 digits.');
        return;
      }
    }
    setState(() => _settingsSaving = true);
    try {
      // Fail loud instead of defaulting to 'school_1': an owner session always
      // has a resolved school, and a silent fallback would read/write another
      // tenant's data (SCALE-06).
      final sid = AuthService.currentSchoolId;
      await FirebaseFirestore.instance.collection('schools').doc(sid).collection('settings').doc('school').set({
        'name': _schoolNameCtrl.text.trim(), 'phone': _schoolPhoneCtrl.text.trim(),
        'address': _schoolAddressCtrl.text.trim(), 'academicYear': _academicYearCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('School settings saved'), backgroundColor: AppTheme.success));
    } catch (e) { if (mounted) _snack('Error: $e'); }
    if (mounted) setState(() => _settingsSaving = false);
  }

  Future<void> _loadAnnouncements() async {
    try {
      final anns = await AnnouncementService().getAnnouncements();
      if (!mounted) return;
      setState(() { _announcements = anns.map((a) => {'title': a.title, 'body': a.body, 'audience': a.audience}).toList(); });
    } catch (e, st) { AppLogger.e('OwnerPrincipalHome', 'Best-effort op failed', e, st); }
  }

  Future<void> _createUser() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim().toLowerCase();
    if (name.isEmpty) { _snack('Enter a name'); return; }
    if (email.isEmpty || !RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(email)) { _snack('Enter a valid email'); return; }
    if (!_perm.canCreate(widget.role, _createRole)) { _snack('No permission'); return; }
    setState(() => _saving = true);
    try {
      // No password needed — auto-generated + setup link emailed.
      // Stamp the creator's own school so sub-accounts stay inside it instead
      // of falling back to the default 'school_1'.
      await _svc.addAllowedUser(email, '', _createRole, name: name, schoolId: AuthService.currentSchoolId, createdByEmail: widget.email, createdByRole: widget.role);
      _nameCtrl.clear(); _emailCtrl.clear();
      // Read the stored display name back from the freshly created profile so
      // the confirmation reflects what was actually saved (falls back to the
      // entered name, then the email).
      final profile     = await _svc.getAllowedUserDoc(email);
      final createdName  = (profile?['name'] as String?)?.trim();
      final displayName  = (createdName != null && createdName.isNotEmpty)
          ? createdName
          : (name.isNotEmpty ? name : email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Account created for $displayName – ${RolePermissionService.roleDisplayName(_createRole)}'), backgroundColor: AppTheme.success));
        await _loadUsers();
      }
    } on RoleConflictException catch (e) {
      if (mounted) _snack(e.toString());
    } catch (e) { if (mounted) _snack('Error: $e'); }
    if (mounted) setState(() => _saving = false);
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final allowed = _perm.getAllowedToCreate(widget.role);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(backgroundColor: _primary, foregroundColor: Colors.white, elevation: 0, title: const Text('Manage School')),
      body: RefreshIndicator(
        onRefresh: _loadAll, color: _primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _opHeader('CREATE ACCOUNTS'),
            if (allowed.isEmpty) _opEmpty(Icons.block_outlined, 'No permission to create accounts')
            else _OPCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (allowed.length > 1) ...[
                DropdownButtonFormField<String>(value: _createRole,
                  decoration: const InputDecoration(labelText: 'Account Role', prefixIcon: Icon(Icons.badge_outlined), isDense: true),
                  items: allowed.map((r) => DropdownMenuItem(value: r, child: Text(RolePermissionService.roleDisplayName(r)))).toList(),
                  onChanged: (v) { if (v != null) setState(() => _createRole = v); }),
                const SizedBox(height: 12),
              ] else Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('Creating: ${RolePermissionService.roleDisplayName(allowed.first)}', style: const TextStyle(fontWeight: FontWeight.w600, color: _primary))),
              _opField(_nameCtrl, 'Full Name', Icons.person_outline, keyboardType: TextInputType.name),
              const SizedBox(height: 10),
              EmailTextFormField(
                controller: _emailCtrl,
                decoration: InputDecoration(
                  labelText: 'Email',
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.info_outline, size: 13, color: _primary),
                const SizedBox(width: 6),
                Expanded(child: Text('A password-setup link will be sent to the user\'s email.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
              ]),
              const SizedBox(height: 14),
              SizedBox(width: double.infinity, child: ElevatedButton.icon(
                icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.person_add_outlined),
                label: Text(_saving ? 'Creating…' : 'Create ${RolePermissionService.roleDisplayName(_createRole)} Account'),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: _saving ? null : _createUser)),
            ])),
            const SizedBox(height: 8),
            if (_usersLoading) const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: LoadingState())
            else if (_users.isEmpty) _opEmpty(Icons.group_outlined, 'No accounts created yet')
            else Column(children: _users.map((u) {
              final email = u['email'] as String? ?? '';
              final role = u['role'] as String? ?? '';
              final createdAt = u['createdAt'];
              String dateStr = '';
              if (createdAt is Timestamp) { final dt = createdAt.toDate(); dateStr = '${dt.day}/${dt.month}/${dt.year}'; }
              return _OPCard(margin: const EdgeInsets.only(bottom: 8), child: Row(children: [
                CircleAvatar(radius: 18, backgroundColor: _primary.withValues(alpha: 0.1),
                  child: Icon(role == 'coordinator' ? Icons.manage_accounts_outlined : Icons.business_outlined, color: _primary, size: 18)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(email, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis),
                  if (dateStr.isNotEmpty) Text('Created: $dateStr', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                ])),
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: _primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                  child: Text(RolePermissionService.roleDisplayName(role), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _primary))),
              ]));
            }).toList()),
            _opHeader('MY SCHOOL SETTINGS'),
            _OPCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _opField(_schoolNameCtrl, 'School Name', Icons.school_outlined),
              const SizedBox(height: 10),
              _opField(_schoolPhoneCtrl, 'Phone Number', Icons.phone_outlined, keyboardType: TextInputType.phone),
              const SizedBox(height: 10),
              _opField(_schoolAddressCtrl, 'Address', Icons.location_on_outlined),
              const SizedBox(height: 10),
              _opField(_academicYearCtrl, 'Academic Year', Icons.calendar_today_outlined),
              const SizedBox(height: 14),
              SizedBox(width: double.infinity, child: ElevatedButton.icon(
                icon: _settingsSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.save_outlined),
                label: Text(_settingsSaving ? 'Saving…' : 'Save Settings'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: _settingsSaving ? null : _saveSchoolSettings)),
            ])),
            _opHeader('ANNOUNCEMENTS'),
            _OPCard(child: AnnouncementComposer(
              email: widget.email,
              role:  widget.role,
              onSent: _loadAnnouncements,
            )),
            const SizedBox(height: 8),
            ..._announcements.take(5).map((a) => _OPCard(margin: const EdgeInsets.only(bottom: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(a['title'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: _primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                  child: Text(a['audience'] as String? ?? '', style: const TextStyle(fontSize: 10, color: _primary))),
              ]),
              const SizedBox(height: 4),
              Text(a['body'] as String? ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black87, fontSize: 13)),
            ]))),
          ]),
        ),
      ),
    );
  }

  Widget _opField(TextEditingController ctrl, String label, IconData icon, {TextInputType keyboardType = TextInputType.text}) {
    return TextField(controller: ctrl, keyboardType: keyboardType,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Shared private widgets (OP prefix to avoid name conflicts if both files imported)
// ══════════════════════════════════════════════════════════════════════════════

class _OPWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final p = Path();
    p.lineTo(0, size.height - 30);
    p.quadraticBezierTo(size.width * 0.25, size.height + 4, size.width * 0.5, size.height - 18);
    p.quadraticBezierTo(size.width * 0.75, size.height - 40, size.width, size.height - 18);
    p.lineTo(size.width, 0);
    p.close();
    return p;
  }

  @override
  bool shouldReclip(_OPWaveClipper old) => false;
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.8)),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, subtitle;
  final VoidCallback onTap;

  const _FeatureTile({required this.icon, required this.color, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 22)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          ])),
          Icon(Icons.chevron_right, color: Colors.grey.shade400),
        ]),
      ),
    );
  }
}

class _OPCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? margin;
  final Color? borderColor;

  const _OPCard({required this.child, this.margin, this.borderColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? EdgeInsets.zero,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: borderColor != null ? Border.all(color: borderColor!, width: 1.5) : null,
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: child,
    );
  }
}

class _OPStatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  final bool compact;

  const _OPStatCard({required this.label, required this.value, required this.icon, required this.color, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 10 : 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [Icon(icon, color: color, size: compact ? 18 : 20), const Spacer(), Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: compact ? 18 : 22, color: color))]),
        Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: compact ? 10 : 11, color: Colors.black87)),
      ]),
    );
  }
}

class _OPFeeCard extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final IconData icon;

  const _OPFeeCard({required this.label, required this.amount, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.3)), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 20), const SizedBox(height: 6),
        Text('₹${amount >= 1000 ? '${(amount / 1000).toStringAsFixed(1)}k' : amount.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
        Text(label, style: const TextStyle(color: Colors.black54, fontSize: 10)),
      ]),
    );
  }
}

Widget _opHeader(String title, {Widget? trailing}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(14, 20, 14, 10),
    child: Row(children: [
      Container(width: 4, height: 16, decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 8),
      Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey.shade600, letterSpacing: 0.8)),
      const Spacer(),
      if (trailing != null) trailing,
    ]),
  );
}

Widget _opEmpty(IconData icon, String msg) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    child: _OPCard(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 40, color: Colors.grey.shade300), const SizedBox(height: 8),
      Text(msg, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
    ])),
  );
}

Widget _opShimmer() {
  return Column(children: List.generate(4, (_) => Container(
    margin: const EdgeInsets.fromLTRB(14, 12, 14, 0), padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(height: 14, width: 140, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4))),
      const SizedBox(height: 8),
      Container(height: 12, width: 220, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4))),
      const SizedBox(height: 6),
      Container(height: 12, width: 100, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4))),
    ]),
  )));
}

Widget _opBadge(int count) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: AppTheme.accent, borderRadius: BorderRadius.circular(12)),
    child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
  );
}

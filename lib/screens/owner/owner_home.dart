import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/exam.dart';
import '../../providers/school_settings_provider.dart';
import '../../services/announcement_service.dart';
import '../../services/auth_service.dart';
import '../../services/exam_service.dart';
import '../../services/fee_service.dart';
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
import '../fee_overview_screen.dart';
import 'edit_school_settings_screen.dart';
import 'staff_directory_helpers.dart';
import '../../widgets/refreshable_data.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Owner Home — menu-list entry point
// ══════════════════════════════════════════════════════════════════════════════

class OwnerHome extends StatefulWidget {
  const OwnerHome({super.key});

  @override
  State<OwnerHome> createState() => _OwnerHomeState();
}

class _OwnerHomeState extends State<OwnerHome> {
  String _myEmail = '';
  String _myRole = 'owner';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      RoleGuard.verify(context, ['owner']);
    });
    _init();
  }

  Future<void> _init() async {
    final session = await AuthService().getSession();
    if (!mounted) return;
    final email = session?['email'] as String? ?? '';
    final role = session?['role'] as String? ?? 'owner';

    // Check onboarding completion
    try {
      final onboarding = await SchoolSettingsService().getOnboardingStatus();
      final isCompleted = onboarding['isCompleted'] as bool? ?? false;
      if (!isCompleted && mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (_) => const SchoolOnboardingScreen(destination: OwnerHome()),
        ));
        return;
      }
    } catch (_) {}

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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          _buildHero(),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
          const SizedBox(height: 4),

          const _SectionHeader('OVERVIEW'),
          _FeatureTile(
            icon: Icons.dashboard_outlined,
            color: AppTheme.primary,
            title: 'School Dashboard',
            subtitle: 'Today\'s health, attendance & weekly trend',
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => const _DashPage(),
            )),
          ),

          const _SectionHeader('STAFF'),
          _FeatureTile(
            icon: Icons.people_outline,
            color: AppTheme.primary,
            title: 'Staff Overview',
            subtitle: 'Teachers, leave requests & activity',
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => const _StaffPage(),
            )),
          ),

          const _SectionHeader('ACADEMICS'),
          _FeatureTile(
            icon: Icons.menu_book_outlined,
            color: AppTheme.primary,
            title: 'Academics',
            subtitle: 'Recent tests & upcoming exam calendar',
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => const _AcademicsPage(),
            )),
          ),

          const _SectionHeader('FINANCE'),
          _FeatureTile(
            icon: Icons.currency_rupee_outlined,
            color: AppTheme.success,
            title: 'Fee Collection',
            subtitle: 'Class-wise collection, instalments & payment history',
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => const FeeOverviewScreen(role: 'owner'),
            )),
          ),
          _FeatureTile(
            icon: Icons.bar_chart_outlined,
            color: AppTheme.primary,
            title: 'Fee Summary & Defaulters',
            subtitle: 'School-wide collected, pending, overdue & defaulters',
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => const _FinancePage(),
            )),
          ),

          const _SectionHeader('MANAGE'),
          _FeatureTile(
            icon: Icons.person_add_outlined,
            color: AppTheme.accent,
            title: 'Create Accounts',
            subtitle: 'Add principal, coordinator & other staff logins',
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => _CreateAccountsPage(email: _myEmail, role: _myRole),
            )),
          ),
          _FeatureTile(
            icon: Icons.campaign_outlined,
            color: AppTheme.primaryMid,
            title: 'Announcements',
            subtitle: 'Broadcast messages to staff, guardians or everyone',
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => _AnnouncementsPage(email: _myEmail, role: _myRole),
            )),
          ),
          _FeatureTile(
            icon: Icons.tune_outlined,
            color: AppTheme.primaryMid,
            title: 'Advanced Settings',
            subtitle: 'Edit basic info, academic, fees & communication',
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => const EditSchoolSettingsScreen(),
            )),
          ),

          const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildHero() {
    final now = DateTime.now();
    const wdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final dateStr = '${wdays[now.weekday - 1]}, ${now.day} ${months[now.month - 1]}';
    final settingsProvider = context.watch<SchoolSettingsProvider>();
    final displayName = settingsProvider.schoolName;
    final logoUrl = settingsProvider.schoolLogo;

    return ClipPath(
      clipper: _WaveClipper(),
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
                  const Icon(Icons.business_outlined, color: Colors.white60, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'OWNER  ·  $dateStr',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 11,
                          fontWeight: FontWeight.w600, letterSpacing: 0.9),
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
                      style: const TextStyle(
                          color: Colors.white, fontSize: 22,
                          fontWeight: FontWeight.bold, height: 1.1),
                    ),
                  ),
                ]),
                const SizedBox(height: 3),
                Text(_myEmail,
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
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

class _DashPage extends StatefulWidget {
  const _DashPage();

  @override
  State<_DashPage> createState() => _DashPageState();
}

class _DashPageState extends State<_DashPage> {
  static const _primary = AppTheme.primary;

  bool _loading = true;
  int _totalStudents = 0;
  int _presentToday = 0;
  int _absentToday = 0;
  int _activeTeachers = 0;
  List<Map<String, dynamic>> _classAtt = [];
  List<String> _alerts = [];
  List<FlSpot> _weeklyTrend = [];
  List<String> _weeklyLabels = [];

  final _svc = TimetableService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final settings = await _svc.getSettings();
      final classes = List<String>.from(settings['classes'] as List? ?? []);
      final summaries = await StudentService().loadTodayFullSummary(classes: classes);

      int total = 0, present = 0, absent = 0;
      final classAtt = <Map<String, dynamic>>[];
      for (final s in summaries) {
        total += s.total;
        present += s.present;
        absent += s.absent + s.leave;
        classAtt.add({
          'className': s.className,
          'total': s.total,
          'present': s.present,
          'marked': s.marked,
          'pct': s.total > 0 ? s.present / s.total * 100 : 0.0,
        });
      }

      final alerts = <String>[];
      for (final c in classAtt) {
        if ((c['marked'] as bool) && (c['pct'] as double) < 70) {
          alerts.add('Low attendance in ${c['className']}: ${(c['pct'] as double).toStringAsFixed(0)}%');
        }
      }
      final leaves = await _svc.getLeaveApplications(status: 'pending');
      if (leaves.length > 3) alerts.add('${leaves.length} leave requests pending approval');

      final studentsByClass = {for (final s in summaries) s.className: s.total};
      final spots = <FlSpot>[];
      final labels = <String>[];
      final db = FirebaseFirestore.instance;
      final days = List.generate(7, (i) => DateTime.now().subtract(Duration(days: 6 - i)));
      final futures = <Future<DocumentSnapshot<Map<String, dynamic>>>>[];
      final sid = AuthService.currentSchoolId;
      for (final day in days) {
        for (final cls in classes) {
          final key = '${cls.replaceAll(' ', '_')}_${day.year}-${day.month}-${day.day}';
          futures.add(db.collection('schools').doc(sid).collection('attendance').doc(key).get());
        }
      }
      final results = await Future.wait(futures);
      for (int d = 0; d < 7; d++) {
        final day = days[d];
        int dPresent = 0, dTotal = 0;
        for (int c = 0; c < classes.length; c++) {
          final doc = results[d * classes.length + c];
          if (doc.exists && doc.data() != null) {
            final rolls = Map<String, dynamic>.from((doc.data()!['rolls'] as Map?) ?? {});
            dPresent += rolls.values.where((v) => v == 'Present').length;
          }
          dTotal += studentsByClass[classes[c]] ?? 0;
        }
        spots.add(FlSpot(d.toDouble(), dTotal > 0 ? dPresent / dTotal * 100 : 0.0));
        labels.add('${day.day}/${day.month}');
      }

      if (!mounted) return;
      setState(() {
        _totalStudents = total;
        _presentToday = present;
        _absentToday = absent;
        _activeTeachers = summaries.where((s) => s.marked).length;
        _classAtt = classAtt;
        _alerts = alerts;
        _weeklyTrend = spots;
        _weeklyLabels = labels;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('School Dashboard'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: _primary,
        child: _loading
            ? _shimmerList()
            : CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _sectionHeader('TODAY\'S SCHOOL HEALTH')),
                  SliverToBoxAdapter(child: _buildHealthCards()),
                  SliverToBoxAdapter(child: _sectionHeader('ATTENDANCE OVERVIEW')),
                  SliverToBoxAdapter(child: _buildAttendanceOverview()),
                  SliverToBoxAdapter(child: _sectionHeader('QUICK ALERTS')),
                  SliverToBoxAdapter(child: _buildAlerts()),
                  SliverToBoxAdapter(child: _sectionHeader('WEEKLY TREND')),
                  SliverToBoxAdapter(child: _buildWeeklyTrend()),
                  const SliverToBoxAdapter(child: SizedBox(height: 32)),
                ],
              ),
      ),
    );
  }

  Widget _buildHealthCards() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.6,
        children: [
          _StatCard(label: 'Total Students', value: '$_totalStudents', icon: Icons.people_outline, color: _primary),
          _StatCard(label: 'Present Today', value: '$_presentToday', icon: Icons.check_circle_outline, color: AppTheme.success),
          _StatCard(label: 'Teachers Active', value: '$_activeTeachers', icon: Icons.person_outline, color: AppTheme.primaryMid),
          _StatCard(label: 'Absent Today', value: '$_absentToday', icon: Icons.cancel_outlined, color: AppTheme.danger),
        ],
      ),
    );
  }

  Widget _buildAttendanceOverview() {
    if (_classAtt.isEmpty) return _emptyCard(Icons.bar_chart_outlined, 'No attendance data yet');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: _classAtt.map((c) {
          final marked = c['marked'] as bool;
          final pct = c['pct'] as double;
          final color = !marked ? Colors.grey.shade400 : pct >= 90 ? AppTheme.success : pct >= 75 ? AppTheme.warning : AppTheme.danger;
          return _OwnerCard(
            margin: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              SizedBox(width: 80, child: Text(c['className'] as String, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: marked ? pct / 100 : 0, minHeight: 10, backgroundColor: Colors.grey.shade200, valueColor: AlwaysStoppedAnimation<Color>(color)),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(width: 56, child: Text(marked ? '${pct.toStringAsFixed(0)}%' : 'Not marked', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: marked ? color : Colors.grey))),
            ]),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAlerts() {
    if (_alerts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: _OwnerCard(
          child: Row(children: [
            Icon(Icons.check_circle_outline, color: AppTheme.success, size: 20),
            SizedBox(width: 10),
            Text('All good today', style: TextStyle(color: AppTheme.success, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: _alerts.map((a) => _OwnerCard(
          margin: const EdgeInsets.only(bottom: 8),
          borderColor: AppTheme.accent,
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: AppTheme.accent, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(a, style: const TextStyle(fontSize: 13))),
          ]),
        )).toList(),
      ),
    );
  }

  Widget _buildWeeklyTrend() {
    if (_weeklyTrend.isEmpty) return _emptyCard(Icons.show_chart, 'Loading trend data…');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: _OwnerCard(
        child: SizedBox(
          height: 160,
          child: LineChart(LineChartData(
            gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey.shade200, strokeWidth: 1)),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 22,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= _weeklyLabels.length) return const SizedBox.shrink();
                  return Padding(padding: const EdgeInsets.only(top: 4), child: Text(_weeklyLabels[i], style: const TextStyle(fontSize: 9, color: Colors.grey)));
                },
              )),
              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32, getTitlesWidget: (v, _) => Text('${v.toInt()}%', style: const TextStyle(fontSize: 9, color: Colors.grey)))),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(show: false),
            minX: 0, maxX: 6, minY: 0, maxY: 100,
            lineBarsData: [LineChartBarData(
              spots: _weeklyTrend, isCurved: true, color: _primary, barWidth: 2.5,
              isStrokeCapRound: true, dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(show: true, color: _primary.withValues(alpha: 0.08)),
            )],
          )),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Sub-page: Staff
// ══════════════════════════════════════════════════════════════════════════════

class _StaffPage extends StatefulWidget {
  const _StaffPage();

  @override
  State<_StaffPage> createState() => _StaffPageState();
}

class _StaffPageState extends State<_StaffPage> {
  static const _primary = AppTheme.primary;

  bool _loading = true;
  List<Map<String, dynamic>> _teachers = [];
  List<Map<String, dynamic>> _leaves = [];
  String _search = '';

  final _svc = TimetableService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final all = await _svc.getAllowedUsers();
      final session = await AuthService().getSession();
      final myEmail = (session?['email'] as String? ?? '').toLowerCase();
      // All staff roles — teachers, coordinators, principals and other
      // management — excluding guardians (parents are not staff) and the
      // owner's own account (no need to list yourself in the staff section).
      final staff = all.where((u) =>
              u['role'] != 'guardian' &&
              (u['email'] as String? ?? '').toLowerCase() != myEmail)
          .toList()
        ..sort(staffByRoleThenName);
      final leaves = await _svc.getLeaveApplications(status: 'pending');
      if (!mounted) return;
      setState(() { _teachers = staff; _leaves = leaves; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
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
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(backgroundColor: _primary, foregroundColor: Colors.white, elevation: 0, title: const Text('Staff')),
        body: _shimmerList(),
      );
    }
    final activeCount  = _teachers.where((t) => staffStatusOf(t) == 'active').length;
    final pendingCount = _teachers.where((t) => staffStatusOf(t) == 'pending').length;
    final filtered = _teachers.where((t) {
      if (_search.isEmpty) return true;
      return (t['email'] as String? ?? '').toLowerCase().contains(_search) ||
             (t['name'] as String? ?? '').toLowerCase().contains(_search);
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(backgroundColor: _primary, foregroundColor: Colors.white, elevation: 0, title: const Text('Staff')),
      body: RefreshIndicator(
        onRefresh: _load,
        color: _primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _sectionHeader('STAFF OVERVIEW')),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(children: [
                  Expanded(child: _StatCard(label: 'Total', value: '${_teachers.length}', icon: Icons.people_outline, color: _primary, compact: true)),
                  const SizedBox(width: 10),
                  Expanded(child: _StatCard(label: 'Active', value: '$activeCount', icon: Icons.check_circle_outline, color: AppTheme.success, compact: true)),
                  const SizedBox(width: 10),
                  Expanded(child: _StatCard(label: 'Pending', value: '$pendingCount', icon: Icons.hourglass_empty_outlined, color: AppTheme.warning, compact: true)),
                ]),
              ),
            ),
            if (_leaves.isNotEmpty) ...[
              SliverToBoxAdapter(child: _sectionHeader('PENDING LEAVES', trailing: _badge(_leaves.length))),
              SliverToBoxAdapter(child: _buildLeaveList()),
            ],
            SliverToBoxAdapter(child: _sectionHeader('STAFF LIST')),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: TextField(
                  decoration: const InputDecoration(hintText: 'Search staff…', prefixIcon: Icon(Icons.search, color: Colors.grey), isDense: true),
                  onChanged: (v) => setState(() => _search = v.toLowerCase()),
                ),
              ),
            ),
            SliverToBoxAdapter(child: _buildTeacherList(filtered)),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaveList() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: _leaves.map((leave) {
          final name = leave['teacherName'] as String? ?? leave['teacherId'] as String? ?? '—';
          final from = leave['fromDate'] as String? ?? '';
          final to = leave['toDate'] as String? ?? '';
          final reason = leave['reason'] as String? ?? '';
          final id = leave['id'] as String? ?? '';
          return _OwnerCard(
            margin: const EdgeInsets.only(bottom: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                CircleAvatar(radius: 16, backgroundColor: _primary.withValues(alpha: 0.12),
                  child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'T', style: const TextStyle(color: _primary, fontWeight: FontWeight.bold, fontSize: 12))),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  Text('$from → $to', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppTheme.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: const Text('Pending', style: TextStyle(fontSize: 11, color: AppTheme.warning, fontWeight: FontWeight.w600)),
                ),
              ]),
              if (reason.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(reason, style: const TextStyle(fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: AppTheme.danger, side: const BorderSide(color: AppTheme.danger), padding: const EdgeInsets.symmetric(vertical: 6)),
                  onPressed: () => _updateLeave(id, 'rejected'),
                  child: const Text('Reject', style: TextStyle(fontSize: 12)),
                )),
                const SizedBox(width: 8),
                Expanded(child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success, padding: const EdgeInsets.symmetric(vertical: 6)),
                  onPressed: () => _updateLeave(id, 'approved'),
                  child: const Text('Approve', style: TextStyle(fontSize: 12)),
                )),
              ]),
            ]),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTeacherList(List<Map<String, dynamic>> filtered) {
    if (filtered.isEmpty) return _emptyCard(Icons.people_outline, 'No staff found');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: filtered.map((t) {
          final email = t['email'] as String? ?? '';
          final name = (t['name'] as String? ?? '').isNotEmpty ? t['name'] as String : email;
          final role = t['role'] as String? ?? 'teacher';
          final classes = List<String>.from(t['assignedClasses'] as List? ?? []);
          final isOnLeave = _leaves.any((l) => (l['teacherId'] as String? ?? '') == email);
          final status = staffStatusOf(t);
          return _OwnerCard(
            margin: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              CircleAvatar(radius: 20, backgroundColor: staffRoleColor(role).withValues(alpha: 0.12),
                child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'S', style: TextStyle(color: staffRoleColor(role), fontWeight: FontWeight.bold))),
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
            ]),
          );
        }).toList(),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Sub-page: Academics
// ══════════════════════════════════════════════════════════════════════════════

class _AcademicsPage extends StatefulWidget {
  const _AcademicsPage();

  @override
  State<_AcademicsPage> createState() => _AcademicsPageState();
}

class _AcademicsPageState extends State<_AcademicsPage> {
  static const _primary = AppTheme.primary;
  bool _loading = true;
  List<Exam> _recent = [];
  List<Exam> _upcoming = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final all = await ExamService().getExams();
      final now = DateTime.now();
      final upcoming = all.where((e) => e.examDate.isAfter(now) && e.examDate.isBefore(now.add(const Duration(days: 30)))).toList()
        ..sort((a, b) => a.examDate.compareTo(b.examDate));
      if (!mounted) return;
      setState(() { _recent = all.take(5).toList(); _upcoming = upcoming; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(backgroundColor: _primary, foregroundColor: Colors.white, elevation: 0, title: const Text('Academics')),
      body: RefreshIndicator(
        onRefresh: _load,
        color: _primary,
        child: _loading
            ? _shimmerList()
            : CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _sectionHeader('RECENT TESTS')),
                  SliverToBoxAdapter(child: _buildExamList(_recent, recent: true)),
                  SliverToBoxAdapter(child: _sectionHeader('EXAM CALENDAR (NEXT 30 DAYS)')),
                  SliverToBoxAdapter(child: _buildExamList(_upcoming, recent: false)),
                  const SliverToBoxAdapter(child: SizedBox(height: 32)),
                ],
              ),
      ),
    );
  }

  Widget _buildExamList(List<Exam> exams, {required bool recent}) {
    if (exams.isEmpty) {
      return _emptyCard(recent ? Icons.quiz_outlined : Icons.event_note_outlined,
          recent ? 'No tests recorded yet' : 'No upcoming exams in the next 30 days');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: exams.map((exam) {
          final dt = exam.examDate;
          if (recent) {
            return _OwnerCard(
              margin: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Container(width: 44, height: 44,
                  decoration: BoxDecoration(color: _primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.quiz_outlined, color: _primary, size: 22)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(exam.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  Text('${exam.className}  ·  ${dt.day}/${dt.month}/${dt.year}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ])),
              ]),
            );
          }
          final daysLeft = dt.difference(DateTime.now()).inDays;
          final dColor = daysLeft <= 3 ? AppTheme.danger : daysLeft <= 7 ? AppTheme.warning : _primary;
          return _OwnerCard(
            margin: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Column(children: [
                Text('${dt.day}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _primary)),
                Text(['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][dt.month - 1],
                    style: const TextStyle(fontSize: 11, color: _primary)),
              ]),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(exam.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text(exam.className, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: dColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(daysLeft == 0 ? 'Today' : '${daysLeft}d left', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: dColor)),
              ),
            ]),
          );
        }).toList(),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Sub-page: Finance
// ══════════════════════════════════════════════════════════════════════════════

class _FinancePage extends StatefulWidget {
  const _FinancePage();

  @override
  State<_FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends State<_FinancePage> {
  static const _primary = AppTheme.primary;
  bool _loading = true;
  double _collected = 0, _pending = 0, _overdue = 0;
  List<Map<String, dynamic>> _defaulters = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final summary = await FeeService().getFeesSummary();
      final defaulters =
          (summary['defaulters'] as List<Map<String, dynamic>>).take(10).toList();
      if (!mounted) return;
      setState(() {
        _collected = summary['collected'] as double;
        _pending   = summary['pending']   as double;
        _overdue   = summary['overdue']   as double;
        _defaulters = defaulters;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
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
      final phone = (d['phone'] as String).replaceAll(RegExp(r'\D'), '');
      if (phone.isEmpty) continue;
      final msg = Uri.encodeComponent('Dear Parent of ${d['name']}, your fee of ₹${(d['amount'] as double).toStringAsFixed(0)} is overdue. Please pay at the earliest.');
      await launchUrl(Uri.parse('https://wa.me/91$phone?text=$msg'), mode: LaunchMode.externalApplication);
      await Future.delayed(const Duration(milliseconds: 800));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(backgroundColor: _primary, foregroundColor: Colors.white, elevation: 0, title: const Text('Fee Collection')),
      body: RefreshIndicator(
        onRefresh: _load,
        color: _primary,
        child: _loading
            ? _shimmerList()
            : CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _sectionHeader('FEE COLLECTION OVERVIEW')),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(children: [
                        Expanded(child: _FeeCard(label: 'Collected', amount: _collected, color: AppTheme.success, icon: Icons.check_circle_outline)),
                        const SizedBox(width: 10),
                        Expanded(child: _FeeCard(label: 'Pending', amount: _pending, color: AppTheme.warning, icon: Icons.hourglass_bottom_outlined)),
                        const SizedBox(width: 10),
                        Expanded(child: _FeeCard(label: 'Overdue', amount: _overdue, color: AppTheme.danger, icon: Icons.warning_amber_outlined)),
                      ]),
                    ),
                  ),
                  SliverToBoxAdapter(child: _sectionHeader('TOP DEFAULTERS')),
                  SliverToBoxAdapter(child: _buildDefaulters()),
                  if (_defaulters.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.chat_outlined),
                          label: const Text('Send WhatsApp Reminder to All Overdue'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF25D366),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _sendReminders,
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 32)),
                ],
              ),
      ),
    );
  }

  Widget _buildDefaulters() {
    if (_defaulters.isEmpty) return _emptyCard(Icons.mood_outlined, 'No overdue fees — great!');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: _defaulters.map((d) => _OwnerCard(
          margin: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text('${d['className']}  ·  ₹${(d['amount'] as double).toStringAsFixed(0)}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
              Text('${d['daysOverdue']} days overdue', style: const TextStyle(color: AppTheme.danger, fontSize: 11)),
            ])),
            if ((d['phone'] as String).isNotEmpty)
              IconButton(
                icon: const Icon(Icons.chat_bubble_outline, color: Color(0xFF25D366)),
                onPressed: () {
                  final n = (d['phone'] as String).replaceAll(RegExp(r'\D'), '');
                  final msg = Uri.encodeComponent('Dear Parent of ${d['name']}, your fee of ₹${(d['amount'] as double).toStringAsFixed(0)} is overdue.');
                  launchUrl(Uri.parse('https://wa.me/91$n?text=$msg'), mode: LaunchMode.externalApplication);
                },
              ),
          ]),
        )).toList(),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Sub-page: Create Accounts
// ══════════════════════════════════════════════════════════════════════════════

class _CreateAccountsPage extends StatefulWidget {
  final String email;
  final String role;
  const _CreateAccountsPage({required this.email, required this.role});

  @override
  State<_CreateAccountsPage> createState() => _CreateAccountsPageState();
}

class _CreateAccountsPageState extends State<_CreateAccountsPage> {
  static const _primary = AppTheme.primary;
  final _svc  = TimetableService();
  final _perm = RolePermissionService();

  final _nameCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();
  // Owned by the screen, not the delete dialog: disposing a controller while the
  // dialog's TextField is still tearing down (e.g. on Cancel, during the route's
  // exit animation / focus loss) trips the framework's InheritedElement
  // `_dependents.isEmpty` assertion and shows a red error screen. Tying it to the
  // screen lifecycle avoids that entirely.
  final _deletePwCtrl = TextEditingController();
  bool _saving     = false;
  late String _createRole;

  List<Map<String, dynamic>> _createdUsers = [];
  bool _usersLoading = true;

  @override
  void initState() {
    super.initState();
    final allowed = _perm.getAllowedToCreate(widget.role);
    _createRole = allowed.isNotEmpty ? allowed.first : 'principal';
    _loadUsers();
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _emailCtrl.dispose(); _deletePwCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    if (mounted) setState(() => _usersLoading = true);
    try {
      final users = await _svc.getUsersCreatedBy(widget.email);
      if (!mounted) return;
      setState(() { _createdUsers = users; _usersLoading = false; });
    } catch (e) {
      // Don't leave the list stuck on "Loading…" if the query fails.
      if (!mounted) return;
      setState(() { _createdUsers = []; _usersLoading = false; });
      _snack('Could not load accounts: $e');
    }
  }

  Future<void> _createUser() async {
    final name  = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim().toLowerCase();
    if (name.isEmpty) { _snack('Enter a name'); return; }
    if (email.isEmpty || !RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(email)) {
      _snack('Enter a valid email'); return;
    }
    if (!_perm.canCreate(widget.role, _createRole)) {
      _snack('No permission to create $_createRole accounts'); return;
    }
    setState(() => _saving = true);
    try {
      // No password needed — auto-generated + setup link emailed.
      await _svc.addAllowedUser(email, '', _createRole,
          name: name, schoolId: AuthService.currentSchoolId,
          createdByEmail: widget.email, createdByRole: widget.role);
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Account created for $displayName – '
              '${RolePermissionService.roleDisplayName(_createRole)}'),
          backgroundColor: AppTheme.success,
        ));
        await _loadUsers();
      }
    } on RoleConflictException catch (e) {
      if (mounted) _snack(e.toString());
    } catch (e) {
      if (mounted) _snack('Error: $e');
    }
    if (mounted) setState(() => _saving = false);
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _deleteUser(String uEmail, String uRole) async {
    // Capture the messenger from the page context up-front. Resolving it from
    // the dialog's own context registers the dialog element as a dependent of
    // the app-root ScaffoldMessenger, which dangles when the dialog tears down
    // and trips the framework's `_dependents.isEmpty` assertion.
    final messenger = ScaffoldMessenger.of(context);
    final pwCtrl = _deletePwCtrl..clear();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        bool obscure = true;
        bool deleting = false;
        return StatefulBuilder(
          builder: (dialogCtx, setDlg) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Confirm Deletion'),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              RichText(text: TextSpan(
                style: const TextStyle(color: Colors.black87, fontSize: 13, height: 1.4),
                children: [
                  const TextSpan(text: 'This will permanently delete the '),
                  TextSpan(
                    text: RolePermissionService.roleDisplayName(uRole),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const TextSpan(text: ' account for\n'),
                  TextSpan(text: uEmail, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accent)),
                  const TextSpan(text: '.\n\nEnter your password to confirm.'),
                ],
              )),
              const SizedBox(height: 16),
              TextField(
                controller: pwCtrl,
                obscureText: obscure,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Your Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setDlg(() => obscure = !obscure),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  isDense: true,
                ),
              ),
            ]),
            actions: [
              TextButton(
                onPressed: deleting ? null : () => Navigator.of(dialogCtx).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.danger,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: deleting
                    ? null
                    : () async {
                        final pw = pwCtrl.text;
                        if (pw.isEmpty) return;
                        setDlg(() => deleting = true);
                        try {
                          await AuthService().reauthenticate(widget.email, pw);
                          if (dialogCtx.mounted) Navigator.of(dialogCtx).pop(true);
                        } catch (_) {
                          if (dialogCtx.mounted) setDlg(() => deleting = false);
                          messenger.showSnackBar(
                            const SnackBar(content: Text('Incorrect password')),
                          );
                        }
                      },
                child: deleting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Delete Account', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      },
    );
    if (confirmed != true || !mounted) return;

    try {
      final full = await _svc.deleteAccountFully(uEmail);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(full
            ? 'Account and all related data deleted'
            : 'Access revoked — deploy the deletion function for full cleanup'),
        backgroundColor: full ? AppTheme.danger : Colors.orange.shade800,
      ));
      await _loadUsers();
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final allowed = _perm.getAllowedToCreate(widget.role);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Create Accounts'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadUsers,
        color: _primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sectionHeader('NEW ACCOUNT'),
            if (allowed.isEmpty)
              _emptyCard(Icons.block_outlined, 'No permission to create accounts')
            else
              _OwnerCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (allowed.length > 1) ...[
                  DropdownButtonFormField<String>(
                    value: _createRole,
                    decoration: const InputDecoration(
                        labelText: 'Account Role',
                        prefixIcon: Icon(Icons.badge_outlined),
                        isDense: true),
                    items: allowed
                        .map((r) => DropdownMenuItem(
                            value: r,
                            child: Text(RolePermissionService.roleDisplayName(r))))
                        .toList(),
                    onChanged: (v) { if (v != null) setState(() => _createRole = v); },
                  ),
                  const SizedBox(height: 12),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Creating: ${RolePermissionService.roleDisplayName(allowed.first)}',
                      style: const TextStyle(fontWeight: FontWeight.w600, color: _primary),
                    ),
                  ),
                _inputField(_nameCtrl, 'Full Name', Icons.person_outline,
                    keyboardType: TextInputType.name),
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
                  Expanded(
                    child: Text(
                      'A password-setup link will be sent to the user\'s email.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: _saving
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.person_add_outlined),
                    label: Text(_saving
                        ? 'Creating…'
                        : 'Create ${RolePermissionService.roleDisplayName(_createRole)} Account'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _saving ? null : _createUser,
                  ),
                ),
              ])),
            _sectionHeader('CREATED BY YOU'),
            if (_usersLoading)
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: LoadingState())
            else if (_createdUsers.isEmpty)
              _emptyCard(Icons.group_outlined, 'No accounts created yet')
            else
              ..._createdUsers.map((u) {
                final uEmail    = u['email']    as String? ?? '';
                final uRole     = u['role']     as String? ?? '';
                final createdAt = u['createdAt'];
                String dateStr  = '';
                if (createdAt is Timestamp) {
                  final dt = createdAt.toDate();
                  dateStr = '${dt.day}/${dt.month}/${dt.year}';
                }
                return _OwnerCard(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: _primary.withValues(alpha: 0.1),
                      child: Icon(
                        uRole == 'principal'
                            ? Icons.business_outlined
                            : Icons.person_outline,
                        color: _primary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(uEmail,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          overflow: TextOverflow.ellipsis),
                      if (dateStr.isNotEmpty)
                        Text('Created: $dateStr',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                    ])),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        RolePermissionService.roleDisplayName(uRole),
                        style: const TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w700, color: _primary),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 20),
                      tooltip: 'Delete account',
                      onPressed: () => _deleteUser(uEmail, uRole),
                    ),
                  ]),
                );
              }),
          ]),
        ),
      ),
    );
  }

  Widget _inputField(TextEditingController ctrl, String label, IconData icon,
      {TextInputType keyboardType = TextInputType.text}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        isDense: true,
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Sub-page: Announcements
// ══════════════════════════════════════════════════════════════════════════════

class _AnnouncementsPage extends StatefulWidget {
  final String email;
  final String role;
  const _AnnouncementsPage({required this.email, required this.role});

  @override
  State<_AnnouncementsPage> createState() => _AnnouncementsPageState();
}

class _AnnouncementsPageState extends State<_AnnouncementsPage> {
  static const _primary = AppTheme.primary;

  List<Map<String, dynamic>> _announcements = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final anns = await AnnouncementService().getAnnouncements();
      if (!mounted) return;
      setState(() {
        _announcements = anns
            .map((a) => {
                  'id':       a.id,
                  'title':    a.title,
                  'body':     a.body,
                  'audience': a.audience,
                })
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Announcements'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: _primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sectionHeader('NEW ANNOUNCEMENT'),
            _OwnerCard(
              child: AnnouncementComposer(
                email: widget.email,
                role:  widget.role,
                onSent: _load,
              ),
            ),
            _sectionHeader('RECENT ANNOUNCEMENTS'),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: LoadingState(),
              )
            else if (_announcements.isEmpty)
              _emptyCard(Icons.campaign_outlined, 'No announcements yet')
            else
              ..._announcements.map((a) => _OwnerCard(
                margin: const EdgeInsets.only(bottom: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        a['title'] as String? ?? '',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        a['audience'] as String? ?? '',
                        style: const TextStyle(fontSize: 10, color: _primary),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    a['body'] as String? ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.black87, fontSize: 13),
                  ),
                ]),
              )),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Shared private widgets
// ══════════════════════════════════════════════════════════════════════════════

class _WaveClipper extends CustomClipper<Path> {
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
  bool shouldReclip(_WaveClipper old) => false;
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
  final String title;
  final String subtitle;
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
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 22),
          ),
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

class _OwnerCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? margin;
  final Color? borderColor;

  const _OwnerCard({required this.child, this.margin, this.borderColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? EdgeInsets.zero,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: borderColor != null ? Border.all(color: borderColor!, width: 1.5) : null,
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: child,
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  final bool compact;

  const _StatCard({required this.label, required this.value, required this.icon, required this.color, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 10 : 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [
          Icon(icon, color: color, size: compact ? 18 : 20),
          const Spacer(),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: compact ? 18 : 22, color: color)),
        ]),
        Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: compact ? 10 : 11, color: Colors.black87)),
      ]),
    );
  }
}

class _FeeCard extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final IconData icon;

  const _FeeCard({required this.label, required this.amount, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.3)), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 6),
        Text('₹${amount >= 1000 ? '${(amount / 1000).toStringAsFixed(1)}k' : amount.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
        Text(label, style: const TextStyle(color: Colors.black54, fontSize: 10)),
      ]),
    );
  }
}

Widget _sectionHeader(String title, {Widget? trailing}) {
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

Widget _emptyCard(IconData icon, String msg) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    child: _OwnerCard(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 40, color: Colors.grey.shade300),
      const SizedBox(height: 8),
      Text(msg, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
    ])),
  );
}

Widget _shimmerList() {
  return Column(
    children: List.generate(4, (_) => Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(height: 14, width: 140, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4))),
        const SizedBox(height: 8),
        Container(height: 12, width: 220, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4))),
        const SizedBox(height: 6),
        Container(height: 12, width: 100, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4))),
      ]),
    )),
  );
}

Widget _badge(int count) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: AppTheme.accent, borderRadius: BorderRadius.circular(12)),
    child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
  );
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/announcement.dart';
import '../../models/exam.dart';
import '../../models/student.dart';
import '../../services/announcement_service.dart';
import '../../services/auth_service.dart';
import '../../services/exam_service.dart';
import '../../services/role_permission_service.dart';
import '../../services/student_service.dart';
import '../../services/timetable_service.dart';
import '../../theme.dart';
import '../principal_home.dart';
import '../role_selection_screen.dart';

class OwnerPrincipalHome extends StatefulWidget {
  const OwnerPrincipalHome({super.key});

  @override
  State<OwnerPrincipalHome> createState() => _OwnerPrincipalHomeState();
}

class _OwnerPrincipalHomeState extends State<OwnerPrincipalHome> {
  static const Color _primary = AppTheme.primary;

  int _tabIndex = 0;
  String _myEmail = '';
  String _myRole = 'ownerPrincipal';
  String _schoolName = '';
  bool _sessionLoaded = false;

  // ── Dashboard ──
  bool _dashLoading = true;
  List<String> _allClasses = [];
  int _totalStudents = 0;
  int _presentToday = 0;
  int _absentToday = 0;
  int _activeTeachersToday = 0;
  List<Map<String, dynamic>> _classAtt = [];
  List<String> _quickAlerts = [];
  List<FlSpot> _weeklyTrend = [];
  List<String> _weeklyLabels = [];

  // ── Staff ──
  bool _staffLoaded = false;
  bool _staffLoading = false;
  List<Map<String, dynamic>> _teachers = [];
  List<Map<String, dynamic>> _pendingLeaves = [];
  String _teacherSearch = '';

  // ── Academics ──
  bool _academicsLoaded = false;
  bool _academicsLoading = false;
  List<Exam> _recentExams = [];
  List<Exam> _upcomingExams = [];

  // ── Finance ──
  bool _financeLoaded = false;
  bool _financeLoading = false;
  double _collectedThisMonth = 0;
  double _pendingFees = 0;
  double _overdueFees = 0;
  List<Map<String, dynamic>> _topDefaulters = [];

  // ── Manage ──
  bool _manageLoaded = false;
  bool _manageLoading = false;
  List<Map<String, dynamic>> _createdUsers = [];
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _showPass = false;
  bool _saving = false;
  String _createRole = 'principal';

  // School settings
  final _schoolNameCtrl = TextEditingController();
  final _schoolPhoneCtrl = TextEditingController();
  final _schoolAddressCtrl = TextEditingController();
  final _academicYearCtrl = TextEditingController();
  bool _settingsSaving = false;
  bool _settingsLoaded = false;

  // Announcements
  final _annTitleCtrl = TextEditingController();
  final _annMsgCtrl = TextEditingController();
  String _annTarget = 'All Staff';
  bool _annSaving = false;
  List<Map<String, dynamic>> _announcements = [];

  final _svc = TimetableService();
  final _perm = RolePermissionService();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _schoolNameCtrl.dispose();
    _schoolPhoneCtrl.dispose();
    _schoolAddressCtrl.dispose();
    _academicYearCtrl.dispose();
    _annTitleCtrl.dispose();
    _annMsgCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final session = await AuthService().getSession();
    if (!mounted) return;
    setState(() {
      _myEmail = session?['email'] as String? ?? '';
      _myRole = session?['role'] as String? ?? 'ownerPrincipal';
      final allowed = _perm.getAllowedToCreate(_myRole);
      _createRole = allowed.isNotEmpty ? allowed.first : 'principal';
      _sessionLoaded = true;
    });
    await Future.wait([_loadDashboard(), _loadCreatedUsers()]);
  }

  void _onTabChanged(int i) {
    switch (i) {
      case 1:
        if (!_staffLoaded) _loadStaff();
      case 2:
        if (!_academicsLoaded) _loadAcademics();
      case 3:
        if (!_financeLoaded) _loadFinance();
      // tab 4 is Principal — PrincipalHome handles its own loading
      case 5:
        if (!_manageLoaded) _loadManage();
    }
  }

  // ── Dashboard ─────────────────────────────────────────────────────────────

  Future<void> _loadDashboard() async {
    if (mounted) setState(() => _dashLoading = true);
    try {
      final settings = await _svc.getSettings();
      final classes = List<String>.from(settings['classes'] as List? ?? []);

      final summaries = await StudentService().loadTodayFullSummary(classes);
      int totalS = 0, presentS = 0, absentS = 0;
      final classAtt = <Map<String, dynamic>>[];
      for (final s in summaries) {
        totalS += s.total;
        presentS += s.present;
        absentS += s.absent + s.leave;
        classAtt.add({
          'className': s.className,
          'total': s.total,
          'present': s.present,
          'marked': s.marked,
          'pct': s.total > 0 ? s.present / s.total * 100 : 0.0,
        });
      }

      final markedCount = summaries.where((s) => s.marked).length;

      final alerts = <String>[];
      for (final c in classAtt) {
        if ((c['marked'] as bool) && (c['pct'] as double) < 70) {
          alerts.add(
              'Low attendance in ${c['className']}: ${(c['pct'] as double).toStringAsFixed(0)}%');
        }
      }
      final leaves = await _svc.getLeaveApplications(status: 'pending');
      if (leaves.length > 3) {
        alerts.add('${leaves.length} leave requests pending approval');
      }

      final spots = <FlSpot>[];
      final labels = <String>[];
      final studentsByClass = <String, int>{};
      for (final s in summaries) {
        studentsByClass[s.className] = s.total;
      }
      final db = FirebaseFirestore.instance;
      for (int d = 6; d >= 0; d--) {
        final day = DateTime.now().subtract(Duration(days: d));
        int dPresent = 0, dTotal = 0;
        for (final cls in classes) {
          final key =
              '${cls.replaceAll(' ', '_')}_${day.year}-${day.month}-${day.day}';
          final doc = await db.collection('attendance').doc(key).get();
          if (doc.exists && doc.data() != null) {
            final rolls =
                Map<String, dynamic>.from((doc.data()!['rolls'] as Map?) ?? {});
            dPresent += rolls.values.where((v) => v == 'Present').length;
          }
          dTotal += studentsByClass[cls] ?? 0;
        }
        final pct = dTotal > 0 ? dPresent / dTotal * 100 : 0.0;
        spots.add(FlSpot((6 - d).toDouble(), pct));
        labels.add('${day.day}/${day.month}');
      }

      final schoolName = settings['schoolName'] as String? ?? '';

      if (!mounted) return;
      setState(() {
        _allClasses = classes;
        _totalStudents = totalS;
        _presentToday = presentS;
        _absentToday = absentS;
        _activeTeachersToday = markedCount;
        _classAtt = classAtt;
        _quickAlerts = alerts;
        _weeklyTrend = spots;
        _weeklyLabels = labels;
        _schoolName = schoolName;
        _dashLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _dashLoading = false);
    }
  }

  // ── Staff ─────────────────────────────────────────────────────────────────

  Future<void> _loadStaff() async {
    if (mounted) setState(() => _staffLoading = true);
    try {
      final all = await _svc.getAllowedUsers();
      final teachers = all
          .where((u) => u['role'] == 'teacher' || u['role'] == 'subjectTeacher')
          .toList();
      final leaves = await _svc.getLeaveApplications(status: 'pending');

      if (!mounted) return;
      setState(() {
        _teachers = teachers;
        _pendingLeaves = leaves;
        _staffLoaded = true;
        _staffLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _staffLoading = false);
    }
  }

  // ── Academics ─────────────────────────────────────────────────────────────

  Future<void> _loadAcademics() async {
    if (mounted) setState(() => _academicsLoading = true);
    try {
      final allExams = await ExamService().getExams();
      final now = DateTime.now();
      final upcoming = allExams
          .where((e) =>
              e.examDate.isAfter(now) &&
              e.examDate.isBefore(now.add(const Duration(days: 30))))
          .toList()
        ..sort((a, b) => a.examDate.compareTo(b.examDate));
      final recent = allExams.take(5).toList();

      if (!mounted) return;
      setState(() {
        _recentExams = recent;
        _upcomingExams = upcoming;
        _academicsLoaded = true;
        _academicsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _academicsLoading = false);
    }
  }

  // ── Finance ───────────────────────────────────────────────────────────────

  Future<void> _loadFinance() async {
    if (mounted) setState(() => _financeLoading = true);
    try {
      final snap =
          await FirebaseFirestore.instance.collection('students').get();
      final students = snap.docs
          .map((d) => Student.fromJson(Map<String, dynamic>.from(d.data())))
          .toList();

      double collected = 0, pending = 0, overdue = 0;
      final defaulters = <Map<String, dynamic>>[];
      final now = DateTime.now();

      for (final s in students) {
        final amount = s.feeAmount ?? 5000.0;
        if (s.feeStatus == 'Paid') {
          collected += amount;
        } else {
          final due = s.feeDueDate != null
              ? DateTime.tryParse(s.feeDueDate!) ?? now
              : now;
          if (due.isBefore(now)) {
            overdue += amount;
            final daysOverdue = now.difference(due).inDays;
            defaulters.add({
              'name': s.name,
              'className': s.className,
              'roll': s.roll,
              'amount': amount,
              'daysOverdue': daysOverdue,
              'phone': s.parentPhone ?? s.phone ?? '',
            });
          } else {
            pending += amount;
          }
        }
      }

      defaulters.sort(
          (a, b) => (b['daysOverdue'] as int).compareTo(a['daysOverdue'] as int));

      if (!mounted) return;
      setState(() {
        _collectedThisMonth = collected;
        _pendingFees = pending;
        _overdueFees = overdue;
        _topDefaulters = defaulters.take(10).toList();
        _financeLoaded = true;
        _financeLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _financeLoading = false);
    }
  }

  // ── Manage ────────────────────────────────────────────────────────────────

  Future<void> _loadCreatedUsers() async {
    if (_myEmail.isEmpty) return;
    setState(() => _manageLoading = true);
    final users = await _svc.getUsersCreatedBy(_myEmail);
    if (!mounted) return;
    setState(() {
      _createdUsers = users;
      _manageLoading = false;
      _manageLoaded = true;
    });
  }

  Future<void> _loadManage() async {
    await Future.wait([_loadSchoolSettings(), _loadAnnouncements()]);
    _manageLoaded = true;
  }

  Future<void> _loadSchoolSettings() async {
    if (_settingsLoaded) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('schools')
          .doc('school_1')
          .collection('settings')
          .doc('school')
          .get();
      if (doc.exists && doc.data() != null) {
        final d = doc.data()!;
        _schoolNameCtrl.text = d['name'] as String? ?? '';
        _schoolPhoneCtrl.text = d['phone'] as String? ?? '';
        _schoolAddressCtrl.text = d['address'] as String? ?? '';
        _academicYearCtrl.text = d['academicYear'] as String? ?? '';
      }
      _settingsLoaded = true;
    } catch (_) {}
  }

  Future<void> _saveSchoolSettings() async {
    setState(() => _settingsSaving = true);
    try {
      await FirebaseFirestore.instance
          .collection('schools')
          .doc('school_1')
          .collection('settings')
          .doc('school')
          .set({
        'name': _schoolNameCtrl.text.trim(),
        'phone': _schoolPhoneCtrl.text.trim(),
        'address': _schoolAddressCtrl.text.trim(),
        'academicYear': _academicYearCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('School settings saved'),
          backgroundColor: AppTheme.success,
        ));
      }
    } catch (e) {
      if (mounted) _snack('Error: $e');
    }
    if (mounted) setState(() => _settingsSaving = false);
  }

  Future<void> _loadAnnouncements() async {
    try {
      final anns = await AnnouncementService().getAnnouncements();
      if (!mounted) return;
      setState(() {
        _announcements = anns
            .map((a) => {
                  'id': a.id,
                  'title': a.title,
                  'body': a.body,
                  'audience': a.audience,
                  'postedAt': a.postedAt,
                })
            .toList();
      });
    } catch (_) {}
  }

  Future<void> _sendAnnouncement() async {
    final title = _annTitleCtrl.text.trim();
    final body = _annMsgCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) {
      _snack('Enter title and message');
      return;
    }
    setState(() => _annSaving = true);
    try {
      await AnnouncementService().postAnnouncement(Announcement(
        id: '',
        title: title,
        body: body,
        postedBy: _myEmail,
        postedByRole: _myRole,
        audience: _annTarget,
        isPinned: false,
      ));
      _annTitleCtrl.clear();
      _annMsgCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Announcement sent'),
          backgroundColor: AppTheme.success,
        ));
      }
      await _loadAnnouncements();
    } catch (e) {
      if (mounted) _snack('Error: $e');
    }
    if (mounted) setState(() => _annSaving = false);
  }

  Future<void> _createUser() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim().toLowerCase();
    final pass = _passCtrl.text.trim();
    if (name.isEmpty) {
      _snack('Enter a name');
      return;
    }
    if (email.isEmpty || !RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(email)) {
      _snack('Enter a valid email');
      return;
    }
    if (pass.length < 6) {
      _snack('Password must be at least 6 characters');
      return;
    }
    if (!_perm.canCreate(_myRole, _createRole)) {
      _snack('No permission to create $_createRole accounts');
      return;
    }
    setState(() => _saving = true);
    try {
      await _svc.addAllowedUser(email, pass, _createRole,
          createdByEmail: _myEmail, createdByRole: _myRole);
      await FirebaseFirestore.instance
          .collection('allowed_users')
          .doc(email)
          .update({'name': name});
      _nameCtrl.clear();
      _emailCtrl.clear();
      _passCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${RolePermissionService.roleDisplayName(_createRole)} account created'),
          backgroundColor: AppTheme.success,
        ));
        await _loadCreatedUsers();
      }
    } catch (e) {
      if (mounted) _snack('Error: $e');
    }
    if (mounted) setState(() => _saving = false);
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  void _confirmSignOut() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out?'),
        content: const Text('You will be returned to the login screen.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await AuthService().clearSession();
              if (!mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
                (_) => false,
              );
            },
            child: const Text('Sign Out', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _updateLeave(String id, String status) async {
    try {
      await _svc.updateLeaveApplication('', id, status);
      await _loadStaff();
    } catch (e) {
      if (mounted) _snack('Error: $e');
    }
  }

  Future<void> _sendAllReminders() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Send Fee Reminders?'),
        content: Text(
            'Send WhatsApp reminders to ${_topDefaulters.length} overdue guardians?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send All'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    for (final d in _topDefaulters) {
      final phone = (d['phone'] as String).replaceAll(RegExp(r'\D'), '');
      if (phone.isEmpty) continue;
      final name = d['name'] as String;
      final amt = d['amount'] as double;
      final msg = Uri.encodeComponent(
          'Dear Parent of $name, your fee of ₹${amt.toStringAsFixed(0)} is overdue. Please pay at the earliest.');
      await launchUrl(Uri.parse('https://wa.me/91$phone?text=$msg'),
          mode: LaunchMode.externalApplication);
      await Future.delayed(const Duration(milliseconds: 800));
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_sessionLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // On the Principal tab, hide our own AppBar so PrincipalHome's AppBar shows
    final showOwnAppBar = _tabIndex != 4;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: showOwnAppBar
          ? AppBar(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              elevation: 0,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Owner-Principal Panel',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold)),
                  Text(
                      _schoolName.isNotEmpty ? _schoolName : _myEmail,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.white70)),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: 'Sign out',
                  onPressed: _confirmSignOut,
                ),
              ],
            )
          : null,
      body: _buildBody(),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _tabIndex,
      onTap: (i) {
        setState(() => _tabIndex = i);
        _onTabChanged(i);
      },
      backgroundColor: Colors.white,
      selectedItemColor: _primary,
      unselectedItemColor: Colors.grey,
      type: BottomNavigationBarType.fixed,
      selectedLabelStyle:
          const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      unselectedLabelStyle: const TextStyle(fontSize: 11),
      items: const [
        BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined), label: 'Dashboard'),
        BottomNavigationBarItem(
            icon: Icon(Icons.people_outline), label: 'Staff'),
        BottomNavigationBarItem(
            icon: Icon(Icons.menu_book_outlined), label: 'Academics'),
        BottomNavigationBarItem(
            icon: Icon(Icons.currency_rupee_outlined), label: 'Finance'),
        BottomNavigationBarItem(
            icon: Icon(Icons.admin_panel_settings_outlined),
            label: 'Principal'),
        BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined), label: 'Manage'),
      ],
    );
  }

  Widget _buildBody() {
    switch (_tabIndex) {
      case 0:
        return _buildDashboardTab();
      case 1:
        return _buildStaffTab();
      case 2:
        return _buildAcademicsTab();
      case 3:
        return _buildFinanceTab();
      case 4:
        return _buildPrincipalTab();
      case 5:
        return _buildManageTab();
      default:
        return const SizedBox.shrink();
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 0 — DASHBOARD
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildDashboardTab() {
    return RefreshIndicator(
      onRefresh: _loadDashboard,
      color: _primary,
      child: _dashLoading
          ? _shimmerList()
          : CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                    child: _sectionHeader('TODAY\'S SCHOOL HEALTH')),
                SliverToBoxAdapter(child: _buildHealthCards()),
                SliverToBoxAdapter(
                    child: _sectionHeader('ATTENDANCE OVERVIEW')),
                SliverToBoxAdapter(child: _buildAttendanceOverview()),
                SliverToBoxAdapter(child: _sectionHeader('QUICK ALERTS')),
                SliverToBoxAdapter(child: _buildAlerts()),
                SliverToBoxAdapter(child: _sectionHeader('WEEKLY TREND')),
                SliverToBoxAdapter(child: _buildWeeklyTrend()),
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            ),
    );
  }

  Widget _buildHealthCards() {
    final cards = [
      _OPStatCard(
        label: 'Total Students',
        value: '$_totalStudents',
        icon: Icons.people_outline,
        color: _primary,
      ),
      _OPStatCard(
        label: 'Present Today',
        value: '$_presentToday',
        icon: Icons.check_circle_outline,
        color: AppTheme.success,
      ),
      _OPStatCard(
        label: 'Teachers Active',
        value: '$_activeTeachersToday',
        icon: Icons.person_outline,
        color: AppTheme.primaryMid,
      ),
      _OPStatCard(
        label: 'Absent Today',
        value: '$_absentToday',
        icon: Icons.cancel_outlined,
        color: AppTheme.danger,
      ),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.6,
        children: cards,
      ),
    );
  }

  Widget _buildAttendanceOverview() {
    if (_classAtt.isEmpty) {
      return _emptyCard(Icons.bar_chart_outlined, 'No attendance data yet');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: _classAtt.map((c) {
          final cls = c['className'] as String;
          final marked = c['marked'] as bool;
          final pct = c['pct'] as double;
          Color barColor;
          if (!marked) {
            barColor = Colors.grey.shade400;
          } else if (pct >= 90) {
            barColor = AppTheme.success;
          } else if (pct >= 75) {
            barColor = AppTheme.warning;
          } else {
            barColor = AppTheme.danger;
          }
          return _opCard(
            margin: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 80,
                  child: Text(cls,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 12)),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: marked ? pct / 100 : 0,
                      minHeight: 10,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(barColor),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 56,
                  child: Text(
                    marked ? '${pct.toStringAsFixed(0)}%' : 'Not marked',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: marked ? barColor : Colors.grey),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAlerts() {
    if (_quickAlerts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: _opCard(
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline,
                  color: AppTheme.success, size: 20),
              const SizedBox(width: 10),
              const Text('All good today',
                  style: TextStyle(
                      color: AppTheme.success, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: _quickAlerts.map((alert) {
          return _opCard(
            margin: const EdgeInsets.only(bottom: 8),
            borderColor: AppTheme.accent,
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: AppTheme.accent, size: 18),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(alert, style: const TextStyle(fontSize: 13))),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildWeeklyTrend() {
    if (_weeklyTrend.isEmpty) {
      return _emptyCard(Icons.show_chart, 'Loading trend data…');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: _opCard(
        child: SizedBox(
          height: 160,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: Colors.grey.shade200, strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= _weeklyLabels.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(_weeklyLabels[idx],
                            style: const TextStyle(
                                fontSize: 9, color: Colors.grey)),
                      );
                    },
                    reservedSize: 22,
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    getTitlesWidget: (value, _) => Text(
                      '${value.toInt()}%',
                      style: const TextStyle(fontSize: 9, color: Colors.grey),
                    ),
                  ),
                ),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              minX: 0,
              maxX: 6,
              minY: 0,
              maxY: 100,
              lineBarsData: [
                LineChartBarData(
                  spots: _weeklyTrend,
                  isCurved: true,
                  color: _primary,
                  barWidth: 2.5,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: true),
                  belowBarData: BarAreaData(
                    show: true,
                    color: _primary.withOpacity(0.08),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 1 — STAFF
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildStaffTab() {
    if (_staffLoading) return _shimmerList();
    return RefreshIndicator(
      onRefresh: () async {
        _staffLoaded = false;
        await _loadStaff();
      },
      color: _primary,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _sectionHeader('STAFF OVERVIEW')),
          SliverToBoxAdapter(child: _buildStaffOverviewCards()),
          if (_pendingLeaves.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _sectionHeader('PENDING LEAVE REQUESTS',
                  trailing: _badge(_pendingLeaves.length)),
            ),
            SliverToBoxAdapter(child: _buildLeaveRequests()),
          ],
          SliverToBoxAdapter(child: _sectionHeader('TEACHER LIST')),
          SliverToBoxAdapter(child: _buildTeacherSearch()),
          SliverToBoxAdapter(child: _buildTeacherList()),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildStaffOverviewCards() {
    final onLeaveToday = _pendingLeaves.where((l) {
      final from = l['fromDate'] as String? ?? '';
      final today =
          '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}';
      return from == today;
    }).length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child: _OPStatCard(
              label: 'Total Teachers',
              value: '${_teachers.length}',
              icon: Icons.people_outline,
              color: _primary,
              compact: true,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _OPStatCard(
              label: 'On Leave Today',
              value: '$onLeaveToday',
              icon: Icons.event_busy_outlined,
              color: AppTheme.warning,
              compact: true,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _OPStatCard(
              label: 'Active Now',
              value: '${_teachers.length - onLeaveToday}',
              icon: Icons.check_circle_outline,
              color: AppTheme.success,
              compact: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaveRequests() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: _pendingLeaves.map((leave) {
          final name = leave['teacherName'] as String? ??
              leave['teacherId'] as String? ??
              '—';
          final from = leave['fromDate'] as String? ?? '';
          final to = leave['toDate'] as String? ?? '';
          final reason = leave['reason'] as String? ?? '';
          final id = leave['id'] as String? ?? '';
          return _opCard(
            margin: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: _primary.withOpacity(0.12),
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'T',
                        style: const TextStyle(
                            color: _primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14)),
                          Text('$from → $to',
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('Pending',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.warning,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                if (reason.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(reason,
                      style: const TextStyle(fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.danger,
                          side: const BorderSide(color: AppTheme.danger),
                          padding: const EdgeInsets.symmetric(vertical: 6),
                        ),
                        onPressed: () => _updateLeave(id, 'rejected'),
                        child: const Text('Reject',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.success,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                        ),
                        onPressed: () => _updateLeave(id, 'approved'),
                        child: const Text('Approve',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTeacherSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: TextField(
        decoration: const InputDecoration(
          hintText: 'Search teachers…',
          prefixIcon: Icon(Icons.search, color: Colors.grey),
          isDense: true,
        ),
        onChanged: (v) => setState(() => _teacherSearch = v.toLowerCase()),
      ),
    );
  }

  Widget _buildTeacherList() {
    final filtered = _teachers.where((t) {
      if (_teacherSearch.isEmpty) return true;
      final email = (t['email'] as String? ?? '').toLowerCase();
      final name = (t['name'] as String? ?? '').toLowerCase();
      return email.contains(_teacherSearch) || name.contains(_teacherSearch);
    }).toList();

    if (filtered.isEmpty) {
      return _emptyCard(Icons.people_outline, 'No teachers found');
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: filtered.map((t) {
          final email = t['email'] as String? ?? '';
          final name = (t['name'] as String? ?? email);
          final classes =
              List<String>.from(t['assignedClasses'] as List? ?? []);
          final isOnLeave = _pendingLeaves
              .any((l) => (l['teacherId'] as String? ?? '') == email);

          return _opCard(
            margin: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: _primary.withOpacity(0.12),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'T',
                    style: const TextStyle(
                        color: _primary, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      Text(email,
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 11),
                          overflow: TextOverflow.ellipsis),
                      if (classes.isNotEmpty)
                        Text(classes.join(', '),
                            style: TextStyle(
                                color: _primary.withOpacity(0.7),
                                fontSize: 11)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: isOnLeave
                        ? AppTheme.warning.withOpacity(0.1)
                        : AppTheme.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isOnLeave ? 'On Leave' : 'Active',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isOnLeave ? AppTheme.warning : AppTheme.success),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 2 — ACADEMICS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildAcademicsTab() {
    if (_academicsLoading) return _shimmerList();
    return RefreshIndicator(
      onRefresh: () async {
        _academicsLoaded = false;
        await _loadAcademics();
      },
      color: _primary,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _sectionHeader('RECENT TESTS')),
          SliverToBoxAdapter(child: _buildRecentExams()),
          SliverToBoxAdapter(
              child: _sectionHeader('EXAM CALENDAR (NEXT 30 DAYS)')),
          SliverToBoxAdapter(child: _buildUpcomingExams()),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildRecentExams() {
    if (_recentExams.isEmpty) {
      return _emptyCard(Icons.quiz_outlined, 'No tests recorded yet');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: _recentExams.map((exam) {
          final dt = exam.examDate;
          final dateStr = '${dt.day}/${dt.month}/${dt.year}';
          return _opCard(
            margin: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child:
                      const Icon(Icons.quiz_outlined, color: _primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(exam.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      Text('${exam.className}  ·  $dateStr',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildUpcomingExams() {
    if (_upcomingExams.isEmpty) {
      return _emptyCard(
          Icons.event_note_outlined, 'No upcoming exams in the next 30 days');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: _upcomingExams.map((exam) {
          final dt = exam.examDate;
          final daysLeft = dt.difference(DateTime.now()).inDays;
          return _opCard(
            margin: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Column(
                  children: [
                    Text('${dt.day}',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: _primary)),
                    Text(
                      ['Jan','Feb','Mar','Apr','May','Jun',
                          'Jul','Aug','Sep','Oct','Nov','Dec'][dt.month - 1],
                      style: TextStyle(fontSize: 11, color: _primary),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(exam.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      Text('${exam.className}',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: daysLeft <= 3
                        ? AppTheme.danger.withOpacity(0.1)
                        : daysLeft <= 7
                            ? AppTheme.warning.withOpacity(0.1)
                            : _primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    daysLeft == 0 ? 'Today' : '${daysLeft}d left',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: daysLeft <= 3
                            ? AppTheme.danger
                            : daysLeft <= 7
                                ? AppTheme.warning
                                : _primary),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 3 — FINANCE
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildFinanceTab() {
    if (_financeLoading) return _shimmerList();
    return RefreshIndicator(
      onRefresh: () async {
        _financeLoaded = false;
        await _loadFinance();
      },
      color: _primary,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _sectionHeader('FEE COLLECTION OVERVIEW')),
          SliverToBoxAdapter(child: _buildFeeOverview()),
          SliverToBoxAdapter(child: _sectionHeader('TOP DEFAULTERS')),
          SliverToBoxAdapter(child: _buildDefaultersList()),
          if (_topDefaulters.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('Send WhatsApp Reminder to All Overdue'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _sendAllReminders,
                ),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildFeeOverview() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child: _OPFeeCard(
              label: 'Collected',
              amount: _collectedThisMonth,
              color: AppTheme.success,
              icon: Icons.check_circle_outline,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _OPFeeCard(
              label: 'Pending',
              amount: _pendingFees,
              color: AppTheme.warning,
              icon: Icons.hourglass_bottom_outlined,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _OPFeeCard(
              label: 'Overdue',
              amount: _overdueFees,
              color: AppTheme.danger,
              icon: Icons.warning_amber_outlined,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultersList() {
    if (_topDefaulters.isEmpty) {
      return _emptyCard(Icons.mood_outlined, 'No overdue fees — great!');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: _topDefaulters.map((d) {
          final name = d['name'] as String;
          final cls = d['className'] as String;
          final amt = d['amount'] as double;
          final days = d['daysOverdue'] as int;
          final phone = d['phone'] as String;

          return _opCard(
            margin: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      Text('$cls  ·  ₹${amt.toStringAsFixed(0)}',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12)),
                      Text('$days days overdue',
                          style: const TextStyle(
                              color: AppTheme.danger, fontSize: 11)),
                    ],
                  ),
                ),
                if (phone.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.chat_bubble_outline,
                        color: Color(0xFF25D366)),
                    tooltip: 'WhatsApp',
                    onPressed: () {
                      final n = phone.replaceAll(RegExp(r'\D'), '');
                      final msg = Uri.encodeComponent(
                          'Dear Parent of $name, your fee of ₹${amt.toStringAsFixed(0)} is overdue. Please pay at the earliest.');
                      launchUrl(Uri.parse('https://wa.me/91$n?text=$msg'),
                          mode: LaunchMode.externalApplication);
                    },
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 4 — PRINCIPAL (embedded via sub-Navigator)
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildPrincipalTab() {
    return Navigator(
      onGenerateRoute: (_) => MaterialPageRoute(
        builder: (_) => const PrincipalHome(),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 5 — MANAGE
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildManageTab() {
    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([_loadCreatedUsers(), _loadManage()]);
      },
      color: _primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader('CREATE ACCOUNTS'),
            _buildCreateAccountForm(),
            const SizedBox(height: 8),
            _buildCreatedUsersList(),
            _sectionHeader('MY SCHOOL SETTINGS'),
            _buildSchoolSettings(),
            _sectionHeader('ANNOUNCEMENTS'),
            _buildAnnouncementForm(),
            const SizedBox(height: 8),
            _buildAnnouncementsList(),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateAccountForm() {
    final allowed = _perm.getAllowedToCreate(_myRole);
    if (allowed.isEmpty) {
      return _emptyCard(
          Icons.block_outlined, 'No permission to create accounts');
    }
    return _opCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (allowed.length > 1) ...[
            DropdownButtonFormField<String>(
              value: _createRole,
              decoration: const InputDecoration(
                labelText: 'Account Role',
                prefixIcon: Icon(Icons.badge_outlined),
                isDense: true,
              ),
              items: allowed
                  .map((r) => DropdownMenuItem(
                      value: r,
                      child: Text(RolePermissionService.roleDisplayName(r))))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _createRole = v);
              },
            ),
            const SizedBox(height: 12),
          ] else
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Creating: ${RolePermissionService.roleDisplayName(allowed.first)}',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, color: _primary),
              ),
            ),
          _formField(_nameCtrl, 'Full Name', Icons.person_outline,
              keyboardType: TextInputType.name),
          const SizedBox(height: 10),
          _formField(_emailCtrl, 'Email', Icons.email_outlined,
              keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 10),
          TextField(
            controller: _passCtrl,
            obscureText: !_showPass,
            maxLength: 50,
            maxLengthEnforcement: MaxLengthEnforcement.enforced,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                    _showPass ? Icons.visibility_off : Icons.visibility,
                    size: 18),
                onPressed: () => setState(() => _showPass = !_showPass),
              ),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              isDense: true,
              counterText: '',
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.person_add_outlined),
              label: Text(_saving
                  ? 'Creating…'
                  : 'Create ${RolePermissionService.roleDisplayName(_createRole)} Account'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _saving ? null : _createUser,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreatedUsersList() {
    if (_manageLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_createdUsers.isEmpty) {
      return _emptyCard(Icons.group_outlined, 'No accounts created yet');
    }
    return Column(
      children: _createdUsers.map((u) {
        final email = u['email'] as String? ?? '';
        final role = u['role'] as String? ?? '';
        final createdAt = u['createdAt'];
        String dateStr = '';
        if (createdAt is Timestamp) {
          final dt = createdAt.toDate();
          dateStr = '${dt.day}/${dt.month}/${dt.year}';
        }
        return _opCard(
          margin: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: _primary.withOpacity(0.1),
                child: Icon(
                  role == 'coordinator'
                      ? Icons.manage_accounts_outlined
                      : Icons.business_outlined,
                  color: _primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(email,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
                        overflow: TextOverflow.ellipsis),
                    if (dateStr.isNotEmpty)
                      Text('Created: $dateStr',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  RolePermissionService.roleDisplayName(role),
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _primary),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSchoolSettings() {
    return _opCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _formField(_schoolNameCtrl, 'School Name', Icons.school_outlined),
          const SizedBox(height: 10),
          _formField(_schoolPhoneCtrl, 'Phone Number', Icons.phone_outlined,
              keyboardType: TextInputType.phone),
          const SizedBox(height: 10),
          _formField(
              _schoolAddressCtrl, 'Address', Icons.location_on_outlined),
          const SizedBox(height: 10),
          _formField(_academicYearCtrl, 'Academic Year',
              Icons.calendar_today_outlined),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: _settingsSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
              label: Text(_settingsSaving ? 'Saving…' : 'Save Settings'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _settingsSaving ? null : _saveSchoolSettings,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnnouncementForm() {
    return _opCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _formField(
              _annTitleCtrl, 'Announcement Title', Icons.title_outlined),
          const SizedBox(height: 10),
          TextField(
            controller: _annMsgCtrl,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Message',
              prefixIcon: const Padding(
                  padding: EdgeInsets.only(bottom: 48),
                  child: Icon(Icons.message_outlined)),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _annTarget,
            decoration: const InputDecoration(
              labelText: 'Target Audience',
              prefixIcon: Icon(Icons.group_outlined),
              isDense: true,
            ),
            items: ['All Staff', 'All Guardians', 'Everyone']
                .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _annTarget = v);
            },
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: _annSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.send_outlined),
              label: Text(_annSaving ? 'Sending…' : 'Send Announcement'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _annSaving ? null : _sendAnnouncement,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnnouncementsList() {
    if (_announcements.isEmpty) {
      return _emptyCard(
          Icons.announcement_outlined, 'No announcements yet');
    }
    return Column(
      children: _announcements.take(5).map((a) {
        final title = a['title'] as String? ?? '';
        final body = a['body'] as String? ?? '';
        final audience = a['audience'] as String? ?? '';
        return _opCard(
          margin: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(audience,
                        style:
                            const TextStyle(fontSize: 10, color: _primary)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(color: Colors.black87, fontSize: 13)),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── Shared helpers ────────────────────────────────────────────────────────

  Widget _sectionHeader(String title, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 10),
      child: Row(
        children: [
          Container(
              width: 4,
              height: 16,
              decoration: BoxDecoration(
                  color: _primary, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Text(title,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade600,
                  letterSpacing: 0.8)),
          const Spacer(),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _opCard({
    required Widget child,
    EdgeInsets? margin,
    Color? borderColor,
  }) {
    return Container(
      margin: margin ?? EdgeInsets.zero,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: borderColor != null
            ? Border.all(color: borderColor, width: 1.5)
            : null,
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
        ],
      ),
      child: child,
    );
  }

  Widget _emptyCard(IconData icon, String msg) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: _opCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text(msg,
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: Colors.grey.shade500, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _shimmerList() {
    return Column(
      children: List.generate(
        4,
        (_) => Container(
          margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _shimmerBox(height: 14, width: 140),
              const SizedBox(height: 8),
              _shimmerBox(height: 12, width: 220),
              const SizedBox(height: 6),
              _shimmerBox(height: 12, width: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shimmerBox({double height = 14, double width = double.infinity}) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Widget _badge(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.accent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text('$count',
          style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold)),
    );
  }

  Widget _formField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    TextInputType keyboardType = TextInputType.text,
  }) {
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

// ══════════════════════════════════════════════════════════════════════════
// Stat card
// ══════════════════════════════════════════════════════════════════════════

class _OPStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool compact;

  const _OPStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 10 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: compact ? 18 : 20),
              const Spacer(),
              Text(value,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: compact ? 18 : 22,
                      color: color)),
            ],
          ),
          Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: compact ? 10 : 11,
                  color: Colors.black87)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// Fee summary card
// ══════════════════════════════════════════════════════════════════════════

class _OPFeeCard extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final IconData icon;

  const _OPFeeCard({
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            '₹${amount >= 1000 ? '${(amount / 1000).toStringAsFixed(1)}k' : amount.toStringAsFixed(0)}',
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 16, color: color),
          ),
          Text(label,
              style: const TextStyle(color: Colors.black54, fontSize: 10)),
        ],
      ),
    );
  }
}

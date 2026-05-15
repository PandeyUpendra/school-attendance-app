import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/student_data.dart';
import '../models/attendance_status.dart';
import '../models/student.dart';
import '../models/student_profile_data.dart';
import '../providers/auth_provider.dart';
import '../services/attendance_service.dart';
import '../services/fee_reminder_service.dart';
import '../services/firestore_service.dart';
import 'timetable_screen.dart';

class GuardianHome extends StatefulWidget {
  const GuardianHome({super.key});

  @override
  State<GuardianHome> createState() => _GuardianHomeState();
}

class _GuardianHomeState extends State<GuardianHome>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  // User / child info
  String _schoolId = '';
  String _guardianId = '';
  String _classId = '';
  int _roll = 0;
  Student? _child;

  // Tab 1 — My Child
  bool _childLoading = true;
  Map<String, AttendanceStatus?> _monthAttendance = {};
  FeesStatus _feesStatus = FeesStatus.pending;
  String? _feeDueDate;
  double? _feeAmount;
  int _presentCount = 0;
  int _totalDays = 0;

  // Tab 2 — Academics
  bool _academicsLoading = false;
  bool _academicsLoaded = false;
  List<Map<String, dynamic>> _tests = [];
  List<Map<String, dynamic>> _teacherComplaints = [];
  String _remarks = '';

  // Tab 3 — School Info
  bool _schoolInfoLoading = false;
  bool _schoolInfoLoaded = false;
  List<Map<String, dynamic>> _subjectTeachers = [];
  Map<String, dynamic>? _busInfo;
  List<Map<String, dynamic>> _events = [];
  String _leaderboardCategory = 'Academics';
  List<Map<String, dynamic>> _leaderboard = [];
  bool _leaderboardLoading = false;

  // Tab 4 — Complaints
  bool _complaintsLoading = false;
  bool _complaintsLoaded = false;
  List<Map<String, dynamic>> _myComplaints = [];
  String _recipientRole = 'Principal';
  final _complaintCtrl = TextEditingController();
  bool _submitting = false;

  static const List<String> _recipients = [
    'Principal',
    'Coordinator',
    'Class Teacher',
  ];

  static const List<String> _leaderboardCategories = [
    'Academics',
    'Sports',
    'Vocabulary',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _loadTabData(_tabController.index);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _initUser());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _complaintCtrl.dispose();
    super.dispose();
  }

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> _initUser() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    _schoolId = user.schoolId;
    _guardianId = user.uid;
    _classId = user.classIds.isNotEmpty ? user.classIds.first : '';
    _roll = int.tryParse(user.studentId ?? '') ?? 0;
    await _loadChildTab();
  }

  void _loadTabData(int tab) {
    switch (tab) {
      case 1:
        if (!_academicsLoaded) _loadAcademics();
      case 2:
        if (!_schoolInfoLoaded) _loadSchoolInfo();
      case 3:
        if (!_complaintsLoaded) _loadMyComplaints();
      default:
        break;
    }
  }

  // ── Tab 1: My Child ────────────────────────────────────────────────────────

  Future<void> _loadChildTab() async {
    setState(() => _childLoading = true);

    // Load student info
    List<Student> students = [];
    if (_schoolId.isNotEmpty && _classId.isNotEmpty) {
      final cloud = await FirestoreService.loadStudents(
          schoolId: _schoolId, classId: _classId);
      if (cloud != null) {
        students = cloud
            .map((e) => Student(
                  roll: (e['roll'] as num).toInt(),
                  name: e['name'] as String,
                  parentPhone: e['parentPhone'] as String?,
                  photoUrl: e['photoUrl'] as String?,
                ))
            .toList();
      }
    }
    if (students.isEmpty) {
      students = await AttendanceService.loadStudents(_classId) ??
          List.from(classStudents[_classId] ?? []);
    }
    final child = students.where((s) => s.roll == _roll).firstOrNull;

    // Load this month's attendance
    final now = DateTime.now();
    final monthAttendance = <String, AttendanceStatus?>{};
    int presentCount = 0;
    int totalDays = 0;

    if (_schoolId.isNotEmpty && _classId.isNotEmpty && _roll > 0) {
      final allDates = await FirestoreService.getAttendanceDates(
          schoolId: _schoolId, classId: _classId);
      final monthDates = allDates.where((d) {
        final parts = d.split('-');
        if (parts.length < 2) return false;
        return int.tryParse(parts[0]) == now.year &&
            int.tryParse(parts[1]) == now.month;
      }).toList();

      for (final date in monthDates) {
        final att = await FirestoreService.loadAttendance(
            schoolId: _schoolId, classId: _classId, date: date);
        final status = att?[_roll];
        monthAttendance[date] = status;
        if (status != null) {
          totalDays++;
          if (status.isPresent) presentCount++;
        }
      }
    }

    // Load fees status + due date + amount
    FeesStatus feesStatus = FeesStatus.pending;
    String? feeDueDate;
    double? feeAmount;
    if (_schoolId.isNotEmpty && _classId.isNotEmpty && _roll > 0) {
      final profile = await FirestoreService.loadStudentProfile(
          schoolId: _schoolId, classId: _classId, roll: _roll);
      if (profile != null) {
        feesStatus = FeesStatus.fromString(profile['feesStatus'] as String?);
        feeDueDate = profile['feeDueDate'] as String?;
        feeAmount = (profile['feeAmount'] as num?)?.toDouble();
      }
    }
    // Also check student document fields if profile didn't have them
    if (feeDueDate == null && child != null) {
      feeDueDate = child.feeDueDate;
      feeAmount ??= child.feeAmount;
    }

    if (mounted) {
      setState(() {
        _child = child;
        _monthAttendance = monthAttendance;
        _feesStatus = feesStatus;
        _feeDueDate = feeDueDate;
        _feeAmount = feeAmount;
        _presentCount = presentCount;
        _totalDays = totalDays;
        _childLoading = false;
      });
    }
  }

  // ── Tab 2: Academics ───────────────────────────────────────────────────────

  Future<void> _loadAcademics() async {
    if (_academicsLoaded) return;
    setState(() => _academicsLoading = true);

    // Load tests for this class
    List<Map<String, dynamic>> tests = [];
    String remarks = '';
    List<Map<String, dynamic>> teacherComplaints = [];

    if (_schoolId.isNotEmpty && _classId.isNotEmpty) {
      tests = await FirestoreService.getTests(
          schoolId: _schoolId, classId: _classId);

      // Load student profile for remarks and teacher complaints
      if (_roll > 0) {
        final profile = await FirestoreService.loadStudentProfile(
            schoolId: _schoolId, classId: _classId, roll: _roll);
        if (profile != null) {
          remarks = profile['remarks'] as String? ?? '';
          final complaintsList = profile['complaints'] as List?;
          if (complaintsList != null) {
            teacherComplaints = complaintsList.cast<Map<String, dynamic>>();
          }
        }
      }
    }

    if (mounted) {
      setState(() {
        _tests = tests;
        _remarks = remarks;
        _teacherComplaints = teacherComplaints;
        _academicsLoading = false;
        _academicsLoaded = true;
      });
    }
  }

  // ── Tab 3: School Info ─────────────────────────────────────────────────────

  Future<void> _loadSchoolInfo() async {
    if (_schoolInfoLoaded) return;
    setState(() => _schoolInfoLoading = true);

    List<Map<String, dynamic>> subjectTeachers = [];
    Map<String, dynamic>? busInfo;
    List<Map<String, dynamic>> events = [];

    if (_schoolId.isNotEmpty) {
      final results = await Future.wait([
        _classId.isNotEmpty
            ? FirestoreService.getSubjectTeachers(
                schoolId: _schoolId, classId: _classId)
            : Future.value(<Map<String, dynamic>>[]),
        FirestoreService.getBusInfo(schoolId: _schoolId),
        FirestoreService.getSchoolEvents(schoolId: _schoolId),
      ]);
      subjectTeachers = results[0] as List<Map<String, dynamic>>;
      busInfo = results[1] as Map<String, dynamic>?;
      events = results[2] as List<Map<String, dynamic>>;
    }

    if (mounted) {
      setState(() {
        _subjectTeachers = subjectTeachers;
        _busInfo = busInfo;
        _events = events;
        _schoolInfoLoading = false;
        _schoolInfoLoaded = true;
      });
      _loadLeaderboard();
    }
  }

  Future<void> _loadLeaderboard() async {
    setState(() => _leaderboardLoading = true);
    final entries = await FirestoreService.getLeaderboardEntries(
        schoolId: _schoolId, category: _leaderboardCategory);
    if (mounted) {
      setState(() {
        _leaderboard = entries;
        _leaderboardLoading = false;
      });
    }
  }

  // ── Tab 4: Complaints ──────────────────────────────────────────────────────

  Future<void> _loadMyComplaints() async {
    if (_complaintsLoaded) return;
    setState(() => _complaintsLoading = true);
    final complaints = await FirestoreService.getGuardianComplaints(
        schoolId: _schoolId, guardianId: _guardianId);
    if (mounted) {
      setState(() {
        _myComplaints = complaints;
        _complaintsLoading = false;
        _complaintsLoaded = true;
      });
    }
  }

  Future<void> _submitComplaint() async {
    final text = _complaintCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _submitting = true);

    await FirestoreService.addSchoolComplaint(
      schoolId: _schoolId,
      complaint: {
        'guardianId': _guardianId,
        'studentId': _roll.toString(),
        'studentName': _child?.name ?? '',
        'className': _classId,
        'recipientRole': _recipientRole,
        'complaintText': text,
        'status': 'Open',
      },
    );

    _complaintCtrl.clear();
    _complaintsLoaded = false;
    await _loadMyComplaints();

    if (mounted) {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Complaint submitted successfully'),
          backgroundColor: Color(0xFF00897B),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _pct(int present, int total) => total == 0
      ? '0%'
      : '${(present / total * 100).toStringAsFixed(1)}%';

  String _fmtDate(String dateStr) {
    final parts = dateStr.split('-');
    if (parts.length != 3) return dateStr;
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final d = int.tryParse(parts[2]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return '$d ${months[m]} ${parts[0]}';
  }

  AttendanceStatus? _statusForDay(DateTime day) {
    final key =
        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    return _monthAttendance[key];
  }

  // ── Progress badge ─────────────────────────────────────────────────────────

  ({String label, Color color, IconData icon}) _progressBadge() {
    if (_tests.length < 2) {
      return (label: 'N/A', color: Colors.grey, icon: Icons.remove);
    }
    final recent = _tests.take(3).toList();
    final scores = recent.map((t) {
      final marks = t['marks'] as Map?;
      final rollMarks = marks?[_roll.toString()];
      final obtained = (rollMarks as num?)?.toInt() ?? 0;
      final total = (t['totalMarks'] as num?)?.toInt() ?? 100;
      return total == 0 ? 0.0 : obtained / total;
    }).toList();

    if (scores.length < 2) {
      return (label: 'Stable', color: Colors.blue, icon: Icons.trending_flat);
    }
    final diff = scores.first - scores.last;
    if (diff > 0.05) {
      return (
        label: 'Improving',
        color: Colors.green,
        icon: Icons.trending_up
      );
    }
    if (diff < -0.05) {
      return (
        label: 'Declining',
        color: Colors.red,
        icon: Icons.trending_down
      );
    }
    return (label: 'Stable', color: Colors.blue, icon: Icons.trending_flat);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF00897B),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_child?.name ?? 'My Child',
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold)),
            Text('$_classId · Roll $_roll',
                style:
                    const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => _confirmSignOut(context, user),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelStyle: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600),
          tabs: const [
            Tab(icon: Icon(Icons.child_care, size: 18), text: 'My Child'),
            Tab(icon: Icon(Icons.school, size: 18), text: 'Academics'),
            Tab(
                icon: Icon(Icons.info_outline, size: 18),
                text: 'School Info'),
            Tab(
                icon: Icon(Icons.report_outlined, size: 18),
                text: 'Complaints'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildMyChildTab(),
          _buildAcademicsTab(),
          _buildSchoolInfoTab(),
          _buildComplaintsTab(),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 1 — MY CHILD
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildMyChildTab() {
    if (_childLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final pct = _totalDays == 0 ? 0.0 : _presentCount / _totalDays;
    final now = DateTime.now();

    return RefreshIndicator(
      onRefresh: _loadChildTab,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // ── Fee reminder card (shown only when not Paid) ──
          if (_feesStatus != FeesStatus.paid) ...[
            _buildFeeReminderCard(),
            const SizedBox(height: 12),
          ],

          // ── Student card ──
          _card(
            child: Row(
              children: [
                _childAvatar(),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_child?.name ?? '—',
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      _infoRow(Icons.class_outlined, _classId),
                      _infoRow(Icons.tag, 'Roll No. $_roll'),
                      if (_child?.parentPhone != null)
                        _infoRow(Icons.phone_outlined,
                            _child!.parentPhone!),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Attendance % badge + progress ──
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.bar_chart_outlined,
                        color: Color(0xFF00897B), size: 20),
                    const SizedBox(width: 8),
                    const Text('Attendance',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: pct >= 0.75
                            ? Colors.green.shade100
                            : pct >= 0.5
                                ? Colors.orange.shade100
                                : Colors.red.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _pct(_presentCount, _totalDays),
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: pct >= 0.75
                                ? Colors.green.shade700
                                : pct >= 0.5
                                    ? Colors.orange.shade700
                                    : Colors.red.shade700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 8,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation(
                      pct >= 0.75
                          ? Colors.green.shade600
                          : pct >= 0.5
                              ? Colors.orange.shade600
                              : Colors.red.shade600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _miniStat('Present', '$_presentCount', Colors.green),
                    _miniStat('Absent',
                        '${_totalDays - _presentCount}', Colors.red),
                    _miniStat('Days Tracked', '$_totalDays', Colors.blue),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Monthly calendar ──
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.calendar_month_outlined,
                        color: Color(0xFF00897B), size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '${_monthName(now.month)} ${now.year}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TableCalendar(
                  firstDay: DateTime(now.year, now.month, 1),
                  lastDay: DateTime(now.year, now.month + 1, 0),
                  focusedDay: now,
                  headerVisible: false,
                  calendarFormat: CalendarFormat.month,
                  daysOfWeekStyle: const DaysOfWeekStyle(
                    weekdayStyle: TextStyle(fontSize: 11),
                    weekendStyle: TextStyle(
                        fontSize: 11, color: Colors.red),
                  ),
                  calendarBuilders: CalendarBuilders(
                    defaultBuilder: (ctx, day, focused) =>
                        _calendarDay(day),
                    todayBuilder: (ctx, day, focused) =>
                        _calendarDay(day, isToday: true),
                    outsideBuilder: (ctx, day, focused) =>
                        const SizedBox.shrink(),
                  ),
                  onDaySelected: null,
                  selectedDayPredicate: (_) => false,
                ),
                const SizedBox(height: 8),
                _calendarLegend(),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Fees status ──
          _card(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _feesStatusColor(_feesStatus)
                        .withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.receipt_long_outlined,
                      color: _feesStatusColor(_feesStatus),
                      size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Fee Status',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey)),
                      const SizedBox(height: 2),
                      Text(
                        _feesStatus.label,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                            color: _feesStatusColor(_feesStatus)),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _feesStatusColor(_feesStatus)
                        .withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: _feesStatusColor(_feesStatus)
                            .withOpacity(0.3)),
                  ),
                  child: Text(
                    _feesStatus == FeesStatus.paid
                        ? '✓ Cleared'
                        : _feesStatus == FeesStatus.pending
                            ? '⏳ Due'
                            : '⚠ Overdue',
                    style: TextStyle(
                        color: _feesStatusColor(_feesStatus),
                        fontWeight: FontWeight.w600,
                        fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 2 — ACADEMICS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildAcademicsTab() {
    if (_academicsLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final badge = _progressBadge();

    return RefreshIndicator(
      onRefresh: () async {
        _academicsLoaded = false;
        await _loadAcademics();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // Progress badge
          _card(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: badge.color.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(badge.icon, color: badge.color, size: 26),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Performance Trend',
                        style:
                            TextStyle(color: Colors.grey, fontSize: 12)),
                    Text(
                      badge.label,
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: badge.color),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  'Last ${_tests.length < 3 ? _tests.length : 3} tests',
                  style: const TextStyle(
                      color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Test results
          _sectionHeader(Icons.assignment_outlined, 'Test Results'),
          const SizedBox(height: 8),

          if (_tests.isEmpty)
            _emptyState('No tests recorded yet')
          else
            ..._tests.map((t) {
              final marks = (t['marks'] as Map?)?[_roll.toString()];
              final obtained = (marks as num?)?.toInt();
              final total =
                  (t['totalMarks'] as num?)?.toInt() ?? 100;
              final pct =
                  obtained == null || total == 0 ? null : obtained / total;
              final dateTs = t['date'];
              String dateStr = '';
              if (dateTs is String) dateStr = dateTs;

              return _card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t['name'] as String? ?? 'Test',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14)),
                              Text(
                                  '${t['subject'] as String? ?? ''}'
                                  '${dateStr.isNotEmpty ? ' · $dateStr' : ''}',
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 12)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: pct == null
                                ? Colors.grey.shade100
                                : pct >= 0.75
                                    ? Colors.green.shade50
                                    : pct >= 0.5
                                        ? Colors.orange.shade50
                                        : Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            obtained == null
                                ? 'N/A'
                                : '$obtained / $total',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: pct == null
                                    ? Colors.grey
                                    : pct >= 0.75
                                        ? Colors.green.shade700
                                        : pct >= 0.5
                                            ? Colors.orange.shade700
                                            : Colors.red.shade700),
                          ),
                        ),
                      ],
                    ),
                    if (pct != null) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 5,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation(
                            pct >= 0.75
                                ? Colors.green
                                : pct >= 0.5
                                    ? Colors.orange
                                    : Colors.red,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),

          const SizedBox(height: 16),

          // Teacher remarks
          _sectionHeader(Icons.comment_outlined, 'Teacher Remarks'),
          const SizedBox(height: 8),
          _card(
            child: _remarks.isEmpty
                ? Text('No remarks added yet.',
                    style: TextStyle(
                        color: Colors.grey.shade400, fontSize: 14))
                : Text(_remarks,
                    style: const TextStyle(fontSize: 14, height: 1.5)),
          ),

          const SizedBox(height: 16),

          // Teacher complaints about student
          _sectionHeader(
              Icons.report_outlined, 'Teacher Observations'),
          const SizedBox(height: 8),

          if (_teacherComplaints.isEmpty)
            _emptyState('No observations recorded')
          else
            ..._teacherComplaints.map((c) {
              final date = c['date'] as String? ?? '';
              return _card(
                margin: const EdgeInsets.only(bottom: 8),
                color: Colors.orange.shade50,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.person_outline,
                            size: 14, color: Colors.orange.shade700),
                        const SizedBox(width: 4),
                        Text(c['addedBy'] as String? ?? 'Teacher',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange.shade700,
                                fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text(date,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(c['text'] as String? ?? '',
                        style: const TextStyle(fontSize: 13)),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 3 — SCHOOL INFO
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildSchoolInfoTab() {
    if (_schoolInfoLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: () async {
        _schoolInfoLoaded = false;
        await _loadSchoolInfo();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // ── Timetable ──
          _sectionHeader(Icons.table_chart_outlined, 'Class Timetable'),
          const SizedBox(height: 8),
          SizedBox(
            height: 320,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: TimetableScreen(
                className: _classId,
                schoolId: _schoolId,
                readOnly: true,
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Subject teachers ──
          _sectionHeader(Icons.people_outline, 'Subject Teachers'),
          const SizedBox(height: 8),

          if (_subjectTeachers.isEmpty)
            _emptyState('No subject teacher contacts added yet')
          else
            ..._subjectTeachers.map((t) {
              final name = t['name'] as String? ?? '';
              final subject = t['subject'] as String? ?? '';
              final phone = t['phone'] as String? ?? '';
              return _card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor:
                          const Color(0xFF6A1B9A).withOpacity(0.12),
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'T',
                        style: const TextStyle(
                            color: Color(0xFF6A1B9A),
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14)),
                          Text(subject,
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    ),
                    if (phone.isNotEmpty)
                      GestureDetector(
                        onTap: () =>
                            launchUrl(Uri.parse('tel:$phone')),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.green.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.call,
                                  size: 14,
                                  color: Colors.green.shade700),
                              const SizedBox(width: 4),
                              Text(phone,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.green.shade700,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),

          const SizedBox(height: 20),

          // ── Bus driver ──
          _sectionHeader(Icons.directions_bus_outlined, 'School Bus'),
          const SizedBox(height: 8),

          _busInfo == null
              ? _emptyState('No bus information available')
              : _card(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color:
                              Colors.amber.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.directions_bus,
                            color: Colors.amber.shade800, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                _busInfo!['driverName'] as String? ??
                                    'Bus Driver',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15)),
                            Text('Bus Driver',
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                      ),
                      if ((_busInfo!['phone'] as String?) != null)
                        GestureDetector(
                          onTap: () => launchUrl(Uri.parse(
                              'tel:${_busInfo!['phone']}')),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.green.shade200),
                            ),
                            child: Icon(Icons.call,
                                color: Colors.green.shade700,
                                size: 20),
                          ),
                        ),
                    ],
                  ),
                ),

          const SizedBox(height: 20),

          // ── Leaderboard ──
          Row(
            children: [
              _sectionHeader(Icons.emoji_events_outlined, 'Leaderboard'),
              const Spacer(),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _leaderboardCategory,
                  isDense: true,
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black87,
                      fontWeight: FontWeight.w600),
                  items: _leaderboardCategories
                      .map((c) => DropdownMenuItem(
                          value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null && v != _leaderboardCategory) {
                      setState(() => _leaderboardCategory = v);
                      _loadLeaderboard();
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          _leaderboardLoading
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : _leaderboard.isEmpty
                  ? _emptyState(
                      'No leaderboard entries for $_leaderboardCategory')
                  : Column(
                      children: _leaderboard
                          .asMap()
                          .entries
                          .map((entry) {
                        final rank = entry.key + 1;
                        final item = entry.value;
                        Color rankColor = Colors.grey;
                        if (rank == 1) rankColor = const Color(0xFFFFD700);
                        if (rank == 2) rankColor = const Color(0xFFC0C0C0);
                        if (rank == 3) rankColor = const Color(0xFFCD7F32);
                        return _card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: rankColor.withOpacity(0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '#$rank',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: rankColor == Colors.grey
                                            ? Colors.grey
                                            : rankColor),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        item['studentName'] as String? ??
                                            '',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14)),
                                    Text(
                                        item['className'] as String? ?? '',
                                        style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 12)),
                                  ],
                                ),
                              ),
                              Text(
                                '${item['score'] ?? ''}',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: rankColor == Colors.grey
                                        ? Colors.black87
                                        : rankColor),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),

          const SizedBox(height: 20),

          // ── School events ──
          _sectionHeader(Icons.event_outlined, 'School Events'),
          const SizedBox(height: 8),

          if (_events.isEmpty)
            _emptyState('No events posted yet')
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.85,
              ),
              itemCount: _events.length,
              itemBuilder: (context, i) {
                final event = _events[i];
                final photoUrl = event['photoUrl'] as String? ?? '';
                final title = event['title'] as String? ?? '';
                final date = event['date'] as String? ?? '';
                return ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: photoUrl.isNotEmpty
                              ? Image.network(photoUrl,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _eventPlaceholder())
                              : _eventPlaceholder(),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12)),
                              Text(date,
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 4 — COMPLAINTS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildComplaintsTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // ── Complaint form ──
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.report_outlined,
                        color: Colors.red.shade700, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Text('New Complaint',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 16),
              const Text('To',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _recipientRole,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.person_outline),
                  isDense: true,
                ),
                items: _recipients
                    .map((r) =>
                        DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _recipientRole = v);
                },
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _complaintCtrl,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Your Complaint',
                  alignLabelWithHint: true,
                  prefixIcon: Padding(
                    padding: EdgeInsets.only(bottom: 60),
                    child: Icon(Icons.edit_note_outlined),
                  ),
                  hintText:
                      'Describe your concern in detail…',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.send_rounded),
                  label: const Text('Submit Complaint'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00897B),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: (_submitting ||
                          _complaintCtrl.text.trim().isEmpty)
                      ? null
                      : _submitComplaint,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── My complaints list ──
        _sectionHeader(Icons.history_outlined, 'My Complaints'),
        const SizedBox(height: 8),

        if (_complaintsLoading)
          const Center(
              child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(strokeWidth: 2)))
        else if (_myComplaints.isEmpty)
          _emptyState('No complaints submitted yet')
        else
          ..._myComplaints.map((c) {
            final status = c['status'] as String? ?? 'Open';
            final text = c['complaintText'] as String? ?? '';
            final recipient = c['recipientRole'] as String? ?? '';
            final createdAt = c['createdAt'];
            String dateStr = '';
            if (createdAt != null) {
              try {
                final ts = createdAt;
                if (ts.runtimeType.toString().contains('Timestamp')) {
                  final dt = (ts as dynamic).toDate() as DateTime;
                  dateStr =
                      '${dt.day}/${dt.month}/${dt.year}';
                }
              } catch (_) {}
            }

            Color statusColor;
            IconData statusIcon;
            switch (status) {
              case 'Resolved':
                statusColor = Colors.green.shade600;
                statusIcon = Icons.check_circle_outline;
              case 'In Progress':
                statusColor = Colors.amber.shade700;
                statusIcon = Icons.hourglass_bottom_outlined;
              default:
                statusColor = Colors.red.shade600;
                statusIcon = Icons.radio_button_unchecked;
            }

            return _card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.person_outline,
                          size: 14, color: Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Text('To: $recipient',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: statusColor.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(statusIcon,
                                size: 12, color: statusColor),
                            const SizedBox(width: 4),
                            Text(status,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: statusColor,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(text,
                      style: const TextStyle(
                          fontSize: 13, height: 1.4)),
                  if (dateStr.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(dateStr,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey)),
                  ],
                ],
              ),
            );
          }),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HELPERS & SMALL WIDGETS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildFeeReminderCard() {
    final reminder = FeeReminderService().checkFeeStatus(
      Student(
        roll: _roll,
        name: _child?.name ?? '',
        feeStatus: _feesStatus == FeesStatus.overdue
            ? 'Overdue'
            : _feesStatus == FeesStatus.paid
                ? 'Paid'
                : 'Pending',
        feeDueDate: _feeDueDate,
        feeAmount: _feeAmount,
      ),
    );

    final isOverdue = _feesStatus == FeesStatus.overdue || reminder.isOverdue;
    final amtStr = _feeAmount != null
        ? '₹${_feeAmount!.toStringAsFixed(0)}'
        : 'Amount not set';
    final daysDiff = reminder.daysDiff;

    String title;
    String subtitle;
    if (isOverdue) {
      final overdueDays = daysDiff != null && daysDiff < 0 ? (-daysDiff) : null;
      title = overdueDays != null
          ? 'Fee OVERDUE by $overdueDays day${overdueDays == 1 ? '' : 's'}'
          : 'Fee OVERDUE';
      subtitle = amtStr;
    } else {
      final dueDays = daysDiff;
      title = dueDays != null
          ? 'Fee Due in $dueDays day${dueDays == 1 ? '' : 's'}'
          : 'Fee Due Soon';
      subtitle = '$amtStr'
          '${_feeDueDate != null ? '  ·  Due: ${_feeDueDate!}' : ''}';
    }

    final borderColor = isOverdue ? Colors.red.shade400 : Colors.amber.shade600;
    final bgColor = isOverdue
        ? Colors.red.shade50
        : Theme.of(context).cardTheme.color ?? Colors.white;
    final iconColor = isOverdue ? Colors.red.shade600 : Colors.amber.shade700;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: borderColor.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isOverdue ? Icons.warning_rounded : Icons.schedule_rounded,
              color: iconColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isOverdue
                            ? Colors.red.shade700
                            : Colors.amber.shade900)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 12,
                        color: isOverdue
                            ? Colors.red.shade600
                            : Colors.amber.shade800)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isOverdue)
            OutlinedButton(
              onPressed: () {
                if (_child?.parentPhone != null) {
                  launchUrl(Uri.parse('tel:+91${_child!.parentPhone!.replaceAll(RegExp(r'\D'), '')}'));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('No contact number available'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade600,
                side: BorderSide(color: Colors.red.shade400),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Contact\nSchool',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11)),
            )
          else
            OutlinedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please contact the school to view fee details.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.amber.shade800,
                side: BorderSide(color: Colors.amber.shade500),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('View\nDetails',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11)),
            ),
        ],
      ),
    );
  }

  Widget _childAvatar() {
    final hasPhoto = _child?.photoUrl != null && _child!.photoUrl!.isNotEmpty;
    return CircleAvatar(
      radius: 36,
      backgroundColor: const Color(0xFF00897B).withOpacity(0.15),
      backgroundImage:
          hasPhoto ? NetworkImage(_child!.photoUrl!) : null,
      child: hasPhoto
          ? null
          : Text(
              _child?.name.isNotEmpty == true
                  ? _child!.name[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00897B)),
            ),
    );
  }

  Widget _calendarDay(DateTime day, {bool isToday = false}) {
    final status = _statusForDay(day);
    Color? bg;
    Color textColor = Colors.black87;

    if (status != null) {
      if (status.isPresent) {
        bg = Colors.green.shade400;
        textColor = Colors.white;
      } else if (status.isAbsent) {
        bg = Colors.red.shade400;
        textColor = Colors.white;
      } else {
        bg = Colors.amber.shade400;
        textColor = Colors.white;
      }
    } else if (isToday) {
      bg = const Color(0xFF00897B).withOpacity(0.2);
    }

    return Container(
      margin: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: isToday
            ? Border.all(color: const Color(0xFF00897B), width: 1.5)
            : null,
      ),
      child: Center(
        child: Text(
          '${day.day}',
          style: TextStyle(
              fontSize: 12,
              fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
              color: textColor),
        ),
      ),
    );
  }

  Widget _calendarLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _legendDot(Colors.green.shade400, 'Present'),
        const SizedBox(width: 16),
        _legendDot(Colors.red.shade400, 'Absent'),
        const SizedBox(width: 16),
        _legendDot(Colors.amber.shade400, 'Leave'),
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(children: [
      Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
    ]);
  }

  Widget _miniStat(String label, String value, Color color) {
    return Column(children: [
      Text(value,
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color)),
      Text(label,
          style: const TextStyle(fontSize: 11, color: Colors.grey)),
    ]);
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(children: [
        Icon(icon, size: 13, color: Colors.grey.shade500),
        const SizedBox(width: 4),
        Text(text,
            style: TextStyle(
                fontSize: 12, color: Colors.grey.shade600)),
      ]),
    );
  }

  Widget _sectionHeader(IconData icon, String title) {
    return Row(children: [
      Icon(icon, size: 18, color: const Color(0xFF00897B)),
      const SizedBox(width: 8),
      Text(title,
          style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 15)),
    ]);
  }

  Widget _emptyState(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Column(children: [
          Icon(Icons.inbox_outlined,
              size: 40, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          Text(message,
              style: TextStyle(
                  color: Colors.grey.shade400, fontSize: 13)),
        ]),
      ),
    );
  }

  Widget _card({
    required Widget child,
    EdgeInsets? margin,
    Color? color,
  }) {
    return Container(
      margin: margin ?? EdgeInsets.zero,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color ?? (Theme.of(context).cardTheme.color ?? Colors.white),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
              color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
        ],
      ),
      child: child,
    );
  }

  Widget _eventPlaceholder() {
    return Container(
      color: Colors.grey.shade200,
      child: Center(
          child: Icon(Icons.image_outlined,
              color: Colors.grey.shade400, size: 36)),
    );
  }

  Color _feesStatusColor(FeesStatus s) {
    switch (s) {
      case FeesStatus.paid:
        return Colors.green.shade600;
      case FeesStatus.pending:
        return Colors.orange.shade700;
      case FeesStatus.overdue:
        return Colors.red.shade600;
    }
  }

  String _monthName(int month) {
    const names = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return names[month];
  }

  void _confirmSignOut(BuildContext context, dynamic user) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out?'),
        content: const Text('You will be returned to the login screen.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<AuthProvider>().signOut();
            },
            child: const Text('Sign Out',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

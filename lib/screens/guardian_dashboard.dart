import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';
import '../models/exam.dart';
import '../models/student.dart';
import '../models/fee.dart';
import '../models/homework.dart';
import '../models/teacher.dart';
import '../models/timetable_entry.dart';
import '../services/auth_service.dart';
import '../services/exam_service.dart';
import '../services/student_service.dart';
import '../services/fee_service.dart';
import '../services/homework_service.dart';
import '../services/notification_service.dart';
import '../services/timetable_service.dart';
import '../services/school_service.dart';
import '../services/contact_service.dart';
import '../models/school_contact.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'school_contacts_screen.dart';
import 'role_selection_screen.dart';
import 'announcements_screen.dart';
import 'notifications_screen.dart';
import 'calendar_screen.dart';
import 'attendance_certificate_screen.dart';
import 'student_remarks_screen.dart';
import 'guardian_student_details_screen.dart';

/// The Guardian Portal — shows a single student's attendance to their parent.
/// Guardian is linked to {studentClass, studentRoll} in allowed_users.
class GuardianDashboard extends StatefulWidget {
  final String studentClass;
  final int    studentRoll;

  const GuardianDashboard({
    super.key,
    required this.studentClass,
    required this.studentRoll,
  });

  @override
  State<GuardianDashboard> createState() => _GuardianDashboardState();
}

class _GuardianDashboardState extends State<GuardianDashboard> {
  final _service     = StudentService();
  final _feeService  = FeeService();
  final _hwService   = HomeworkService();
  final _examService = ExamService();
  final _ttService   = TimetableService();

  bool _loading = true;
  String? _error;
  Student? _student;

  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Map<int, Map<int, String>> _monthData = {};
  String? _todayStatus;

  // Fee
  FeeStructure? _feeStructure;
  double        _totalPaid = 0;

  // Homework
  List<Homework> _homeworkList = [];

  // Notifications
  int _unreadNotifCount = 0;

  // Exam results — (Exam, ExamResult?) pairs sorted newest first
  List<MapEntry<Exam, ExamResult?>> _examData = [];

  // Timetable
  Map<String, Map<int, TimetableEntry>> _classTimetable = {};
  List<Map<String, dynamic>> _bellSettings = [];
  String _firstBellTime = '08:00';
  Map<String, Teacher> _teacherById = {};

  // School Policy
  String _dressPhotoUrl = '';
  List<String> _rules = [];

  // Other students for this guardian
  List<String> _allStudentLinks = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
    _loadOtherStudents();
  }

  Future<void> _loadOtherStudents() async {
    final session = await AuthService().getSession();
    if (session != null && session['studentLinks'] != null) {
      if (mounted) {
        setState(() {
          _allStudentLinks = List<String>.from(session['studentLinks']);
        });
      }
    }
  }

  /// Loads every exam for the class + this student's result for each.
  Future<List<MapEntry<Exam, ExamResult?>>> _loadExamData() async {
    final exams = await _examService.getExams(className: widget.studentClass);
    if (exams.isEmpty) return [];
    final resultFuts =
        exams.map((e) => _examService.getResult(e.id, widget.studentRoll));
    final results = await Future.wait(resultFuts);
    return List.generate(exams.length, (i) => MapEntry(exams[i], results[i]));
  }

  Future<void> _loadAll() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        _service.getStudentByRoll(widget.studentClass, widget.studentRoll),  // 0
        _service.loadMonthAttendance(
            widget.studentClass, _month.year, _month.month),                  // 1
        _service.loadTodayAttendance(widget.studentClass),                     // 2
        _feeService.getFeeStructure(widget.studentClass),                      // 3
        _feeService.getTotalPaid(widget.studentClass, widget.studentRoll),     // 4
        NotificationService().unreadCount(
          role:         'guardian',
          studentClass: widget.studentClass,
          studentRoll:  widget.studentRoll,
        ),                                                                     // 5
        _hwService.getHomeworkForClass(widget.studentClass),                   // 6
        _loadExamData(),                                                       // 7
        _ttService.getTimetable(),                                             // 8
        _ttService.getSettings(),                                              // 9
        _ttService.getTeachers(),                                              // 10
        SchoolService().getSchoolPolicy(),                                     // 11
      ]);
      if (!mounted) return;

      final student      = results[0]  as Student?;
      final monthData    = results[1]  as Map<int, Map<int, String>>;
      final todayByRoll  = results[2]  as Map<int, String>;
      final feeStructure = results[3]  as FeeStructure;
      final totalPaid    = results[4]  as double;
      final notifCount   = results[5]  as int;
      final hwList       = results[6]  as List<Homework>;
      final examData     = results[7]  as List<MapEntry<Exam, ExamResult?>>;
      final timetable    = results[8]
          as Map<String, Map<String, Map<int, TimetableEntry>>>;
      final ttSettings   = results[9]  as Map<String, dynamic>;
      final teachers     = results[10] as List<Teacher>;
      final policy       = results[11] as Map<String, dynamic>;

      final bells = List<Map<String, dynamic>>.from(
        ((ttSettings['bells'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map)),
      );

      setState(() {
        _student          = student;
        _monthData        = monthData;
        _todayStatus      = todayByRoll[widget.studentRoll];
        _feeStructure     = feeStructure;
        _totalPaid        = totalPaid;
        _unreadNotifCount = notifCount;
        _homeworkList     = hwList;
        _examData         = examData;
        _classTimetable   = timetable[widget.studentClass] ?? {};
        _bellSettings     = bells;
        _firstBellTime    = ttSettings['firstBellTime'] as String? ?? '08:00';
        _teacherById      = {for (final t in teachers) t.id: t};
        _dressPhotoUrl    = policy['idealDressPhoto'] ?? '';
        _rules            = List<String>.from(policy['disciplineRules'] ?? []);
        _loading          = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error   = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _changeMonth(DateTime newMonth) async {
    setState(() { _month = newMonth; _loading = true; _error = null; });
    try {
      final data = await _service.loadMonthAttendance(
          widget.studentClass, newMonth.year, newMonth.month);
      if (!mounted) return;
      setState(() { _monthData = data; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  int get _workingDays => _monthData.keys.length;
  int get _present => _monthData.values
      .where((d) => d[widget.studentRoll] == 'Present').length;
  int get _absent => _monthData.values
      .where((d) => d[widget.studentRoll] == 'Absent').length;
  int get _leave => _monthData.values
      .where((d) => d[widget.studentRoll] == 'Leave').length;

  double get _pct =>
      _workingDays == 0 ? 0 : _present / _workingDays * 100;

  bool get _isLow => _workingDays > 0 && _pct < 75;

  String _monthLabel(DateTime dt) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[dt.month - 1]} ${dt.year}';
  }

  Color _statusColor(String? s) {
    switch (s) {
      case 'Present': return Colors.green;
      case 'Absent':  return Colors.red;
      case 'Leave':   return const Color(0xFFF57F17);
      default:        return Colors.grey;
    }
  }

  List<Widget> _buildErrorChildren() => [
    const SizedBox(height: 40),
    Icon(Icons.wifi_off_outlined, size: 64, color: Colors.grey.shade400),
    const SizedBox(height: 20),
    const Center(
      child: Text('Could not load data',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    ),
    const SizedBox(height: 8),
    Center(
      child: Text(
        _error ?? 'Unknown error',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      ),
    ),
    const SizedBox(height: 24),
    ElevatedButton.icon(
      onPressed: _loadAll,
      icon: const Icon(Icons.refresh),
      label: const Text('Try Again'),
    ),
  ];

  List<Widget> _buildNoStudentChildren() => [
    const SizedBox(height: 40),
    Icon(Icons.person_off_outlined, size: 64, color: Colors.grey.shade400),
    const SizedBox(height: 16),
    Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          'No student found for Roll ${widget.studentRoll} '
          'in ${widget.studentClass}. Please contact the school '
          'administrator to verify your account link.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
      ),
    ),
  ];

  List<Widget> _buildContentChildren() => [
    const SizedBox(height: 16),
    // ── Today's status banner ────────────────────────────────────
    _TodayBanner(status: _todayStatus),
    const SizedBox(height: 16),
    // ── This month summary card ──────────────────────────────────
    _MonthSummaryCard(
      monthLabel: _monthLabel(_month),
      workingDays: _workingDays,
      present: _present,
      absent: _absent,
      leave: _leave,
      pct: _pct,
      isLow: _isLow,
      isCurrentMonth: _isCurrentMonth,
      onPrev: () => _changeMonth(DateTime(_month.year, _month.month - 1)),
      onNext: _isCurrentMonth
          ? null
          : () => _changeMonth(DateTime(_month.year, _month.month + 1)),
    ),
    const SizedBox(height: 16),
    // ── Low attendance banner ────────────────────────────────────
    if (_isLow) ...[
      _LowAttendanceBanner(pct: _pct),
      const SizedBox(height: 16),
    ],

    // ── ACADEMICS ────────────────────────────────────────────────
    const _SectionHeader('ACADEMICS'),
    _FeatureTile(
      icon: Icons.schedule_outlined,
      color: AppTheme.primary,
      title: "Today's Schedule",
      subtitle: 'View bell-wise classes and teachers',
      onTap: () => _showDetail("Today's Schedule", _TodayScheduleCard(
        classTimetable: _classTimetable,
        bellSettings:   _bellSettings,
        firstBellTime:  _firstBellTime,
        teacherById:    _teacherById,
      )),
    ),
    const _Divider(),
    _FeatureTile(
      icon: Icons.assignment_outlined,
      color: AppTheme.primary,
      title: 'Homework',
      subtitle: 'Latest assignments and tasks for your child',
      onTap: () => _showDetail('Homework', _HomeworkSection(homeworkList: _homeworkList)),
    ),
    const _Divider(),
    _FeatureTile(
      icon: Icons.school_outlined,
      color: AppTheme.primary,
      title: 'Exam Results',
      subtitle: 'Marks and grades for recent tests',
      onTap: () => _showDetail('Exam Results', _ExamResultsSection(examData: _examData)),
    ),
    const _Divider(),
    _FeatureTile(
      icon: Icons.people_outline,
      color: AppTheme.primary,
      title: 'Subject Teachers',
      subtitle: 'List of teachers for each subject',
      onTap: () => _showDetail('Subject Teachers', _SubjectTeachersCard(
        classTimetable: _classTimetable,
        teacherById:    _teacherById,
      )),
    ),

    // ── PROGRESS & RECORDS ────────────────────────────────────────
    const _SectionHeader('PROGRESS & RECORDS'),
    _FeatureTile(
      icon: Icons.badge_outlined,
      color: AppTheme.primary,
      title: 'Student Details',
      subtitle: 'Manage student information and parent contacts',
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GuardianStudentDetailsScreen(student: _student!),
          ),
        );
        _loadAll(); // Refresh student data
      },
    ),
    const _Divider(),
    _FeatureTile(
      icon: Icons.comment_outlined,
      color: AppTheme.primary,
      title: 'Student Remarks',
      subtitle: 'View teacher observations and feedback',
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StudentRemarksScreen(
            role:            'guardian',
            guardianStudent: _student,
          ),
        ),
      ),
    ),

    // ── ATTENDANCE ────────────────────────────────────────────────
    const _SectionHeader('ATTENDANCE'),
    _FeatureTile(
      icon: Icons.calendar_month_outlined,
      color: AppTheme.primary,
      title: 'Attendance Calendar',
      subtitle: 'View daily attendance history for this month',
      onTap: () => _showDetail('Attendance Calendar', Column(children: [
        _CalendarCard(
          month: _month,
          monthData: _monthData,
          roll: widget.studentRoll,
          statusColor: _statusColor,
        ),
        const SizedBox(height: 16),
        _LegendRow(),
      ])),
    ),
    const _Divider(),
    _FeatureTile(
      icon: Icons.workspace_premium_outlined,
      color: AppTheme.primary,
      title: 'Attendance Certificate',
      subtitle: 'Download official attendance record',
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                AttendanceCertificateScreen(student: _student!)),
      ),
    ),

    // ── COMMUNICATION ─────────────────────────────────────────────
    const _SectionHeader('COMMUNICATION'),
    _KeyContactsSection(
      student: _student,
      contactService: ContactService(),
    ),
    const _Divider(),
    _FeatureTile(
      icon: Icons.campaign_outlined,
      color: AppTheme.primary,
      title: 'Notice Board',
      subtitle: 'Latest announcements and school news',
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => AnnouncementsScreen(
                  viewerRole: 'guardian',
                  viewerClass: widget.studentClass,
                )),
      ),
    ),
    const _Divider(),
    _FeatureTile(
      icon: Icons.notifications_active_outlined,
      color: AppTheme.primary,
      title: 'Updates',
      subtitle: 'New notifications and activities',
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => NotificationsScreen(
              role:         'guardian',
              studentClass: widget.studentClass,
              studentRoll:  widget.studentRoll,
            ),
          ),
        );
        _loadAll();
      },
    ),
    const _Divider(),
    _FeatureTile(
      icon: Icons.contact_phone_outlined,
      color: AppTheme.primary,
      title: 'School Contact List',
      subtitle: 'Call or WhatsApp school staff & drivers',
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const SchoolContactsScreen(canEdit: false),
        ),
      ),
    ),
    const _Divider(),
    _FeatureTile(
      icon: Icons.calendar_month_outlined,
      color: AppTheme.primary,
      title: 'School Calendar',
      subtitle: 'View holidays and upcoming school events',
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const CalendarScreen(userRole: 'guardian'),
        ),
      ),
    ),

    // ── SCHOOL POLICY ─────────────────────────────────────────────
    const _SectionHeader('SCHOOL POLICY'),
    _FeatureTile(
      icon: Icons.assignment_turned_in_outlined,
      color: AppTheme.primary,
      title: 'Ideal Dress & Discipline',
      subtitle: 'Uniform standards and school rules',
      onTap: () => _showDetail('School Policy', _SchoolPolicyCard(dressPhotoUrl: _dressPhotoUrl, rules: _rules)),
    ),

    if (_feeStructure != null && _feeStructure!.totalAnnualFee > 0) ...[
      const _Divider(),
      _FeatureTile(
        icon: Icons.account_balance_wallet_outlined,
        color: AppTheme.success,
        title: 'Fee Status',
        subtitle: 'View payment history and pending dues',
        onTap: () => _showDetail('Fee Status', _FeeStatusCard(structure: _feeStructure!, totalPaid: _totalPaid)),
      ),
    ],

    const SizedBox(height: 32),
  ];

  void _showDetail(String title, Widget content) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text(title),
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
          ),
          backgroundColor: AppTheme.background,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: content,
          ),
        ),
      ),
    );
  }

  Future<void> _logout() async {
    await AuthService().clearSession();
    if (!mounted) return;
    Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => const RoleSelectionScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: RefreshIndicator(
        onRefresh: _loadAll,
        color: AppTheme.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Wave hero (always visible, covers status bar) ─────────
            SliverToBoxAdapter(
              child: _GuardianHeroCard(
                studentName:      _student?.name ?? '',
                studentClass:     widget.studentClass,
                studentRoll:      widget.studentRoll,
                todayStatus:      _todayStatus,
                loading:          _loading,
                unreadNotifCount: _unreadNotifCount,
                allStudentLinks:  _allStudentLinks,
                onNotifTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NotificationsScreen(
                        role:         'guardian',
                        studentClass: widget.studentClass,
                        studentRoll:  widget.studentRoll,
                      ),
                    ),
                  );
                  _loadAll();
                },
                onLogout: _logout,
              ),
            ),

            // ── Content ───────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                  _loading
                    ? [const SizedBox(height: 60),
                       const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                       const SizedBox(height: 60)]
                    : _error != null
                      ? _buildErrorChildren()
                      : _student == null
                        ? _buildNoStudentChildren()
                        : _buildContentChildren(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Guardian hero wave card ─────────────────────────────────────────────────

class _GuardianHeroCard extends StatelessWidget {
  final String  studentName;
  final String  studentClass;
  final int     studentRoll;
  final String? todayStatus;
  final bool    loading;
  final int     unreadNotifCount;
  final List<String> allStudentLinks;
  final VoidCallback onNotifTap;
  final VoidCallback onLogout;

  const _GuardianHeroCard({
    required this.studentName,
    required this.studentClass,
    required this.studentRoll,
    required this.todayStatus,
    required this.loading,
    required this.unreadNotifCount,
    required this.allStudentLinks,
    required this.onNotifTap,
    required this.onLogout,
  });

  Color _statusColor(String? s) {
    switch (s) {
      case 'Present': return const Color(0xFF80CBC4);
      case 'Absent':  return const Color(0xFFEF9A9A);
      case 'Leave':   return const Color(0xFFFFCC80);
      default:        return Colors.white54;
    }
  }

  void _showStudentSwitcher(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('Switch Child',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          ...allStudentLinks.map((link) {
            final parts = link.split('|');
            final sClass = parts[0];
            final sRoll = int.parse(parts[1]);
            final sName = parts.length > 2 ? parts[2] : 'Student';
            final isCurrent = sClass == studentClass && sRoll == studentRoll;

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: isCurrent ? AppTheme.primary : Colors.grey.shade200,
                child: Icon(Icons.person,
                    color: isCurrent ? Colors.white : Colors.grey),
              ),
              title: Text(sName,
                  style: TextStyle(
                      fontWeight:
                          isCurrent ? FontWeight.bold : FontWeight.normal)),
              subtitle: Text('$sClass · Roll $sRoll'),
              selected: isCurrent,
              onTap: isCurrent
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GuardianDashboard(
                            studentClass: sClass,
                            studentRoll: sRoll,
                          ),
                        ),
                      );
                    },
            );
          }),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const dy = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    final dateStr = '${dy[now.weekday-1]}, ${now.day} ${mo[now.month-1]}'.toUpperCase();

    return ClipPath(
      clipper: _WaveClipper(),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.primaryDark, Color(0xFF880E4F)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 8, 56),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Top action row ──────────────────────────────────
                Row(children: [
                  const Icon(Icons.family_restroom_outlined,
                      color: Colors.white60, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'GUARDIAN  ·  $dateStr',
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.9),
                    ),
                  ),
                  if (allStudentLinks.length > 1)
                    IconButton(
                      icon: const Icon(Icons.swap_horiz,
                          color: Colors.white, size: 22),
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(),
                      tooltip: 'Switch Child',
                      onPressed: () => _showStudentSwitcher(context),
                    ),
                  if (allStudentLinks.length > 1)
                    IconButton(
                      icon: const Icon(Icons.swap_horiz,
                          color: Colors.white, size: 22),
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(),
                      tooltip: 'Switch Child',
                      onPressed: () => _showStudentSwitcher(context),
                    ),
                  Stack(children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_outlined,
                          color: Colors.white, size: 22),
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(),
                      onPressed: onNotifTap,
                    ),
                    if (unreadNotifCount > 0)
                      Positioned(
                        right: 4, top: 4,
                        child: Container(
                          width: 14, height: 14,
                          decoration: const BoxDecoration(
                              color: AppTheme.accent,
                              shape: BoxShape.circle),
                          child: Center(
                            child: Text(
                              unreadNotifCount > 9
                                  ? '9+'
                                  : '$unreadNotifCount',
                              style: const TextStyle(
                                  fontSize: 8,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                  ]),
                  IconButton(
                    icon: const Icon(Icons.logout,
                        color: Colors.white, size: 20),
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                    onPressed: onLogout,
                  ),
                  const SizedBox(width: 4),
                ]),
                const SizedBox(height: 8),

                if (loading)
                  const SizedBox(
                    height: 80,
                    child: Center(
                      child: CircularProgressIndicator(
                          color: Colors.white60, strokeWidth: 2.5),
                    ),
                  )
                else ...[
                  // Student name + class
                  Text(
                    studentName.isNotEmpty ? studentName : 'Guardian Portal',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        height: 1.1),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$studentClass  ·  Roll $studentRoll',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  // Today status chip
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white30),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                            color: _statusColor(todayStatus),
                            shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Today: ${todayStatus ?? 'Not marked'}',
                        style: TextStyle(
                            color: _statusColor(todayStatus),
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ]),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Today's schedule card ───────────────────────────────────────────────────

class _TodayScheduleCard extends StatelessWidget {
  final Map<String, Map<int, TimetableEntry>> classTimetable;
  final List<Map<String, dynamic>> bellSettings;
  final String firstBellTime;
  final Map<String, Teacher> teacherById;

  const _TodayScheduleCard({
    required this.classTimetable,
    required this.bellSettings,
    required this.firstBellTime,
    required this.teacherById,
  });

  static const _dayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  String _bellTime(int bellIdx) {
    try {
      final parts = firstBellTime.split(':');
      int h = int.parse(parts[0]);
      int m = int.parse(parts[1]);
      for (int i = 0; i < bellIdx; i++) {
        final dur = (bellSettings[i]['duration'] as num?)?.toInt() ?? 45;
        m += dur;
        h += m ~/ 60;
        m = m % 60;
      }
      final ampm = h >= 12 ? 'PM' : 'AM';
      final hh = h > 12 ? h - 12 : (h == 0 ? 12 : h);
      return '$hh:${m.toString().padLeft(2, '0')} $ampm';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final todayName = _dayNames[DateTime.now().weekday - 1];
    final todayPeriods = classTimetable[todayName] ?? {};
    final bellCount = bellSettings.length;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(children: [
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.schedule_outlined,
                    color: AppTheme.primary, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Today's Schedule",
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
                    Text(todayName,
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),

          if (bellCount == 0 || todayPeriods.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                  vertical: 20, horizontal: 16),
              child: Text('No timetable for $todayName',
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey.shade500)),
            )
          else
            ...List.generate(bellCount, (i) {
              final bell = i + 1;
              final isLunch = (bellSettings[i]['isLunch'] as bool?) ?? false;
              final time = _bellTime(i);
              final entry = todayPeriods[bell];

              if (isLunch) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  color: Colors.orange.shade50,
                  child: Row(children: [
                    const Icon(Icons.lunch_dining_outlined,
                        size: 16, color: Colors.orange),
                    const SizedBox(width: 8),
                    Text(time,
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                            fontFeatures: const [])),
                    const SizedBox(width: 12),
                    Text('Lunch Break',
                        style: TextStyle(
                            fontSize: 13,
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.w500)),
                  ]),
                );
              }

              String subject = '—';
              String teacherName = '';
              Color periodColor = Colors.grey.shade100;

              if (entry != null && !entry.isEmpty) {
                final teacher = teacherById[entry.teacherId];
                subject = entry.subject ??
                    (teacher?.subject ?? '—');
                teacherName = teacher?.name ?? '';
                periodColor = AppTheme.primary.withOpacity(0.07);
              }

              return Container(
                decoration: BoxDecoration(
                  color: periodColor,
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade100),
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 9),
                child: Row(children: [
                  // Bell number badge
                  Container(
                    width: 26, height: 26,
                    decoration: BoxDecoration(
                      color: entry != null && !entry.isEmpty
                          ? AppTheme.primary
                          : Colors.grey.shade300,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text('$bell',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Time
                  SizedBox(
                    width: 72,
                    child: Text(time,
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500)),
                  ),
                  // Subject + teacher
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(subject,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                        if (teacherName.isNotEmpty)
                          Text(teacherName,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500)),
                      ],
                    ),
                  ),
                ]),
              );
            }),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ─── Exam results section ────────────────────────────────────────────────────

class _ExamResultsSection extends StatefulWidget {
  final List<MapEntry<Exam, ExamResult?>> examData;
  const _ExamResultsSection({required this.examData});

  @override
  State<_ExamResultsSection> createState() => _ExamResultsSectionState();
}

class _ExamResultsSectionState extends State<_ExamResultsSection> {
  int? _expandedIdx;

  Color _gradeColor(String grade) {
    switch (grade) {
      case 'A+': return Colors.green.shade700;
      case 'A':  return Colors.green;
      case 'B+': return Colors.teal;
      case 'B':  return Colors.blue.shade700;
      case 'C':  return const Color(0xFFF57F17);
      default:   return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(children: [
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.school_outlined,
                    color: AppTheme.primary, size: 19),
              ),
              const SizedBox(width: 10),
              const Text('Exam Results',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('${widget.examData.length} exam(s)',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade500)),
            ]),
          ),
          const Divider(height: 1),

          ...widget.examData.asMap().entries.map((entry) {
            final idx    = entry.key;
            final exam   = entry.value.key;
            final result = entry.value.value;
            final isExp  = _expandedIdx == idx;
            final dateStr =
                '${exam.examDate.day} ${months[exam.examDate.month - 1]} '
                '${exam.examDate.year}';

            // If no result yet
            if (result == null) {
              return Column(children: [
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  title: Text(exam.name,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Text(dateStr,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade500)),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('Not Entered',
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey.shade500)),
                  ),
                ),
                if (idx < widget.examData.length - 1)
                  const Divider(height: 1, indent: 16),
              ]);
            }

            final grade      = result.grade;
            final gradeColor = _gradeColor(grade);
            final pct        = result.percentage;
            final total      = result.total;
            final maxTotal   = result.subjectCount * result.maxMarks;

            return Column(children: [
              InkWell(
                onTap: () => setState(
                    () => _expandedIdx = isExp ? null : idx),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  child: Row(children: [
                    // Grade badge
                    Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                        color: gradeColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(grade,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: gradeColor)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(exam.name,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(dateStr,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500)),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: (pct / 100).clamp(0.0, 1.0),
                              minHeight: 5,
                              backgroundColor: Colors.grey.shade200,
                              valueColor: AlwaysStoppedAnimation(gradeColor),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${pct.toStringAsFixed(1)}%',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: gradeColor)),
                        Text('$total/$maxTotal',
                            style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade500)),
                      ],
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      isExp
                          ? Icons.expand_less
                          : Icons.expand_more,
                      color: Colors.grey.shade400,
                    ),
                  ]),
                ),
              ),

              // Expanded marks per subject
              if (isExp)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      // Column headers
                      Row(children: [
                        const Expanded(
                            child: Text('Subject',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black54))),
                        SizedBox(
                          width: 60,
                          child: Text('Marks',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black54)),
                        ),
                        SizedBox(
                          width: 50,
                          child: Text('%',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black54)),
                        ),
                      ]),
                      const Divider(height: 10),
                      ...result.marks.entries.map((me) {
                        final subj    = me.key;
                        final marks   = me.value;
                        final subPct  = marks == null
                            ? null
                            : marks / result.maxMarks * 100;
                        final subCol  = subPct == null
                            ? Colors.grey
                            : subPct >= 75
                                ? Colors.green
                                : subPct >= 50
                                    ? const Color(0xFFF57F17)
                                    : Colors.red;
                        return Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: 3),
                          child: Row(children: [
                            Expanded(
                              child: Text(subj,
                                  style:
                                      const TextStyle(fontSize: 12)),
                            ),
                            SizedBox(
                              width: 60,
                              child: Text(
                                marks == null
                                    ? 'Absent'
                                    : '${marks.toStringAsFixed(0)}/${result.maxMarks}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: subCol),
                              ),
                            ),
                            SizedBox(
                              width: 50,
                              child: Text(
                                subPct == null
                                    ? '—'
                                    : '${subPct.toStringAsFixed(0)}%',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: subCol),
                              ),
                            ),
                          ]),
                        );
                      }),
                      const Divider(height: 10),
                      Row(children: [
                        const Expanded(
                          child: Text('Total',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold)),
                        ),
                        SizedBox(
                          width: 60,
                          child: Text(
                            '$total/$maxTotal',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: gradeColor),
                          ),
                        ),
                        SizedBox(
                          width: 50,
                          child: Text(
                            '${pct.toStringAsFixed(1)}%',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: gradeColor),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),

              if (idx < widget.examData.length - 1)
                const Divider(height: 1, indent: 16),
            ]);
          }),

          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ─── Subject teachers card ────────────────────────────────────────────────────

class _SubjectTeachersCard extends StatelessWidget {
  final Map<String, Map<int, TimetableEntry>> classTimetable;
  final Map<String, Teacher> teacherById;

  const _SubjectTeachersCard({
    required this.classTimetable,
    required this.teacherById,
  });

  @override
  Widget build(BuildContext context) {
    // Build subject → teacher list from the timetable (all days combined)
    final Map<String, Set<String>> subjectTeacherIds = {};
    classTimetable.forEach((day, bells) {
      bells.forEach((bell, entry) {
        if (!entry.isEmpty && entry.teacherId != null) {
          final teacher = teacherById[entry.teacherId!];
          final subj    = entry.subject ??
              teacher?.subject ?? 'Unknown';
          subjectTeacherIds
              .putIfAbsent(subj, () => {})
              .add(entry.teacherId!);
        }
      });
    });

    if (subjectTeacherIds.isEmpty) return const SizedBox.shrink();

    // Sort subjects alphabetically
    final subjects = subjectTeacherIds.keys.toList()..sort();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(children: [
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.people_outline,
                    color: AppTheme.primary, size: 19),
              ),
              const SizedBox(width: 10),
              const Text('Subject Teachers',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold)),
            ]),
          ),
          const Divider(height: 1),
          ...subjects.asMap().entries.map((e) {
            final subj      = e.value;
            final tIds      = subjectTeacherIds[subj]!;
            final teachers  = tIds
                .map((id) => teacherById[id])
                .whereType<Teacher>()
                .toList();
            final names = teachers.map((t) => t.name).join(', ');

            return Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                child: Row(children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        subj.isNotEmpty ? subj[0].toUpperCase() : '?',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(subj,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                        if (names.isNotEmpty)
                          Text(names,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                ]),
              ),
              if (e.key < subjects.length - 1)
                const Divider(height: 1, indent: 64),
            ]);
          }),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ─── Guardian hero wave card ─────────────────────────────────────────────────

class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 30);
    path.quadraticBezierTo(
        size.width * 0.25, size.height + 4,
        size.width * 0.5, size.height - 18);
    path.quadraticBezierTo(
        size.width * 0.75, size.height - 40,
        size.width, size.height - 18);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_WaveClipper old) => false;
}

// ─── Today's status banner ───────────────────────────────────────────────────

class _TodayBanner extends StatelessWidget {
  final String? status;
  const _TodayBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;
    String title;
    String sub;

    switch (status) {
      case 'Present':
        color = Colors.green;
        icon  = Icons.check_circle_outline;
        title = 'Present Today';
        sub   = 'Your child attended school today.';
        break;
      case 'Absent':
        color = Colors.red;
        icon  = Icons.cancel_outlined;
        title = 'Absent Today';
        sub   = 'Your child was marked absent today.';
        break;
      case 'Leave':
        color = const Color(0xFFF57F17);
        icon  = Icons.event_busy_outlined;
        title = 'On Leave Today';
        sub   = 'Your child is on approved leave today.';
        break;
      default:
        color = Colors.grey;
        icon  = Icons.schedule_outlined;
        title = 'Attendance Not Marked';
        sub   = "The class teacher hasn't taken attendance yet today.";
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: color)),
              const SizedBox(height: 2),
              Text(sub,
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            ],
          ),
        ),
      ]),
    );
  }
}

// ─── Month summary card ──────────────────────────────────────────────────────

class _MonthSummaryCard extends StatelessWidget {
  final String monthLabel;
  final int    workingDays, present, absent, leave;
  final double pct;
  final bool   isLow, isCurrentMonth;
  final VoidCallback  onPrev;
  final VoidCallback? onNext;

  const _MonthSummaryCard({
    required this.monthLabel,
    required this.workingDays,
    required this.present,
    required this.absent,
    required this.leave,
    required this.pct,
    required this.isLow,
    required this.isCurrentMonth,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final pctColor = isLow
        ? Colors.red
        : pct >= 85
            ? Colors.green
            : const Color(0xFFF57F17);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: Icon(Icons.chevron_left, color: Colors.grey.shade700),
              onPressed: onPrev,
            ),
            Text(monthLabel,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            IconButton(
              icon: Icon(Icons.chevron_right,
                  color: onNext == null
                      ? Colors.grey.shade300
                      : Colors.grey.shade700),
              onPressed: onNext,
            ),
          ],
        ),
        const Divider(height: 14),
        if (workingDays == 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text('No school days recorded in this month',
                style: TextStyle(color: Colors.grey.shade500)),
          )
        else ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _StatCell(value: '$workingDays', label: 'Days',
                  color: AppTheme.primary),
              _StatCell(value: '$present', label: 'Present',
                  color: Colors.green),
              _StatCell(value: '$absent', label: 'Absent',
                  color: Colors.red),
              _StatCell(value: '$leave', label: 'Leave',
                  color: const Color(0xFFF57F17)),
            ],
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (pct / 100).clamp(0.0, 1.0),
                  minHeight: 10,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(pctColor),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text('${pct.toStringAsFixed(1)}%',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: pctColor)),
          ]),
        ],
      ]),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String value, label;
  final Color  color;
  const _StatCell(
      {required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value,
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      ]);
}

// ─── Low attendance banner ───────────────────────────────────────────────────

class _LowAttendanceBanner extends StatelessWidget {
  final double pct;
  const _LowAttendanceBanner({required this.pct});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded,
            color: Colors.red, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Low Attendance (${pct.toStringAsFixed(1)}%)',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade800),
              ),
              const SizedBox(height: 2),
              Text(
                'Your child is below the 75% attendance requirement. '
                'Please ensure regular school attendance to avoid '
                'shortage action.',
                style: TextStyle(
                    fontSize: 12, color: Colors.red.shade700),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

// ─── Calendar card ───────────────────────────────────────────────────────────

class _CalendarCard extends StatelessWidget {
  final DateTime               month;
  final Map<int, Map<int, String>> monthData;
  final int                    roll;
  final Color Function(String?) statusColor;

  const _CalendarCard({
    required this.month,
    required this.monthData,
    required this.roll,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    final daysInMonth  = DateTime(month.year, month.month + 1, 0).day;
    final firstWeekday = DateTime(month.year, month.month, 1).weekday;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(children: [
        // Day-of-week headers
        Row(
          children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
              .map((d) => Expanded(
                    child: Center(
                      child: Text(d,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: d == 'Sun'
                                  ? Colors.red.shade300
                                  : Colors.grey.shade500)),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: 1,
            mainAxisSpacing: 5,
            crossAxisSpacing: 4,
          ),
          itemCount: (firstWeekday - 1) + daysInMonth,
          itemBuilder: (_, idx) {
            if (idx < firstWeekday - 1) return const SizedBox();
            final day    = idx - (firstWeekday - 1) + 1;
            final date   = DateTime(month.year, month.month, day);
            final status = monthData[day]?[roll];
            final isSun  = date.weekday == DateTime.sunday;
            final isFut  = date.isAfter(DateTime.now());

            final bg = isFut
                ? Colors.transparent
                : status != null
                    ? statusColor(status).withOpacity(0.15)
                    : isSun
                        ? Colors.red.shade50
                        : Colors.grey.shade50;
            final bd = status != null
                ? statusColor(status).withOpacity(0.45)
                : Colors.grey.shade200;
            final tc = isFut
                ? Colors.grey.shade300
                : status != null
                    ? statusColor(status)
                    : isSun
                        ? Colors.red.shade200
                        : Colors.grey.shade400;

            return Container(
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                    color: bd, width: status != null ? 1.5 : 0.8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('$day',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: status != null
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: tc)),
                  if (status != null)
                    Text(status[0],
                        style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: statusColor(status))),
                ],
              ),
            );
          },
        ),
      ]),
    );
  }
}

// ─── Fee status card for guardian ────────────────────────────────────────────

class _FeeStatusCard extends StatelessWidget {
  final FeeStructure structure;
  final double       totalPaid;

  const _FeeStatusCard({required this.structure, required this.totalPaid});

  @override
  Widget build(BuildContext context) {
    final total = structure.totalAnnualFee;
    final due   = (total - totalPaid).clamp(0, double.infinity);
    final pct   = total > 0 ? (totalPaid / total).clamp(0.0, 1.0) : 0.0;
    final isFullyPaid = due < 1;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(Icons.account_balance_wallet_outlined,
                  color: Colors.green.shade700, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Fee Status',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isFullyPaid
                    ? Colors.green.shade50
                    : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isFullyPaid ? 'Fully Paid' : 'Pending',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isFullyPaid
                      ? Colors.green.shade700
                      : Colors.orange.shade700,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                isFullyPaid ? Colors.green : Colors.orange,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Paid: ₹${totalPaid.toStringAsFixed(0)}',
                  style: TextStyle(
                      fontSize: 12, color: Colors.green.shade700)),
              Text('Due: ₹${due.toStringAsFixed(0)}',
                  style: TextStyle(
                      fontSize: 12,
                      color: due > 0
                          ? Colors.orange.shade700
                          : Colors.grey.shade500)),
              Text('Total: ₹${total.toStringAsFixed(0)}',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
        ],
      ),
    );
  }
}

class _HomeworkSection extends StatelessWidget {
  final List<Homework> homeworkList;
  const _HomeworkSection({required this.homeworkList});

  Color _statusColor(Homework hw) {
    if (hw.isReviewed) return Colors.green;
    if (hw.isOverdue)  return Colors.red;
    return Colors.orange;
  }

  String _statusLabel(Homework hw) {
    if (hw.isReviewed) return 'Reviewed';
    if (hw.isOverdue)  return 'Overdue';
    final d = hw.daysUntilDue;
    if (d == 0) return 'Due Today';
    if (d == 1) return 'Tomorrow';
    return 'Due in $d days';
  }

  @override
  Widget build(BuildContext context) {
    // Show latest 5
    final list = homeworkList.take(5).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.assignment_outlined,
                    color: AppTheme.primary, size: 18),
              ),
              const SizedBox(width: 10),
              const Text('Homework',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('${homeworkList.length} total',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade500)),
            ]),
          ),
          const Divider(height: 1),
          ...list.asMap().entries.map((entry) {
            final i  = entry.key;
            final hw = entry.value;
            final due =
                '${hw.dueDate.day}/${hw.dueDate.month}/${hw.dueDate.year}';
            final sc = _statusColor(hw);
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(hw.title,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(
                              '${hw.subject}  •  Due: $due',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500),
                            ),
                            const SizedBox(height: 4),
                            Text(hw.description,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: sc.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(_statusLabel(hw),
                            style: TextStyle(
                                fontSize: 10,
                                color: sc,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
                if (i < list.length - 1)
                  const Divider(height: 1, indent: 16),
              ],
            );
          }),
          if (homeworkList.length > 5)
            Padding(
              padding: const EdgeInsets.only(
                  left: 16, right: 16, bottom: 10, top: 4),
              child: Text(
                '+ ${homeworkList.length - 5} more assignments',
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade500),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── School Policy Card ──────────────────────────────────────────────────────

class _SchoolPolicyCard extends StatelessWidget {
  final String dressPhotoUrl;
  final List<String> rules;

  const _SchoolPolicyCard({required this.dressPhotoUrl, required this.rules});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(children: [
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.assignment_turned_in_outlined,
                    color: AppTheme.primary, size: 19),
              ),
              const SizedBox(width: 10),
              const Text('Ideal Dress & Discipline',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold)),
            ]),
          ),
          const Divider(height: 1),
          if (dressPhotoUrl.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ideal Dress Standard',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      dressPhotoUrl,
                      width: double.infinity,
                      height: 200,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          Container(
                        height: 100,
                        color: Colors.grey.shade100,
                        child: const Center(
                          child: Icon(Icons.broken_image_outlined,
                              color: Colors.grey),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (rules.isNotEmpty) ...[
            if (dressPhotoUrl.isNotEmpty) const Divider(height: 1, indent: 16),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Discipline Rules',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  ...rules.map((rule) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('• ',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primary)),
                            Expanded(
                              child: Text(rule,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade800)),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

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

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, indent: 72);
  }
}

class _FeatureTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _FeatureTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
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
          Icon(Icons.chevron_right,
              color: Colors.grey.shade400, size: 20),
        ]),
      ),
    );
  }
}

class _KeyContactsSection extends StatelessWidget {
  final Student? student;
  final ContactService contactService;

  const _KeyContactsSection({required this.student, required this.contactService});

  Future<void> _makeCall(String phoneNumber) async {
    final Uri url = Uri.parse('tel:$phoneNumber');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  Future<void> _openWhatsApp(String phoneNumber) async {
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'\D'), '');
    final Uri url = Uri.parse('https://wa.me/$cleanPhone');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SchoolContact>>(
      stream: contactService.getContacts(),
      builder: (context, snapshot) {
        List<SchoolContact> keyContacts = [];
        if (snapshot.hasData) {
          keyContacts = snapshot.data!.where((c) => c.isKey).toList();
        }

        // Add class teacher if not already in list
        if (student != null && student!.phone.isNotEmpty) {
          final hasClassTeacher = keyContacts.any((c) =>
            c.role.toLowerCase().contains('class teacher') ||
            c.phoneNumber.replaceAll(RegExp(r'\D'), '') == student!.phone.replaceAll(RegExp(r'\D'), '')
          );
          if (!hasClassTeacher) {
            keyContacts.insert(0, SchoolContact(
              id: 'class_teacher',
              name: 'Class Teacher',
              phoneNumber: student!.phone,
              role: 'Class Teacher',
              isKey: true,
            ));
          }
        }

        if (keyContacts.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          children: keyContacts.map((contact) {
            final title = contact.name.isEmpty ? contact.role : contact.name;
            final subtitle = contact.name.isEmpty ? contact.phoneNumber : contact.role;

            return Column(
              children: [
                _FeatureTileWithActions(
                  icon: Icons.person_outline,
                  color: AppTheme.primary,
                  title: title,
                  subtitle: subtitle,
                  onCall: () => _makeCall(contact.phoneNumber),
                  onWhatsApp: () => _openWhatsApp(contact.phoneNumber),
                ),
                if (keyContacts.indexOf(contact) < keyContacts.length - 1)
                  const _Divider(),
              ],
            );
          }).toList(),
        );
      },
    );
  }
}

class _FeatureTileWithActions extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onCall;
  final VoidCallback onWhatsApp;

  const _FeatureTileWithActions({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onCall,
    required this.onWhatsApp,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
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
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.phone, color: AppTheme.success),
            onPressed: onCall,
          ),
          IconButton(
            icon: const FaIcon(FontAwesomeIcons.whatsapp, color: Colors.green),
            onPressed: onWhatsApp,
          ),
        ],
      ),
    );
  }
}

// ── Legend ──────────────────────────────────────────────────────────────────


class _LegendRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Widget dot(Color c, String lbl) => Row(children: [
          Container(
              width: 10, height: 10,
              decoration: BoxDecoration(
                  color: c, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(lbl,
              style:
                  TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ]);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 16,
      runSpacing: 6,
      children: [
        dot(Colors.green, 'Present'),
        dot(Colors.red, 'Absent'),
        dot(const Color(0xFFF57F17), 'Leave'),
        dot(Colors.grey.shade300, 'No School'),
      ],
    );
  }
}

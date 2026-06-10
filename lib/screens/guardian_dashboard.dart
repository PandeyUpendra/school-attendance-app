import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/school_settings_provider.dart';
import '../theme.dart';
import '../l10n/app_strings.dart';
import 'profile_screen.dart';
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
import '../services/base_firestore_service.dart';
import '../utils/role_guard.dart';
import 'announcements_screen.dart';
import 'guardian_leave_application_screen.dart';
import 'notifications_screen.dart';
import 'attendance_certificate_screen.dart';
import 'student_remarks_screen.dart';
import 'guardian_student_details_screen.dart';
import '../widgets/consent_pending_banner.dart';
import '../services/consent_service.dart';

/// The Guardian Portal — shows a single student's attendance to their parent.
/// Guardian is linked to {studentClass, studentRoll} in allowed_users.
class GuardianDashboard extends StatefulWidget {
  final String studentClass;
  final int    studentRoll;
  final String studentSection;

  const GuardianDashboard({
    super.key,
    required this.studentClass,
    required this.studentRoll,
    this.studentSection = '',
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

  // Active child identity. Starts from the widget params, but can change when a
  // guardian with more than one child picks a different one. All data loads key
  // off these instead of widget.* so switching reloads the whole dashboard.
  late String _activeClass;
  late int    _activeRoll;
  late String _activeSection;
  // Active child's STABLE admission id (#39). Drives the 'guardian_adm:' notif
  // subscription. SAFETY: set ONLY when the active child's admissionId equals
  // the guardian's PROVISIONED id (`_sessionAdmissionId`, == the top-level
  // studentAdmissionId the firestore.rules check). Subscribing to a guardian_adm
  // value the rules can't authorise would get the WHOLE notifications whereIn
  // query denied (proven in test_rules/notifications.test.mjs), so we never do.
  String? _activeAdmissionId;
  // The guardian's provisioned admissionId from their allowed_users doc (carried
  // in the session). Null for guardians provisioned before #39 / not yet
  // backfilled — in which case the guardian_adm channel stays off (legacy roll
  // channel only) and the feed is never at risk.
  String? _sessionAdmissionId;

  // Every student that shares this guardian's email — i.e. all their children.
  // When more than one, a child switcher appears in the header.
  List<Student> _children = [];

  String? _todayStatus;

  // Attendance is stored by the teacher under a section-scoped key
  // ('$className $section' when a section exists). The guardian MUST read with
  // the identical key or the lookup misses every doc and history shows blank —
  // matches AttendanceScreen._attendanceKey / AttendanceHistoryScreen._attendanceKey.
  String get _attendanceKey =>
      _activeSection.trim().isEmpty
          ? _activeClass
          : '$_activeClass ${_activeSection.trim()}';

  // Fee
  FeeStructure? _feeStructure;
  double        _totalPaid = 0;

  // Homework
  List<Homework> _homeworkList = [];

  // Notifications (real-time)
  int _unreadNotifCount = 0;
  StreamSubscription? _notifSub;
  int _lastSeenMs = 0;
  List<Map<String, dynamic>> _latestNotifs = [];

  // Exam results — (Exam, ExamResult?) pairs sorted newest first
  List<MapEntry<Exam, ExamResult?>> _examData = [];

  // Timetable
  Map<String, Map<int, TimetableEntry>> _classTimetable = {};
  List<Map<String, dynamic>> _bellSettings = [];
  String _firstBellTime = '08:00';
  Map<String, Teacher> _teacherById = {};

  // Consent
  final _consentSvc = ConsentService();
  bool  _hasConsent  = true;  // optimistic — don't show banner until we know
  bool  _needsReConsent = false;
  String get _studentDocId => Student.buildDocId(
        _activeRoll,
        _activeClass,
        _activeSection,
      );

  @override
  void initState() {
    super.initState();
    _activeClass   = widget.studentClass;
    _activeRoll    = widget.studentRoll;
    _activeSection = widget.studentSection;
    // Guard: only a session with the guardian role may stay here.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      RoleGuard.verify(context, ['guardian']);
    });
    _loadChildren();
    _loadAll();
    _initNotifStream();
  }

  /// Finds every student that shares this guardian's email so a parent with
  /// more than one child can switch between them. Falls back silently to the
  /// single child passed in if the lookup fails or finds nothing.
  Future<void> _loadChildren() async {
    try {
      final session = await AuthService().getSession();
      final email = (session?['email'] as String? ?? '').trim();
      if (email.isEmpty) return;
      final kids = await _service.getStudentsByGuardianEmail(email);
      if (!mounted || kids.length < 2) return;
      setState(() => _children = kids);
    } catch (_) {/* keep single-child view */}
  }

  /// Switches the dashboard to another of the guardian's children and reloads.
  void _switchChild(Student child) {
    if (child.className == _activeClass &&
        child.roll == _activeRoll &&
        child.section == _activeSection) {
      return;
    }
    setState(() {
      _activeClass       = child.className;
      _activeRoll        = child.roll;
      _activeSection     = child.section;
      // Reset until _loadAll confirms the new child's admissionId matches the
      // provisioned (rules-authorised) id — avoids ever subscribing to a
      // guardian_adm value the rules would reject.
      _activeAdmissionId = null;
      _student           = null;
      _loading           = true;
    });
    _notifSub?.cancel();
    _initNotifStream();
    _loadAll();
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    super.dispose();
  }

  Future<void> _initNotifStream() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _lastSeenMs = prefs.getInt('notif_last_seen_ms') ?? 0;

    _notifSub = NotificationService()
        .streamFor(
          role:               'guardian',
          studentClass:       _activeClass,
          studentRoll:        _activeRoll,
          studentAdmissionId: _activeAdmissionId,
        )
        .listen((items) {
      if (!mounted) return;
      _latestNotifs = items;
      _recomputeUnread();
    });
  }

  void _recomputeUnread() {
    final ms = _lastSeenMs;
    final count = _latestNotifs.where((n) {
      final ts = n['createdAt'];
      if (ts is! Timestamp) return false;
      return ts.toDate().millisecondsSinceEpoch > ms;
    }).length;
    if (mounted) setState(() => _unreadNotifCount = count);
  }

  Future<void> _refreshLastSeen() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _lastSeenMs = prefs.getInt('notif_last_seen_ms') ?? 0);
    _recomputeUnread();
  }

  /// Loads every exam for the class + this student's result for each.
  Future<List<MapEntry<Exam, ExamResult?>>> _loadExamData() async {
    final exams = await _examService.getExams(className: _activeClass);
    if (exams.isEmpty) return [];
    final resultFuts =
        exams.map((e) => _examService.getResult(e.id, _activeRoll, className: _activeClass));
    final results = await Future.wait(resultFuts);
    return List.generate(exams.length, (i) => MapEntry(exams[i], results[i]));
  }

  Future<void> _loadAll() async {
    setState(() { _loading = true; _error = null; });
    try {
      // ── Critical: student identity + attendance ─────────────────────────────
      // These must succeed; if not, show the error screen.
      final coreResults = await Future.wait([
        _service.getStudentByRoll(_activeClass, _activeRoll, section: _activeSection),  // 0
        _service.loadTodayAttendance(className: _attendanceKey),                  // 1
      ]);
      if (!mounted) return;

      final student     = coreResults[0] as Student?;
      final todayByRoll = coreResults[1] as Map<int, String>;

      // ── Optional: fee / exams / homework / timetable ────────────────────────
      // Any individual failure just leaves that section empty; no full crash.
      final optResults = await Future.wait([
        _feeService.getFeeStructure(className: _activeClass).catchError((_) => FeeStructure.empty(_activeClass)),          // 0
        _feeService.getTotalPaid(className: _activeClass, roll: _activeRoll).catchError((_) => 0.0),                       // 1
        _hwService.getHomeworkForClass(BaseFirestoreService.currentSchoolId ?? 'default_school', _activeClass).catchError((_) => <Homework>[]),  // 2
        _loadExamData().catchError((_) => <MapEntry<Exam, ExamResult?>>[]),                                                              // 3
        _ttService.getTimetable().catchError((_) => <String, Map<String, Map<int, TimetableEntry>>>{}),                                  // 4
        _ttService.getSettings().catchError((_) => <String, dynamic>{}),                                                                 // 5
        _ttService.getTeachers().catchError((_) => <Teacher>[]),                                                                         // 6
      ]);
      if (!mounted) return;

      final feeStructure = optResults[0] as FeeStructure;
      final totalPaid    = optResults[1] as double;
      final hwList       = optResults[2] as List<Homework>;
      final examData     = optResults[3] as List<MapEntry<Exam, ExamResult?>>;
      final timetable    = optResults[4] as Map<String, Map<String, Map<int, TimetableEntry>>>;
      final ttSettings   = optResults[5] as Map<String, dynamic>;
      final teachers     = optResults[6] as List<Teacher>;

      final bells = List<Map<String, dynamic>>.from(
        ((ttSettings['bells'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map)),
      );

      // ── Consent check (fire-and-forget, does NOT block load) ─────────────────
      _consentSvc.hasActiveConsent(_studentDocId)
          .then((has) {
            if (!mounted) return;
            setState(() => _hasConsent = has);
            if (!has) {
              _consentSvc.needsReConsent(_studentDocId).then((needs) {
                if (mounted) setState(() => _needsReConsent = needs);
              }).catchError((_) {});
            }
          })
          .catchError((_) {}); // never crash the dashboard over consent check

      setState(() {
        _student        = student;
        _todayStatus    = todayByRoll[_activeRoll];
        _feeStructure   = feeStructure;
        _totalPaid      = totalPaid;
        _homeworkList   = hwList;
        _examData       = examData;
        _classTimetable = timetable[_activeClass] ?? {};
        _bellSettings   = bells;
        _firstBellTime  = ttSettings['firstBellTime'] as String? ?? '08:00';
        _teacherById    = {for (final t in teachers) t.id: t};
        _loading        = false;
      });

      // Load the guardian's provisioned admissionId once (from the session,
      // sourced from allowed_users at login).
      _sessionAdmissionId ??=
          (await AuthService().getSession())?['studentAdmissionId'] as String?;
      // Subscribe to the stable-identity channel ONLY when the loaded child's
      // admissionId matches the provisioned id the rules authorise — otherwise
      // the channel stays off (safe). See the field doc above.
      final adm  = _student?.admissionId ?? '';
      final next = (adm.isNotEmpty && adm == _sessionAdmissionId) ? adm : null;
      if (next != _activeAdmissionId) {
        _activeAdmissionId = next;
        _notifSub?.cancel();
        _initNotifStream();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error   = e.toString();
        _loading = false;
      });
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
          'No student found for Roll $_activeRoll '
          'in $_activeClass. Please contact the school '
          'administrator to verify your account link.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
      ),
    ),
  ];

  List<Widget> _buildContentChildren() => [
    if (!_hasConsent) ...[
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ConsentPendingBanner(
          hasConsent:  false,
          isReConsent: _needsReConsent,
        ),
      ),
    ],
    const SizedBox(height: 12),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _TodayBanner(status: _todayStatus),
    ),

    _SectionHeader(context.tr('secAcademics')),
    _FeatureTile(
      icon: Icons.calendar_month_outlined,
      color: AppTheme.primary,
      title: context.tr('myTimetable'),
      subtitle: context.tr('subViewBellSchedule'),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GuardianTimetableScreen(
            classTimetable: _classTimetable,
            bellSettings: _bellSettings,
            firstBellTime: _firstBellTime,
            teacherById: _teacherById,
            className: _student?.className ?? _activeClass,
          ),
        ),
      ),
    ),
    const _Divider(),
    _FeatureTile(
      icon: Icons.people_outline,
      color: AppTheme.primary,
      title: context.tr('subjectTeachers'),
      subtitle: context.tr('subTeachersThisClass'),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GuardianSubjectTeachersScreen(
            classTimetable: _classTimetable,
            teacherById: _teacherById,
            className: _student?.className ?? _activeClass,
          ),
        ),
      ),
    ),
    const _Divider(),
    _FeatureTile(
      icon: Icons.assignment_outlined,
      color: AppTheme.primary,
      title: context.tr('homework'),
      subtitle: context.tr('subViewHomework'),
      badge: _homeworkList.isNotEmpty ? '${_homeworkList.length}' : null,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GuardianHomeworkScreen(
            homeworkList: _homeworkList,
            className: _student?.className ?? _activeClass,
          ),
        ),
      ),
    ),
    const _Divider(),
    _FeatureTile(
      icon: Icons.quiz_outlined,
      color: AppTheme.primary,
      title: context.tr('examResults'),
      subtitle: context.tr('subViewReportCards'),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GuardianExamResultsScreen(
            examData: _examData,
          ),
        ),
      ),
    ),

    _SectionHeader(context.tr('secAttendance')),
    _FeatureTile(
      icon: Icons.bar_chart_outlined,
      color: AppTheme.primary,
      title: context.tr('attendanceHistory'),
      subtitle: context.tr('subMonthlyReports'),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GuardianAttendanceHistoryScreen(
            attendanceKey: _attendanceKey,
            studentRoll: _activeRoll,
            studentName: _student?.name ?? 'Student',
          ),
        ),
      ),
    ),
    const _Divider(),
    _FeatureTile(
      icon: Icons.workspace_premium_outlined,
      color: AppTheme.primary,
      title: context.tr('attendanceCertificate'),
      subtitle: context.tr('subDownloadCertificate'),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AttendanceCertificateScreen(student: _student!),
        ),
      ),
    ),
    const _Divider(),
    _FeatureTile(
      icon: Icons.event_busy_outlined,
      color: AppTheme.warning,
      title: context.tr('applyForLeave'),
      subtitle: context.tr('subSubmitLeave'),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GuardianLeaveApplicationScreen(student: _student!),
        ),
      ).then((_) => _loadAll()),
    ),

    _SectionHeader(context.tr('secFees')),
    _FeatureTile(
      icon: Icons.account_balance_wallet_outlined,
      color: Colors.green,
      title: context.tr('feeStatus'),
      subtitle: _feeStructure != null && _feeStructure!.totalAnnualFee > 0
          ? ((_feeStructure!.totalAnnualFee - _totalPaid) < 1 ? 'Fully Paid' : 'Pending: ₹${(_feeStructure!.totalAnnualFee - _totalPaid).toStringAsFixed(0)}')
          : 'No fee info',
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GuardianFeeStatusScreen(
            structure: _feeStructure ?? FeeStructure.empty(_activeClass),
            totalPaid: _totalPaid,
          ),
        ),
      ),
    ),

    _SectionHeader(context.tr('secLeaveRemarks')),
    _FeatureTile(
      icon: Icons.comment_outlined,
      color: AppTheme.primary,
      title: context.tr('studentRemarks'),
      subtitle: context.tr('subViewObservations'),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StudentRemarksScreen(
            role: 'guardian',
            guardianStudent: _student,
          ),
        ),
      ),
    ),

    _SectionHeader(context.tr('secSchoolProfile')),
    _FeatureTile(
      icon: Icons.badge_outlined,
      color: AppTheme.primary,
      title: context.tr('studentDetails'),
      subtitle: context.tr('subViewProfile'),
      onTap: _openChildDetails,
    ),
    const _Divider(),
    _FeatureTile(
      icon: Icons.gavel_outlined,
      color: AppTheme.primary,
      title: context.tr('parentalConsent'),
      subtitle: context.tr('subManagePermissions'),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GuardianConsentScreen(
            studentDocId: _studentDocId,
            studentName: _student!.name,
            guardianName: _student!.fatherName,
            guardianPhone: _student!.parentPhone ?? _student!.phone,
            guardianEmail: _student!.guardianEmail,
          ),
        ),
      ),
    ),
    const _Divider(),
    _FeatureTile(
      icon: Icons.school_outlined,
      color: AppTheme.primary,
      title: context.tr('schoolInfo'),
      subtitle: context.tr('subViewSchoolContact'),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const GuardianSchoolInfoScreen(),
        ),
      ),
    ),
    const _Divider(),
    _FeatureTile(
      icon: Icons.campaign_outlined,
      color: AppTheme.primary,
      title: context.tr('noticeBoard'),
      subtitle: context.tr('subViewAnnouncements'),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const AnnouncementsScreen(viewerRole: 'guardian'),
        ),
      ),
    ),
    const _Divider(),
    _FeatureTile(
      icon: Icons.phone_callback_outlined,
      color: AppTheme.primary,
      title: 'Contact School',
      subtitle: 'Call student\'s class teacher',
      onTap: _callSchool,
    ),

    const SizedBox(height: 32),
  ];

  Future<void> _openChildDetails() async {
    if (_student == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GuardianStudentDetailsScreen(student: _student!),
      ),
    );
    // Reload to reflect any edits the guardian just saved
    _loadAll();
  }

  Future<void> _callSchool() async {
    if (_student == null || _student!.phone.isEmpty) return;
    // Calls school number saved on student — usually the class teacher contact.
    final uri = Uri.parse('tel:${_student!.phone}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }



  /// Horizontal chips to switch between this guardian's children. Hidden when
  /// there's only one child linked to the email.
  Widget _childSwitcher() {
    if (_children.length < 2) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 6),
          child: Text('VIEWING',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey,
                  letterSpacing: 0.8)),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _children.map((c) {
              final selected = c.className == _activeClass &&
                  c.roll == _activeRoll &&
                  c.section == _activeSection;
              final sec = c.section.isNotEmpty ? '-${c.section}' : '';
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  selected: selected,
                  onSelected: (_) => _switchChild(c),
                  label: Text('${c.name}  ·  ${c.className}$sec'),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    color: selected ? Colors.white : AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  selectedColor: AppTheme.primary,
                  backgroundColor: AppTheme.background,
                  side: BorderSide(
                      color: selected ? AppTheme.primary : AppTheme.border),
                ),
              );
            }).toList(),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          // ── Wave hero (sticky — never scrolls) ───────────────────────
          _GuardianHeroCard(
            studentName:      _student?.name ?? '',
            studentClass:     _activeClass,
            studentRoll:      _activeRoll,
            todayStatus:      _todayStatus,
            loading:          _loading,
            unreadNotifCount: _unreadNotifCount,
            onNotifTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NotificationsScreen(
                    role:         'guardian',
                    studentClass: _activeClass,
                    studentRoll:  _activeRoll,
                  ),
                ),
              );
              _refreshLastSeen();
            },
          ),

          // ── Child switcher (only when this guardian has >1 child) ───────
          _childSwitcher(),

          // ── Scrollable content ────────────────────────────────────────
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadAll,
              color: AppTheme.primary,
              child: ListView(
                // Full-bleed list — matches teacher / coordinator / principal
                // dashboards (edge-to-edge white rows on the lavender page).
                padding: EdgeInsets.zero,
                physics: const AlwaysScrollableScrollPhysics(),
                children: _loading
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
  final VoidCallback onNotifTap;

  const _GuardianHeroCard({
    required this.studentName,
    required this.studentClass,
    required this.studentRoll,
    required this.todayStatus,
    required this.loading,
    required this.unreadNotifCount,
    required this.onNotifTap,
  });

  Color _statusColor(String? s) {
    switch (s) {
      case 'Present': return const Color(0xFF80CBC4);
      case 'Absent':  return const Color(0xFFEF9A9A);
      case 'Leave':   return const Color(0xFFFFCC80);
      default:        return Colors.white54;
    }
  }

  Widget _vDivider() => Container(
        width: 1,
        height: 28,
        color: Colors.white24,
        margin: const EdgeInsets.symmetric(horizontal: 8),
      );

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
          color: AppTheme.primaryDark,
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 8, 52),
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
                    icon: const Icon(Icons.account_circle_outlined,
                        color: Colors.white, size: 22),
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                    tooltip: 'My Profile',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ProfileScreen()),
                    ),
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
                  const SizedBox(height: 14),
                  // ── Stats glass card (mirrors the teacher dashboard) ──
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(children: [
                      _HeroInfo(
                        label: 'Class',
                        value: studentClass.isNotEmpty ? studentClass : '—',
                      ),
                      _vDivider(),
                      _HeroInfo(
                        label: 'Roll',
                        value: '$studentRoll',
                      ),
                      _vDivider(),
                      _HeroInfo(
                        label: 'Today',
                        value: todayStatus ?? 'Not marked',
                        color: _statusColor(todayStatus),
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

// ── Hero info cell (matches the teacher dashboard's glass-card cells) ─────────

class _HeroInfo extends StatelessWidget {
  final String label, value;
  final Color? color;
  const _HeroInfo({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: color ?? Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: Colors.white60, fontSize: 10),
              textAlign: TextAlign.center),
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
                  color: AppTheme.primary.withValues(alpha: 0.1),
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
            final isAllAbsent = result.marks.values.isNotEmpty && result.marks.values.every((v) => v == -1.0);

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
                        color: gradeColor.withValues(alpha: 0.1),
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
                        Text(isAllAbsent ? 'Absent' : '${pct.toStringAsFixed(1)}%',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: gradeColor)),
                        Text(isAllAbsent ? '' : '$total/$maxTotal',
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
                      const Row(children: [
                        Expanded(
                            child: Text('Subject',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black54))),
                        SizedBox(
                          width: 60,
                          child: Text('Marks',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black54)),
                        ),
                        SizedBox(
                          width: 50,
                          child: Text('%',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black54)),
                        ),
                      ]),
                      const Divider(height: 10),
                      ...result.marks.entries.map((me) {
                        final subj    = me.key;
                        final marks   = me.value;
                        final subPct  = (marks == null || marks == -1.0)
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
                                marks == -1.0
                                    ? 'Absent'
                                    : (marks != null
                                        ? '${marks.toStringAsFixed(0)}/${result.maxMarks}'
                                        : '—'),
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



class _GDRow {
  final IconData icon;
  final String   label;
  final String   value;
  const _GDRow(this.icon, this.label, this.value);
}

// ─── School information read-only card ───────────────────────────────────────
// Sourced from SchoolSettingsProvider (the same data the owner/principal edit
// under School Settings). Guardians can view but never edit it.

class _SchoolInfoCard extends StatelessWidget {
  const _SchoolInfoCard();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SchoolSettingsProvider>();

    // Until the settings stream has delivered data, render nothing rather than
    // a card full of placeholder defaults.
    if (!s.isLoaded) return const SizedBox.shrink();

    final name = s.schoolName.trim();
    final hasName = name.isNotEmpty && name != 'My School';

    final addressParts = [
      s.schoolAddress.trim(),
      s.schoolCity.trim(),
      s.schoolState.trim(),
      s.schoolPinCode.trim(),
    ].where((p) => p.isNotEmpty).toList();

    final rows = <_GDRow>[
      if (addressParts.isNotEmpty)
        _GDRow(Icons.location_on_outlined, 'Address', addressParts.join(', ')),
      if (s.schoolPhone.trim().isNotEmpty)
        _GDRow(Icons.phone_outlined, 'Phone', s.schoolPhone.trim()),
      if (s.schoolEmail.trim().isNotEmpty)
        _GDRow(Icons.email_outlined, 'Email', s.schoolEmail.trim()),
      if (s.schoolWebsite.trim().isNotEmpty)
        _GDRow(Icons.language_outlined, 'Website', s.schoolWebsite.trim()),
      if (s.board.trim().isNotEmpty)
        _GDRow(Icons.menu_book_outlined, 'Board', s.board.trim()),
      if (s.principalName.trim().isNotEmpty)
        _GDRow(Icons.person_outline, 'Principal', s.principalName.trim()),
      if (s.establishedYear.trim().isNotEmpty)
        _GDRow(Icons.calendar_today_outlined, 'Established', s.establishedYear.trim()),
    ];

    // Nothing meaningful to show yet.
    if (!hasName && rows.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header — logo + school name + tagline
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(children: [
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.school_outlined,
                    color: AppTheme.primary, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(hasName ? name : 'School Information',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
                    if (s.schoolTagline.trim().isNotEmpty)
                      Text(s.schoolTagline.trim(),
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ),
              ),
            ]),
          ),
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            ...rows.asMap().entries.map((e) {
              final r = e.value;
              return Column(children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(children: [
                    Icon(r.icon, size: 18, color: Colors.grey.shade400),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.label,
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade500)),
                          const SizedBox(height: 2),
                          Text(r.value,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  ]),
                ),
                if (e.key < rows.length - 1)
                  const Divider(height: 1, indent: 46),
              ]);
            }),
          ],
          const SizedBox(height: 10),
        ],
      ),
    );
  }
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
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
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

// ─── Combined attendance calendar card ───────────────────────────────────────

class _AttendanceCalendarCard extends StatelessWidget {
  final DateTime                   month;
  final Map<int, Map<int, String>> monthData;
  final int                        roll;
  final int                        workingDays, present, absent, leave;
  final double                     pct;
  final bool                       isLow, isCurrentMonth;
  final VoidCallback               onPrev;
  final VoidCallback?              onNext;

  const _AttendanceCalendarCard({
    required this.month,
    required this.monthData,
    required this.roll,
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

  static const _monthNames = [
    'January', 'February', 'March',     'April',   'May',      'June',
    'July',    'August',   'September', 'October', 'November', 'December',
  ];
  static const _dayHeaders = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  Color _circleColor(String status) {
    switch (status) {
      case 'Present': return const Color(0xFF43A047);
      case 'Absent':  return const Color(0xFFE53935);
      case 'Leave':   return const Color(0xFFF57C00);
      default:        return Colors.transparent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = '${_monthNames[month.month - 1]} ${month.year}';
    final pctColor = isLow
        ? Colors.red
        : pct >= 85
            ? Colors.green
            : const Color(0xFFF57F17);

    final daysInMonth  = DateTime(month.year, month.month + 1, 0).day;
    final firstWeekday = DateTime(month.year, month.month, 1).weekday;
    final today        = DateTime.now();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Month navigation ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: Icon(Icons.chevron_left, color: Colors.grey.shade700),
                  onPressed: onPrev,
                ),
                Text(
                  monthLabel,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: Icon(Icons.chevron_right,
                      color: onNext == null
                          ? Colors.grey.shade300
                          : Colors.grey.shade700),
                  onPressed: onNext,
                ),
              ],
            ),
          ),

          // ── Stats row + progress bar ────────────────────────────
          if (workingDays == 0)
            Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              child: Text('No school days recorded in this month',
                  style: TextStyle(color: Colors.grey.shade500)),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _StatCell(
                      value: '$workingDays',
                      label: 'Days',
                      color: AppTheme.primary),
                  _StatCell(
                      value: '$present',
                      label: 'Present',
                      color: Colors.green),
                  _StatCell(
                      value: '$absent',
                      label: 'Absent',
                      color: Colors.red),
                  _StatCell(
                      value: '$leave',
                      label: 'Leave',
                      color: const Color(0xFFF57F17)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
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
            ),
            const SizedBox(height: 12),
          ],

          const Divider(height: 1),

          // ── Day-of-week header ──────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Row(
              children: List.generate(7, (i) {
                final isSun = i == 6;
                return Expanded(
                  child: Center(
                    child: Text(
                      _dayHeaders[i],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isSun
                            ? Colors.red.shade300
                            : Colors.grey.shade400,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),

          // ── Calendar grid ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount:   7,
                childAspectRatio: 1,
                mainAxisSpacing:  4,
                crossAxisSpacing: 2,
              ),
              itemCount: (firstWeekday - 1) + daysInMonth,
              itemBuilder: (_, idx) {
                if (idx < firstWeekday - 1) return const SizedBox();

                final day    = idx - (firstWeekday - 1) + 1;
                final date   = DateTime(month.year, month.month, day);
                final status = monthData[day]?[roll];
                final isSun    = date.weekday == DateTime.sunday;
                final isFuture = date.isAfter(today);
                final isToday  = date.year  == today.year &&
                                 date.month == today.month &&
                                 date.day   == today.day;

                final Color circleFill = (!isFuture && status != null)
                    ? _circleColor(status)
                    : Colors.transparent;
                final bool filled = circleFill != Colors.transparent;

                Color textColor;
                if (filled) {
                  textColor = Colors.white;
                } else if (isFuture) {
                  textColor = Colors.grey.shade300;
                } else if (isSun) {
                  textColor = Colors.red.shade200;
                } else {
                  textColor = Colors.grey.shade500;
                }

                return Center(
                  child: Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(
                      color: filled ? circleFill : Colors.transparent,
                      shape: BoxShape.circle,
                      border: isToday && !filled
                          ? Border.all(color: AppTheme.primary, width: 1.5)
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        '$day',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: filled || isToday
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isToday && !filled
                              ? AppTheme.primary
                              : textColor,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // ── Legend ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legendItem(const Color(0xFF43A047), 'Present'),
                const SizedBox(width: 16),
                _legendItem(const Color(0xFFE53935), 'Absent'),
                const SizedBox(width: 16),
                _legendItem(const Color(0xFFF57C00), 'Leave'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 20, height: 20,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Center(
          child: Text(
            label[0],
            style: const TextStyle(
                fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
      ),
      const SizedBox(width: 5),
      Text(label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
    ],
  );
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
      padding: const EdgeInsets.all(16),
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



// ── Shared list widgets for Guardian Dashboard ────────────────────────────────

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
    return const Divider(height: 1, indent: 70);
  }
}

class _FeatureTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? badge;

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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(children: [
          Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            if (badge != null)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.accent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(badge!,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ),
              ),
          ]),
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

// ── Guardian Dedicated Screens ───────────────────────────────────────────────

class GuardianTimetableScreen extends StatefulWidget {
  final Map<String, Map<int, TimetableEntry>> classTimetable;
  final List<Map<String, dynamic>> bellSettings;
  final String firstBellTime;
  final Map<String, Teacher> teacherById;
  final String className;

  const GuardianTimetableScreen({
    super.key,
    required this.classTimetable,
    required this.bellSettings,
    required this.firstBellTime,
    required this.teacherById,
    required this.className,
  });

  @override
  State<GuardianTimetableScreen> createState() => _GuardianTimetableScreenState();
}

class _GuardianTimetableScreenState extends State<GuardianTimetableScreen> {
  String _selectedDay = 'Monday';
  late final PageController _pageController;

  static const _days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'
  ];
  static const _dayAbbr = {
    'Monday': 'Mon', 'Tuesday': 'Tue', 'Wednesday': 'Wed',
    'Thursday': 'Thu', 'Friday': 'Fri', 'Saturday': 'Sat',
  };

  String _bellTime(int bellIdx) {
    try {
      final parts = widget.firstBellTime.split(':');
      int h = int.parse(parts[0]);
      int m = int.parse(parts[1]);
      for (int i = 0; i < bellIdx; i++) {
        final dur = (widget.bellSettings[i]['duration'] as num?)?.toInt() ?? 45;
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
  void initState() {
    super.initState();
    final dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final todayName = dayNames[DateTime.now().weekday - 1];
    if (_days.contains(todayName)) {
      _selectedDay = todayName;
    }
    _pageController = PageController(initialPage: _days.indexOf(_selectedDay));
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Builds the period list for a single [day]. Each [PageView] page renders
  /// one of these so the guardian can swipe left/right between days.
  Widget _buildDayBody(String day) {
    final dayPeriods = widget.classTimetable[day] ?? {};
    final bellCount = widget.bellSettings.length;

    if (bellCount == 0 || dayPeriods.isEmpty) {
      return Center(
        child: Text('No timetable for $day',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: bellCount,
      itemBuilder: (context, i) {
        final bell = i + 1;
        final isLunch = (widget.bellSettings[i]['isLunch'] as bool?) ?? false;
        final time = _bellTime(i);
        final entry = dayPeriods[bell];

        if (isLunch) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              const Icon(Icons.lunch_dining_outlined, size: 16, color: Colors.orange),
              const SizedBox(width: 8),
              Text(time, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(width: 12),
              Text('Lunch Break',
                  style: TextStyle(
                      fontSize: 14,
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.w500)),
            ]),
          );
        }

        String subject = '—';
        String teacherName = '';
        Color periodColor = Colors.white;

        if (entry != null && !entry.isEmpty) {
          final teacher = widget.teacherById[entry.teacherId];
          subject = entry.subject ?? (teacher?.subject ?? '—');
          teacherName = teacher?.name ?? '';
          periodColor = AppTheme.primary.withValues(alpha: 0.05);
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: periodColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: entry != null && !entry.isEmpty ? AppTheme.primary : Colors.grey.shade300,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text('$bell',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 80,
              child: Text(time, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(subject,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  if (teacherName.isNotEmpty)
                    Text(teacherName,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                ],
              ),
            ),
          ]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text('${widget.className} Timetable'),
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: _days.map((d) {
                  final sel = d == _selectedDay;
                  return GestureDetector(
                    onTap: () => _pageController.animateToPage(
                      _days.indexOf(d),
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                      decoration: BoxDecoration(
                        color: sel ? AppTheme.primary : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: sel ? AppTheme.primary : Colors.grey.shade300,
                        ),
                      ),
                      child: Text(_dayAbbr[d]!,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: sel ? Colors.white : Colors.grey.shade600)),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: _days.length,
              onPageChanged: (i) => setState(() => _selectedDay = _days[i]),
              itemBuilder: (context, i) => _buildDayBody(_days[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class GuardianSubjectTeachersScreen extends StatelessWidget {
  final Map<String, Map<int, TimetableEntry>> classTimetable;
  final Map<String, Teacher> teacherById;
  final String className;

  const GuardianSubjectTeachersScreen({
    super.key,
    required this.classTimetable,
    required this.teacherById,
    required this.className,
  });

  @override
  Widget build(BuildContext context) {
    final Map<String, Set<String>> subjectTeacherIds = {};
    classTimetable.forEach((day, bells) {
      bells.forEach((bell, entry) {
        if (!entry.isEmpty && entry.teacherId != null) {
          final teacher = teacherById[entry.teacherId!];
          final subj = entry.subject ?? teacher?.subject ?? 'Unknown';
          subjectTeacherIds.putIfAbsent(subj, () => {}).add(entry.teacherId!);
        }
      });
    });

    final subjects = subjectTeacherIds.keys.toList()..sort();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text('$className Teachers'),
      ),
      body: subjects.isEmpty
          ? Center(
              child: Text('No subject teachers assigned yet',
                  style: TextStyle(color: Colors.grey.shade500)),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: subjects.length,
              itemBuilder: (context, idx) {
                final subj = subjects[idx];
                final tIds = subjectTeacherIds[subj]!;
                final teachers = tIds.map((id) => teacherById[id]).whereType<Teacher>().toList();
                final names = teachers.map((t) => t.name).join(', ');

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                      child: Text(
                        subj.isNotEmpty ? subj[0].toUpperCase() : '?',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary),
                      ),
                    ),
                    title: Text(subj, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(names.isNotEmpty ? names : 'No teacher assigned'),
                  ),
                );
              },
            ),
    );
  }
}

class GuardianHomeworkScreen extends StatelessWidget {
  final List<Homework> homeworkList;
  final String className;

  const GuardianHomeworkScreen({
    super.key,
    required this.homeworkList,
    required this.className,
  });

  Color _statusColor(Homework hw) {
    if (hw.isReviewed) return Colors.green;
    if (hw.isOverdue) return Colors.red;
    return Colors.orange;
  }

  String _statusLabel(Homework hw) {
    if (hw.isReviewed) return 'Reviewed';
    if (hw.isOverdue) return 'Overdue';
    final d = hw.daysUntilDue;
    if (d == 0) return 'Due Today';
    if (d == 1) return 'Tomorrow';
    return 'Due in $d days';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text('Homework — $className'),
      ),
      body: homeworkList.isEmpty
          ? Center(
              child: Text('No homework assignments posted',
                  style: TextStyle(color: Colors.grey.shade500)),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: homeworkList.length,
              itemBuilder: (context, i) {
                final hw = homeworkList[i];
                final due = '${hw.dueDate.day}/${hw.dueDate.month}/${hw.dueDate.year}';
                final sc = _statusColor(hw);
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(hw.subject,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: AppTheme.primary)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: sc.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _statusLabel(hw),
                                style: TextStyle(color: sc, fontWeight: FontWeight.bold, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(hw.title,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 6),
                        Text(hw.description, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        Text('Due Date: $due',
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class GuardianExamResultsScreen extends StatefulWidget {
  final List<MapEntry<Exam, ExamResult?>> examData;
  const GuardianExamResultsScreen({super.key, required this.examData});

  @override
  State<GuardianExamResultsScreen> createState() => _GuardianExamResultsScreenState();
}

class _GuardianExamResultsScreenState extends State<GuardianExamResultsScreen> {
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
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Exam Results'),
      ),
      body: widget.examData.isEmpty
          ? Center(
              child: Text('No exam results available',
                  style: TextStyle(color: Colors.grey.shade500)),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: widget.examData.length,
              itemBuilder: (context, idx) {
                final exam = widget.examData[idx].key;
                final result = widget.examData[idx].value;
                final isExp = _expandedIdx == idx;
                final dateStr = '${exam.examDate.day} ${months[exam.examDate.month - 1]} ${exam.examDate.year}';

                if (result == null) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(exam.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(dateStr),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('Not Entered', style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                      ),
                    ),
                  );
                }

                final grade = result.grade;
                final gradeColor = _gradeColor(grade);
                final pct = result.percentage;
                final total = result.total;
                final maxTotal = result.subjectCount * result.maxMarks;
                final isAllAbsent = result.marks.values.isNotEmpty && result.marks.values.every((v) => v == -1.0);

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    children: [
                      ListTile(
                        onTap: () => setState(() => _expandedIdx = isExp ? null : idx),
                        leading: CircleAvatar(
                          backgroundColor: gradeColor.withValues(alpha: 0.1),
                          child: Text(grade, style: TextStyle(color: gradeColor, fontWeight: FontWeight.bold)),
                        ),
                        title: Text(exam.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(dateStr),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: (pct / 100).clamp(0.0, 1.0),
                                minHeight: 6,
                                backgroundColor: Colors.grey.shade200,
                                valueColor: AlwaysStoppedAnimation(gradeColor),
                              ),
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(isAllAbsent ? 'Absent' : '${pct.toStringAsFixed(1)}%',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: gradeColor)),
                                Text(isAllAbsent ? '' : '$total/$maxTotal', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                              ],
                            ),
                            const SizedBox(width: 8),
                            Icon(isExp ? Icons.expand_less : Icons.expand_more, color: Colors.grey.shade400),
                          ],
                        ),
                      ),
                      if (isExp)
                        Container(
                          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            children: [
                              const Row(children: [
                                Expanded(child: Text('Subject', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                SizedBox(width: 60, child: Text('Marks', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                SizedBox(width: 50, child: Text('%', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                              ]),
                              const Divider(height: 16),
                              ...result.marks.entries.map((me) {
                                final subj = me.key;
                                final marks = me.value;
                                final subPct = (marks == null || marks == -1.0) ? null : marks / result.maxMarks * 100;
                                final subCol = subPct == null
                                    ? Colors.grey
                                    : subPct >= 75
                                        ? Colors.green
                                        : subPct >= 50
                                            ? const Color(0xFFF57F17)
                                            : Colors.red;
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(children: [
                                    Expanded(child: Text(subj, style: const TextStyle(fontSize: 13))),
                                    SizedBox(
                                      width: 60,
                                      child: Text(
                                        marks == -1.0
                                            ? 'Absent'
                                            : (marks != null
                                                ? '${marks.toStringAsFixed(0)}/${result.maxMarks}'
                                                : '—'),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(fontWeight: FontWeight.bold, color: subCol, fontSize: 13),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 50,
                                      child: Text(
                                        subPct == null ? '—' : '${subPct.toStringAsFixed(0)}%',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: subCol, fontSize: 12),
                                      ),
                                    ),
                                  ]),
                                );
                              }),
                              const Divider(height: 16),
                              Row(children: [
                                const Expanded(child: Text('Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                                SizedBox(
                                  width: 60,
                                  child: Text('$total/$maxTotal',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontWeight: FontWeight.bold, color: gradeColor, fontSize: 13)),
                                ),
                                SizedBox(
                                  width: 50,
                                  child: Text('${pct.toStringAsFixed(1)}%',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontWeight: FontWeight.bold, color: gradeColor, fontSize: 12)),
                                ),
                              ]),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class GuardianAttendanceHistoryScreen extends StatefulWidget {
  final String attendanceKey;
  final int studentRoll;
  final String studentName;

  const GuardianAttendanceHistoryScreen({
    super.key,
    required this.attendanceKey,
    required this.studentRoll,
    required this.studentName,
  });

  @override
  State<GuardianAttendanceHistoryScreen> createState() => _GuardianAttendanceHistoryScreenState();
}

class _GuardianAttendanceHistoryScreenState extends State<GuardianAttendanceHistoryScreen> {
  final _service = StudentService();
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Map<int, Map<int, String>> _monthData = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAttendance();
  }

  Future<void> _loadAttendance() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.loadMonthAttendance(
        className: widget.attendanceKey,
        year: _month.year,
        month: _month.month,
      );
      if (mounted) {
        setState(() {
          _monthData = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _changeMonth(DateTime newMonth) async {
    _month = newMonth;
    await _loadAttendance();
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  int get _workingDays => _monthData.keys.length;
  int get _present => _monthData.values.where((d) => d[widget.studentRoll] == 'Present').length;
  int get _absent => _monthData.values.where((d) => d[widget.studentRoll] == 'Absent').length;
  int get _leave => _monthData.values.where((d) => d[widget.studentRoll] == 'Leave').length;

  double get _pct => _workingDays == 0 ? 0 : _present / _workingDays * 100;
  bool get _isLow => _workingDays > 0 && _pct < 75;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text('${widget.studentName}\'s Attendance'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 12),
                      Text('Error: $_error'),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _loadAttendance, child: const Text('Retry')),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _AttendanceCalendarCard(
                        month: _month,
                        monthData: _monthData,
                        roll: widget.studentRoll,
                        workingDays: _workingDays,
                        present: _present,
                        absent: _absent,
                        leave: _leave,
                        pct: _pct,
                        isLow: _isLow,
                        isCurrentMonth: _isCurrentMonth,
                        onPrev: () => _changeMonth(DateTime(_month.year, _month.month - 1)),
                        onNext: _isCurrentMonth ? null : () => _changeMonth(DateTime(_month.year, _month.month + 1)),
                      ),
                      if (_isLow) ...[
                        const SizedBox(height: 16),
                        _LowAttendanceBanner(pct: _pct),
                      ],
                    ],
                  ),
                ),
    );
  }
}

class GuardianFeeStatusScreen extends StatelessWidget {
  final FeeStructure structure;
  final double totalPaid;

  const GuardianFeeStatusScreen({
    super.key,
    required this.structure,
    required this.totalPaid,
  });

  @override
  Widget build(BuildContext context) {
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Fee Details'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FeeStatusCard(structure: structure, totalPaid: totalPaid),
            
            if (structure.components.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text(
                'FEE BREAKDOWN',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: structure.components.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final comp = entry.value;
                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(comp.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                                Text('₹${comp.amount.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          if (idx < structure.components.length - 1)
                            const Divider(height: 1),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],

            if (structure.installments.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text(
                'INSTALLMENTS SCHEDULE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              ...structure.installments.map((inst) {
                final dateStr = '${inst.dueDate.day} ${months[inst.dueDate.month - 1]} ${inst.dueDate.year}';
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.orange.shade50,
                      child: const Icon(Icons.calendar_today_outlined, color: Colors.orange, size: 18),
                    ),
                    title: Text(inst.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Due: $dateStr'),
                    trailing: Text(
                      '₹${inst.amount.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

class GuardianSchoolInfoScreen extends StatelessWidget {
  const GuardianSchoolInfoScreen({super.key});

  Future<void> _launchUrlHelper(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SchoolSettingsProvider>();
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('School Information'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const _SchoolInfoCard(),
            const SizedBox(height: 24),
            if (s.isLoaded) ...[
              if (s.schoolPhone.trim().isNotEmpty)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                    child: const Icon(Icons.phone, color: AppTheme.primary),
                  ),
                  title: const Text('Call School'),
                  subtitle: Text(s.schoolPhone.trim()),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _launchUrlHelper('tel:${s.schoolPhone.trim()}'),
                ),
              const SizedBox(height: 8),
              if (s.schoolEmail.trim().isNotEmpty)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                    child: const Icon(Icons.email, color: AppTheme.primary),
                  ),
                  title: const Text('Email School'),
                  subtitle: Text(s.schoolEmail.trim()),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _launchUrlHelper('mailto:${s.schoolEmail.trim()}'),
                ),
              const SizedBox(height: 8),
              if (s.schoolWebsite.trim().isNotEmpty)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                    child: const Icon(Icons.language, color: AppTheme.primary),
                  ),
                  title: const Text('Visit Website'),
                  subtitle: Text(s.schoolWebsite.trim()),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    String url = s.schoolWebsite.trim();
                    if (!url.startsWith('http://') && !url.startsWith('https://')) {
                      url = 'https://$url';
                    }
                    _launchUrlHelper(url);
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class GuardianConsentScreen extends StatelessWidget {
  final String studentDocId;
  final String studentName;
  final String guardianName;
  final String guardianPhone;
  final String? guardianEmail;

  const GuardianConsentScreen({
    super.key,
    required this.studentDocId,
    required this.studentName,
    required this.guardianName,
    required this.guardianPhone,
    this.guardianEmail,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Parental Consent'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: GuardianConsentSection(
            studentDocId: studentDocId,
            studentName: studentName,
            guardianName: guardianName,
            guardianPhone: guardianPhone,
            guardianEmail: guardianEmail,
          ),
        ),
      ),
    );
  }
}



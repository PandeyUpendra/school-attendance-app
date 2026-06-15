import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme.dart';
import '../../l10n/app_strings.dart';
import '../auth/profile_screen.dart';
import 'package:school_app/services/student_service.dart';
import 'package:school_app/services/timetable_service.dart';
import 'package:school_app/services/notification_service.dart';
import 'package:school_app/services/fee_service.dart';
import '../teachers/teacher_management_screen.dart';
import '../timetable/timetable_settings_screen.dart';
import '../timetable/assign_duties_screen.dart';
import '../students/student_details_screen.dart';
import '../students/promotion_screen.dart';
import '../timetable/my_timetable_screen.dart';
import '../timetable/free_bells_screen.dart';
import '../substitution/substitution_history_screen.dart';
import '../leave/leave_requests_screen.dart';
import '../attendance/attendance_history_screen.dart';
import '../attendance/class_picker_screen.dart';
import 'package:school_app/services/auth_service.dart';
import '../announcements/announcements_screen.dart';
import '../announcements/notifications_screen.dart';
import '../fees/fee_structure_screen.dart';
import '../fees/fee_overview_screen.dart';
import '../exams/exam_management_screen.dart';
import '../copy_check/copy_check_overview_screen.dart';
import '../homework/homework_overview_screen.dart';
import '../analytics/analytics_screen.dart';
import '../students/student_remarks_screen.dart';
import '../students/staff_remarks_screen.dart';
import '../students/deleted_students_screen.dart';
import '../tasks/unified_staff_task_screen.dart';
import '../substitution/absent_teachers_screen.dart';
import 'package:school_app/services/staff_task_service.dart';
import '../../shared/utils/role_guard.dart';
import '../../shared/utils/app_transitions.dart';
import '../exams/exam_datesheet_screen.dart';
import '../syllabus/syllabus_coverage_dashboard_screen.dart';
import '../students/id_card_generator_screen.dart';
import '../meeting/coordinator_meeting_records_screen.dart';
import '../birthdays/birthdays_screen.dart';
import '../todo/todo_list_screen.dart';
import '../todo/todo_reminder_banner.dart';
import '../exams/report_card_template_editor.dart';
import '../fees/payment_claims_verification_screen.dart';
import '../students/bulk_student_import_screen.dart';
import '../admin/admission_crm_screen.dart';
import '../owner/transport_driver_screen.dart';
import '../../shared/widgets/social_media_links_screen.dart';

const _cPurple    = AppTheme.primary;
const _cPurpleMid = AppTheme.primaryMid;
const _cPink      = AppTheme.accent;
const _cBg        = AppTheme.background;

class CoordinatorDashboard extends StatefulWidget {
  const CoordinatorDashboard({super.key});

  @override
  State<CoordinatorDashboard> createState() => _CoordinatorDashboardState();
}

class _CoordinatorDashboardState extends State<CoordinatorDashboard> {
  final GlobalKey _heroKey = GlobalKey();
  double _heroHeight = 260.0;

  void _measureHeroHeight() {
    if (!mounted) return;
    final RenderBox? renderBox = _heroKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final height = renderBox.size.height;
      if (height != _heroHeight) {
        setState(() {
          _heroHeight = height;
        });
      }
    }
  }

  bool _attendanceLoading = true;
  bool _navigating        = false; // prevents double-push navigation loop
  List<ClassSummary>       _summaries          = [];
  Map<String, Map<int, int>> _streaks          = {}; // className → roll → days
  int  _pendingLeaveCount   = 0;
  int  _unreadNotifCount    = 0;
  int  _teachersAbsent      = 0;
  int  _unassignedBells     = 0;
  int  _incompleteTaskCount = 0;
  String _coordEmail        = '';

  // Real-time badge streams
  StreamSubscription? _notifSub;
  StreamSubscription? _leaveSub;
  StreamSubscription? _taskSub;
  int _lastSeenMs = 0;
  List<Map<String, dynamic>> _latestNotifs = [];

  StreamSubscription? _studentSub;
  Map<String, int>? _knownClassTotals;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      RoleGuard.verify(context, ['coordinator', 'ownerPrincipal']);
    });
    _loadAll();
    _initBadgeStreams();
    // Re-run summaries whenever the roster changes (add/delete/class move).
    // SCALE-03: listen to the tiny per-class `class_stats` counters (one doc
    // per class, server-maintained) instead of a capped 500-student window —
    // O(#classes) listener cost, and exact at any school size.
    _studentSub = StudentService.instance
        .watchClassStatsTotals()
        .listen((totals) {
      final known = _knownClassTotals;
      if (known != null && !mapEquals(known, totals)) {
        _loadAll();
      }
      _knownClassTotals = totals;
    });
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    _leaveSub?.cancel();
    _taskSub?.cancel();
    _studentSub?.cancel();
    super.dispose();
  }

  Future<void> _initBadgeStreams() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _lastSeenMs = prefs.getInt('notif_last_seen_ms') ?? 0;

    _notifSub = NotificationService()
        .streamFor(role: 'coordinator')
        .listen((items) {
      if (!mounted) return;
      _latestNotifs = items;
      _recomputeUnread();
    });

    _leaveSub = TimetableService.instance
        .streamPendingLeaveCount()
        .listen((n) {
      if (!mounted) return;
      setState(() => _pendingLeaveCount = n);
    });

    _taskSub = StaffTaskService()
        .streamAllIncompleteCount()
        .listen((n) {
      if (!mounted) return;
      setState(() => _incompleteTaskCount = n);
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

  Future<void> _loadAll() async {
    setState(() => _attendanceLoading = true);

    final session = await AuthService().getSession();
    final email   = (session?['email'] as String?) ?? '';

    final settings = await TimetableService.instance.getSettings();
    final allClasses = List<String>.from(settings['classes'] as List);

    // Filter to assigned classes; fall back to all if none assigned.
    final assignedRaw = session?['assignedClasses'];
    final List<String> classes = (assignedRaw is List && assignedRaw.isNotEmpty)
        ? List<String>.from(assignedRaw).where(allClasses.contains).toList()
        : allClasses;

    // Fire attendance-related reads in parallel (badges handled by streams).
    final summariesFuture  = StudentService.instance.loadTodayFullSummary(classes: classes);
    final absentInfoFuture = TimetableService.instance.getTodayAbsentTeachersInfo();

    final summaries  = await summariesFuture;
    final absentInfo = await absentInfoFuture;

    // Load consecutive absence streaks for all classes in parallel.
    final streaksList = await Future.wait(
      classes.map((cls) => StudentService.instance.loadConsecutiveAbsenceDays(cls)),
    );
    final streaks = <String, Map<int, int>>{};
    for (var i = 0; i < classes.length; i++) {
      streaks[classes[i]] = streaksList[i];
    }

    if (!mounted) return;
    setState(() {
      _coordEmail        = email;
      _summaries         = summaries;
      _streaks           = streaks;
      _teachersAbsent    = absentInfo['absentCount']    ?? 0;
      _unassignedBells   = absentInfo['unassignedBells'] ?? 0;
      _attendanceLoading = false;
    });
  }

  Future<void> _navigate(Widget screen) async {
    if (_navigating || !mounted) return;
    _navigating = true;
    try {
      await Navigator.push(context, AppPageRoute(child: screen));
      if (mounted) await _loadAll();
    } finally {
      _navigating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureHeroHeight());
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
      backgroundColor: _cBg,
      body: Stack(
        children: [
          Positioned.fill(
            child: RefreshIndicator(
              edgeOffset: _heroHeight,
              onRefresh: _loadAll,
              color: _cPurple,
              child: ListView(
                padding: EdgeInsets.only(top: _heroHeight),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
            const SizedBox(height: 4),
            TodoReminderBanner(
              userId: _coordEmail,
              role: 'coordinator',
            ),
            if (!_attendanceLoading)
              FadeInUp(
                delay: const Duration(milliseconds: 50),
                child: _CoordinatorMorningSummaryCard(
                  absentStudents: _summaries.fold(0, (acc, s) => acc + s.absent),
                  pendingLeaves: _pendingLeaveCount,
                  absentTeachers: _teachersAbsent,
                  incompleteTasks: _incompleteTaskCount,
                  onViewTasks: () => _navigate(UnifiedStaffTaskScreen(
                    role: 'coordinator',
                    userEmail: _coordEmail,
                    userName: _coordEmail,
                  )),
                ),
              ),

            // ── Staff Tasks ───────────────────────────────────────────────
            _SectionHeader(context.tr('secStaffTasks')),
            _FeatureTile(
              icon: Icons.assignment_outlined,
              color: _cPurple,
              title: context.tr('staffTasks'),
              subtitle: context.tr('subStaffTasksDesc'),
              badge: _incompleteTaskCount > 0
                  ? '$_incompleteTaskCount'
                  : null,
              onTap: () => _navigate(UnifiedStaffTaskScreen(
                role: 'coordinator',
                userEmail: _coordEmail,
                userName: _coordEmail,
              )),
            ),
            const _Divider(),
            _FeatureTile(
              icon: Icons.history_edu_outlined,
              color: _cPurple,
              title: context.tr('meetingRecords'),
              subtitle: context.tr('subMeetingRecordsDesc'),
              onTap: () => _navigate(CoordinatorMeetingRecordsScreen(
                coordinatorEmail: _coordEmail,
                coordinatorName:  _coordEmail,
              )),
            ),
            const _Divider(),
            _FeatureTile(
              icon: Icons.rate_review_outlined,
              color: _cPurple,
              title: context.tr('staffRemarks'),
              subtitle: context.tr('subStaffRemarksDesc'),
              onTap: () => _navigate(StaffRemarksScreen(
                role: 'coordinator',
                userEmail: _coordEmail,
                userName: _coordEmail,
              )),
            ),

            // ── Announcements ──────────────────────────────────────────────
            _SectionHeader(context.tr('secAnnouncements')),
            _FeatureTile(
              icon: Icons.campaign_outlined,
              color: _cPurple,
              title: context.tr('noticeBoard'),
              subtitle: context.tr('subAnnouncementsManageDesc'),
              onTap: () => _navigate(AnnouncementsScreen(
                viewerRole: 'coordinator',
                posterName: _coordEmail,
              )),
            ),

            // ── Fee Management ─────────────────────────────────────────────
            _SectionHeader(context.tr('secFeeManagement')),
            _FeatureTile(
              icon: Icons.account_balance_wallet_outlined,
              color: AppTheme.success,
              title: context.tr('feeStructure'),
              subtitle: context.tr('subFeeStructureDesc'),
              onTap: () => _navigate(const FeeStructureScreen()),
            ),
            const _Divider(),
            _FeatureTile(
              icon: Icons.currency_rupee_outlined,
              color: AppTheme.success,
              title: context.tr('feeCollection'),
              subtitle: context.tr('subFeeCollectionDesc'),
              onTap: () => _navigate(const FeeOverviewScreen(role: 'coordinator')),
            ),
            const _Divider(),
            StreamBuilder<QuerySnapshot>(
              stream: FeeService().streamPendingPaymentClaims(),
              builder: (context, snapshot) {
                final pendingCount = snapshot.hasData ? snapshot.data!.docs.length : 0;
                return _FeatureTile(
                  icon: Icons.fact_check_outlined,
                  color: AppTheme.success,
                  title: context.tr('verifyUpiClaims'),
                  subtitle: 'Approve or reject parent UPI fee payment claims',
                  badge: pendingCount > 0 ? '$pendingCount' : null,
                  onTap: () => _navigate(const PaymentClaimsVerificationScreen()),
                );
              },
            ),

            // ── Exams & Marks ──────────────────────────────────────────────
            _SectionHeader(context.tr('secExamsMarks')),
            _FeatureTile(
              icon: Icons.quiz_outlined,
              color: _cPurple,
              title: context.tr('examManagement'),
              subtitle: context.tr('subExamMgmtDesc'),
              onTap: () => _navigate(const ExamManagementScreen(role: 'coordinator')),
            ),
            _FeatureTile(
              icon: Icons.description_outlined,
              color: _cPurpleMid,
              title: context.tr('reportCardTemplates'),
              subtitle: context.tr('subReportTemplatesDesc'),
              onTap: () => _navigate(const ReportCardTemplateListScreen()),
            ),

            // ── Copy Checking ──────────────────────────────────────────────
            _SectionHeader(context.tr('secCopyChecking')),
            _FeatureTile(
              icon: Icons.menu_book_outlined,
              color: _cPurple,
              title: context.tr('copyCheckingOverview'),
              subtitle: context.tr('subCopyCheckOverviewDesc'),
              onTap: () => _navigate(const CopyCheckOverviewScreen()),
            ),

            // ── Homework ───────────────────────────────────────────────────
            _SectionHeader(context.tr('secHomework')),
            _FeatureTile(
              icon: Icons.assignment_outlined,
              color: _cPurple,
              title: context.tr('homeworkOverview'),
              subtitle: context.tr('subHomeworkOverviewDesc'),
              onTap: () => _navigate(const HomeworkOverviewScreen()),
            ),

            // ── Timetable ──────────────────────────────────────────────────
            _SectionHeader(context.tr('secTimetable')),
            _FeatureTile(
              icon: Icons.table_chart_outlined,
              color: _cPurple,
              title: context.tr('timetableSettings'),
              subtitle: context.tr('subTimetableSettingsDesc'),
              onTap: () => _navigate(const TimetableSettingsScreen()),
            ),
            const _Divider(),
            _FeatureTile(
              icon: Icons.picture_as_pdf_outlined,
              color: _cPurple,
              title: context.tr('schoolTimetablePdf'),
              subtitle: context.tr('subViewTimetablesDesc'),
              onTap: () => _navigate(const MyTimetableScreen()),
            ),
            const _Divider(),
            _FeatureTile(
              icon: Icons.swap_vert_circle_outlined,
              color: _cPurple,
              title: context.tr('assignDuties'),
              subtitle: context.tr('subAssignDutiesDesc'),
              onTap: () => _navigate(const AssignDutiesScreen()),
            ),

            // ── Staff ──────────────────────────────────────────────────────
            _SectionHeader(context.tr('secStaff')),
            _FeatureTile(
              icon: Icons.people_outline,
              color: _cPurple,
              title: context.tr('manageTeachers'),
              subtitle: context.tr('subManageTeachersDesc'),
              onTap: () => _navigate(const TeacherManagementScreen()),
            ),

            // ── Students ───────────────────────────────────────────────────
            _SectionHeader(context.tr('secStudents')),
            _FeatureTile(
              icon: Icons.school_outlined,
              color: _cPurple,
              title: context.tr('studentDetails'),
              subtitle: context.tr('subStudentDetailsDesc'),
              onTap: () => _navigate(const StudentDetailsScreen()),
            ),
            const _Divider(),
            _FeatureTile(
              icon: Icons.upgrade_outlined,
              color: _cPurple,
              title: context.tr('promoteClass'),
              subtitle: context.tr('subPromoteClassDesc'),
              onTap: () => _navigate(const PromotionScreen()),
            ),
            const _Divider(),
            _FeatureTile(
              icon: Icons.upload_file_outlined,
              color: _cPurple,
              title: context.tr('importFromCsv'),
              subtitle: 'Batch import student rosters from a CSV file',
              onTap: () => _navigate(const BulkStudentImportScreen()),
            ),
            const _Divider(),
            _FeatureTile(
              icon: Icons.assignment_ind_outlined,
              color: _cPurple,
              title: 'Admission CRM',
              subtitle: 'Manage enrollment pipeline leads and follow-ups',
              onTap: () => _navigate(const AdmissionCrmScreen()),
            ),
            const _Divider(),
            _FeatureTile(
              icon: Icons.directions_bus_outlined,
              color: _cPurple,
              title: 'Transport Tracking',
              subtitle: 'Manage bus routes, drivers, and update stops',
              onTap: () => _navigate(const TransportDriverScreen()),
            ),
            const _Divider(),
            _FeatureTile(
              icon: Icons.comment_outlined,
              color: _cPurple,
              title: context.tr('studentRemarks'),
              subtitle: context.tr('subStudentRemarksCoordDesc'),
              onTap: () => _navigate(
                  const StudentRemarksScreen(role: 'coordinator')),
            ),
            const _Divider(),
            _FeatureTile(
              icon: Icons.person_off_outlined,
              color: AppTheme.danger,
              title: context.tr('deletedStudents'),
              subtitle: context.tr('subDeletedStudentsDesc'),
              onTap: () => _navigate(const DeletedStudentsScreen()),
            ),
            // Student Deletion Requests are reviewed by the PRINCIPAL only
            // (Firestore rules exclude coordinators from reading
            // student_deletion_requests), so the tile lives on the principal
            // dashboard — not here.

            // ── Free Bells & Substitution ──────────────────────────────────
            _SectionHeader(context.tr('secFreeBells')),
            _FeatureTile(
              icon: Icons.person_off_outlined,
              color: AppTheme.danger,
              title: context.tr('absentTeachersToday'),
              subtitle: _teachersAbsent > 0
                  ? '$_teachersAbsent absent · $_unassignedBells uncovered'
                  : 'All teachers present today',
              badge: _teachersAbsent > 0 ? '$_teachersAbsent' : null,
              onTap: () => _navigate(const AbsentTeachersScreen()),
            ),
            const _Divider(),
            _FeatureTile(
              icon: Icons.swap_horiz_outlined,
              color: AppTheme.warning,
              title: context.tr('teacherSFreeBells'),
              subtitle: context.tr('subSubstitutionBellsDesc'),
              onTap: () => _navigate(const FreeBellsScreen()),
            ),
            const _Divider(),
            _FeatureTile(
              icon: Icons.history_outlined,
              color: AppTheme.warning,
              title: context.tr('substitutionBells'),
              subtitle: context.tr('subSubstitutionHistoryDesc'),
              onTap: () => _navigate(const SubstitutionHistoryScreen()),
            ),

            // ── Leave Requests ─────────────────────────────────────────────
            _SectionHeader(context.tr('secLeaveRequests')),
            _LeaveRequestTile(
              pendingCount: _pendingLeaveCount,
              onTap: () => _navigate(const LeaveRequestsScreen(viewerRole: 'coordinator')),
            ),

            // ── Analytics ─────────────────────────────────────────────────
            _SectionHeader(context.tr('secAnalytics')),
            _FeatureTile(
              icon: Icons.analytics_outlined,
              color: _cPurpleMid,
              title: context.tr('analyticsDashboard'),
              subtitle: context.tr('subAnalyticsDesc'),
              onTap: () => _navigate(const AnalyticsScreen()),
            ),

            // ── Attendance Reports ─────────────────────────────────────────
            _SectionHeader(context.tr('secReports')),
            _FeatureTile(
              icon: Icons.bar_chart_outlined,
              color: _cPurpleMid,
              title: context.tr('attendanceReports'),
              subtitle: 'Monthly history, % per student & low-attendance flags',
              onTap: () async {
                final pick = await Navigator.push<ClassSectionPick>(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const ClassPickerScreen(mode: ClassPickerMode.reports),
                  ),
                );
                if (pick != null && context.mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AttendanceHistoryScreen(
                        className: pick.className,
                        section:   pick.section,
                      ),
                    ),
                  );
                }
              },
            ),

           _SectionHeader(context.tr('secReports')),
           _FeatureTile(
             icon: Icons.event_note_outlined,
             color: _cPurpleMid,
             title: context.tr('datesheetsHallTickets'),
             subtitle: 'Create and view exam datesheets and admit cards',
             onTap: () => _navigate(const ExamDatesheetScreen()),
           ),
           const _Divider(),
           _FeatureTile(
             icon: Icons.assessment_outlined,
             color: _cPurpleMid,
             title: context.tr('syllabusProgressSummary'),
             subtitle: 'View class-wise syllabus coverage',
             onTap: () => _navigate(const SyllabusCoverageDashboardScreen()),
           ),
           const _Divider(),
           _FeatureTile(
             icon: Icons.badge_outlined,
             color: _cPurpleMid,
             title: context.tr('idCardGenerator'),
             subtitle: 'Batch generate student ID cards',
             onTap: () => _navigate(const IdCardGeneratorScreen()),
           ),
            // ── Birthdays ──────────────────────────────────────────────────
            _SectionHeader(context.tr('secBirthdays')),
            BirthdayBanner(
              role: 'coordinator',
              onTap: () => _navigate(const BirthdaysScreen(
                role: 'coordinator',
              )),
            ),
            _FeatureTile(
              icon: Icons.cake_outlined,
              color: AppTheme.accent,
              title: context.tr('birthdays'),
              subtitle: context.tr('subBirthdaysDesc'),
              onTap: () => _navigate(const BirthdaysScreen(
                role: 'coordinator',
              )),
            ),

            // ── My To-Do List ─────────────────────────────────────────────
            _SectionHeader(context.tr('secMyTodoList')),
            _FeatureTile(
              icon: Icons.checklist_outlined,
              color: _cPurple,
              title: context.tr('myTodoList'),
              subtitle: context.tr('subTodoDesc'),
              onTap: () => _navigate(TodoListScreen(
                userId: _coordEmail,
                role: 'coordinator',
              )),
            ),

            // ── Social Media Links ─────────────────────────────────────────
            _SectionHeader(context.tr('socialMediaLinksTitle')),
            _FeatureTile(
              icon: Icons.share_outlined,
              color: _cPurple,
              title: context.tr('socialMediaLinksTitle'),
              subtitle: context.tr('socialMediaSubtitle'),
              onTap: () => _navigate(const SocialMediaLinksScreen()),
            ),

            // ── Today's Attendance ─────────────────────────────────────────
            const _SectionHeader("TODAY'S ATTENDANCE"),
            _buildAttendanceSection(),

            const SizedBox(height: 32),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _CoordHeroCard(
              key: _heroKey,
              loading:           _attendanceLoading,
              teachersAbsent:    _teachersAbsent,
              unassignedBells:   _unassignedBells,
              unreadNotifCount:  _unreadNotifCount,
              onNotifTap: () async {
                await _navigate(const NotificationsScreen(
                  role: 'coordinator'));
                _refreshLastSeen();
              },
            ),
          ),
        ],
      ),
      ),
    );
  }

  // ── Inline attendance section ─────────────────────────────────────────────

  Widget _buildAttendanceSection() {
    if (_attendanceLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(color: _cPurple)),
      );
    }

    if (_summaries.isEmpty) {
      return _emptyCard('No classes configured yet');
    }

    final marked = _summaries.where((s) => s.marked).toList();
    if (marked.isEmpty) {
      return _emptyCard('No attendance taken yet');
    }

    return Column(
      children: [
        for (final s in _summaries) _buildClassBlock(s),
      ],
    );
  }

  Widget _buildClassBlock(ClassSummary s) {
    final absent  = s.absentLeave.where((n) => n.status == 'Absent').toList();
    final onLeave = s.absentLeave.where((n) => n.status == 'Leave').toList();
    final classStreaks = _streaks[s.className] ?? {};

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Class header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: s.marked
                      ? _classColor(s).withValues(alpha: 0.12)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  s.marked ? Icons.fact_check_outlined : Icons.pending_outlined,
                  color: s.marked ? _classColor(s) : Colors.grey.shade400,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.className,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 1),
                    if (!s.marked)
                      Text(context.tr('notMarkedYet'),
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade400,
                              fontStyle: FontStyle.italic))
                    else
                      Text(
                        'Present ${s.present}/${s.total}  ·  '
                        'Absent ${s.absent}  ·  Leave ${s.leave}',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500),
                      ),
                  ],
                ),
              ),
            ]),
          ),

          // All present — no students to list
          if (s.marked && s.absentLeave.isEmpty) ...[
            Divider(height: 1, color: Colors.grey.shade100),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                Icon(Icons.check_circle_outline,
                    color: Colors.green.shade400, size: 16),
                const SizedBox(width: 6),
                Text('All ${s.total} students present',
                    style: TextStyle(
                        fontSize: 12, color: Colors.green.shade600)),
              ]),
            ),
          ],

          // Absent students
          if (absent.isNotEmpty) ...[
            Divider(height: 1, color: Colors.grey.shade100),
            _groupLabel('ABSENT  (${absent.length})',
                AppTheme.danger),
            for (int i = 0; i < absent.length; i++) ...[
              _StudentRow(
                note:       absent[i],
                streak:     classStreaks[absent[i].roll] ?? 0,
              ),
              if (i < absent.length - 1)
                const Divider(height: 1, indent: 52),
            ],
          ],

          // On-leave students
          if (onLeave.isNotEmpty) ...[
            Divider(height: 1, color: Colors.grey.shade100),
            _groupLabel('ON LEAVE  (${onLeave.length})',
                AppTheme.warning),
            for (int i = 0; i < onLeave.length; i++) ...[
              _StudentRow(
                note:       onLeave[i],
                streak:     classStreaks[onLeave[i].roll] ?? 0,
              ),
              if (i < onLeave.length - 1)
                const Divider(height: 1, indent: 52),
            ],
          ],

          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Color _classColor(ClassSummary s) {
    if (s.absent > 0) return AppTheme.danger;
    if (s.leave  > 0) return AppTheme.warning;
    return AppTheme.success;
  }

  Widget _groupLabel(String text, Color color) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
        child: Text(text,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: 0.5)),
      );

  Widget _emptyCard(String msg) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.info_outline,
                color: Colors.grey.shade400, size: 22),
          ),
          const SizedBox(width: 14),
          Text(msg,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
        ]),
      );
}

// ── Per-student row ───────────────────────────────────────────────────────────

class _StudentRow extends StatelessWidget {
  final StudentNote note;
  final int         streak;
  const _StudentRow({required this.note, required this.streak});

  @override
  Widget build(BuildContext context) {
    final isAbsent   = note.status == 'Absent';
    final statusClr  = isAbsent
        ? AppTheme.danger
        : AppTheme.warning;
    final hasReason  = note.reason != null && note.reason!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        // Avatar
        CircleAvatar(
          radius: 17,
          backgroundColor: statusClr.withValues(alpha: 0.1),
          child: Text(
            note.name.isNotEmpty ? note.name[0].toUpperCase() : '?',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: statusClr),
          ),
        ),
        const SizedBox(width: 10),

        // Name + status + reason
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(note.name,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 6),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusClr.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(note.status,
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: statusClr)),
                ),
              ]),
              const SizedBox(height: 3),
              Row(children: [
                // Reason indicator
                Icon(
                  hasReason
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 12,
                  color: hasReason
                      ? Colors.green.shade600
                      : Colors.grey.shade400,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    hasReason ? note.reason! : 'No reason provided',
                    style: TextStyle(
                        fontSize: 11,
                        color: hasReason
                            ? Colors.grey.shade700
                            : Colors.grey.shade400),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Consecutive-day streak badge
                if (streak > 1) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Text(context.tr('streakDaysCount').replaceAll('{count}', streak.toString()),
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.orange.shade800,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ]),
            ],
          ),
        ),
      ]),
    );
  }
}

// ── Hero card ─────────────────────────────────────────────────────────────────

class _CoordHeroCard extends StatelessWidget {
  final bool loading;
  final int  teachersAbsent;
  final int  unassignedBells;
  final int  unreadNotifCount;
  final VoidCallback onNotifTap;

  const _CoordHeroCard({
    super.key,
    required this.loading,
    required this.teachersAbsent,
    required this.unassignedBells,
    required this.unreadNotifCount,
    required this.onNotifTap,
  });

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
            padding: const EdgeInsets.fromLTRB(20, 10, 8, 56),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top action row
                Row(children: [
                  const Icon(Icons.admin_panel_settings_outlined,
                      color: Colors.white60, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'COORDINATOR  ·  $dateStr',
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
                              color: _cPink, shape: BoxShape.circle),
                          child: Center(
                            child: Text(
                              unreadNotifCount > 9 ? '9+' : '$unreadNotifCount',
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
                const SizedBox(height: 10),

                if (loading)
                  const SizedBox(
                    height: 72,
                    child: Center(
                      child: CircularProgressIndicator(
                          color: Colors.white60, strokeWidth: 2.5),
                    ),
                  )
                else
                  Row(children: [
                    _HeroInfoCard(
                      icon: Icons.person_off_outlined,
                      value: '$teachersAbsent',
                      label: teachersAbsent == 1
                          ? 'Teacher absent'
                          : 'Teachers absent',
                      alertColor: teachersAbsent > 0
                          ? AppTheme.dangerLight
                          : Colors.white70,
                    ),
                    const SizedBox(width: 10),
                    _HeroInfoCard(
                      icon: Icons.notification_important_outlined,
                      value: '$unassignedBells',
                      label: unassignedBells == 1
                          ? 'Bell unassigned'
                          : 'Bells unassigned',
                      alertColor: unassignedBells > 0
                          ? AppTheme.warningLight
                          : Colors.white70,
                    ),
                  ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroInfoCard extends StatelessWidget {
  final IconData icon;
  final String   value, label;
  final Color    alertColor;
  const _HeroInfoCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.alertColor,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            Icon(icon, color: alertColor, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: TextStyle(
                          color: alertColor,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          height: 1.1)),
                  const SizedBox(height: 1),
                  Text(label,
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 10.5),
                      maxLines: 2),
                ],
              ),
            ),
          ]),
        ),
      );
}

class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 30);
    path.quadraticBezierTo(
      size.width * 0.25, size.height + 4,
      size.width * 0.5,  size.height - 18,
    );
    path.quadraticBezierTo(
      size.width * 0.75, size.height - 40,
      size.width,        size.height - 18,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_WaveClipper old) => false;
}

// ── Leave request tile ────────────────────────────────────────────────────────

class _LeaveRequestTile extends StatelessWidget {
  final int pendingCount;
  final VoidCallback onTap;
  const _LeaveRequestTile({required this.pendingCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasPending = pendingCount > 0;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: hasPending
                  ? _cPink.withValues(alpha: 0.12)
                  : AppTheme.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.event_busy_outlined,
                color: hasPending ? _cPink : AppTheme.warning, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Leave Requests',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  hasPending
                      ? '$pendingCount pending application${pendingCount > 1 ? 's' : ''}'
                      : 'No pending leave requests',
                  style: TextStyle(
                      fontSize: 12,
                      color: hasPending ? _cPink : Colors.grey.shade500),
                ),
              ],
            ),
          ),
          if (hasPending)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _cPink, borderRadius: BorderRadius.circular(10)),
              child: Text('$pendingCount',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            )
          else
            Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
        ]),
      ),
    );
  }
}

// ── Shared section widgets ────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(title,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade500,
                letterSpacing: 0.8)),
      );
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, indent: 72, endIndent: 0);
}

class _FeatureTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, subtitle;
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
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 44, height: 44,
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
            Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
          ]),
        ),
      );
}

class _CoordinatorMorningSummaryCard extends StatelessWidget {
  final int absentStudents;
  final int pendingLeaves;
  final int absentTeachers;
  final int incompleteTasks;
  final VoidCallback onViewTasks;

  const _CoordinatorMorningSummaryCard({
    required this.absentStudents,
    required this.pendingLeaves,
    required this.absentTeachers,
    required this.incompleteTasks,
    required this.onViewTasks,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryDark.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.wb_sunny_outlined, color: Colors.amber, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'My Segment Today',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          // Main content grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricTile(
                        icon: Icons.person_off_outlined,
                        label: 'Absent Students',
                        value: '$absentStudents',
                        color: Colors.redAccent.shade100,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildMetricTile(
                        icon: Icons.hourglass_top_outlined,
                        label: 'Pending Leaves',
                        value: '$pendingLeaves',
                        color: Colors.orangeAccent.shade100,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricTile(
                        icon: Icons.people_outline,
                        label: 'Absent Teachers',
                        value: '$absentTeachers',
                        color: Colors.amberAccent.shade100,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildMetricTile(
                        icon: Icons.task_outlined,
                        label: 'Incomplete Tasks',
                        value: '$incompleteTasks',
                        color: Colors.greenAccent.shade100,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Action Button
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: onViewTasks,
              icon: const Icon(Icons.assignment_outlined, size: 16),
              label: const Text('View Coordinator Tasks'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.15),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: Colors.white24),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: color.withValues(alpha: 0.2),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


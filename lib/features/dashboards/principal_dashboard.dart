import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme.dart';
import '../../l10n/app_strings.dart';
import '../auth/profile_screen.dart';
import '../../services/auth_service.dart';
import '../../services/student_service.dart';
import '../../services/timetable_service.dart';
import '../../services/notification_service.dart';
import '../../shared/utils/app_logger.dart';
import '../../shared/widgets/index_building_notice.dart';
import '../attendance/attendance_history_screen.dart';
import '../attendance/class_picker_screen.dart';
import '../leave/leave_requests_screen.dart';
import '../teachers/teacher_deletion_requests_screen.dart';
import '../students/student_deletion_requests_screen.dart';
import '../students/deleted_students_screen.dart';
import '../../services/teacher_deletion_service.dart';
import '../../services/base_firestore_service.dart';
import '../timetable/my_timetable_screen.dart';
import '../students/student_details_screen.dart';
import '../announcements/announcements_screen.dart';
import '../announcements/notifications_screen.dart';
import '../analytics/analytics_screen.dart';
import '../digest/principal_digest_screen.dart';
import '../tasks/unified_staff_task_screen.dart';
import '../students/staff_remarks_screen.dart';
import './coordinator_dashboard.dart';
import './coordinator_management_screen.dart';
import '../owner/edit_school_settings_screen.dart';
import '../birthdays/birthdays_screen.dart';
import '../../models/task.dart';
import '../../services/task_service.dart';
import '../../shared/utils/role_guard.dart';
import '../../shared/utils/app_transitions.dart';
import '../meeting/principal_meeting_records_screen.dart';
import '../admin/admission_crm_screen.dart';
import '../todo/todo_list_screen.dart';
import '../todo/todo_reminder_banner.dart';
import '../fees/fee_overview_screen.dart';
import '../admin/audit_log_screen.dart';
import '../substitution/absent_teachers_screen.dart';
import '../../shared/widgets/social_media_links_screen.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../shared/providers/school_settings_provider.dart';


/// The Principal Portal — school-wide overview dashboard.
class PrincipalDashboard extends StatefulWidget {
  const PrincipalDashboard({super.key});

  @override
  State<PrincipalDashboard> createState() => _PrincipalDashboardState();
}

class _PrincipalDashboardState extends State<PrincipalDashboard> {
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

  bool _loading = true;

  List<ClassSummary>         _summaries      = [];
  int  _pendingLeaveCount       = 0;
  int  _pendingTeacherDelCount  = 0;
  int  _teachersAbsent          = 0;
  int  _unassignedBells         = 0;
  int  _unreadNotifCount        = 0;
  String _principalEmail        = '';
  String _principalName         = '';
  String _sessionRole           = 'principal';

  // Real-time badge streams
  StreamSubscription? _notifSub;
  StreamSubscription? _leaveSub;
  StreamSubscription? _teacherDelSub;
  int _lastSeenMs = 0;
  List<Map<String, dynamic>> _latestNotifs = [];

  StreamSubscription? _studentSub;
  Map<String, int>? _knownClassTotals;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      RoleGuard.verify(context, ['principal', 'ownerPrincipal']);
    });
    _loadAll();
    _initBadgeStreams();
    // Re-run summaries whenever the roster changes (add/delete/class move).
    // SCALE-03: listen to the tiny per-class `class_stats` counters (one doc
    // per class, server-maintained) instead of a capped 500-student window —
    // O(#classes) listener cost, and exact at any school size.
    _studentSub = StudentService.instance.watchClassStatsTotals().listen(
      (totals) {
        final known = _knownClassTotals;
        if (known != null && !mapEquals(known, totals)) {
          _loadAll();
        }
        _knownClassTotals = totals;
      },
      onError: (e) => AppLogger.e('PrincipalDashboard', 'class stats stream error: $e', e),
    );
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    _leaveSub?.cancel();
    _teacherDelSub?.cancel();
    _studentSub?.cancel();
    super.dispose();
  }

  Future<void> _initBadgeStreams() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _lastSeenMs = prefs.getInt('notif_last_seen_ms') ?? 0;

    _notifSub = NotificationService()
        .streamFor(role: 'principal')
        .listen(
          (items) {
            if (!mounted) return;
            _latestNotifs = items;
            _recomputeUnread();
          },
          onError: (e) => AppLogger.e('PrincipalDashboard', 'notif stream error: $e', e),
        );

    _leaveSub = TimetableService.instance
        .streamPendingLeaveCount()
        .listen(
          (n) {
            if (!mounted) return;
            setState(() => _pendingLeaveCount = n);
          },
          onError: (e) => AppLogger.e('PrincipalDashboard', 'leave stream error: $e', e),
        );

    final sid = BaseFirestoreService.currentSchoolId ?? 'default_school';
    _teacherDelSub = TeacherDeletionService()
        .streamPendingCount(sid)
        .listen(
          (n) {
            if (!mounted) return;
            setState(() => _pendingTeacherDelCount = n);
          },
          onError: (e) =>
              AppLogger.e('PrincipalDashboard', 'teacher-deletion stream error', e),
        );
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
    setState(() => _loading = true);
    try {
      final session = await AuthService().getSession();
      final email   = (session?['email'] as String?) ?? '';
      final role    = (session?['role']  as String?) ?? 'principal';
      final name    = (session?['name'] as String?) ?? '';

      String principalName = name;
      if (principalName.isEmpty && email.isNotEmpty) {
        final doc = await TimetableService.instance.getAllowedUserDoc(email);
        if (doc != null) {
          principalName = (doc['name'] as String?) ?? '';
          if (principalName.isNotEmpty) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('auth_name', principalName);
          }
        }
      }
      if (principalName.isEmpty) {
        principalName = email;
      }

      final settings   = await TimetableService.instance.getSettings();
      final allClasses = List<String>.from(settings['classes'] as List);

      // Filter to assigned classes; fall back to all.
      final assignedRaw = session?['assignedClasses'];
      final List<String> classes = (assignedRaw is List && assignedRaw.isNotEmpty)
          ? List<String>.from(assignedRaw).where(allClasses.contains).toList()
          : allClasses;

      // Fire attendance-related reads in parallel (badges handled by streams).
      final summariesFuture  = StudentService.instance.loadTodayFullSummary(classes: classes);
      final absentInfoFuture = TimetableService.instance.getTodayAbsentTeachersInfo();

      final summaries  = await summariesFuture;
      final absentInfo = await absentInfoFuture;

      if (!mounted) return;
      setState(() {
        _principalEmail  = email;
        _principalName   = principalName;
        _sessionRole     = role;
        _summaries       = summaries;
        _teachersAbsent  = absentInfo['absentCount']    ?? 0;
        _unassignedBells = absentInfo['unassignedBells'] ?? 0;
        _loading         = false;
      });
    } catch (e) {
      AppLogger.e('PrincipalDashboard', '_loadAll failed: $e', e);
      if (!mounted) return;
      setState(() {
        _summaries       = [];
        _teachersAbsent  = 0;
        _unassignedBells = 0;
        _loading         = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr('couldNotLoadDashboardError').replaceAll('{error}', e.toString())),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 8),
      ));
    }
  }



  Future<void> _navigate(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

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
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: RefreshIndicator(
              edgeOffset: _heroHeight,
              onRefresh: _loadAll,
              color: AppTheme.primary,
              child: ListView(
                padding: EdgeInsets.only(top: _heroHeight),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
            TodoReminderBanner(
              userId: _principalEmail,
              role: _sessionRole,
            ),
            if (_loading)
              _buildShimmerLoader()
            else ...[
              FadeInUp(
                delay: const Duration(milliseconds: 50),
                child: _PrincipalMorningSummaryCard(
                  absentStudents: _summaries.fold(0, (acc, s) => acc + s.absent),
                  pendingLeaves: _pendingLeaveCount,
                  absentTeachers: _teachersAbsent,
                  unassignedBells: _unassignedBells,
                  onViewLeaves: () => _navigate(
                    const LeaveRequestsScreen(viewerRole: 'principal'),
                  ),
                ),
              ),
              // ── Active Tasks ───────────────────────────────────────────
              _SectionHeader(context.tr('secActiveTasks')),
              _buildTasksSection(),

              // ── Birthdays ─────────────────────────────────────────────
              _SectionHeader(context.tr('secBirthdays')),
              BirthdayBanner(
                role: 'principal',
                onTap: () => _navigate(const BirthdaysScreen(role: 'principal')),
              ),
              _FeatureTile(
                icon: Icons.cake_outlined,
                color: AppTheme.accent,
                title: context.tr('birthdays'),
                subtitle: context.tr('subBirthdaysDesc'),
                onTap: () => _navigate(const BirthdaysScreen(role: 'principal')),
              ),
              const Divider(height: 1, indent: 72),

              // ── Analytics ─────────────────────────────────────────────
              _SectionHeader(context.tr('secAnalytics')),
              _FeatureTile(
                icon: Icons.analytics_outlined,
                color: AppTheme.primary,
                title: context.tr('analyticsDashboard'),
                subtitle: context.tr('subAnalyticsDesc'),
                onTap: () => _navigate(const AnalyticsScreen()),
              ),
              const Divider(height: 1, indent: 72),

              // ── Finance ───────────────────────────────────────────────
              _SectionHeader(context.tr('secFinance')),
              _FeatureTile(
                icon: Icons.currency_rupee_outlined,
                color: AppTheme.success,
                title: context.tr('feeCollection'),
                subtitle: context.tr('subFeeCollectionDesc'),
                onTap: () => _navigate(const FeeOverviewScreen(role: 'principal')),
              ),
              const Divider(height: 1, indent: 72),

              // ── Tools ─────────────────────────────────────────────────
              _SectionHeader(context.tr('secTools')),
              _FeatureTile(
                icon: Icons.manage_accounts_outlined,
                color: AppTheme.primary,
                title: context.tr('manageCoordinators'),
                subtitle: context.tr('subManageCoordinatorsDesc'),
                onTap: () => _navigate(CoordinatorManagementScreen(
                  principalEmail: _principalEmail,
                )),
              ),
              const Divider(height: 1, indent: 72),
              _FeatureTile(
                icon: Icons.history_edu_outlined,
                color: AppTheme.primary,
                title: context.tr('meetingRecords'),
                subtitle: context.tr('subMeetingRecordsPrincipalDesc'),
                onTap: () => _navigate(PrincipalMeetingRecordsScreen(
                  principalEmail: _principalEmail,
                  principalName:  _principalName,
                )),
              ),
              const Divider(height: 1, indent: 72),
              _FeatureTile(
                icon: Icons.assignment_ind_outlined,
                color: AppTheme.primary,
                title: 'Admission CRM',
                subtitle: 'Manage enrollment pipeline leads and follow-ups',
                onTap: () => _navigate(const AdmissionCrmScreen()),
              ),
              const Divider(height: 1, indent: 72),
              _FeatureTile(
                icon: Icons.tune_outlined,
                color: AppTheme.primaryMid,
                title: context.tr('schoolSettings'),
                subtitle: context.tr('subSchoolSettingsDesc'),
                onTap: () => _navigate(const EditSchoolSettingsScreen()),
              ),
              const Divider(height: 1, indent: 72),
              _FeatureTile(
                icon: Icons.task_outlined,
                color: AppTheme.primary,
                title: context.tr('staffTasks'),
                subtitle: context.tr('subStaffTasksUnifiedDesc'),
                onTap: () => _navigate(UnifiedStaffTaskScreen(
                  role: 'principal',
                  userEmail: _principalEmail,
                  userName: _principalName,
                )),
              ),
              const Divider(height: 1, indent: 72),
              _FeatureTile(
                icon: Icons.rate_review_outlined,
                color: AppTheme.primary,
                title: context.tr('staffRemarks'),
                subtitle: context.tr('subStaffRemarksPrincipalDesc'),
                onTap: () => _navigate(StaffRemarksScreen(
                  role: _sessionRole,
                  userEmail: _principalEmail,
                  userName: _principalName,
                )),
              ),
              const Divider(height: 1, indent: 72),
              _FeatureTile(
                icon: Icons.summarize_outlined,
                color: AppTheme.primary,
                title: context.tr('todaySDigest'),
                subtitle: context.tr('subPrincipalDigestDesc'),
                onTap: () => _navigate(const PrincipalDigestScreen()),
              ),
              const Divider(height: 1, indent: 72),
              _FeatureTile(
                icon: Icons.campaign_outlined,
                color: AppTheme.primary,
                title: context.tr('announcements'),
                subtitle: context.tr('subAnnouncementsPrincipalDesc'),
                onTap: () => _navigate(AnnouncementsScreen(
                  viewerRole: 'principal',
                  posterName: _principalEmail,
                )),
              ),
              const Divider(height: 1, indent: 72),
              _FeatureTile(
                icon: Icons.hourglass_top_outlined,
                color: AppTheme.warning,
                title: context.tr('leaveRequests'),
                subtitle: context.tr('subLeaveApproveDesc'),
                badge: _pendingLeaveCount > 0 ? '$_pendingLeaveCount' : null,
                onTap: () => _navigate(const LeaveRequestsScreen(viewerRole: 'principal')),
              ),
              const Divider(height: 1, indent: 72),
              _FeatureTile(
                icon: Icons.no_accounts_outlined,
                color: AppTheme.danger,
                title: context.tr('teacherDeletionRequests'),
                subtitle: context.tr('subTeacherDeletionDesc'),
                badge: _pendingTeacherDelCount > 0
                    ? '$_pendingTeacherDelCount'
                    : null,
                onTap: () =>
                    _navigate(const TeacherDeletionRequestsScreen()),
              ),
              const Divider(height: 1, indent: 72),
              StreamBuilder<int>(
                stream: StudentService.instance.streamPendingDeletionCount(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return _FeatureTile(
                      icon: Icons.person_remove_outlined,
                      color: AppTheme.danger,
                      title: context.tr('studentDeletionRequests'),
                      subtitle:
                          'Review & approve teacher requests to remove student records',
                      badge: '!',
                      onTap: () =>
                          _navigate(const StudentDeletionRequestsScreen()),
                    );
                  }
                  final n = snap.data ?? 0;
                  return _FeatureTile(
                    icon: Icons.person_remove_outlined,
                    color: AppTheme.danger,
                    title: context.tr('studentDeletionRequests'),
                    subtitle:
                        'Review & approve teacher requests to remove student records',
                    badge: n > 0 ? '$n' : null,
                    onTap: () =>
                        _navigate(const StudentDeletionRequestsScreen()),
                  );
                },
              ),
              const Divider(height: 1, indent: 72),
              _FeatureTile(
                icon: Icons.person_off_outlined,
                color: AppTheme.danger,
                title: context.tr('deletedStudents'),
                subtitle: context.tr('subDeletedStudentsDesc'),
                onTap: () => _navigate(const DeletedStudentsScreen()),
              ),
              const Divider(height: 1, indent: 72),
              _FeatureTile(
                icon: Icons.bar_chart_outlined,
                color: AppTheme.primary,
                title: context.tr('attendanceReports'),
                subtitle: context.tr('subAttendanceReportsDesc'),
                onTap: () async {
                  final pick = await Navigator.push<ClassSectionPick>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ClassPickerScreen(
                          mode: ClassPickerMode.reports),
                    ),
                  );
                  if (pick != null && mounted) {
                    _navigate(AttendanceHistoryScreen(
                      className: pick.className,
                      section:   pick.section,
                    ));
                  }
                },
              ),
              const Divider(height: 1, indent: 72),
              _FeatureTile(
                icon: Icons.table_chart_outlined,
                color: AppTheme.primary,
                title: context.tr('schoolTimetable'),
                subtitle: context.tr('subViewTimetablesDesc'),
                onTap: () => _navigate(const MyTimetableScreen()),
              ),
              const Divider(height: 1, indent: 72),
              _FeatureTile(
                icon: Icons.people_outlined,
                color: AppTheme.primary,
                title: context.tr('studentRecords'),
                subtitle: context.tr('subStudentRecordsDesc'),
                onTap: () => _navigate(const StudentDetailsScreen()),
              ),
              const Divider(height: 1, indent: 72),
              _FeatureTile(
                icon: Icons.security_outlined,
                color: AppTheme.primary,
                title: context.tr('auditLog'),
                subtitle: context.tr('subAuditLogDesc'),
                onTap: () => _navigate(const AuditLogScreen()),
              ),

              // ── Owner-Principal: Coordinator Tools ────────────────────────
              if (_sessionRole == 'ownerPrincipal') ...[
                const Divider(height: 1, indent: 72),
                _SectionHeader(context.tr('secCoordinatorTools')),
                _FeatureTile(
                  icon: Icons.admin_panel_settings_outlined,
                  color: AppTheme.primaryMid,
                  title: context.tr('coordinatorTools'),
                  subtitle: context.tr('subCoordinatorToolsDesc'),
                  onTap: () => _navigate(const CoordinatorDashboard()),
                ),
              ],

              // ── My To-Do List ───────────────────────────────────────────
              _SectionHeader(context.tr('secMyTodoList')),
              _FeatureTile(
                icon: Icons.checklist_outlined,
                color: AppTheme.primary,
                title: context.tr('myTodoList'),
                subtitle: context.tr('subTodoDesc'),
                onTap: () => _navigate(TodoListScreen(
                  userId: _principalEmail,
                  role: _sessionRole,
                )),
              ),

              // ── Social Media Links ─────────────────────────────────────
              _SectionHeader(context.tr('socialMediaLinksTitle')),
              _FeatureTile(
                icon: Icons.share_outlined,
                color: AppTheme.primary,
                title: context.tr('socialMediaLinksTitle'),
                subtitle: context.tr('socialMediaSubtitle'),
                onTap: () => _navigate(const SocialMediaLinksScreen()),
              ),

              // ── Today's Attendance (shown last) ────────────────────────
              const _SectionHeader("TODAY'S ATTENDANCE"),
              _buildAttendanceSection(),

              const SizedBox(height: 32),
            ],
          ],
                ),
              ),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _PrincipalHeroCard(
              key: _heroKey,
              loading:          _loading,
              teachersAbsent:   _teachersAbsent,
              unassignedBells:  _unassignedBells,
              unreadNotifCount: _unreadNotifCount,
              onNotifTap: () async {
                await _navigate(const NotificationsScreen(role: 'principal'));
                _refreshLastSeen();
              },
              onTeachersAbsentTap: () => _navigate(
                const LeaveRequestsScreen(viewerRole: 'principal'),
              ),
              onBellsTap: () =>
                  _navigate(const AbsentTeachersScreen()),
            ),
          ),
        ],
      ),
      ),
    );
  }

  // ── Inline attendance section ───────────────────────────────────────────────

  Widget _buildAttendanceSection() {
    if (_summaries.isEmpty) return _emptyInfo('No classes configured yet');

    final marked = _summaries.where((s) => s.marked).toList();
    if (marked.isEmpty) return _emptyInfo('No attendance taken yet');

    return Column(
      children: [for (final s in _summaries) _buildClassBlock(s)],
    );
  }

  Widget _buildClassBlock(ClassSummary s) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
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
              Text(s.className,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              if (!s.marked) ...[
                const SizedBox(width: 8),
                Text(context.tr('notMarkedYet'),
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade400,
                        fontStyle: FontStyle.italic)),
              ],
            ]),
            if (s.marked) ...[
              const SizedBox(height: 12),
              Divider(height: 1, color: Colors.grey.shade100),
              const SizedBox(height: 12),
              Row(children: [
                _AttendanceStat('${s.total}',   'Total',    AppTheme.textSecondary),
                _AttendanceStat('${s.present}', 'Present',  AppTheme.success),
                _AttendanceStat('${s.absent}',  'Absent',   AppTheme.danger),
                _AttendanceStat('${s.leave}',   'On Leave', AppTheme.warning),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  Color _classColor(ClassSummary s) {
    if (s.absent > 0) return AppTheme.danger;
    if (s.leave  > 0) return AppTheme.warning;
    return AppTheme.success;
  }

  Widget _buildShimmerLoader() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Morning summary card skeleton
            Container(
              height: 160,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            // Section header skeleton
            Container(
              width: 120,
              height: 16,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            // Tasks skeleton
            Container(
              height: 100,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            // Section header skeleton
            Container(
              width: 120,
              height: 16,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            // Birthday banner skeleton
            Container(
              height: 70,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            // Tiles skeleton
            ...List.generate(3, (index) => Container(
              height: 60,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildTasksSection() {
    return StreamBuilder<List<Task>>(
      stream: TaskService().getAllTasks(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          if (isIndexBuildingError(snapshot.error)) {
            return IndexBuildingNotice(onRetry: () => setState(() {}));
          }
          return _errorInfo('Failed to load tasks: ${snapshot.error}');
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return _emptyInfo('No active tasks');
        }
        final tasks = snapshot.data!.take(3).toList();
        return Column(
          children: tasks.map((task) {
            final done = task.studentStatuses.values.where((v) => v).length;
            final totalMarked = task.studentStatuses.length;
            final progress = totalMarked == 0 ? 0.0 : done / totalMarked;

            return Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.task_alt, color: AppTheme.primary, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          task.title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${(progress * 100).round()}%',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.grey.shade100,
                    color: AppTheme.success,
                    minHeight: 6,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Classes: ${task.assignedClasses.join(", ")}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _emptyInfo(String msg) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(Icons.info_outline, color: Colors.grey.shade400, size: 20),
          const SizedBox(width: 10),
          Text(msg,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        ]),
      );

  Widget _errorInfo(String msg) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const Icon(Icons.error_outline, color: AppTheme.danger, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(msg,
                style: const TextStyle(fontSize: 13, color: AppTheme.danger)),
          ),
        ]),
      );
}

// ── Attendance stat cell ──────────────────────────────────────────────────────

class _AttendanceStat extends StatelessWidget {
  final String value, label;
  final Color  color;
  const _AttendanceStat(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                  height: 1.1)),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 10.5,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w500)),
        ]),
      );
}

// ── Hero card ─────────────────────────────────────────────────────────────────

class _PrincipalHeroCard extends StatelessWidget {
  final bool loading;
  final int  teachersAbsent;
  final int  unassignedBells;
  final int  unreadNotifCount;
  final VoidCallback onNotifTap;
  final VoidCallback onTeachersAbsentTap;
  final VoidCallback onBellsTap;

  const _PrincipalHeroCard({
    super.key,
    required this.loading,
    required this.teachersAbsent,
    required this.unassignedBells,
    required this.unreadNotifCount,
    required this.onNotifTap,
    required this.onTeachersAbsentTap,
    required this.onBellsTap,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const dy = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    final dateStr = '${dy[now.weekday-1]}, ${now.day} ${mo[now.month-1]}'.toUpperCase();
    final settings = Provider.of<SchoolSettingsProvider>(context);

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
                  const Icon(Icons.business_outlined,
                      color: Colors.white60, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'PRINCIPAL  ·  $dateStr',
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
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
                // School name & logo  |  App name & logo
                Row(
                  children: [
                    // ── School branding ──
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.white24,
                      backgroundImage: settings.schoolLogo.isNotEmpty
                          ? CachedNetworkImageProvider(settings.schoolLogo)
                          : null,
                      child: settings.schoolLogo.isEmpty
                          ? const Icon(Icons.school, size: 14, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        settings.schoolName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // ── App branding ──
                    const CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.white24,
                      backgroundImage: AssetImage('assets/images/logo.png'),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Klassivo',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
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
                      onTap: onTeachersAbsentTap,
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
                      onTap: onBellsTap,
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
  final IconData     icon;
  final String       value, label;
  final Color        alertColor;
  final VoidCallback onTap;

  const _HeroInfoCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.alertColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            splashColor: Colors.white24,
            highlightColor: Colors.white10,
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
                const Icon(Icons.chevron_right,
                    color: Colors.white38, size: 16),
              ]),
            ),
          ),
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
        size.width * 0.5,  size.height - 18);
    path.quadraticBezierTo(
        size.width * 0.75, size.height - 40,
        size.width,        size.height - 18);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_WaveClipper old) => false;
}

// ── Shared small widgets ──────────────────────────────────────────────────────

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
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
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
                  color: AppTheme.accent,
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

class _PrincipalMorningSummaryCard extends StatelessWidget {
  final int absentStudents;
  final int pendingLeaves;
  final int absentTeachers;
  final int unassignedBells;
  final VoidCallback onViewLeaves;

  const _PrincipalMorningSummaryCard({
    required this.absentStudents,
    required this.pendingLeaves,
    required this.absentTeachers,
    required this.unassignedBells,
    required this.onViewLeaves,
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
                    'School Today',
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
                        icon: Icons.notification_important_outlined,
                        label: 'Unassigned Bells',
                        value: '$unassignedBells',
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
              onPressed: onViewLeaves,
              icon: const Icon(Icons.rate_review_outlined, size: 16),
              label: const Text('View Leave Requests'),
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


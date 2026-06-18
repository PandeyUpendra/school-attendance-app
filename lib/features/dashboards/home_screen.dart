import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme.dart';
import '../../l10n/app_strings.dart';
import '../../models/teacher.dart';
import '../auth/profile_screen.dart';
import 'package:school_app/services/notification_service.dart';
import 'package:school_app/services/staff_task_service.dart';
import 'package:school_app/services/timetable_service.dart';
import '../../shared/utils/role_guard.dart';
import '../../shared/utils/app_transitions.dart';
import '../class_diary/class_diary_screen.dart';
import '../study_material/study_material_upload_screen.dart';
import '../syllabus/syllabus_tracker_screen.dart';
import '../attendance/attendance_screen.dart';
import '../students/student_list_screen.dart';
import '../students/deleted_students_screen.dart';
import '../timetable/my_timetable_screen.dart';
import '../attendance/class_picker_screen.dart';
import '../leave/leave_application_screen.dart';
import '../leave/student_leave_requests_screen.dart';
import '../attendance/daily_calls_screen.dart';
import '../attendance/attendance_history_screen.dart';
import '../announcements/announcements_screen.dart';
import '../announcements/notifications_screen.dart';
import '../exams/exam_management_screen.dart';
import '../copy_check/copy_checking_screen.dart';
import '../homework/homework_screen.dart';
import '../substitution/substitution_history_screen.dart';
import '../students/student_remarks_screen.dart';
import '../students/staff_remarks_screen.dart';
import '../tasks/staff_tasks_screen.dart';
import '../meeting/teacher_meeting_tasks_screen.dart';
import 'package:school_app/services/meeting_service.dart';
import 'package:school_app/services/substitution_history_service.dart';
import '../birthdays/birthdays_screen.dart';
import '../todo/todo_list_screen.dart';
import '../todo/todo_reminder_banner.dart';
import '../teachers/teacher_morning_summary_card.dart';
import '../../shared/widgets/social_media_links_screen.dart';
import '../admin/admission_crm_screen.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../shared/providers/school_settings_provider.dart';


class HomeScreen extends StatefulWidget {
  final Teacher? teacher;
  const HomeScreen({super.key, this.teacher});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _morningSummaryKey1 = GlobalKey<TeacherMorningSummaryCardState>();
  final _morningSummaryKey2 = GlobalKey<TeacherMorningSummaryCardState>();
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

  int _unreadNotifCount     = 0;
  int _pendingTaskCount     = 0;
  int _pendingMeetingTasks  = 0;
  int _pendingStudentLeaves = 0;

  StreamSubscription? _notifSub;
  StreamSubscription? _taskSub;
  StreamSubscription? _meetingTaskSub;
  StreamSubscription? _studentLeaveSub;
  int _lastSeenMs = 0;
  List<Map<String, dynamic>> _latestNotifs = [];

  @override
  void initState() {
    super.initState();
    // Guard: only a signed-in teacher / subject-teacher may stay here.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      RoleGuard.verify(context, ['teacher', 'subjectTeacher']);
    });
    _initStreams();
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    _taskSub?.cancel();
    _meetingTaskSub?.cancel();
    _studentLeaveSub?.cancel();
    super.dispose();
  }

  Future<void> _initStreams() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _lastSeenMs = prefs.getInt('notif_last_seen_ms') ?? 0;

    final tid = widget.teacher?.id ?? '';

    _notifSub = NotificationService()
        .streamFor(role: 'teacher', teacherId: tid)
        .listen((items) {
      if (!mounted) return;
      _latestNotifs = items;
      _recomputeUnread();
    });

    if (tid.isNotEmpty) {
      _taskSub = StaffTaskService()
          .streamPendingCountForTeacher(tid)
          .listen((n) {
        if (!mounted) return;
        setState(() => _pendingTaskCount = n);
      });
      _meetingTaskSub = MeetingService()
          .streamPendingTaskCountForTeacher(tid)
          .listen((n) {
        if (!mounted) return;
        setState(() => _pendingMeetingTasks = n);
      });
    }

    // Student leave badge — only if this teacher is a class teacher
    final cls = widget.teacher?.classTeacherOf;
    if (cls != null && cls.isNotEmpty) {
      _studentLeaveSub = TimetableService.instance
          .streamPendingStudentLeaveCount(
            studentClass: cls,
            studentSection: widget.teacher?.section ?? '',
          )
          .listen((n) {
        if (!mounted) return;
        setState(() => _pendingStudentLeaves = n);
      });
    }
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

  Future<void> _loadNotifCount() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _lastSeenMs = prefs.getInt('notif_last_seen_ms') ?? 0);
    _recomputeUnread();
  }

  /// Pull-to-refresh handler for the dashboard. Re-reads the notification
  /// count (and lets any descendant streams re-settle).
  Future<void> _refreshAll() async {
    await _loadNotifCount();
    _morningSummaryKey1.currentState?.loadData();
    _morningSummaryKey2.currentState?.loadData();
    if (mounted) setState(() {});
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
        backgroundColor: AppTheme.background,
        body: _buildBody(context),
      ),
    );
  }

  Teacher? get teacher => widget.teacher;

  bool get _isClassTeacher =>
      teacher?.isClassTeacher == true && teacher?.classTeacherOf != null;

  // ── Wave hero card ────────────────────────────────────────────────────────

  Widget _buildHero() {
    final t = teacher;
    final now = DateTime.now();
    const wdays  = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    final dateStr =
        '${wdays[now.weekday - 1]}, ${now.day} ${months[now.month - 1]}';

    final roleStr = t == null
        ? 'Teacher'
        : t.isClassTeacher && t.classTeacherOf != null
            ? 'Class Teacher  ·  ${t.classTeacherOf}'
            : 'Teacher  ·  ${t.subject}';
    final settings = Provider.of<SchoolSettingsProvider>(context);

    return ClipPath(
      key: _heroKey,
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
                // School name and logo row
                Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: Colors.white24,
                      backgroundImage: settings.schoolLogo.isNotEmpty
                          ? CachedNetworkImageProvider(settings.schoolLogo)
                          : null,
                      child: settings.schoolLogo.isEmpty
                          ? const Icon(Icons.school, size: 12, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(width: 8),
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
                  ],
                ),
                const SizedBox(height: 8),
                // ── Top action row (bell + logout) ──────────────────────
                Row(children: [
                  // Date label
                  const Icon(Icons.person_outlined,
                      color: Colors.white60, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'TEACHER  ·  $dateStr',
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.9),
                    ),
                  ),
                  // Notification bell
                  Stack(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.notifications_outlined,
                            color: Colors.white, size: 22),
                        tooltip: 'Notifications',
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => NotificationsScreen(
                                role:      'teacher',
                                teacherId: t?.id,
                                teacher:   t,
                              ),
                            ),
                          );
                          _loadNotifCount();
                        },
                      ),
                      if (_unreadNotifCount > 0)
                        Positioned(
                          right: 8, top: 8,
                          child: Container(
                            width: 14, height: 14,
                            decoration: const BoxDecoration(
                              color: AppTheme.accent,
                              shape: BoxShape.circle),
                            child: Center(
                              child: Text(
                                _unreadNotifCount > 9
                                    ? '9+'
                                    : '$_unreadNotifCount',
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
                  // Profile
                  IconButton(
                    icon: const Icon(Icons.account_circle_outlined,
                        color: Colors.white, size: 22),
                    tooltip: 'My Profile',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ProfileScreen()),
                    ),
                  ),
                ]),

                const SizedBox(height: 6),

                // ── Teacher name ─────────────────────────────────────────
                Text(
                  t?.name ?? 'Klassivo',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      height: 1.1),
                ),
                const SizedBox(height: 3),
                Text(roleStr,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 14),

                // ── Stats glass card ─────────────────────────────────────
                if (t != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(children: [
                      _HeroInfo(
                        label: 'Subject',
                        value: t.subject.isNotEmpty ? t.subject : '—',
                      ),
                      _vDivider(),
                      _HeroInfo(
                        label: 'My Class',
                        value: t.isClassTeacher &&
                                t.classTeacherOf != null
                            ? t.classTeacherOf!
                            : '—',
                      ),
                      _vDivider(),
                      _HeroInfo(
                        label: 'Alerts',
                        value: _unreadNotifCount > 0
                            ? '$_unreadNotifCount'
                            : 'None',
                        highlight: _unreadNotifCount > 0,
                      ),
                    ]),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _vDivider() => Container(
        width: 1,
        height: 28,
        color: Colors.white24,
        margin: const EdgeInsets.symmetric(horizontal: 8),
      );

  Widget _buildBody(BuildContext context) {
    if (_isClassTeacher) {
      return Stack(
        children: [
          Positioned.fill(
            child: RefreshIndicator(
              edgeOffset: _heroHeight,
              onRefresh: _refreshAll,
              color: AppTheme.primary,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(top: _heroHeight),
                children: [
          const SizedBox(height: 4),
          TodoReminderBanner(
            userId: teacher?.id ?? teacher?.email ?? '',
            role: 'teacher',
          ),
          if (teacher != null)
            FadeInUp(
              delay: const Duration(milliseconds: 50),
              child: TeacherMorningSummaryCard(
                key: _morningSummaryKey1,
                teacher: teacher!,
              ),
            ),
          FadeInUp(
            delay: const Duration(milliseconds: 120),
            child: _buildSubDutyCard(),
          ),

           _SectionHeader(context.tr('secAcademics')),
           _FeatureTile(
             icon: Icons.book_outlined,
             color: AppTheme.primary,
             title: context.tr('dailyClassDiary'),
             subtitle: 'Log daily teaching activities',
             onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClassDiaryScreen(teacher: teacher!))),
           ),
           const _Divider(),
           _FeatureTile(
             icon: Icons.library_books_outlined,
             color: AppTheme.primary,
             title: context.tr('studyMaterials'),
             subtitle: 'Upload and view classroom resources',
             onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StudyMaterialUploadScreen(teacher: teacher!))),
           ),
            const _Divider(),
            _FeatureTile(
              icon: Icons.list_alt_outlined,
              color: AppTheme.primary,
              title: context.tr('syllabusProgress'),
              subtitle: 'Track syllabus coverage',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SyllabusTrackerScreen(teacher: teacher!))),
            ),
            const _Divider(),
            _FeatureTile(
              icon: Icons.fact_check_outlined,
            color: AppTheme.primary,
            title: context.tr('takeAttendance'),
            subtitle: 'Mark attendance for ${teacher!.classTeacherOf}',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    AttendanceScreen(
                      className: teacher!.classTeacherOf!,
                      section: teacher!.section,
                    ),
              ),
            ),
          ),
          const _Divider(),
          _FeatureTile(
            icon: Icons.calendar_month_outlined,
            color: AppTheme.primary,
            title: context.tr('myTimetable'),
            subtitle: context.tr('subTimetablePersonalDesc'),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(
                    builder: (_) => MyTimetableScreen(teacher: teacher))),
          ),
          const _Divider(),
          _FeatureTile(
            icon: Icons.swap_horiz_outlined,
            color: AppTheme.primary,
            title: context.tr('mySubstitutionDuties'),
            subtitle: context.tr('subSubDutiesDesc'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SubstitutionHistoryScreen(
                  teacherId:   teacher?.id,
                  teacherName: teacher?.name,
                ),
              ),
            ),
          ),

          _SectionHeader(context.tr('secStudents')),
          _FeatureTile(
            icon: Icons.people_outline,
            color: AppTheme.primary,
            title: context.tr('studentList'),
            subtitle:
                'View and manage students in ${teacher!.classTeacherOf}',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StudentListScreen(
                  className: teacher!.classTeacherOf!,
                  section: teacher!.section,
                  isClassTeacher: true,
                  teacherId: teacher!.id,
                  teacherName: teacher!.name,
                  teacherEmail: teacher!.email,
                ),
              ),
            ),
          ),
          const _Divider(),
          _FeatureTile(
            icon: Icons.bar_chart_outlined,
            color: AppTheme.primary,
            title: context.tr('attendanceHistory'),
            subtitle:
                'Monthly reports, % per student & low-attendance flags',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AttendanceHistoryScreen(
                    className: teacher!.classTeacherOf!,
                    section:   teacher!.section),
              ),
            ),
          ),

          const _Divider(),
          _FeatureTile(
            icon: Icons.person_off_outlined,
            color: AppTheme.danger,
            title: context.tr('deletedStudents'),
            subtitle: 'Read-only history of removed students in your class',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DeletedStudentsScreen(
                  classNameFilter: teacher!.classTeacherOf!,
                  sectionFilter:   teacher!.section,
                ),
              ),
            ),
          ),
          const _Divider(),
          _FeatureTile(
            icon: Icons.comment_outlined,
            color: AppTheme.primary,
            title: context.tr('studentRemarks'),
            subtitle: context.tr('subStudentRemarksDesc2'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StudentRemarksScreen(
                  role:             'teacher',
                  teacherClassName: teacher!.classTeacherOf,
                  teacherSection:   teacher!.section,
                  teacherId:        teacher!.id,
                ),
              ),
            ),
          ),
          const _Divider(),
          _FeatureTile(
            icon: Icons.assignment_ind_outlined,
            color: AppTheme.primary,
            title: 'Admission Enquiries',
            subtitle: 'Log prospective students & follow-ups',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdmissionCrmScreen()),
            ),
          ),

          _SectionHeader(context.tr('secCalls')),
          _FeatureTile(
            icon: Icons.phone_callback_outlined,
            color: AppTheme.primary,
            title: context.tr('dailyCalls'),
            subtitle: 'Track guardian calls for absent/leave students',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => DailyCallsScreen(teacher: teacher!)),
            ),
          ),

          _SectionHeader(context.tr('secLeave')),
          _FeatureTile(
            icon: Icons.event_busy_outlined,
            color: AppTheme.warning,
            title: context.tr('applyForLeave'),
            subtitle:
                'Submit a leave application to coordinator or principal',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      LeaveApplicationScreen(teacher: teacher!)),
            ),
          ),
          const _Divider(),
          _FeatureTile(
            icon: Icons.assignment_return_outlined,
            color: AppTheme.accent,
            title: context.tr('studentLeaveRequests'),
            subtitle: context.tr('subStudentLeaveDesc'),
            badge: _pendingStudentLeaves > 0
                ? '$_pendingStudentLeaves'
                : null,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StudentLeaveRequestsScreen(
                  studentClass: teacher!.classTeacherOf!,
                  studentSection: teacher!.section,
                ),
              ),
            ),
          ),

          _SectionHeader(context.tr('secCopyChecking')),
          _FeatureTile(
            icon: Icons.menu_book_outlined,
            color: AppTheme.primary,
            title: context.tr('copyChecking'),
            subtitle: context.tr('subCopyCheckDesc'),
            onTap: () {
              if (teacher != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          CopyCheckingScreen(teacher: teacher!)),
                );
              }
            },
          ),

          _SectionHeader(context.tr('secHomework')),
          _FeatureTile(
            icon: Icons.assignment_outlined,
            color: AppTheme.primary,
            title: context.tr('homework'),
            subtitle: context.tr('subHomeworkDesc'),
            onTap: () {
              if (teacher != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => HomeworkScreen(teacher: teacher!)),
                );
              }
            },
          ),

          _SectionHeader(context.tr('secExamsMarks')),
          _FeatureTile(
            icon: Icons.quiz_outlined,
            color: AppTheme.primary,
            title: context.tr('examsMarks'),
            subtitle: context.tr('subExamsDesc'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => ExamManagementScreen(
                      role: 'teacher',
                      section: teacher!.section,
                      allowedClasses: teacher!.classTeacherOf != null
                          ? [teacher!.classTeacherOf!]
                          : [])),
            ),
          ),

          _SectionHeader(context.tr('secRemarks')),
          _FeatureTile(
            icon: Icons.rate_review_outlined,
            color: AppTheme.primary,
            title: context.tr('myRemarks'),
            subtitle: context.tr('subMyRemarksDesc'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StaffRemarksScreen(
                  role: 'teacher',
                  userEmail: teacher?.email ?? '',
                  userName: teacher?.name ?? '',
                  teacherId: teacher?.id,
                ),
              ),
            ),
          ),

          _SectionHeader(context.tr('secMyTasks')),
          _FeatureTile(
            icon: Icons.task_outlined,
            color: AppTheme.primary,
            title: context.tr('myTasks'),
            subtitle: context.tr('subMyTasksDesc'),
            badge: _pendingTaskCount > 0 ? '$_pendingTaskCount' : null,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        StaffTasksScreen(teacherId: teacher?.id)),
              );
              _loadNotifCount();
            },
          ),
          const _Divider(),
          _FeatureTile(
            icon: Icons.assignment_outlined,
            color: AppTheme.primary,
            title: context.tr('meetingTasks'),
            subtitle: context.tr('subMeetingTasksDesc'),
            badge: _pendingMeetingTasks > 0 ? '$_pendingMeetingTasks' : null,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TeacherMeetingTasksScreen(
                  teacherId:   teacher?.id ?? '',
                  teacherName: teacher?.name ?? '',
                ),
              ),
            ),
          ),

          _SectionHeader(context.tr('secAnnouncements')),
          _FeatureTile(
            icon: Icons.campaign_outlined,
            color: AppTheme.primary,
            title: context.tr('noticeBoard'),
            subtitle: context.tr('subAnnouncementsDesc'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => AnnouncementsScreen(
                      viewerRole: 'class_teacher',
                      posterName: teacher?.email,
                      viewerClasses: <String>{
                        if ((teacher?.classTeacherOf ?? '').isNotEmpty)
                          teacher!.classTeacherOf!,
                        ...?teacher?.assignedClasses,
                      }.toList())),
            ),
          ),

          _SectionHeader(context.tr('secBirthdays')),
          BirthdayBanner(
            role: 'class_teacher',
            className: teacher?.classTeacherOf,
            section: teacher?.section,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => BirthdaysScreen(
                  role: 'class_teacher',
                  className: teacher?.classTeacherOf,
                  section: teacher?.section,
                ),
              ),
            ),
          ),
          _FeatureTile(
            icon: Icons.cake_outlined,
            color: AppTheme.accent,
            title: context.tr('birthdays'),
            subtitle: context.tr('subBirthdaysDesc'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => BirthdaysScreen(
                  role: 'class_teacher',
                  className: teacher?.classTeacherOf,
                  section: teacher?.section,
                ),
              ),
            ),
          ),

          _SectionHeader(context.tr('secMyTodoList')),
          _FeatureTile(
            icon: Icons.checklist_outlined,
            color: AppTheme.primary,
            title: 'My To-Do List',
            subtitle: context.tr('subTodoDesc'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TodoListScreen(
                  userId: teacher?.id ?? teacher?.email ?? '',
                  role: 'teacher',
                ),
              ),
            ),
          ),

          // ── Social Media Links ───────────────────────────────────────
          _SectionHeader(context.tr('socialMediaLinksTitle')),
          _FeatureTile(
            icon: Icons.share_outlined,
            color: AppTheme.primary,
            title: context.tr('socialMediaLinksTitle'),
            subtitle: context.tr('socialMediaSubtitle'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const SocialMediaLinksScreen(),
              ),
            ),
          ),

          const SizedBox(height: 32),
              ],
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _buildHero(),
        ),
      ],
    );
  }

    // Regular teacher
    return Stack(
      children: [
        Positioned.fill(
          child: RefreshIndicator(
            edgeOffset: _heroHeight,
            onRefresh: _refreshAll,
            color: AppTheme.primary,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(top: _heroHeight),
              children: [
        const SizedBox(height: 4),
        TodoReminderBanner(
          userId: teacher?.id ?? teacher?.email ?? '',
          role: 'teacher',
        ),
        if (teacher != null)
          FadeInUp(
            delay: const Duration(milliseconds: 50),
            child: TeacherMorningSummaryCard(
              key: _morningSummaryKey2,
              teacher: teacher!,
            ),
          ),
        FadeInUp(
          delay: const Duration(milliseconds: 120),
          child: _buildSubDutyCard(),
        ),

        _SectionHeader(context.tr('secAcademics')),
        _FeatureTile(
          icon: Icons.book_outlined,
          color: AppTheme.primary,
          title: context.tr('dailyClassDiary'),
          subtitle: 'Log daily teaching activities',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClassDiaryScreen(teacher: teacher!))),
        ),
        const _Divider(),
        _FeatureTile(
          icon: Icons.library_books_outlined,
          color: AppTheme.primary,
          title: context.tr('studyMaterials'),
          subtitle: 'Upload and view classroom resources',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StudyMaterialUploadScreen(teacher: teacher!))),
        ),
        const _Divider(),
        _FeatureTile(
          icon: Icons.list_alt_outlined,
          color: AppTheme.primary,
          title: context.tr('syllabusProgress'),
          subtitle: 'Track syllabus coverage',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SyllabusTrackerScreen(teacher: teacher!))),
        ),
        const _Divider(),
        _FeatureTile(
          icon: Icons.calendar_month_outlined,
          color: AppTheme.primary,
          title: context.tr('myTimetable'),
          subtitle: context.tr('subTimetableAllDesc'),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(
                  builder: (_) => MyTimetableScreen(teacher: teacher))),
        ),
        const _Divider(),
        _FeatureTile(
          icon: Icons.swap_horiz_outlined,
          color: AppTheme.primary,
          title: context.tr('mySubstitutionDuties'),
          subtitle: context.tr('subSubDutiesDesc'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SubstitutionHistoryScreen(
                teacherId:   teacher?.id,
                teacherName: teacher?.name,
              ),
            ),
          ),
        ),

        _SectionHeader(context.tr('secStudents')),
        _FeatureTile(
          icon: Icons.people_outline,
          color: AppTheme.primary,
          title: context.tr('studentList'),
          subtitle: context.tr('subStudentListDesc'),
          onTap: () async {
            final pick = await Navigator.push<ClassSectionPick>(
              context,
              MaterialPageRoute(
                  builder: (_) => ClassPickerScreen(
                      mode: ClassPickerMode.studentList,
                      allowedClasses: teacher?.assignedClasses ?? [])),
            );
            if (pick != null && context.mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => StudentListScreen(
                          className: pick.className,
                          section:    pick.section,
                          isClassTeacher: false,
                          teacherId: teacher?.id,
                          teacherName: teacher?.name ?? '',
                          teacherEmail: teacher?.email ?? '',
                        )),
              );
            }
          },
        ),
        const _Divider(),
        _FeatureTile(
          icon: Icons.comment_outlined,
          color: AppTheme.primary,
          title: context.tr('studentRemarks'),
          subtitle: context.tr('subStudentRemarksDesc'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StudentRemarksScreen(
                role:             'teacher',
                teacherClassName: teacher?.classTeacherOf,
                teacherSection:   teacher?.section,
                teacherId:        teacher?.id,
              ),
            ),
          ),
        ),
        const _Divider(),
        _FeatureTile(
          icon: Icons.assignment_ind_outlined,
          color: AppTheme.primary,
          title: 'Admission Enquiries',
          subtitle: 'Log prospective students & follow-ups',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdmissionCrmScreen()),
          ),
        ),

        _SectionHeader(context.tr('secLeave')),
        _FeatureTile(
          icon: Icons.event_busy_outlined,
          color: AppTheme.warning,
          title: context.tr('applyForLeave'),
          subtitle:
              'Submit a leave application to coordinator or principal',
          onTap: () {
            if (teacher != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        LeaveApplicationScreen(teacher: teacher!)),
              );
            }
          },
        ),

        _SectionHeader(context.tr('secCopyChecking')),
        _FeatureTile(
          icon: Icons.menu_book_outlined,
          color: AppTheme.primary,
          title: context.tr('copyChecking'),
          subtitle: context.tr('subCopyCheckDesc'),
          onTap: () {
            if (teacher != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        CopyCheckingScreen(teacher: teacher!)),
              );
            }
          },
        ),

        _SectionHeader(context.tr('secHomework')),
        _FeatureTile(
          icon: Icons.assignment_outlined,
          color: AppTheme.primary,
          title: context.tr('homework'),
          subtitle: context.tr('subHomeworkDesc'),
          onTap: () {
            if (teacher != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => HomeworkScreen(teacher: teacher!)),
              );
            }
          },
        ),

        _SectionHeader(context.tr('secExamsMarks')),
        _FeatureTile(
          icon: Icons.quiz_outlined,
          color: AppTheme.primary,
          title: context.tr('examsMarks'),
          subtitle: context.tr('subExamsDesc'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => ExamManagementScreen(
                    role: 'teacher',
                    section: teacher?.section ?? '',
                    allowedClasses: teacher?.assignedClasses ?? [])),
          ),
        ),

        _SectionHeader(context.tr('secRemarks')),
        _FeatureTile(
          icon: Icons.rate_review_outlined,
          color: AppTheme.primary,
          title: context.tr('myRemarks'),
          subtitle: context.tr('subMyRemarksDesc'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StaffRemarksScreen(
                role: 'teacher',
                userEmail: teacher?.email ?? '',
                userName: teacher?.name ?? '',
                teacherId: teacher?.id,
              ),
            ),
          ),
        ),

        _SectionHeader(context.tr('secMyTasks')),
        _FeatureTile(
          icon: Icons.task_outlined,
          color: AppTheme.primary,
          title: context.tr('myTasks'),
          subtitle: context.tr('subMyTasksDesc'),
          badge: _pendingTaskCount > 0 ? '$_pendingTaskCount' : null,
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => StaffTasksScreen(teacherId: teacher?.id)),
            );
            _loadNotifCount();
          },
        ),
        const _Divider(),
        _FeatureTile(
          icon: Icons.assignment_outlined,
          color: AppTheme.primary,
          title: context.tr('meetingTasks'),
          subtitle: context.tr('subMeetingTasksDesc'),
          badge: _pendingMeetingTasks > 0 ? '$_pendingMeetingTasks' : null,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TeacherMeetingTasksScreen(
                teacherId:   teacher?.id ?? '',
                teacherName: teacher?.name ?? '',
              ),
            ),
          ),
        ),

        _SectionHeader(context.tr('secAnnouncements')),
        _FeatureTile(
          icon: Icons.campaign_outlined,
          color: AppTheme.primary,
          title: context.tr('noticeBoard'),
          subtitle: context.tr('subAnnouncementsDesc'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => AnnouncementsScreen(
                    viewerRole: 'teacher',
                    posterName: teacher?.email,
                    viewerClasses: <String>{
                      if ((teacher?.classTeacherOf ?? '').isNotEmpty)
                        teacher!.classTeacherOf!,
                      ...?teacher?.assignedClasses,
                    }.toList())),
          ),
        ),

        _SectionHeader(context.tr('secBirthdays')),
        BirthdayBanner(
          role: 'subject_teacher',
          assignedClasses: teacher?.assignedClasses,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BirthdaysScreen(
                role: 'subject_teacher',
                assignedClasses: teacher?.assignedClasses,
              ),
            ),
          ),
        ),
        _FeatureTile(
          icon: Icons.cake_outlined,
          color: AppTheme.accent,
          title: context.tr('birthdays'),
          subtitle: context.tr('subBirthdaysDesc'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BirthdaysScreen(
                role: 'subject_teacher',
                assignedClasses: teacher?.assignedClasses,
              ),
            ),
          ),
        ),

        _SectionHeader(context.tr('secMyTodoList')),
        _FeatureTile(
          icon: Icons.checklist_outlined,
          color: AppTheme.primary,
          title: 'My To-Do List',
          subtitle: context.tr('subTodoDesc'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TodoListScreen(
                userId: teacher?.id ?? teacher?.email ?? '',
                role: 'teacher',
              ),
            ),
          ),
        ),

        // ── Social Media Links ───────────────────────────────────────
        _SectionHeader(context.tr('socialMediaLinksTitle')),
        _FeatureTile(
          icon: Icons.share_outlined,
          color: AppTheme.primary,
          title: context.tr('socialMediaLinksTitle'),
          subtitle: context.tr('socialMediaSubtitle'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const SocialMediaLinksScreen(),
            ),
          ),
        ),

        const SizedBox(height: 32),
            ],
        ),
      ),
    ),
    Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: _buildHero(),
      ),
    ],
  );
  }

  // ── Substitute duty card ──────────────────────────────────────────────────

  Widget _buildSubDutyCard() {
    final tid = widget.teacher?.id ?? '';
    if (tid.isEmpty) return const SizedBox.shrink();

    final now      = DateTime.now();
    final todayKey = '${now.year}-${now.month}-${now.day}';

    return StreamBuilder<DocumentSnapshot>(
      stream: SubstitutionHistoryService().streamSubstitutions(todayKey),
      builder: (context, snap) {
        // Optional inline banner — single-doc read, stay hidden on any error
        // rather than intruding.
        if (snap.hasError) {
          return const SizedBox.shrink();
        }
        if (!snap.hasData || !snap.data!.exists) return const SizedBox.shrink();

        final data = snap.data!.data() as Map<String, dynamic>;
        final duties = <_SubDutyItem>[];

        data.forEach((key, value) {
          if (value != tid) return;
          final lastUs = key.lastIndexOf('_');
          if (lastUs <= 0) return;
          final className = key.substring(0, lastUs);
          final bell = int.tryParse(key.substring(lastUs + 1));
          if (bell != null) duties.add(_SubDutyItem(className, bell));
        });

        if (duties.isEmpty) return const SizedBox.shrink();
        duties.sort((a, b) => a.bell.compareTo(b.bell));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(context.tr('secSubstituteDutyToday')),
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppTheme.warning, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.swap_horiz_outlined,
                        color: AppTheme.warning, size: 20),
                    const SizedBox(width: 8),
                    Text(context.tr('substituteDutyToday'),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                  ]),
                  const SizedBox(height: 10),
                  for (final duty in duties)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(children: [
                        Container(
                          width: 28, height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppTheme.warning,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('${duty.bell}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12)),
                        ),
                        const SizedBox(width: 10),
                        Text(duty.className,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                      ]),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Substitute duty item ──────────────────────────────────────────────────────

class _SubDutyItem {
  final String className;
  final int    bell;
  _SubDutyItem(this.className, this.bell);
}

// ── Wave clipper ──────────────────────────────────────────────────────────────

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

// ── Hero info cell ────────────────────────────────────────────────────────────

class _HeroInfo extends StatelessWidget {
  final String label, value;
  final bool highlight;
  const _HeroInfo(
      {required this.label, required this.value, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: highlight
                      ? AppTheme.alertHighlight
                      : Colors.white,
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

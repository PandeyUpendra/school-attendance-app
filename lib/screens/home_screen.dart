import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../models/teacher.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/staff_task_service.dart';
import '../services/timetable_service.dart';
import 'attendance_screen.dart';
import 'student_list_screen.dart';
import 'my_timetable_screen.dart';
import 'role_selection_screen.dart';
import 'class_picker_screen.dart';
import 'leave_application_screen.dart';
import 'daily_calls_screen.dart';
import 'attendance_history_screen.dart';
import 'announcements_screen.dart';
import 'notifications_screen.dart';
import 'exam_management_screen.dart';
import 'copy_checking_screen.dart';
import 'homework_screen.dart';
import 'substitution_history_screen.dart';
import 'student_remarks_screen.dart';
import 'tasks/unified_staff_task_screen.dart';
import 'meeting/teacher_meeting_tasks_screen.dart';
import '../services/meeting_service.dart';
import 'birthdays/birthdays_screen.dart';

class HomeScreen extends StatefulWidget {
  final Teacher? teacher;
  const HomeScreen({super.key, this.teacher});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _unreadNotifCount   = 0;
  int _pendingTaskCount   = 0;
  int _pendingMeetingTasks = 0;

  StreamSubscription? _notifSub;
  StreamSubscription? _taskSub;
  StreamSubscription? _meetingTaskSub;
  int _lastSeenMs = 0;
  List<Map<String, dynamic>> _latestNotifs = [];

  @override
  void initState() {
    super.initState();
    _initStreams();
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    _taskSub?.cancel();
    _meetingTaskSub?.cancel();
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
          .listen((count) {
        if (!mounted) return;
        setState(() => _pendingTaskCount = count);
      });
      _meetingTaskSub = MeetingService()
          .streamPendingTaskCountForTeacher(tid)
          .listen((count) {
        if (!mounted) return;
        setState(() => _pendingMeetingTasks = count);
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

  @override
  Widget build(BuildContext context) {
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

    return ClipPath(
      clipper: _WaveClipper(),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.primaryDark, AppTheme.primaryMid],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 8, 52),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                  // Logout
                  IconButton(
                    icon: const Icon(Icons.logout,
                        color: Colors.white70, size: 20),
                    tooltip: 'Logout',
                    onPressed: () async {
                      await AuthService().clearSession();
                      if (context.mounted) {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  const RoleSelectionScreen()),
                        );
                      }
                    },
                  ),
                ]),

                const SizedBox(height: 6),

                // ── Teacher name ─────────────────────────────────────────
                Text(
                  t?.name ?? 'School App',
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
                      color: Colors.white.withOpacity(0.13),
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

  void _showAddGuardianSheet(BuildContext context) {
    final emailCtrl = TextEditingController();
    final rollCtrl  = TextEditingController();
    final classCtrl = TextEditingController(
        text: _isClassTeacher ? (teacher!.classTeacherOf ?? '') : '');
    bool saving = false;
    String? sheetError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.family_restroom_outlined,
                        color: AppTheme.primary, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Add Guardian Account',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx)),
                ]),
                const SizedBox(height: 4),
                const Text(
                  'Creates a guardian login linked to a student. Default password: Parent@123',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  maxLength: 100,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  decoration: InputDecoration(
                    labelText: 'Guardian Email',
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    isDense: true,
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: classCtrl,
                  readOnly: _isClassTeacher,
                  maxLength: 20,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  decoration: InputDecoration(
                    labelText: 'Student Class',
                    prefixIcon: const Icon(Icons.class_outlined),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    isDense: true,
                    counterText: '',
                    filled: _isClassTeacher,
                    fillColor:
                        _isClassTeacher ? Colors.grey.shade100 : null,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: rollCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  decoration: InputDecoration(
                    labelText: 'Student Roll Number',
                    prefixIcon: const Icon(Icons.tag_outlined),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    isDense: true,
                    counterText: '',
                  ),
                ),
                if (sheetError != null) ...[
                  const SizedBox(height: 8),
                  Text(sheetError!,
                      style: const TextStyle(
                          color: Colors.red, fontSize: 12)),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.person_add_outlined),
                    label: Text(saving ? 'Adding…' : 'Add Guardian'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: saving
                        ? null
                        : () async {
                            final email =
                                emailCtrl.text.trim().toLowerCase();
                            final cls = classCtrl.text.trim();
                            final roll =
                                int.tryParse(rollCtrl.text.trim());

                            if (email.isEmpty ||
                                !RegExp(r'^[^@]+@[^@]+\.[^@]+$')
                                    .hasMatch(email)) {
                              setInner(
                                  () => sheetError = 'Enter a valid email');
                              return;
                            }
                            if (cls.isEmpty) {
                              setInner(() =>
                                  sheetError = 'Enter the student class');
                              return;
                            }
                            if (roll == null || roll <= 0) {
                              setInner(() =>
                                  sheetError = 'Enter a valid roll number');
                              return;
                            }
                            setInner(() {
                              saving = true;
                              sheetError = null;
                            });
                            try {
                              await TimetableService().addAllowedUser(
                                email,
                                'Parent@123',
                                'guardian',
                                studentClass: cls,
                                studentRoll: roll,
                                createdByEmail: teacher?.email ?? '',
                                createdByRole: 'teacher',
                              );
                              if (ctx.mounted) {
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(
                                  content: Text(
                                      'Guardian $email added (password: Parent@123)'),
                                  backgroundColor: AppTheme.success,
                                  duration: const Duration(seconds: 3),
                                ));
                              }
                            } catch (e) {
                              if (ctx.mounted) {
                                setInner(() {
                                  saving = false;
                                  sheetError = 'Error: $e';
                                });
                              }
                            }
                          },
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isClassTeacher) {
      return Column(
        children: [
          _buildHero(),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
          const SizedBox(height: 4),
          _buildSubDutyCard(),

          _SectionHeader('ACADEMICS'),
          _FeatureTile(
            icon: Icons.fact_check_outlined,
            color: AppTheme.primary,
            title: 'Take Attendance',
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
            title: 'My Timetable',
            subtitle: 'View your personal bell schedule',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(
                    builder: (_) => MyTimetableScreen(teacher: teacher))),
          ),
          const _Divider(),
          _FeatureTile(
            icon: Icons.swap_horiz_outlined,
            color: AppTheme.primary,
            title: 'My Substitution Duties',
            subtitle: 'Classes I have covered as substitute',
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

          _SectionHeader('STUDENTS'),
          _FeatureTile(
            icon: Icons.people_outline,
            color: AppTheme.primary,
            title: 'Student List',
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
                ),
              ),
            ),
          ),
          const _Divider(),
          _FeatureTile(
            icon: Icons.bar_chart_outlined,
            color: AppTheme.primary,
            title: 'Attendance History',
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
            icon: Icons.comment_outlined,
            color: AppTheme.primary,
            title: 'Student Remarks',
            subtitle: 'Record observations and feedback for your students',
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

          _SectionHeader('CALLS'),
          _FeatureTile(
            icon: Icons.phone_callback_outlined,
            color: AppTheme.primary,
            title: 'Daily Calls',
            subtitle: 'Track guardian calls for absent/leave students',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => DailyCallsScreen(teacher: teacher!)),
            ),
          ),

          _SectionHeader('LEAVE'),
          _FeatureTile(
            icon: Icons.event_busy_outlined,
            color: AppTheme.warning,
            title: 'Apply for Leave',
            subtitle:
                'Submit a leave application to coordinator or principal',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      LeaveApplicationScreen(teacher: teacher!)),
            ),
          ),

          _SectionHeader('COPY CHECKING'),
          _FeatureTile(
            icon: Icons.menu_book_outlined,
            color: AppTheme.primary,
            title: 'Copy Checking',
            subtitle: 'Mark student copies for your classes',
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

          _SectionHeader('HOMEWORK'),
          _FeatureTile(
            icon: Icons.assignment_outlined,
            color: AppTheme.primary,
            title: 'Homework',
            subtitle: 'Post and manage assignments for your classes',
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

          _SectionHeader('EXAMS & MARKS'),
          _FeatureTile(
            icon: Icons.quiz_outlined,
            color: AppTheme.primary,
            title: 'Exams & Marks',
            subtitle: 'Enter marks and view report cards',
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

          _SectionHeader('MY TASKS'),
          _FeatureTile(
            icon: Icons.task_outlined,
            color: AppTheme.primary,
            title: 'My Tasks',
            subtitle: 'View tasks assigned to you',
            badge: _pendingTaskCount > 0 ? '$_pendingTaskCount' : null,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        UnifiedStaffTaskScreen(
                          role: 'teacher',
                          userEmail: teacher?.email ?? '',
                          teacherId: teacher?.id,
                          userName: teacher?.name ?? '',
                        )),
              );
              _loadNotifCount();
            },
          ),
          const _Divider(),
          _FeatureTile(
            icon: Icons.assignment_outlined,
            color: AppTheme.primary,
            title: 'Meeting Tasks',
            subtitle: 'Tasks assigned to you from staff meetings',
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

          _SectionHeader('ANNOUNCEMENTS'),
          _FeatureTile(
            icon: Icons.campaign_outlined,
            color: AppTheme.primary,
            title: 'Notice Board',
            subtitle: 'Post and view school announcements',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => AnnouncementsScreen(
                      viewerRole: 'class_teacher',
                      posterName: teacher?.email)),
            ),
          ),

          _SectionHeader('GUARDIANS'),
          _FeatureTile(
            icon: Icons.family_restroom_outlined,
            color: AppTheme.primary,
            title: 'Add Guardian',
            subtitle: 'Create a guardian login linked to a student',
            onTap: () => _showAddGuardianSheet(context),
          ),

          _SectionHeader('BIRTHDAYS'),
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
            title: 'Birthdays',
            subtitle: 'Staff and student birthday wishes',
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

          const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      );
    }

    // Regular teacher
    return Column(
      children: [
        _buildHero(),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
        const SizedBox(height: 4),
        _buildSubDutyCard(),

        _SectionHeader('ACADEMICS'),
        _FeatureTile(
          icon: Icons.calendar_month_outlined,
          color: AppTheme.primary,
          title: 'My Timetable',
          subtitle: 'View your bell schedule for all classes',
          onTap: () => Navigator.push(context,
              MaterialPageRoute(
                  builder: (_) => MyTimetableScreen(teacher: teacher))),
        ),
        const _Divider(),
        _FeatureTile(
          icon: Icons.swap_horiz_outlined,
          color: AppTheme.primary,
          title: 'My Substitution Duties',
          subtitle: 'Classes I have covered as substitute',
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

        _SectionHeader('STUDENTS'),
        _FeatureTile(
          icon: Icons.people_outline,
          color: AppTheme.primary,
          title: 'Student List',
          subtitle: 'View student records by class',
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
                        )),
              );
            }
          },
        ),
        const _Divider(),
        _FeatureTile(
          icon: Icons.comment_outlined,
          color: AppTheme.primary,
          title: 'Student Remarks',
          subtitle: 'Record observations and feedback for students',
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

        _SectionHeader('LEAVE'),
        _FeatureTile(
          icon: Icons.event_busy_outlined,
          color: AppTheme.warning,
          title: 'Apply for Leave',
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

        _SectionHeader('COPY CHECKING'),
        _FeatureTile(
          icon: Icons.menu_book_outlined,
          color: AppTheme.primary,
          title: 'Copy Checking',
          subtitle: 'Mark student copies for your classes',
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

        _SectionHeader('HOMEWORK'),
        _FeatureTile(
          icon: Icons.assignment_outlined,
          color: AppTheme.primary,
          title: 'Homework',
          subtitle: 'Post and manage assignments for your classes',
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

        _SectionHeader('EXAMS & MARKS'),
        _FeatureTile(
          icon: Icons.quiz_outlined,
          color: AppTheme.primary,
          title: 'Exams & Marks',
          subtitle: 'Enter marks and view report cards',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => ExamManagementScreen(
                    role: 'teacher',
                    section: teacher?.section ?? '',
                    allowedClasses: teacher?.assignedClasses ?? [])),
          ),
        ),

        _SectionHeader('MY TASKS'),
        _FeatureTile(
          icon: Icons.task_outlined,
          color: AppTheme.primary,
          title: 'My Tasks',
          subtitle: 'View tasks assigned to you',
          badge: _pendingTaskCount > 0 ? '$_pendingTaskCount' : null,
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => UnifiedStaffTaskScreen(
                          role: 'teacher',
                          userEmail: teacher?.email ?? '',
                          teacherId: teacher?.id,
                          userName: teacher?.name ?? '',
                        )),
            );
            _loadNotifCount();
          },
        ),
        const _Divider(),
        _FeatureTile(
          icon: Icons.assignment_outlined,
          color: AppTheme.primary,
          title: 'Meeting Tasks',
          subtitle: 'Tasks assigned to you from staff meetings',
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

        _SectionHeader('ANNOUNCEMENTS'),
        _FeatureTile(
          icon: Icons.campaign_outlined,
          color: AppTheme.primary,
          title: 'Notice Board',
          subtitle: 'Post and view school announcements',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => AnnouncementsScreen(
                    viewerRole: 'teacher',
                    posterName: teacher?.email)),
          ),
        ),

        _SectionHeader('GUARDIANS'),
        _FeatureTile(
          icon: Icons.family_restroom_outlined,
          color: AppTheme.primary,
          title: 'Add Guardian',
          subtitle: 'Create a guardian login linked to a student',
          onTap: () => _showAddGuardianSheet(context),
        ),

        _SectionHeader('BIRTHDAYS'),
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
          title: 'Birthdays',
          subtitle: 'Staff and student birthday wishes',
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

        const SizedBox(height: 32),
            ],
          ),
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
      stream: FirebaseFirestore.instance
          .collection('substitutions')
          .doc(todayKey)
          .snapshots(),
      builder: (context, snap) {
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
            const _SectionHeader('SUBSTITUTE DUTY TODAY'),
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
                    const Text('Substitute Duty Today',
                        style: TextStyle(
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
                        color: AppTheme.warning.withOpacity(0.08),
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
                      ? const Color(0xFFF48FB1)
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
                color: color.withOpacity(0.12),
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

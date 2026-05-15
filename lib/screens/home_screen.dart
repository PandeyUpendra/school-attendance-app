import 'package:flutter/material.dart';
import '../theme.dart';
import '../models/teacher.dart';
import '../models/copy_check.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/copy_check_service.dart';
import 'attendance_screen.dart';
import 'student_list_screen.dart';
import 'my_timetable_screen.dart';
import 'role_selection_screen.dart';
import 'class_picker_screen.dart';
import 'leave_application_screen.dart';
import 'daily_calls_screen.dart';
import 'attendance_history_screen.dart';
import 'attendance_report_screen.dart';
import 'announcements_screen.dart';
import 'notifications_screen.dart';
import 'calendar_screen.dart';
import 'exam_management_screen.dart';
import 'copy_checking_screen.dart';
import 'homework_screen.dart';
import 'substitution_history_screen.dart';
import 'student_remarks_screen.dart';
import 'guardian_details_list_screen.dart';
import 'tasks/staff_task_management_screen.dart';
import 'teacher_tasks_screen.dart';
import 'leaderboard_screen.dart';
import 'create_account_sheet.dart';
import '../services/timetable_service.dart';

class HomeScreen extends StatefulWidget {
  final Teacher? teacher;
  const HomeScreen({super.key, this.teacher});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _unreadNotifCount = 0;

  @override
  void initState() {
    super.initState();
    _loadNotifCount();
  }

  Future<void> _loadNotifCount() async {
    final session = await AuthService().getSession();
    final email = session?['email'];
    final sId   = widget.teacher?.schoolId ?? session?['schoolId'] ?? 'default_school';
    final count = await NotificationService().unreadCount(
      schoolId:  sId,
      role:      'teacher',
      teacherId: widget.teacher?.id,
      userEmail: email,
    );
    if (mounted) setState(() => _unreadNotifCount = count);
  }

  Future<void> _showCreateGuardianSheet() async {
    final session  = await AuthService().getSession();
    final schoolId = widget.teacher?.schoolId
        ?? (session?['schoolId'] as String?)
        ?? 'default_school';
    final settings = await TimetableService().getSettings(schoolId: schoolId);
    final classes  = List<String>.from(settings['classes'] as List? ?? []);
    if (!mounted) return;
    final created = await showCreateAccountSheet(
      context,
      targetRole: 'guardian',
      schoolId: schoolId,
      availableClasses: classes,
      defaultClass: widget.teacher?.classTeacherOf,
    );
    if (created && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Guardian account created successfully'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: _buildBody(context),
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
            colors: [AppTheme.primaryDark, Color(0xFF880E4F)],
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

  Widget _buildBody(BuildContext context) {
    if (_isClassTeacher) {
      return ListView(
        children: [
          _buildHero(),
          const SizedBox(height: 4),

          // ── ATTENDANCE ────────────────────────────────────────────────
          const _SectionHeader('ATTENDANCE'),
          _FeatureTile(
            icon: Icons.fact_check_outlined,
            color: AppTheme.primary,
            title: 'Take Attendance',
            subtitle: 'Mark daily attendance for students',
            onTap: () {
              // Direct navigation for class teacher to their own class.
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AttendanceScreen(
                    schoolId: teacher!.schoolId,
                    className: teacher!.classTeacherOf!,
                    section: teacher!.section,
                  ),
                ),
              );
            },
          ),
          const _Divider(),
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
          _FeatureTile(
            icon: Icons.assessment_outlined,
            color: AppTheme.primary,
            title: 'Attendance Summary & Edit',
            subtitle: 'Weekly/Monthly summaries and edit past attendance',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AttendanceReportScreen(
                  schoolId:  teacher!.schoolId,
                  className: teacher!.classTeacherOf!,
                  section: teacher!.section,
                ),
              ),
            ),
          ),

          // ── ACADEMICS ─────────────────────────────────────────────────
          const _SectionHeader('ACADEMICS'),
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
          const _Divider(),
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
          const _Divider(),
          _FeatureTile(
            icon: Icons.quiz_outlined,
            color: AppTheme.primary,
            title: 'Exams & Marks',
            subtitle: 'Enter marks and view report cards',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      ExamManagementScreen(role: 'teacher', section: teacher!.section)),
            ),
          ),

          // ── STUDENTS ──────────────────────────────────────────────────
          const _SectionHeader('STUDENTS'),
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
            icon: Icons.badge_outlined,
            color: AppTheme.primary,
            title: 'Details by Guardian',
            subtitle: 'View student information provided by parents',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GuardianDetailsListScreen(
                  className: teacher!.classTeacherOf!,
                  section: teacher!.section,
                  teacherId: teacher!.id,
                ),
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

          const _Divider(),
          _FeatureTile(
            icon: Icons.leaderboard_outlined,
            color: AppTheme.primary,
            title: 'Class Leaderboard',
            subtitle: 'Rankings for academics, attendance, discipline & more',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LeaderboardScreen(
                    className: teacher!.classTeacherOf!,
                    section:   teacher!.section,
                    schoolId:  teacher!.schoolId,
                  ),
                ),
              );
            },
          ),
          const _Divider(),
          _FeatureTile(
            icon: Icons.family_restroom_outlined,
            color: AppTheme.primary,
            title: 'Create Guardian Account',
            subtitle: 'Set up a parent/guardian login for a student',
            onTap: _showCreateGuardianSheet,
          ),

          // ── DUTIES & TASKS ────────────────────────────────────────────
          const _SectionHeader('DUTIES & TASKS'),
          _FeatureTile(
            icon: Icons.assignment_outlined,
            color: AppTheme.primary,
            title: 'Staff Tasks',
            subtitle: 'View tasks from leadership & manage personal to-do',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StaffTaskManagementScreen()),
            ),
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
          const _Divider(),
          _FeatureTile(
            icon: Icons.task_outlined,
            color: AppTheme.primary,
            title: 'Tasks',
            subtitle: 'View and mark tasks from coordinator/principal',
            onTap: () {
              if (teacher != null && teacher!.classTeacherOf != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TeacherTasksScreen(
                      className: teacher!.classTeacherOf!,
                      section: teacher!.section,
                    ),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Only class teachers can access tasks for now')),
                );
              }
            },
          ),
          const _Divider(),
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

          // ── COMMUNICATION ─────────────────────────────────────────────
          const _SectionHeader('COMMUNICATION'),
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
                      posterName: teacher?.email,
                      viewerClass: teacher?.classTeacherOf)),
            ),
          ),
          const _Divider(),
          _FeatureTile(
            icon: Icons.calendar_month_outlined,
            color: AppTheme.primary,
            title: 'School Calendar',
            subtitle: 'View holidays and school events',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const CalendarScreen(userRole: 'teacher'),
              ),
            ),
          ),
          const _Divider(),
          _FeatureTile(
            icon: Icons.privacy_tip_outlined,
            color: Colors.grey,
            title: 'Privacy Policy',
            subtitle: 'How we protect your data',
            onTap: () => _showPrivacyPolicy(context),
          ),
          const SizedBox(height: 32),
        ],
      );
    }

    // Regular teacher
    return ListView(
      children: [
        _buildHero(),
        const SizedBox(height: 4),

        // ── ACADEMICS ─────────────────────────────────────────────────
        const _SectionHeader('ACADEMICS'),
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
        const _Divider(),
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
        const _Divider(),
        _FeatureTile(
          icon: Icons.quiz_outlined,
          color: AppTheme.primary,
          title: 'Exams & Marks',
          subtitle: 'Enter marks and view report cards',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    ExamManagementScreen(role: 'teacher', section: teacher?.section ?? '')),
          ),
        ),

        // ── STUDENTS ──────────────────────────────────────────────────
        const _SectionHeader('STUDENTS'),
        _FeatureTile(
          icon: Icons.people_outline,
          color: AppTheme.primary,
          title: 'Student List',
          subtitle: 'View student records by class',
          onTap: () async {
            final pick = await Navigator.push<ClassSectionPick>(
              context,
              MaterialPageRoute(
                  builder: (_) => const ClassPickerScreen(
                      mode: ClassPickerMode.studentList)),
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
        const _Divider(),
        _FeatureTile(
          icon: Icons.family_restroom_outlined,
          color: AppTheme.primary,
          title: 'Create Guardian Account',
          subtitle: 'Set up a parent/guardian login for a student',
          onTap: _showCreateGuardianSheet,
        ),

        // ── DUTIES & TASKS ────────────────────────────────────────────
        const _SectionHeader('DUTIES & TASKS'),
        _FeatureTile(
          icon: Icons.assignment_outlined,
          color: AppTheme.primary,
          title: 'Staff Tasks',
          subtitle: 'View tasks from leadership & manage personal to-do',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const StaffTaskManagementScreen()),
          ),
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
        const _Divider(),
        _FeatureTile(
          icon: Icons.task_outlined,
          color: AppTheme.primary,
          title: 'Tasks',
          subtitle: 'View and mark tasks from coordinator/principal',
          onTap: () async {
            final pick = await Navigator.push<ClassSectionPick>(
              context,
              MaterialPageRoute(
                  builder: (_) => const ClassPickerScreen(
                      mode: ClassPickerMode.studentList)),
            );
            if (pick != null && context.mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TeacherTasksScreen(
                    className: pick.className,
                    section: pick.section,
                  ),
                ),
              );
            }
          },
        ),
        const _Divider(),
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

        // ── COMMUNICATION ─────────────────────────────────────────────
        const _SectionHeader('COMMUNICATION'),
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
                    posterName: teacher?.email,
                    viewerClass: teacher?.classTeacherOf)),
          ),
        ),
        const _Divider(),
        _FeatureTile(
          icon: Icons.calendar_month_outlined,
          color: AppTheme.primary,
          title: 'School Calendar',
          subtitle: 'View holidays and school events',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const CalendarScreen(userRole: 'teacher'),
            ),
          ),
        ),
        const _Divider(),
        _FeatureTile(
          icon: Icons.privacy_tip_outlined,
          color: Colors.grey,
          title: 'Privacy Policy',
          subtitle: 'How we protect your data',
          onTap: () => _showPrivacyPolicy(context),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  void _showPrivacyPolicy(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Privacy Policy'),
        content: const SingleChildScrollView(
          child: Text(
            'This School App is committed to protecting your privacy. '
            'We collect minimal data required for school operations, including '
            'attendance, marks, and communication. Your data is never shared '
            'with third parties without consent.\n\n'
            'For full details, please visit: https://example.com/privacy', // TODO: Update with real link
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }
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

// ── Cascading Attendance Dialog ──────────────────────────────────────────────

class _CascadingAttendanceDialog extends StatefulWidget {
  final Teacher teacher;
  const _CascadingAttendanceDialog({required this.teacher});

  @override
  State<_CascadingAttendanceDialog> createState() => _CascadingAttendanceDialogState();
}

class _CascadingAttendanceDialogState extends State<_CascadingAttendanceDialog> {
  bool _loading = true;
  List<TeacherAssignment> _assignments = [];
  String? _selectedClass;
  String? _selectedSection;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final assignments = await CopyCheckService().getTeacherAssignments(widget.teacher.id);
    if (!mounted) return;
    
    // For attendance, we also want to include the teacher's own class if they are a class teacher,
    // even if it's not explicitly in the subject timetable (though it usually is).
    if (widget.teacher.isClassTeacher && widget.teacher.classTeacherOf != null) {
      final ownClass = widget.teacher.classTeacherOf!;
      final ownSection = widget.teacher.section;
      bool exists = assignments.any((a) => a.className == ownClass && a.section == ownSection);
      if (!exists) {
        assignments.add(TeacherAssignment(className: ownClass, section: ownSection, subject: 'Class Teacher'));
      }
    }

    setState(() {
      _assignments = assignments;
      _loading = false;
      
      final classes = _classes;
      if (classes.isNotEmpty) {
        _selectedClass = classes.first;
        final sects = _sections;
        if (sects.contains(widget.teacher.section)) {
          _selectedSection = widget.teacher.section;
        } else if (sects.isNotEmpty) {
          _selectedSection = sects.first;
        }
      }
    });
  }

  List<String> get _classes => _assignments.map((a) => a.className).toSet().toList()..sort();
  List<String> get _sections => _selectedClass == null 
      ? [] 
      : _assignments.where((a) => a.className == _selectedClass).map((a) => a.section).toSet().toList()..sort();

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Take Attendance', style: TextStyle(fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Select Class', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _selectedClass,
            isExpanded: true,
            decoration: _inputDeco(),
            items: _classes.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (val) {
              setState(() {
                _selectedClass = val;
                _selectedSection = null;
                final sects = _sections;
                if (sects.isNotEmpty) {
                  _selectedSection = sects.contains(widget.teacher.section) ? widget.teacher.section : sects.first;
                }
              });
            },
          ),
          const SizedBox(height: 16),
          const Text('Select Section', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _selectedSection,
            isExpanded: true,
            decoration: _inputDeco(enabled: _selectedClass != null),
            items: _sections.map((s) => DropdownMenuItem(value: s, child: Text(s.isEmpty ? 'General' : 'Section $s'))).toList(),
            onChanged: _selectedClass == null ? null : (val) => setState(() => _selectedSection = val),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
        ElevatedButton(
          onPressed: _selectedSection == null ? null : () {
            Navigator.pop(context, ClassSectionPick(_selectedClass!, section: _selectedSection!));
          },
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
          child: const Text('PROCEED'),
        ),
      ],
    );
  }

  InputDecoration _inputDeco({bool enabled = true}) => InputDecoration(
    filled: true,
    fillColor: enabled ? Colors.white : Colors.grey.shade100,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
  );
}

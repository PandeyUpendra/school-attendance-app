import 'package:flutter/material.dart';
import '../models/teacher.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
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
    final count = await NotificationService().unreadCount(
      role:      'teacher',
      teacherId: widget.teacher?.id,
    );
    if (mounted) setState(() => _unreadNotifCount = count);
  }

  @override
  Widget build(BuildContext context) {
    final teacher = widget.teacher;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(teacher?.name ?? 'School App',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            Text(
                teacher != null
                    ? (teacher.isClassTeacher
                        ? [
                            'Class Teacher',
                            if (teacher.classTeacherOf != null)
                              teacher.classTeacherOf!,
                          ].join('  •  ')
                        : 'Teacher  •  ${teacher.subject}')
                    : 'Teacher',
                style:
                    const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                tooltip: 'Notifications',
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NotificationsScreen(
                        role:      'teacher',
                        teacherId: teacher?.id,
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
                      color: Colors.red, shape: BoxShape.circle),
                    child: Center(
                      child: Text(
                        _unreadNotifCount > 9 ? '9+' : '$_unreadNotifCount',
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
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
              await AuthService().clearSession();
              if (context.mounted) {
                Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const RoleSelectionScreen()));
              }
            },
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Teacher? get teacher => widget.teacher;

  bool get _isClassTeacher =>
      teacher?.isClassTeacher == true && teacher?.classTeacherOf != null;

  Widget _buildBody(BuildContext context) {
    if (_isClassTeacher) {
      // Change 1 & 4: Class teacher gets Attendance + My Timetable + Students
      return ListView(
        children: [
          _SectionHeader('ACADEMICS'),
          _FeatureTile(
            icon: Icons.fact_check_outlined,
            color: Colors.red,
            title: 'Take Attendance',
            subtitle: 'Mark attendance for ${teacher!.classTeacherOf}',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    AttendanceScreen(className: teacher!.classTeacherOf!),
              ),
            ),
          ),
          const _Divider(),
          _FeatureTile(
            icon: Icons.calendar_month_outlined,
            color: Colors.indigo,
            title: 'My Timetable',
            subtitle: 'View your personal bell schedule',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(
                    builder: (_) => MyTimetableScreen(teacher: teacher))),
          ),
          const _Divider(),
          _FeatureTile(
            icon: Icons.swap_horiz_outlined,
            color: Colors.teal,
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
            color: Colors.teal,
            title: 'Student List',
            subtitle: 'View and manage students in ${teacher!.classTeacherOf}',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StudentListScreen(
                  className: teacher!.classTeacherOf!,
                  isClassTeacher: true,
                ),
              ),
            ),
          ),
          const _Divider(),
          _FeatureTile(
            icon: Icons.bar_chart_outlined,
            color: Colors.indigo,
            title: 'Attendance History',
            subtitle: 'Monthly reports, % per student & low-attendance flags',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AttendanceHistoryScreen(
                    className: teacher!.classTeacherOf!),
              ),
            ),
          ),

          _SectionHeader('CALLS'),
          _FeatureTile(
            icon: Icons.phone_callback_outlined,
            color: Colors.teal,
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
            color: Colors.orange,
            title: 'Apply for Leave',
            subtitle: 'Submit a leave application to coordinator or principal',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => LeaveApplicationScreen(teacher: teacher!)),
            ),
          ),

          _SectionHeader('COPY CHECKING'),
          _FeatureTile(
            icon: Icons.menu_book_outlined,
            color: Colors.indigo,
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
            color: Colors.teal,
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
            color: Colors.deepPurple,
            title: 'Exams & Marks',
            subtitle: 'Enter marks and view report cards',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      const ExamManagementScreen(role: 'teacher')),
            ),
          ),

          _SectionHeader('ANNOUNCEMENTS'),
          _FeatureTile(
            icon: Icons.campaign_outlined,
            color: Colors.deepOrange,
            title: 'Notice Board',
            subtitle: 'View school announcements and notices',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const AnnouncementsScreen(
                      viewerRole: 'teacher')),
            ),
          ),

          const SizedBox(height: 32),
        ],
      );
    }

    // Change 1: Regular teacher — NO Take Attendance (only class teachers can)
    return ListView(
      children: [
        _SectionHeader('ACADEMICS'),
        _FeatureTile(
          icon: Icons.calendar_month_outlined,
          color: Colors.indigo,
          title: 'My Timetable',
          subtitle: 'View your bell schedule for all classes',
          onTap: () => Navigator.push(context,
              MaterialPageRoute(
                  builder: (_) => MyTimetableScreen(teacher: teacher))),
        ),
        const _Divider(),
        _FeatureTile(
          icon: Icons.swap_horiz_outlined,
          color: Colors.teal,
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

        // ── Students ──────────────────────────────────────────────────────
        _SectionHeader('STUDENTS'),
        _FeatureTile(
          icon: Icons.people_outline,
          color: Colors.teal,
          title: 'Student List',
          subtitle: 'View student records by class',
          onTap: () async {
            final cls = await Navigator.push<String>(
              context,
              MaterialPageRoute(
                  builder: (_) => const ClassPickerScreen(
                      mode: ClassPickerMode.studentList)),
            );
            if (cls != null && context.mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => StudentListScreen(
                          className: cls,
                          isClassTeacher: false,
                        )),
              );
            }
          },
        ),

        // ── Leave ─────────────────────────────────────────────────────────
        _SectionHeader('LEAVE'),
        _FeatureTile(
          icon: Icons.event_busy_outlined,
          color: Colors.orange,
          title: 'Apply for Leave',
          subtitle: 'Submit a leave application to coordinator or principal',
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
          color: Colors.indigo,
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
          color: Colors.teal,
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
          color: Colors.deepPurple,
          title: 'Exams & Marks',
          subtitle: 'Enter marks and view report cards',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    const ExamManagementScreen(role: 'teacher')),
          ),
        ),

        _SectionHeader('ANNOUNCEMENTS'),
        _FeatureTile(
          icon: Icons.campaign_outlined,
          color: Colors.deepOrange,
          title: 'Notice Board',
          subtitle: 'View school announcements and notices',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const AnnouncementsScreen(
                    viewerRole: 'teacher')),
          ),
        ),

        const SizedBox(height: 32),
      ],
    );
  }
}

// ── Shared widgets ─────────────────────────────────────────────────────────────

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
      child: Padding(
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

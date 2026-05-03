import 'package:flutter/material.dart';
import '../theme.dart';
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
import 'gallery/gallery_home_screen.dart';

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
                    className: teacher!.classTeacherOf!),
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
                  builder: (_) =>
                      const ExamManagementScreen(role: 'teacher')),
            ),
          ),

          _SectionHeader('ANNOUNCEMENTS'),
          _FeatureTile(
            icon: Icons.campaign_outlined,
            color: AppTheme.primary,
            title: 'Notice Board',
            subtitle: 'View school announcements and notices',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const AnnouncementsScreen(
                      viewerRole: 'teacher')),
            ),
          ),

          _SectionHeader('GALLERY'),
          _FeatureTile(
            icon: Icons.photo_library_outlined,
            color: AppTheme.primary,
            title: 'Event Gallery',
            subtitle: 'View school event photos',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GalleryHomeScreen(
                  role:      'teacher',
                  userEmail: teacher?.id ?? '',
                ),
              ),
            ),
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
                builder: (_) =>
                    const ExamManagementScreen(role: 'teacher')),
          ),
        ),

        _SectionHeader('ANNOUNCEMENTS'),
        _FeatureTile(
          icon: Icons.campaign_outlined,
          color: AppTheme.primary,
          title: 'Notice Board',
          subtitle: 'View school announcements and notices',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const AnnouncementsScreen(
                    viewerRole: 'teacher')),
          ),
        ),

        _SectionHeader('GALLERY'),
        _FeatureTile(
          icon: Icons.photo_library_outlined,
          color: AppTheme.primary,
          title: 'Event Gallery',
          subtitle: 'View school event photos',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GalleryHomeScreen(
                role:      'teacher',
                userEmail: teacher?.id ?? '',
              ),
            ),
          ),
        ),

        const SizedBox(height: 32),
      ],
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

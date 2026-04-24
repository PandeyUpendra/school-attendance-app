import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/student_service.dart';
import '../services/timetable_service.dart';
import '../services/notification_service.dart';
import 'teacher_management_screen.dart';
import 'timetable_settings_screen.dart';
import 'assign_duties_screen.dart';
import 'student_details_screen.dart';
import 'my_timetable_screen.dart';
import 'role_selection_screen.dart';
import 'attendance_class_detail_screen.dart';
import 'free_bells_screen.dart';
import 'leave_requests_screen.dart';
import 'attendance_history_screen.dart';
import 'class_picker_screen.dart';
import '../services/auth_service.dart';
import 'announcements_screen.dart';
import 'notifications_screen.dart';
import 'fee_structure_screen.dart';
import 'fee_collection_screen.dart';
import 'exam_management_screen.dart';
import 'copy_check_overview_screen.dart';
import 'homework_overview_screen.dart';
import 'analytics_screen.dart';

class CoordinatorDashboard extends StatefulWidget {
  const CoordinatorDashboard({super.key});

  @override
  State<CoordinatorDashboard> createState() => _CoordinatorDashboardState();
}

class _CoordinatorDashboardState extends State<CoordinatorDashboard> {
  // Attendance state
  bool _attendanceLoading = true;
  List<ClassSummary> _summaries = [];
  int _pendingLeaveCount = 0;
  int _unreadNotifCount  = 0;
  String _coordEmail = '';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _attendanceLoading = true);

    // Load session for notification context
    final session = await AuthService().getSession();
    final email   = (session?['email'] as String?) ?? '';

    // getSettings() is cached in memory after the first call, so subsequent
    // refreshes cost zero Firestore reads for settings.
    final settings = await TimetableService().getSettings();
    final classes  = List<String>.from(settings['classes'] as List);

    // Fire all heavy operations in parallel
    final summariesFuture =
        StudentService().loadTodayFullSummary(classes);
    final leavesFuture    =
        TimetableService().getLeaveApplications(status: 'pending');
    final notifFuture     =
        NotificationService().unreadCount(role: 'coordinator');

    final summaries    = await summariesFuture;
    final leaves       = await leavesFuture;
    final notifCount   = await notifFuture;

    if (!mounted) return;
    setState(() {
      _coordEmail        = email;
      _summaries         = summaries;
      _pendingLeaveCount = leaves.length;
      _unreadNotifCount  = notifCount;
      _attendanceLoading = false;
    });
  }

  Future<void> _navigate(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('School App',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('Coordinator',
                style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          // Notification bell with unread badge
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                tooltip: 'Notifications',
                onPressed: () async {
                  await _navigate(const NotificationsScreen(role: 'coordinator'));
                  _loadAll();
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
      body: RefreshIndicator(
        onRefresh: _loadAll,
        color: AppTheme.primary,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            // ── Announcements ──────────────────────────────────────────────
            _SectionHeader('ANNOUNCEMENTS'),
            _FeatureTile(
              icon: Icons.campaign_outlined,
              color: AppTheme.primary,
              title: 'Notice Board',
              subtitle: 'Post and manage school announcements',
              onTap: () => _navigate(AnnouncementsScreen(
                viewerRole: 'coordinator',
                posterName: _coordEmail,
              )),
            ),

            // ── Fee Management ─────────────────────────────────────────────
            _SectionHeader('FEE MANAGEMENT'),
            _FeatureTile(
              icon: Icons.account_balance_wallet_outlined,
              color: AppTheme.success,
              title: 'Fee Structure',
              subtitle: 'Set annual fee and components per class',
              onTap: () => _navigate(const FeeStructureScreen()),
            ),
            const _Divider(),
            _FeatureTile(
              icon: Icons.currency_rupee_outlined,
              color: AppTheme.success,
              title: 'Fee Collection',
              subtitle: 'Record payments and view outstanding dues',
              onTap: () => _navigate(const FeeCollectionScreen()),
            ),

            // ── Exams & Marks ──────────────────────────────────────────────
            _SectionHeader('EXAMS & MARKS'),
            _FeatureTile(
              icon: Icons.quiz_outlined,
              color: AppTheme.primary,
              title: 'Exam Management',
              subtitle: 'Create exams, enter marks and view report cards',
              onTap: () => _navigate(
                  const ExamManagementScreen(role: 'coordinator')),
            ),

            // ── Copy Checking ──────────────────────────────────────────────
            _SectionHeader('COPY CHECKING'),
            _FeatureTile(
              icon: Icons.menu_book_outlined,
              color: AppTheme.primary,
              title: 'Copy Checking Overview',
              subtitle: 'View copy-checking status across all classes',
              onTap: () => _navigate(const CopyCheckOverviewScreen()),
            ),

            // ── Homework ───────────────────────────────────────────────────
            _SectionHeader('HOMEWORK'),
            _FeatureTile(
              icon: Icons.assignment_outlined,
              color: AppTheme.primary,
              title: 'Homework Overview',
              subtitle: 'View all assignments posted across classes',
              onTap: () => _navigate(const HomeworkOverviewScreen()),
            ),

            // ── Timetable ──────────────────────────────────────────────────
            _SectionHeader('TIMETABLE'),
            _FeatureTile(
              icon: Icons.table_chart_outlined,
              color: AppTheme.primary,
              title: 'Timetable & Settings',
              subtitle: 'Bell schedule, classes and teacher assignments',
              onTap: () => _navigate(const TimetableSettingsScreen()),
            ),
            const _Divider(),
            _FeatureTile(
              icon: Icons.picture_as_pdf_outlined,
              color: AppTheme.primary,
              title: 'School Timetable (PDF)',
              subtitle: 'View & share class timetables as PDF',
              onTap: () => _navigate(const MyTimetableScreen()),
            ),
            const _Divider(),
            _FeatureTile(
              icon: Icons.assignment_outlined,
              color: AppTheme.primary,
              title: 'Assign Duties',
              subtitle: 'Assembly, lunch duty, gate duty and more',
              onTap: () => _navigate(const AssignDutiesScreen()),
            ),

            // ── Staff ──────────────────────────────────────────────────────
            _SectionHeader('STAFF'),
            _FeatureTile(
              icon: Icons.people_outline,
              color: AppTheme.primary,
              title: 'Manage Teachers',
              subtitle: 'Add or remove teachers from the school',
              onTap: () => _navigate(const TeacherManagementScreen()),
            ),

            // ── Students ───────────────────────────────────────────────────
            _SectionHeader('STUDENTS'),
            _FeatureTile(
              icon: Icons.school_outlined,
              color: AppTheme.primary,
              title: 'Student Details',
              subtitle: 'View and manage student records by class',
              onTap: () => _navigate(const StudentDetailsScreen()),
            ),

            // ── Free Bells & Substitution ──────────────────────────────────
            _SectionHeader('FREE BELLS'),
            _FeatureTile(
              icon: Icons.swap_horiz_outlined,
              color: AppTheme.warning,
              title: "Teacher's Free Bells",
              subtitle: 'View free periods & assign substitutions',
              onTap: () => _navigate(const FreeBellsScreen()),
            ),

            // ── Leave Requests ─────────────────────────────────────────────
            _SectionHeader('LEAVE REQUESTS'),
            _LeaveRequestTile(
              pendingCount: _pendingLeaveCount,
              onTap: () async {
                await _navigate(const LeaveRequestsScreen());
                _loadAll(); // refresh count after returning
              },
            ),

            // ── Analytics ─────────────────────────────────────────────────
            _SectionHeader('ANALYTICS'),
            _FeatureTile(
              icon: Icons.analytics_outlined,
              color: AppTheme.primary,
              title: 'Analytics Dashboard',
              subtitle: 'Attendance trends, absences, fee progress & charts',
              onTap: () => _navigate(const AnalyticsScreen()),
            ),

            // ── Attendance Reports ─────────────────────────────────────────
            _SectionHeader('REPORTS'),
            _FeatureTile(
              icon: Icons.bar_chart_outlined,
              color: AppTheme.primary,
              title: 'Attendance Reports',
              subtitle: 'Monthly history, % per student & low-attendance flags',
              onTap: () async {
                final cls = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ClassPickerScreen(
                        mode: ClassPickerMode.reports),
                  ),
                );
                if (cls != null && context.mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          AttendanceHistoryScreen(className: cls),
                    ),
                  );
                }
              },
            ),

            // ── Today's Attendance ─────────────────────────────────────────
            _SectionHeader('TODAY\'S ATTENDANCE'),
            _buildAttendanceTiles(),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceTiles() {
    if (_attendanceLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final marked = _summaries.where((s) => s.marked).toList();

    if (_summaries.isEmpty || marked.isEmpty) {
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.info_outline,
                  color: Colors.grey.shade400, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('No attendance taken yet',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('Class teachers will mark attendance today',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade500)),
                ],
              ),
            ),
          ]),
        ),
      );
    }

    // Show all summaries (marked + unmarked)
    return Column(
      children: [
        for (int i = 0; i < _summaries.length; i++) ...[
          _buildAttendanceTile(_summaries[i]),
          if (i < _summaries.length - 1)
            const Divider(height: 1, indent: 72),
        ],
      ],
    );
  }

  Widget _buildAttendanceTile(ClassSummary s) {
    final markedColor = s.absent > 0
        ? const Color(0xFFC62828)
        : s.leave > 0
            ? const Color(0xFFF57F17)
            : const Color(0xFF2E7D32);

    return InkWell(
      onTap: s.marked
          ? () => _navigate(
              AttendanceClassDetailScreen(summary: s))
          : null,
      child: Container(
        color: Colors.white,
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: s.marked
                  ? markedColor.withOpacity(0.12)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              s.marked
                  ? Icons.fact_check_outlined
                  : Icons.pending_outlined,
              color: s.marked ? markedColor : Colors.grey.shade400,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.className,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                if (s.marked)
                  Text(
                    'Present ${s.present}/${s.total}  ·  '
                    'Absent ${s.absent}  ·  Leave ${s.leave}',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500),
                  )
                else
                  Text('Not marked yet',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade400,
                          fontStyle: FontStyle.italic)),
              ],
            ),
          ),
          if (s.marked)
            Icon(Icons.chevron_right,
                color: Colors.grey.shade400, size: 20),
        ]),
      ),
    );
  }
}

// ── Shared widgets ─────────────────────────────────────────────────────────────

class _LeaveRequestTile extends StatelessWidget {
  final int pendingCount;
  final VoidCallback onTap;

  const _LeaveRequestTile({
    required this.pendingCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: AppTheme.warning.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.event_busy_outlined,
                color: AppTheme.warning, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Leave Requests',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                pendingCount > 0
                    ? '$pendingCount pending application${pendingCount > 1 ? 's' : ''}'
                    : 'No pending leave requests',
                style: TextStyle(
                    fontSize: 12,
                    color: pendingCount > 0
                        ? Colors.orange.shade700
                        : Colors.grey.shade500),
              ),
            ],
          )),
          if (pendingCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(10),
              ),
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
  Widget build(BuildContext context) =>
      const Divider(height: 1, indent: 72, endIndent: 0);
}

class _FeatureTile extends StatelessWidget {
  final IconData     icon;
  final Color        color;
  final String       title, subtitle;
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Container(
            width: 44, height: 44,
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

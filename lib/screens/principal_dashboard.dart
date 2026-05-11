import 'dart:async';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/auth_service.dart';
import '../services/student_service.dart';
import '../services/timetable_service.dart';
import '../services/notification_service.dart';
import 'attendance_history_screen.dart';
import 'class_picker_screen.dart';
import 'leave_requests_screen.dart';
import 'my_timetable_screen.dart';
import 'student_details_screen.dart';
import 'student_remarks_screen.dart';
import 'role_selection_screen.dart';
import 'announcements_screen.dart';
import 'notifications_screen.dart';
import 'analytics_screen.dart';
import 'calendar_screen.dart';
import 'class_setup_screen.dart';
import 'timetable_settings_screen.dart';
import 'school_contacts_screen.dart';
import 'tasks/staff_task_management_screen.dart';
import 'tasks/staff_task_analytics_view.dart';
import 'create_task_screen.dart';
import 'task_status_screen.dart';
import '../models/task.dart';
import '../services/task_service.dart';

/// The Principal Portal — school-wide overview dashboard.
class PrincipalDashboard extends StatefulWidget {
  const PrincipalDashboard({super.key});

  @override
  State<PrincipalDashboard> createState() => _PrincipalDashboardState();
}

class _PrincipalDashboardState extends State<PrincipalDashboard> {
  bool _loading = true;

  List<ClassSummary>         _summaries      = [];
  int  _pendingLeaveCount    = 0;
  int  _teachersAbsent       = 0;
  int  _unassignedBells      = 0;
  int  _unreadNotifCount     = 0;
  String _principalEmail     = '';

  StreamSubscription? _studentSub;
  Set<String> _knownStudentIds = {};

  @override
  void initState() {
    super.initState();
    _loadAll();
    // Re-run summaries whenever the student roster changes (add/delete).
    _studentSub = StudentService().watchStudents().listen((students) {
      final ids = students.map((s) => '${s.className}_${s.roll}').toSet();
      if (_knownStudentIds.isNotEmpty && ids != _knownStudentIds) {
        _loadAll();
      }
      _knownStudentIds = ids;
    });
  }

  @override
  void dispose() {
    _studentSub?.cancel();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);

    final session = await AuthService().getSession();
    final email   = (session?['email'] as String?) ?? '';

    final settings   = await TimetableService().getSettings();
    final allClasses = List<String>.from(settings['classes'] as List);

    // Filter to assigned classes; fall back to all.
    final assignedRaw = session?['assignedClasses'];
    final List<String> classes = (assignedRaw is List && assignedRaw.isNotEmpty)
        ? List<String>.from(assignedRaw).where(allClasses.contains).toList()
        : allClasses;

    // Fire all heavy reads in parallel.
    final summariesFuture  = StudentService().loadTodayFullSummary(classes);
    final leavesFuture     = TimetableService().getLeaveApplications(status: 'pending');
    final notifFuture      = NotificationService().unreadCount(role: 'principal', userEmail: email);
    final absentInfoFuture = TimetableService().getTodayAbsentTeachersInfo();

    final summaries  = await summariesFuture;
    final pending    = await leavesFuture;
    final notifCount = await notifFuture;
    final absentInfo = await absentInfoFuture;

    if (!mounted) return;
    setState(() {
      _principalEmail      = email;
      _summaries           = summaries;
      _pendingLeaveCount   = pending.length;
      _teachersAbsent      = absentInfo['absentCount']    ?? 0;
      _unassignedBells     = absentInfo['unassignedBells'] ?? 0;
      _unreadNotifCount    = notifCount;
      _loading             = false;
    });
  }

  Future<void> _logout() async {
    await AuthService().clearSession();
    if (!mounted) return;
    Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => const RoleSelectionScreen()));
  }

  Future<void> _navigate(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: RefreshIndicator(
        onRefresh: _loadAll,
        color: AppTheme.primary,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            // ── Wave hero card ────────────────────────────────────────────
            _PrincipalHeroCard(
              loading:          _loading,
              teachersAbsent:   _teachersAbsent,
              unassignedBells:  _unassignedBells,
              unreadNotifCount: _unreadNotifCount,
              onNotifTap: () async {
                await _navigate(const NotificationsScreen(role: 'principal'));
                _loadAll();
              },
              onLogout: _logout,
            ),

            if (!_loading) ...[
              // ── TODAY'S OVERVIEW ─────────────────────────────────────
              const _SectionHeader('TODAY\'S OVERVIEW'),
              _buildAttendanceSection(),
              _buildTasksSection(),
              _buildStaffTasksSummary(),

              // ── ANALYTICS & SETUP ──────────────────────────────────────
              const _SectionHeader('ANALYTICS & SETUP'),
              _FeatureTile(
                icon: Icons.analytics_outlined,
                color: AppTheme.primary,
                title: 'Analytics Dashboard',
                subtitle: 'Attendance trends, absences, fee progress & charts',
                onTap: () => _navigate(const AnalyticsScreen()),
              ),
              const Divider(height: 1, indent: 72),
              _FeatureTile(
                icon: Icons.list_alt_outlined,
                color: AppTheme.primary,
                title: 'Classes & Sections',
                subtitle: 'Set up class range and manage sections',
                onTap: () async {
                  final changed = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ClassSetupScreen()),
                  );
                  if (changed == true) _loadAll();
                },
              ),
              const Divider(height: 1, indent: 72),
              _FeatureTile(
                icon: Icons.people_outlined,
                color: AppTheme.primary,
                title: 'Student Records',
                subtitle: 'View student details and contact info by class',
                onTap: () => _navigate(const StudentDetailsScreen()),
              ),
              const Divider(height: 1, indent: 72),
              _FeatureTile(
                icon: Icons.comment_outlined,
                color: AppTheme.primary,
                title: 'Student Remarks',
                subtitle: 'Add and view observations for any student',
                onTap: () => _navigate(const StudentRemarksScreen(role: 'principal')),
              ),

              // ── SCHOOL INFO ─────────────────────────────────────────────
              const _SectionHeader('SCHOOL INFO'),
              _FeatureTile(
                icon: Icons.contact_phone_outlined,
                color: AppTheme.primary,
                title: 'School Contact List',
                subtitle: 'Manage roles and numbers for staff/drivers',
                onTap: () => _navigate(const SchoolContactsScreen(canEdit: true)),
              ),
              const Divider(height: 1, indent: 72),
              _FeatureTile(
                icon: Icons.table_chart_outlined,
                color: AppTheme.primary,
                title: 'School Timetable',
                subtitle: 'View & share class timetables as PDF',
                onTap: () => _navigate(const MyTimetableScreen()),
              ),

              // ── REPORTS & REQUESTS ──────────────────────────────────────
              const _SectionHeader('REPORTS & REQUESTS'),
              _FeatureTile(
                icon: Icons.bar_chart_outlined,
                color: AppTheme.primary,
                title: 'Attendance Reports',
                subtitle: 'Monthly history, % per student & low-attendance flags',
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
                icon: Icons.hourglass_top_outlined,
                color: AppTheme.warning,
                title: 'Leave Requests',
                subtitle: 'Review & approve pending applications from teachers',
                badge: _pendingLeaveCount > 0 ? '$_pendingLeaveCount' : null,
                onTap: () async {
                  await _navigate(const LeaveRequestsScreen(viewerRole: 'principal'));
                  _loadAll();
                },
              ),

              // ── TASKS & TOOLS ───────────────────────────────────────────
              const _SectionHeader('TASKS & TOOLS'),
              _FeatureTile(
                icon: Icons.assignment_outlined,
                color: AppTheme.primary,
                title: 'Staff Task Management',
                subtitle: 'Hierarchical to-do list for coordinators & teachers',
                onTap: () => _navigate(const StaffTaskManagementScreen()),
              ),
              const Divider(height: 1, indent: 72),
              _FeatureTile(
                icon: Icons.task_alt_outlined,
                color: AppTheme.primary,
                title: 'Task Status',
                subtitle: 'Check completion status of created tasks',
                onTap: () => _navigate(TaskStatusScreen(
                  createdByEmail: _principalEmail,
                  isAdmin: true,
                )),
              ),
              const Divider(height: 1, indent: 72),
              _FeatureTile(
                icon: Icons.add_task_outlined,
                color: AppTheme.primary,
                title: 'Create Task',
                subtitle: 'Assign tasks to teachers/classes',
                onTap: () => _navigate(CreateTaskScreen(
                  createdBy: _principalEmail,
                  creatorRole: 'principal',
                )),
              ),

              // ── COMMUNICATION & EVENTS ──────────────────────────────────
              const _SectionHeader('COMMUNICATION & EVENTS'),
              _FeatureTile(
                icon: Icons.campaign_outlined,
                color: AppTheme.primary,
                title: 'Notice Board (Announcements)',
                subtitle: 'Post and view school notices',
                onTap: () => _navigate(AnnouncementsScreen(
                  viewerRole: 'principal',
                  posterName: _principalEmail,
                )),
              ),
              const Divider(height: 1, indent: 72),
              _FeatureTile(
                icon: Icons.calendar_month_outlined,
                color: AppTheme.primary,
                title: 'School Calendar',
                subtitle: 'National, state holidays and school events',
                onTap: () => _navigate(const CalendarScreen(userRole: 'principal')),
              ),

              // ── SETTINGS ───────────────────────────────────────────────
              const _SectionHeader('SETTINGS'),
              _FeatureTile(
                icon: Icons.settings_outlined,
                color: AppTheme.primary,
                title: 'School Settings',
                subtitle: 'Manage bells and general schedule',
                onTap: () => _navigate(const TimetableSettingsScreen()),
              ),

              const SizedBox(height: 32),
            ],
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
                      ? _classColor(s).withOpacity(0.12)
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
              Text(s.displayName,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              if (!s.marked) ...[
                const SizedBox(width: 8),
                Text('Not marked yet',
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
                _AttendanceStat('${s.total}',   'Total',    const Color(0xFF546E7A)),
                _AttendanceStat('${s.present}', 'Present',  const Color(0xFF2E7D32)),
                _AttendanceStat('${s.absent}',  'Absent',   const Color(0xFFC62828)),
                _AttendanceStat('${s.leave}',   'On Leave', const Color(0xFFF57F17)),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  Color _classColor(ClassSummary s) {
    if (s.absent > 0) return const Color(0xFFC62828);
    if (s.leave  > 0) return const Color(0xFFF57F17);
    return const Color(0xFF2E7D32);
  }

  Widget _buildTasksSection() {
    return StreamBuilder<List<Task>>(
      stream: TaskService().getAllTasks(),
      builder: (context, snapshot) {
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

  Widget _buildStaffTasksSummary() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Staff Task Analytics', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              TextButton(
                onPressed: () => _navigate(const AnalyticsScreen()),
                child: const Text('View All', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const SizedBox(height: 150, child: StaffTaskAnalyticsView()),
        ],
      ),
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
  final VoidCallback onLogout;

  const _PrincipalHeroCard({
    required this.loading,
    required this.teachersAbsent,
    required this.unassignedBells,
    required this.unreadNotifCount,
    required this.onNotifTap,
    required this.onLogout,
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
                    icon: const Icon(Icons.logout,
                        color: Colors.white, size: 20),
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                    onPressed: onLogout,
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
                          ? const Color(0xFFEF9A9A)
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
                          ? const Color(0xFFFFCC80)
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
            color: Colors.white.withOpacity(0.12),
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

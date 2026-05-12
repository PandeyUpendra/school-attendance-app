import 'dart:async';
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
import 'free_bells_screen.dart';
import 'leave_requests_screen.dart';
import 'attendance_history_screen.dart';
import 'class_picker_screen.dart';
import '../services/auth_service.dart';
import 'school_contacts_screen.dart';
import 'announcements_screen.dart';
import 'notifications_screen.dart';
import 'fee_structure_screen.dart';
import 'fee_collection_screen.dart';
import 'exam_management_screen.dart';
import 'copy_check_overview_screen.dart';
import 'homework_overview_screen.dart';
import 'analytics_screen.dart';
import 'calendar_screen.dart';
import 'student_remarks_screen.dart';
import 'tasks/staff_task_management_screen.dart';
import 'create_task_screen.dart';
import 'task_status_screen.dart';
import 'school_policy_screen.dart';
import '../models/task.dart';
import '../models/copy_check.dart';
import '../services/task_service.dart';
import '../services/copy_check_service.dart';

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
  bool _attendanceLoading = true;
  bool _navigating        = false; // prevents double-push navigation loop
  List<ClassSummary>       _summaries          = [];
  Map<String, Map<int, int>> _streaks          = {}; // className → roll → days
  List<CopyCheckSummary>   _copySummaries      = [];
  int  _pendingLeaveCount   = 0;
  int  _unreadNotifCount    = 0;
  int  _teachersAbsent      = 0;
  int  _unassignedBells     = 0;
  String _coordEmail        = '';
  String _schoolId           = '';

  StreamSubscription? _studentSub;
  Set<String> _knownStudentIds = {};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _studentSub?.cancel();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _attendanceLoading = true);

    final session = await AuthService().getSession();
    final email   = (session?['email'] as String?) ?? '';
    final schoolId = (session?['schoolId'] as String?) ?? '';

    if (schoolId.isEmpty) {
      await AuthService().clearSession();
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const RoleSelectionScreen()));
      }
      return;
    }

    _schoolId = schoolId;
    _coordEmail = email;

    // Set up student subscription
    if (_studentSub == null) {
      _studentSub = StudentService().watchStudents(schoolId: schoolId).listen((students) {
        final ids = students.map((s) => '${s.className}_${s.roll}').toSet();
        if (_knownStudentIds.isNotEmpty && ids != _knownStudentIds) {
          _loadAll();
        }
        _knownStudentIds = ids;
      });
    }

    final settings = await TimetableService().getSettings(schoolId: schoolId);
    final allClasses = List<String>.from(settings['classes'] as List);

    // Filter to assigned classes; fall back to all if none assigned.
    final assignedRaw = session?['assignedClasses'];
    final List<String> classes = (assignedRaw is List && assignedRaw.isNotEmpty)
        ? List<String>.from(assignedRaw).where(allClasses.contains).toList()
        : allClasses;

    final summariesFuture   = StudentService().loadTodayFullSummary(schoolId: schoolId, classes: classes);
    final leavesFuture      = TimetableService().getLeaveApplications(schoolId: schoolId, status: 'pending');
    final notifFuture       = NotificationService().unreadCount(schoolId: schoolId, role: 'coordinator', userEmail: email);
    final absentInfoFuture  = TimetableService().getTodayAbsentTeachersInfo(schoolId);

    final summaries  = await summariesFuture;
    final leaves     = await leavesFuture;
    final notifCount = await notifFuture;
    final absentInfo = await absentInfoFuture;

    setState(() {
      _coordEmail         = email;
      _summaries          = summaries;
      _pendingLeaveCount  = leaves.length;
      _unreadNotifCount   = notifCount;
      _teachersAbsent     = absentInfo['absentCount'] ?? 0;
      _unassignedBells    = absentInfo['unassignedBells'] ?? 0;
      _attendanceLoading  = false;
    });
  }

  Future<void> _navigate(Widget screen) async {
    if (_navigating || !mounted) return;
    _navigating = true;
    try {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    } finally {
      _navigating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _cBg,
      body: RefreshIndicator(
        onRefresh: _loadAll,
        color: _cPurple,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            // ── Hero card ──────────────────────────────────────────────────
            _CoordHeroCard(
              loading:           _attendanceLoading,
              teachersAbsent:    _teachersAbsent,
              unassignedBells:   _unassignedBells,
              unreadNotifCount:  _unreadNotifCount,
              onNotifTap: () async {
                await _navigate(const NotificationsScreen(role: 'coordinator'));
                _loadAll();
              },
              onLogout: () async {
                await AuthService().clearSession();
                if (context.mounted) {
                  Navigator.pushReplacement(context,
                      MaterialPageRoute(builder: (_) => const RoleSelectionScreen()));
                }
              },
            ),

            // ── REPORTS & ANALYTICS ───────────────────────────────────────
            const _SectionHeader('REPORTS & ANALYTICS'),
            _FeatureTile(
              icon: Icons.bar_chart_outlined,
              color: _cPurpleMid,
              title: 'Attendance Reports',
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
            const _Divider(),
            _FeatureTile(
              icon: Icons.analytics_outlined,
              color: _cPurpleMid,
              title: 'Analytics Dashboard',
              subtitle: 'Attendance trends, absences, fee progress & charts',
              onTap: () => _navigate(const AnalyticsScreen()),
            ),

            // ── STAFF & STUDENTS ──────────────────────────────────────────
            const _SectionHeader('STAFF & STUDENTS'),
            _FeatureTile(
              icon: Icons.people_outline,
              color: _cPurple,
              title: 'Manage Teachers',
              subtitle: 'Add or remove teachers from the school',
              onTap: () => _navigate(const TeacherManagementScreen()),
            ),
            const _Divider(),
            _FeatureTile(
              icon: Icons.school_outlined,
              color: _cPurple,
              title: 'Student Details',
              subtitle: 'View and manage student records by class',
              onTap: () => _navigate(const StudentDetailsScreen()),
            ),
            const _Divider(),
            _FeatureTile(
              icon: Icons.comment_outlined,
              color: _cPurple,
              title: 'Student Remarks',
              subtitle: 'Add and view observations for any student',
              onTap: () => _navigate(
                  const StudentRemarksScreen(role: 'coordinator')),
            ),
            const _Divider(),
            _FeatureTile(
              icon: Icons.swap_horiz_outlined,
              color: AppTheme.warning,
              title: "Substitution Bell",
              subtitle: 'Assign substitutes for free periods',
              onTap: () => _navigate(const FreeBellsScreen()),
            ),
            const _Divider(),
            _LeaveRequestTile(
              pendingCount: _pendingLeaveCount,
              onTap: () async {
                await _navigate(const LeaveRequestsScreen(viewerRole: 'coordinator'));
                _loadAll();
              },
            ),

            // ── INFORMATION ───────────────────────────────────────────────
            const _SectionHeader('INFORMATION'),
            _FeatureTile(
              icon: Icons.contact_phone_outlined,
              color: _cPurple,
              title: 'School Contact List',
              subtitle: 'Manage roles and numbers for staff/drivers',
              onTap: () => _navigate(const SchoolContactsScreen(canEdit: true)),
            ),
            const _Divider(),
            _FeatureTile(
              icon: Icons.campaign_outlined,
              color: _cPurple,
              title: 'Notice Board',
              subtitle: 'Post and manage school announcements',
              onTap: () => _navigate(AnnouncementsScreen(
                viewerRole: 'coordinator',
                posterName: _coordEmail,
              )),
            ),
            const _Divider(),
            _FeatureTile(
              icon: Icons.calendar_month_outlined,
              color: _cPurple,
              title: 'School Calendar',
              subtitle: 'National, state holidays and school events',
              onTap: () => _navigate(const CalendarScreen(userRole: 'coordinator')),
            ),
            const _Divider(),
            // ── TASKS & DUTIES ───────────────────────────────────────────
            const _SectionHeader('TASKS & DUTIES'),
            _FeatureTile(
              icon: Icons.assignment_outlined,
              color: _cPurple,
              title: 'Staff Task Management',
              subtitle: 'Manage assigned and personal tasks',
              onTap: () => _navigate(const StaffTaskManagementScreen()),
            ),
            const _Divider(),
            _FeatureTile(
              icon: Icons.add_task_outlined,
              color: _cPurple,
              title: 'Create Task',
              subtitle: 'Assign tasks to teachers/classes',
              onTap: () => _navigate(CreateTaskScreen(
                createdBy: _coordEmail,
                creatorRole: 'coordinator',
              )),
            ),
            const _Divider(),
            _FeatureTile(
              icon: Icons.task_alt_outlined,
              color: _cPurple,
              title: 'Task Status',
              subtitle: 'Check completion status of created tasks',
              onTap: () => _navigate(TaskStatusScreen(
                createdByEmail: _coordEmail,
                isAdmin: true,
              )),
            ),
            const _Divider(),
            _FeatureTile(
              icon: Icons.swap_vert_circle_outlined,
              color: _cPurple,
              title: 'Assign Duties',
              subtitle: 'Assembly, lunch duty, gate duty and more',
              onTap: () => _navigate(const AssignDutiesScreen()),
            ),
            const _Divider(),
            _FeatureTile(
              icon: Icons.assignment_turned_in_outlined,
              color: _cPurple,
              title: 'Ideal Dress & Discipline',
              subtitle: 'Manage uniform standards and rules',
              onTap: () => _navigate(const SchoolPolicyScreen()),
            ),

            // ── ACADEMICS ───────────────────────────────────────────────
            const _SectionHeader('ACADEMICS'),
            _FeatureTile(
              icon: Icons.menu_book_outlined,
              color: _cPurple,
              title: 'Copy Checking Overview',
              subtitle: 'View copy-checking status across all classes',
              onTap: () => _navigate(const CopyCheckOverviewScreen()),
            ),
            const _Divider(),
            _FeatureTile(
              icon: Icons.assignment_outlined,
              color: _cPurple,
              title: 'Homework Overview',
              subtitle: 'View all assignments posted across classes',
              onTap: () => _navigate(const HomeworkOverviewScreen()),
            ),
            const _Divider(),
            _FeatureTile(
              icon: Icons.quiz_outlined,
              color: _cPurple,
              title: 'Exam Management',
              subtitle: 'Create exams, enter marks and view report cards',
              onTap: () => _navigate(const ExamManagementScreen(role: 'coordinator')),
            ),

            // ── ADMINISTRATION ───────────────────────────────────────────
            const _SectionHeader('ADMINISTRATION'),
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
            const _Divider(),
            _FeatureTile(
              icon: Icons.table_chart_outlined,
              color: _cPurple,
              title: 'Timetable & Settings',
              subtitle: 'Bell schedule, classes and teacher assignments',
              onTap: () => _navigate(const TimetableSettingsScreen()),
            ),
            const _Divider(),
            _FeatureTile(
              icon: Icons.picture_as_pdf_outlined,
              color: _cPurple,
              title: 'School Timetable (PDF)',
              subtitle: 'View & share class timetables as PDF',
              onTap: () => _navigate(const MyTimetableScreen()),
            ),
            const _Divider(),
            _FeatureTile(
              icon: Icons.privacy_tip_outlined,
              color: Colors.grey,
              title: 'Privacy Policy',
              subtitle: 'How we protect your data',
              onTap: () => _showPrivacyPolicy(context),
            ),

            // ── TODAY'S OVERVIEW ─────────────────────────────────────────
            const _SectionHeader('TODAY\'S OVERVIEW'),
            _buildAttendanceSection(),
            _buildTasksSection(),
            _buildCopyCheckingSection(),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Inline tasks section ──────────────────────────────────────────────────
  Widget _buildTasksSection() {
    return StreamBuilder<List<Task>>(
      stream: TaskService().getAllTasks(schoolId: _schoolId),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return _emptyCard('No active tasks');
        }
        final tasks = snapshot.data!.take(3).toList(); // Show last 3 tasks
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

  // ── Inline Copy Checking Section ──────────────────────────────────────────

  Widget _buildCopyCheckingSection() {
    if (_attendanceLoading) return const SizedBox();
    if (_copySummaries.isEmpty) {
      return _emptyCard('No copy checking sessions recorded yet');
    }

    // Since _copySummaries is currently a flat list of CopyCheckSummary,
    // and I want Class -> Section -> Summary structure, 
    // I should use the getStructuredSummaries method I added to the service,
    // or group it here. Let's group it here for simplicity since I have the data.

    final classMap = <String, Map<String, List<CopyCheckSummary>>>{};
    for (final s in _copySummaries) {
      classMap.putIfAbsent(s.check.className, () => {});
      classMap[s.check.className]!.putIfAbsent(s.check.section, () => []);
      classMap[s.check.className]![s.check.section]!.add(s);
    }

    final sortedClasses = classMap.keys.toList()..sort();

    return Column(
      children: sortedClasses.map((className) {
        final sectionsMap = classMap[className]!;
        final sortedSections = sectionsMap.keys.toList()..sort();

        return Card(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.grey.shade200)),
          child: ExpansionTile(
            leading: const Icon(Icons.class_outlined, color: AppTheme.primary),
            title: Text(className,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            children: sortedSections.map((section) {
              final summaries = sectionsMap[section]!;
              return Padding(
                padding: const EdgeInsets.only(left: 16),
                child: ExpansionTile(
                  leading: const Icon(Icons.grid_view, color: AppTheme.primaryMid, size: 20),
                  title: Text(section.isEmpty ? 'General Section' : 'Section $section',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  children: summaries.map((s) => _buildSummaryTile(s)).toList(),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSummaryTile(CopyCheckSummary s) {
    final c = s.check;
    final progress = s.progress;
    final progressPct = (progress * 100).round();
    
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(c.subject,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              Text('$progressPct%',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: progress == 1.0 ? Colors.green : AppTheme.primary)),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.grey.shade200,
            color: progress == 1.0 ? Colors.green : Colors.orange,
            minHeight: 6,
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _stat('Total', '${s.totalCount}'),
              _stat('Checked', '${s.checkedCount}', color: Colors.green),
              _stat('Pending', '${s.totalCount - s.checkedCount}', color: Colors.red),
            ],
          ),
          if (s.uncheckedNames.isNotEmpty) ...[
            const Divider(height: 20),
            const Text('PENDING STUDENTS:',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.redAccent,
                    letterSpacing: 0.5)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: s.uncheckedNames.map((name) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(name, style: TextStyle(fontSize: 11, color: Colors.red.shade800)),
              )).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String label, String value, {Color? color}) => Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        ],
      );

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
    final classStreaks = _streaks[s.displayName] ?? {};

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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.displayName,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 1),
                    if (!s.marked)
                      Text('Not marked yet',
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
                const Color(0xFFC62828)),
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
                const Color(0xFFF57F17)),
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
    if (s.absent > 0) return const Color(0xFFC62828);
    if (s.leave  > 0) return const Color(0xFFF57F17);
    return const Color(0xFF2E7D32);
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

// ── Per-student row ───────────────────────────────────────────────────────────

class _StudentRow extends StatelessWidget {
  final StudentNote note;
  final int         streak;
  const _StudentRow({required this.note, required this.streak});

  @override
  Widget build(BuildContext context) {
    final isAbsent   = note.status == 'Absent';
    final statusClr  = isAbsent
        ? const Color(0xFFC62828)
        : const Color(0xFFF57F17);
    final hasReason  = note.reason != null && note.reason!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        // Avatar
        CircleAvatar(
          radius: 17,
          backgroundColor: statusClr.withOpacity(0.1),
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
                    color: statusClr.withOpacity(0.1),
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
                    child: Text('$streak days',
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
  final VoidCallback onLogout;

  const _CoordHeroCard({
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
            colors: [Color(0xFF4A148C), Color(0xFF880E4F)],
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
                  ? _cPink.withOpacity(0.12)
                  : AppTheme.warning.withOpacity(0.12),
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

  const _FeatureTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
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
            Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
          ]),
        ),
      );
}

import 'package:flutter/material.dart';
import '../../models/teacher.dart';
import '../../services/student_service.dart';
import '../../services/timetable_service.dart';
import '../../services/birthday_service.dart';
import '../../services/copy_check_service.dart';
import '../../shared/utils/school_clock.dart';
import '../../theme.dart';
import './teacher_leave_balance_screen.dart';
import '../copy_check/copy_checking_screen.dart';
import '../birthdays/birthdays_screen.dart';
import '../leave/student_leave_requests_screen.dart';

class TeacherMorningSummaryCard extends StatefulWidget {
  final Teacher teacher;
  const TeacherMorningSummaryCard({super.key, required this.teacher});

  @override
  State<TeacherMorningSummaryCard> createState() => TeacherMorningSummaryCardState();
}

class TeacherMorningSummaryCardState extends State<TeacherMorningSummaryCard> {
  bool _loading = true;
  String? _error;

  int _todayAbsentees = 0;
  int _activeLeavesToday = 0;
  int _upcomingBirthdays = 0;
  int _pendingCopyChecks = 0;
  String _dutyToday = '';

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final teacher = widget.teacher;
      final classTeacherOf = teacher.classTeacherOf;

      // 1. Fetch Today's Attendance summary if class teacher
      Future<List<ClassSummary>> attendanceFuture = classTeacherOf != null && classTeacherOf.isNotEmpty
          ? StudentService.instance.loadTodayFullSummary(classes: [classTeacherOf])
          : Future.value([]);

      // 2. Fetch approved student leave applications if class teacher
      Future<List<Map<String, dynamic>>> leaveFuture = classTeacherOf != null && classTeacherOf.isNotEmpty
          ? TimetableService.instance.getStudentLeaveApplications(
              studentClass: classTeacherOf,
              status: 'approved',
            )
          : Future.value([]);

      // 3. Fetch upcoming student birthdays if class teacher
      Future<List<Map<String, dynamic>>> birthdayFuture = classTeacherOf != null && classTeacherOf.isNotEmpty
          ? BirthdayService().getUpcomingStudentBirthdays(7, className: classTeacherOf)
          : Future.value([]);

      // 4. Fetch duties for today
      Future<Map<String, String>> dutyFuture = TimetableService.instance.getTodayDuties();

      // 5. Fetch copy checking sessions
      Future<List<dynamic>> copyCheckFuture = CopyCheckService().getChecks(teacherId: teacher.id);

      final results = await Future.wait([
        attendanceFuture,
        leaveFuture,
        birthdayFuture,
        dutyFuture,
        copyCheckFuture,
      ]);

      final summaries = results[0] as List<ClassSummary>;
      final studentLeaves = results[1] as List<Map<String, dynamic>>;
      final birthdays = results[2] as List<Map<String, dynamic>>;
      final duties = results[3] as Map<String, String>;
      final copyChecks = results[4] as List<dynamic>;

      // Calculate today's absentees
      final todayAbsentees = summaries.isNotEmpty ? summaries.first.absent : 0;

      // Calculate active student leaves today
      final today = SchoolClock.today();
      int activeLeavesToday = 0;
      for (final leave in studentLeaves) {
        final startStr = leave['startDate'] as String? ?? '';
        final days = leave['numberOfDays'] as int? ?? 1;
        if (startStr.isNotEmpty) {
          try {
            final start = DateTime.parse(startStr);
            final end = start.add(Duration(days: days - 1));
            if (!today.isBefore(start) && !today.isAfter(end)) {
              activeLeavesToday++;
            }
          } catch (_) {}
        }
      }

      // Calculate upcoming birthdays count
      final upcomingBirthdays = birthdays.length;

      // Calculate duty today
      final dutyToday = duties[teacher.id] ?? '';

      // Calculate pending copy checks count
      int pendingCopyChecks = 0;
      for (final check in copyChecks) {
        if (check.pendingCount != null) {
          pendingCopyChecks += check.pendingCount as int;
        }
      }

      if (!mounted) return;
      setState(() {
        _todayAbsentees = todayAbsentees;
        _activeLeavesToday = activeLeavesToday;
        _upcomingBirthdays = upcomingBirthdays;
        _dutyToday = dutyToday;
        _pendingCopyChecks = pendingCopyChecks;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        height: 180,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Column(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 28),
            const SizedBox(height: 8),
            Text('Failed to load morning summary: $_error', style: const TextStyle(fontSize: 12, color: Colors.red)),
            const SizedBox(height: 8),
            TextButton(onPressed: loadData, child: const Text('Retry')),
          ],
        ),
      );
    }

    final isClassTeacher = widget.teacher.classTeacherOf != null && widget.teacher.classTeacherOf!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primaryDark, AppTheme.primaryMid],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
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
                Expanded(
                  child: Text(
                    isClassTeacher ? 'My Class Today' : 'My Day Today',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  SchoolClock.todayKey(),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          // Main content grid/rows
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                if (isClassTeacher) ...[
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricTile(
                          icon: Icons.person_off_outlined,
                          label: 'Absentees',
                          value: '$_todayAbsentees',
                          color: Colors.redAccent.shade100,
                          onTap: () {
                            // No direct screen but highlights the status
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildMetricTile(
                          icon: Icons.event_busy_outlined,
                          label: 'Student Leaves',
                          value: '$_activeLeavesToday',
                          color: Colors.orangeAccent.shade100,
                          onTap: () {
                            if (widget.teacher.classTeacherOf != null) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => StudentLeaveRequestsScreen(
                                    studentClass: widget.teacher.classTeacherOf!,
                                    studentSection: widget.teacher.section,
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricTile(
                          icon: Icons.cake_outlined,
                          label: 'Birthdays (Week)',
                          value: '$_upcomingBirthdays',
                          color: Colors.amberAccent.shade100,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => BirthdaysScreen(
                                  role: 'class_teacher',
                                  className: widget.teacher.classTeacherOf,
                                  section: widget.teacher.section,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildMetricTile(
                          icon: Icons.menu_book_outlined,
                          label: 'Pending Checks',
                          value: '$_pendingCopyChecks',
                          color: Colors.greenAccent.shade100,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CopyCheckingScreen(teacher: widget.teacher),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  // Subject teacher layout
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricTile(
                          icon: Icons.menu_book_outlined,
                          label: 'Pending Copy Checks',
                          value: '$_pendingCopyChecks',
                          color: Colors.greenAccent.shade100,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CopyCheckingScreen(teacher: widget.teacher),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],

                // Duties block if any
                if (_dutyToday.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.work_history_outlined, color: Colors.orangeAccent, size: 18),
                        const SizedBox(width: 10),
                        const Text(
                          'Today\'s Duty: ',
                          style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                        Expanded(
                          child: Text(
                            _dutyToday,
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Action Button
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TeacherLeaveBalanceScreen(teacher: widget.teacher),
                  ),
                );
              },
              icon: const Icon(Icons.beach_access, size: 16),
              label: const Text('My Leave Quota & Balances'),
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
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
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
      ),
    );
  }
}

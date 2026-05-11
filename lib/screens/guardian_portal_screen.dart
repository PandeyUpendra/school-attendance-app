import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/attendance_status.dart';
import '../models/student.dart';
import '../providers/auth_provider.dart';
import '../services/attendance_service.dart';
import '../services/firestore_service.dart';
import '../data/student_data.dart';

class GuardianPortalScreen extends StatefulWidget {
  const GuardianPortalScreen({super.key});

  @override
  State<GuardianPortalScreen> createState() => _GuardianPortalScreenState();
}

class _GuardianPortalScreenState extends State<GuardianPortalScreen> {
  bool _loading = true;
  Student? _child;
  String _childClass = '';
  List<Map<String, dynamic>> _history = []; // {date, present}
  int _presentCount = 0;
  int _totalDays = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;

    final schoolId = user.schoolId;
    final classId =
        user.classIds.isNotEmpty ? user.classIds.first : '';
    final rollStr = user.studentId ?? '';
    final roll = int.tryParse(rollStr) ?? 0;

    _childClass = classId;

    // Find child's info from student list
    List<Student>? students;
    if (schoolId.isNotEmpty && classId.isNotEmpty) {
      final cloud = await FirestoreService.loadStudents(
          schoolId: schoolId, classId: classId);
      if (cloud != null) {
        students = cloud
            .map((e) => Student(
                  roll: (e['roll'] as num).toInt(),
                  name: e['name'] as String,
                  parentPhone: e['parentPhone'] as String?,
                  photoPath: e['photoPath'] as String?,
                ))
            .toList();
      }
    }
    students ??= await AttendanceService.loadStudents(classId) ??
        (classStudents[classId] ?? []);

    final child =
        students.where((s) => s.roll == roll).firstOrNull;

    // Load attendance history
    List<Map<String, dynamic>> history = [];
    if (schoolId.isNotEmpty && classId.isNotEmpty && roll > 0) {
      history = await FirestoreService.getStudentAttendanceHistory(
        schoolId: schoolId,
        classId: classId,
        studentRoll: roll,
      );
    }

    // Fall back to local
    if (history.isEmpty && classId.isNotEmpty) {
      final dates = await AttendanceService.getSavedDates(classId);
      for (final dateStr in dates) {
        final summary = await AttendanceService.loadAttendanceSummary(
            className: classId, dateStr: dateStr);
        if (summary == null) continue;
        final att = summary['attendance'] as Map<int, AttendanceStatus>;
        if (att.containsKey(roll)) {
          history.add({'date': dateStr, 'status': att[roll]!});
        }
      }
    }

    setState(() {
      _child = child;
      _history = history.reversed.toList();
      _totalDays = history.length;
      _presentCount = history
          .where((h) => (h['status'] as AttendanceStatus).isPresent)
          .length;
      _loading = false;
    });
  }

  double get _percentage =>
      _totalDays == 0 ? 0 : _presentCount / _totalDays;

  String _formatDate(String dateStr) {
    final parts = dateStr.split('-');
    if (parts.length != 3) return dateStr;
    const months = [
      '',
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final day = int.tryParse(parts[2]) ?? 0;
    final month = int.tryParse(parts[1]) ?? 0;
    return '$day ${months[month]} ${parts[0]}';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 160,
            pinned: true,
            backgroundColor: const Color(0xFF00897B),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.white),
                tooltip: 'Sign out',
                onPressed: () => _confirmSignOut(context, auth),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF00897B), Color(0xFF26A69A)],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 60, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.family_restroom,
                                color: Colors.white70, size: 18),
                            const SizedBox(width: 8),
                            const Text('Parent / Guardian',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _child?.name ?? 'My Child',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$_childClass · Roll ${user?.studentId ?? '—'}',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          if (_loading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            // Stats row
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _StatCard(
                      value: '$_presentCount',
                      label: 'Days Present',
                      color: Colors.green,
                      icon: Icons.check_circle_outline,
                    ),
                    const SizedBox(width: 12),
                    _StatCard(
                      value: '${_totalDays - _presentCount}',
                      label: 'Days Absent',
                      color: Colors.red,
                      icon: Icons.cancel_outlined,
                    ),
                    const SizedBox(width: 12),
                    _StatCard(
                      value: '${(_percentage * 100).toStringAsFixed(1)}%',
                      label: 'Attendance',
                      color: _percentage >= 0.75
                          ? Colors.green
                          : _percentage >= 0.50
                              ? Colors.orange
                              : Colors.red,
                      icon: Icons.bar_chart,
                    ),
                  ],
                ),
              ),
            ),

            // Progress bar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Overall Attendance',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14)),
                        Text(
                          '$_totalDays days tracked',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: _percentage,
                        minHeight: 10,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _percentage >= 0.75
                              ? Colors.green.shade600
                              : _percentage >= 0.50
                                  ? Colors.orange.shade700
                                  : Colors.red.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // History header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Attendance History',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.grey.shade800)),
              ),
            ),

            if (_history.isEmpty)
              SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text('No records yet',
                        style: TextStyle(
                            color: Colors.grey.shade400, fontSize: 14)),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 30),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final record = _history[index];
                      final status = record['status'] as AttendanceStatus;
                      final isPresent = status.isPresent;
                      final isLeave = status.isLeave;
                      final borderColor = isPresent
                          ? Colors.green.shade100
                          : isLeave
                              ? Colors.blue.shade100
                              : Colors.red.shade100;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderColor),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 3,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: isPresent
                                  ? Colors.green.shade50
                                  : isLeave
                                      ? Colors.blue.shade50
                                      : Colors.red.shade50,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isPresent
                                  ? Icons.check_circle_outline
                                  : isLeave
                                      ? Icons.event_busy_outlined
                                      : Icons.cancel_outlined,
                              color: isPresent
                                  ? Colors.green.shade600
                                  : isLeave
                                      ? Colors.blue.shade400
                                      : Colors.red.shade400,
                              size: 22,
                            ),
                          ),
                          title: Text(
                            _formatDate(record['date'] as String),
                            style: const TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 14),
                          ),
                          subtitle: Text(
                            record['date'] as String,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isPresent
                                  ? Colors.green.shade50
                                  : isLeave
                                      ? Colors.blue.shade50
                                      : Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              status.label,
                              style: TextStyle(
                                color: isPresent
                                    ? Colors.green.shade700
                                    : isLeave
                                        ? Colors.blue.shade700
                                        : Colors.red.shade600,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                    childCount: _history.length,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  void _confirmSignOut(BuildContext context, AuthProvider auth) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out?'),
        content: const Text('You will be returned to the login screen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              auth.signOut();
            },
            child: const Text('Sign Out',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final IconData icon;

  const _StatCard({
    required this.value,
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
                color: Colors.black12,
                blurRadius: 4,
                offset: Offset(0, 2))
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color)),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

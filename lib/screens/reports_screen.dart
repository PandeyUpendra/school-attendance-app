import 'package:flutter/material.dart';
import '../models/attendance_status.dart';
import '../models/student.dart';
import '../data/student_data.dart';
import '../services/attendance_service.dart';
import '../services/firestore_service.dart';

class ReportsScreen extends StatefulWidget {
  final String className;
  final String schoolId;

  const ReportsScreen({
    super.key,
    required this.className,
    required this.schoolId,
  });

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  bool _loading = true;
  List<Student> _students = [];
  Map<int, Map<String, int>> _stats = {}; // roll → {present, absent, total}
  int _totalDays = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    // Load students
    List<Student>? students;
    if (widget.schoolId.isNotEmpty) {
      final cloud = await FirestoreService.loadStudents(
          schoolId: widget.schoolId, classId: widget.className);
      if (cloud != null) {
        students = cloud
            .map((e) => Student(
                  roll: (e['roll'] as num).toInt(),
                  name: e['name'] as String,
                ))
            .toList();
      }
    }
    students ??= await AttendanceService.loadStudents(widget.className) ??
        (classStudents[widget.className] ?? []);

    // Load attendance stats
    Map<int, Map<String, int>> stats = {};
    List<String> dates = [];

    if (widget.schoolId.isNotEmpty) {
      stats = await FirestoreService.getStudentAttendanceStats(
          schoolId: widget.schoolId, classId: widget.className);
      dates = await FirestoreService.getAttendanceDates(
          schoolId: widget.schoolId, classId: widget.className);
    }

    // Fall back to local if no Firestore data
    if (stats.isEmpty) {
      dates = await AttendanceService.getSavedDates(widget.className);
      for (final dateStr in dates) {
        final summary = await AttendanceService.loadAttendanceSummary(
            className: widget.className, dateStr: dateStr);
        if (summary == null) continue;
        final att = summary['attendance'] as Map<int, AttendanceStatus>;
        for (final e in att.entries) {
          stats[e.key] ??= {'present': 0, 'absent': 0, 'leave': 0, 'total': 0};
          if (e.value.isPresent) {
            stats[e.key]!['present'] = (stats[e.key]!['present'] ?? 0) + 1;
          } else if (e.value.isLeave) {
            stats[e.key]!['leave'] = (stats[e.key]!['leave'] ?? 0) + 1;
          } else {
            stats[e.key]!['absent'] = (stats[e.key]!['absent'] ?? 0) + 1;
          }
          stats[e.key]!['total'] = dates.length;
        }
      }
    }

    setState(() {
      _students = students!;
      _stats = stats;
      _totalDays = dates.length;
      _loading = false;
    });
  }

  double _percentage(int roll) {
    final s = _stats[roll];
    if (s == null || _totalDays == 0) return 0;
    return (s['present'] ?? 0) / _totalDays;
  }

  Color _percentColor(double pct) {
    if (pct >= 0.75) return Colors.green.shade600;
    if (pct >= 0.50) return Colors.orange.shade700;
    return Colors.red.shade600;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Reports — ${widget.className}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _totalDays == 0
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.bar_chart,
                          size: 72, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('No attendance data yet',
                          style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 16,
                              fontWeight: FontWeight.w500)),
                      const SizedBox(height: 6),
                      Text('Save attendance to see reports',
                          style: TextStyle(
                              color: Colors.grey.shade400, fontSize: 13)),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Summary header
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      color: const Color(0xFF1565C0),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today,
                              color: Colors.white70, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            '$_totalDays working days tracked',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500),
                          ),
                          const Spacer(),
                          Text(
                            '${_students.length} students',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                    ),

                    // Legend
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(
                        children: [
                          _LegendDot(color: Colors.green.shade600,
                              label: '≥75% Good'),
                          const SizedBox(width: 16),
                          _LegendDot(color: Colors.orange.shade700,
                              label: '50–74% At Risk'),
                          const SizedBox(width: 16),
                          _LegendDot(color: Colors.red.shade600,
                              label: '<50% Critical'),
                        ],
                      ),
                    ),

                    // Student list
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
                        itemCount: _students.length,
                        itemBuilder: (context, index) {
                          final student = _students[index];
                          final pct = _percentage(student.roll);
                          final color = _percentColor(pct);
                          final s = _stats[student.roll];
                          final present = s?['present'] ?? 0;
                          final absent = s?['absent'] ?? 0;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor:
                                          color.withOpacity(0.12),
                                      child: Text(
                                        '${student.roll}',
                                        style: TextStyle(
                                            color: color,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(student.name,
                                              style: const TextStyle(
                                                  fontWeight:
                                                      FontWeight.w600,
                                                  fontSize: 14)),
                                          Text(
                                            '$present present · $absent absent · $_totalDays days',
                                            style: const TextStyle(
                                                color: Colors.grey,
                                                fontSize: 11),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      '${(pct * 100).toStringAsFixed(1)}%',
                                      style: TextStyle(
                                          color: color,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: pct,
                                    backgroundColor:
                                        color.withOpacity(0.12),
                                    valueColor:
                                        AlwaysStoppedAnimation<Color>(color),
                                    minHeight: 6,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label,
            style:
                const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}

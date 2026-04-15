import 'package:flutter/material.dart';
import '../models/student.dart';
import '../data/student_data.dart';
import '../services/attendance_service.dart';
import 'history_screen.dart';
import 'add_student_screen.dart';
import 'scan_students_screen.dart';

class AttendanceScreen extends StatefulWidget {
  final String className;

  const AttendanceScreen({
    super.key,
    required this.className,
  });

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final DateTime today = DateTime.now();
  String searchQuery = "";
  late List<Student> students;
  final Map<int, bool> attendance = {};

  @override
  void initState() {
    super.initState();
    students = List.from(classStudents[widget.className] ?? []);
    for (var student in students) {
      attendance[student.roll] = false;
    }
    loadAttendance();
  }

  Future<void> saveAttendance() async {
    await AttendanceService.saveAttendance(
      className: widget.className,
      date: today,
      attendance: attendance,
    );
  }

  Future<void> loadAttendance() async {
    final saved = await AttendanceService.loadAttendance(
      className: widget.className,
      date: today,
    );
    if (saved != null) {
      setState(() {
        saved.forEach((roll, present) {
          attendance[roll] = present;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Attendance - ${widget.className}"),
        actions: [
          IconButton(
            icon: const Icon(Icons.document_scanner),
            tooltip: "Scan student list",
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ScanStudentsScreen(),
                ),
              );
              if (result != null && result is List<Student>) {
                setState(() {
                  for (final s in result) {
                    if (!students.any((e) => e.roll == s.roll)) {
                      students.add(s);
                      attendance[s.roll] = false;
                    }
                  }
                });
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: "Add student",
            onPressed: () async {
              final student = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AddStudentScreen(),
                ),
              );
              if (student != null) {
                setState(() {
                  students.add(student);
                  attendance[student.roll] = false;
                });
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: "View history",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => HistoryScreen(className: widget.className),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: "Mark all present",
            onPressed: () {
              setState(() {
                for (var student in students) {
                  attendance[student.roll] = true;
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.restart_alt),
            tooltip: "Reset attendance",
            onPressed: () {
              setState(() {
                for (var student in students) {
                  attendance[student.roll] = false;
                }
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: "Search student by name or roll",
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  searchQuery = value.toLowerCase();
                });
              },
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: students.length,
              itemBuilder: (context, index) {
                final student = students[index];

                if (searchQuery.isNotEmpty &&
                    !student.name.toLowerCase().contains(searchQuery) &&
                    !student.roll.toString().contains(searchQuery)) {
                  return const SizedBox.shrink();
                }

                final bool isPresent = attendance[student.roll] ?? false;

                return ListTile(
                  leading: CircleAvatar(
                    child: Text(student.roll.toString()),
                  ),
                  title: Text(student.name),
                  subtitle: Text(
                    isPresent ? "Present" : "Absent",
                    style: TextStyle(
                      color: isPresent ? Colors.green : Colors.red,
                    ),
                  ),
                  trailing: Switch(
                    value: isPresent,
                    onChanged: (value) {
                      setState(() {
                        attendance[student.roll] = value;
                      });
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: "Save & summarize",
        child: const Icon(Icons.check),
        onPressed: () async {
          final int present = attendance.values.where((v) => v).length;
          final int absent = students.length - present;
          final List<String> absentNames = [
            for (var s in students)
              if (attendance[s.roll] == false) s.name,
          ];

          await saveAttendance();

          if (!context.mounted) return;
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text("Attendance Summary"),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("Present: $present"),
                    Text("Absent: $absent"),
                    if (absentNames.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      const Text(
                        "Absent Students:",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      for (final name in absentNames) Text("• $name"),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("OK"),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../models/student.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {

  final DateTime today = DateTime.now();

  final List<Student> students = [
    Student(roll: 1, name: "Rahul Sharma"),
    Student(roll: 2, name: "Ananya Singh"),
    Student(roll: 3, name: "Rohan Verma"),
    Student(roll: 4, name: "Priya Gupta"),
    Student(roll: 5, name: "Aman Yadav"),
  ];

  final Map<int, bool> attendance = {};

  @override
  void initState() {
    super.initState();

    // Default all students as absent
    for (var student in students) {
      attendance[student.roll] = false;
    }

    // Load saved attendance if it exists
    loadAttendance();
  }

  Future<void> saveAttendance() async {

    print("Saving attendance...");

    final prefs = await SharedPreferences.getInstance();

    String todayKey =
        "${today.year}-${today.month}-${today.day}";

    Map<String, bool> stringKeyMap =
    attendance.map((key, value) => MapEntry(key.toString(), value));

    String data = jsonEncode(stringKeyMap);

    await prefs.setString(todayKey, data);

    print("Saved successfully");
  }

  Future<void> loadAttendance() async {
    final prefs = await SharedPreferences.getInstance();

    String todayKey =
        "${today.year}-${today.month}-${today.day}";

    String? data = prefs.getString(todayKey);

    if (data != null) {
      Map<String, dynamic> decoded = jsonDecode(data);

      setState(() {
        decoded.forEach((key, value) {
          attendance[int.parse(key)] = value;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text("Take Attendance"),
      ),

      body: ListView.builder(
        itemCount: students.length,
        itemBuilder: (context, index) {

          final student = students[index];
          bool isPresent = attendance[student.roll] ?? false;

          return ListTile(
            leading: CircleAvatar(
              child: Text(student.roll.toString()),
            ),

            title: Text(student.name),

            trailing: Switch(
              value: isPresent,
              onChanged: (value) {
                setState(() {
                  attendance[student.roll] = value;
                });
              },
            ),

            subtitle: Text(
              isPresent ? "Present" : "Absent",
              style: TextStyle(
                color: isPresent ? Colors.green : Colors.red,
              ),
            ),
          );
        },
      ),

      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.check),
          onPressed: () async {

            int present = attendance.values.where((v) => v).length;
            int absent = students.length - present;

            await saveAttendance();

            showDialog(
              context: context,
              builder: (context) {
                return AlertDialog(
                  title: const Text("Attendance Summary"),
                  content: Text(
                    "Present: $present\nAbsent: $absent",
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      child: const Text("OK"),
                    )
                  ],
                );
              },
            );
          }
      ),
    );
  }
}
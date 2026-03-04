import 'package:flutter/material.dart';
import 'attendance_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("School Attendance"),
      ),
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const AttendanceScreen(),
              ),
            );
          },
          child: const Text("Start Attendance"),
        ),
        ),
    );
  }
}
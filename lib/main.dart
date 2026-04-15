import 'package:flutter/material.dart';
import 'screens/class_selection_screen.dart';

void main() {
  runApp(const SchoolApp());
}

class SchoolApp extends StatelessWidget {
  const SchoolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'School Attendance',
      theme: ThemeData(primarySwatch: Colors.red),
      home: const ClassSelectionScreen(),
    );
  }
}

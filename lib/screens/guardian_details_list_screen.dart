import 'dart:io';
import 'package:flutter/material.dart';
import '../models/student.dart';
import '../services/student_service.dart';
import '../theme.dart';
import 'student_list_screen.dart';

class GuardianDetailsListScreen extends StatefulWidget {
  final String className;
  final String section;
  final String? teacherId;

  const GuardianDetailsListScreen({
    super.key,
    required this.className,
    this.section = '',
    this.teacherId,
  });

  @override
  State<GuardianDetailsListScreen> createState() => _GuardianDetailsListScreenState();
}

class _GuardianDetailsListScreenState extends State<GuardianDetailsListScreen> {
  final _service = StudentService();
  bool _loading = true;
  List<Student> _students = [];

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    setState(() => _loading = true);
    try {
      final list = await _service.getStudentsByClass(
        widget.className,
        section: widget.section,
        teacherId: widget.teacherId,
      );
      // Only show students who have guardian details provided
      if (mounted) {
        setState(() {
          _students = list.where((s) => s.guardianDetails != null).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading students: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Details provided by guardian'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _students.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.badge_outlined, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      const Text(
                        'No guardian details provided yet',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _students.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final student = _students[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppTheme.primary.withOpacity(0.1),
                        backgroundImage: student.photoUrl != null
                            ? NetworkImage(student.photoUrl!)
                            : (student.photoPath != null
                                ? FileImage(File(student.photoPath!))
                                : null) as ImageProvider?,
                        child: (student.photoUrl == null && student.photoPath == null)
                            ? Text('${student.roll}', style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold))
                            : null,
                      ),
                      title: Text(student.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('Last updated: ${student.guardianDetails?.lastUpdated?.split('T')[0] ?? 'Unknown'}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => StudentDetailPage(
                              student: student,
                              canEdit: false, // Guardian details are view-only from this list
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}

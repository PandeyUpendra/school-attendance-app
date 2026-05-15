import 'package:flutter/material.dart';
import '../models/task.dart';
import '../models/student.dart';
import '../services/student_service.dart';
import '../services/task_service.dart';
import '../theme.dart';

class TaskMarkingScreen extends StatefulWidget {
  final Task task;
  final String className;
  final String section;

  const TaskMarkingScreen({
    super.key,
    required this.task,
    required this.className,
    required this.section,
  });

  @override
  State<TaskMarkingScreen> createState() => _TaskMarkingScreenState();
}

class _TaskMarkingScreenState extends State<TaskMarkingScreen> {
  List<Student> _students = [];
  Map<String, bool> _localStatuses = {};
  bool _loading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final students = await StudentService().getStudentsByClass(
      className: widget.className,
      section: widget.section,
    );
    
    // We should probably get the latest task status too, 
    // though widget.task has some initial data.
    // For simplicity, we initialize from widget.task.studentStatuses
    // but filter for the students we just loaded.
    
    final statuses = Map<String, bool>.from(widget.task.studentStatuses);

    if (mounted) {
      setState(() {
        _students = students;
        _localStatuses = statuses;
        _loading = false;
      });
    }
  }

  void _markAll(bool? val) {
    if (val == null) return;
    setState(() {
      for (var student in _students) {
        final key = '${student.className}_${student.roll}';
        _localStatuses[key] = val;
      }
    });
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      // We only want to save statuses for students in THIS class/section
      // to be safe, though updateBulkStudentStatuses handles specific keys.
      final updates = <String, bool>{};
      for (var student in _students) {
        final key = '${student.className}_${student.roll}';
        updates[key] = _localStatuses[key] ?? false;
      }

      await TaskService().updateBulkStudentStatuses(taskId: widget.task.id, updates: updates);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Statuses saved successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool allChecked = _students.isNotEmpty &&
        _students.every((s) => _localStatuses['${s.className}_${s.roll}'] == true);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.task.title),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: AppTheme.primary.withOpacity(0.05),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Mark completion for ${widget.className} ${widget.section}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      InkWell(
                        onTap: () => _markAll(!allChecked),
                        child: Row(
                          children: [
                            const Text('Mark All'),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: Checkbox(
                                value: allChecked,
                                activeColor: AppTheme.success,
                                onChanged: (v) => _markAll(v),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 100),
                    itemCount: _students.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final student = _students[index];
                      final key = '${student.className}_${student.roll}';
                      final isDone = _localStatuses[key] ?? false;

                      return CheckboxListTile(
                        title: Text(student.name),
                        subtitle: Text('Roll: ${student.roll}'),
                        value: isDone,
                        activeColor: AppTheme.success,
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _localStatuses[key] = val;
                            });
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: !_loading
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: FloatingActionButton.extended(
                  onPressed: _isSaving ? null : _save,
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  label: _isSaving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'SAVE COMPLETION STATUS',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                  icon: _isSaving ? null : const Icon(Icons.save),
                ),
              ),
            )
          : null,
    );
  }
}

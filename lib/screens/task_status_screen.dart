import 'package:flutter/material.dart';
import '../models/task.dart';
import '../services/task_service.dart';
import '../theme.dart';

class TaskStatusScreen extends StatelessWidget {
  final String createdByEmail;
  final bool isAdmin; // true if principal or admin who should see all tasks

  const TaskStatusScreen({
    super.key,
    required this.createdByEmail,
    this.isAdmin = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Task Status'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<Task>>(
        stream: isAdmin
            ? TaskService().getAllTasks()
            : TaskService().getTasksCreatedBy(email: createdByEmail),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final tasks = snapshot.data ?? [];
          if (tasks.isEmpty) {
            return const Center(child: Text('No tasks created yet.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: tasks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final task = tasks[index];
              return _TaskProgressCard(task: task);
            },
          );
        },
      ),
    );
  }
}

class _TaskProgressCard extends StatelessWidget {
  final Task task;

  const _TaskProgressCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final totalStudents = task.studentStatuses.length;
    final doneStudents = task.studentStatuses.values.where((v) => v).length;
    final progress = totalStudents == 0 ? 0.0 : doneStudents / totalStudents;

    return Card(
      child: ExpansionTile(
        title: Text(task.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey.shade200,
              color: AppTheme.success,
            ),
            const SizedBox(height: 4),
            Text(
              '$doneStudents students completed (out of $totalStudents records)',
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              'Classes: ${task.assignedClasses.join(", ")}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Completion Details:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (task.studentStatuses.isEmpty)
                  const Text('No students marked yet.')
                else
                  ...task.studentStatuses.entries.map((e) {
                    final parts = e.key.split('_');
                    final className = parts[0];
                    final roll = parts.length > 1 ? parts[1] : '';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Icon(
                            e.value ? Icons.check_circle : Icons.radio_button_unchecked,
                            color: e.value ? AppTheme.success : Colors.grey,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text('$className - Roll $roll'),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

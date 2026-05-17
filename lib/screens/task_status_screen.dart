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
            : TaskService().getTasksCreatedBy(createdByEmail),
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

class _ClassBreakdownTable extends StatelessWidget {
  final Map<String, bool> studentStatuses;

  const _ClassBreakdownTable({required this.studentStatuses});

  @override
  Widget build(BuildContext context) {
    if (studentStatuses.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text('No students assigned yet.', style: TextStyle(color: Colors.grey)),
      );
    }

    // Group by class name (key format: "ClassName_roll")
    final Map<String, List<bool>> byClass = {};
    for (final entry in studentStatuses.entries) {
      final lastUnderscore = entry.key.lastIndexOf('_');
      final className = lastUnderscore > 0 ? entry.key.substring(0, lastUnderscore) : entry.key;
      byClass.putIfAbsent(className, () => []).add(entry.value);
    }

    final sortedClasses = byClass.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        Row(
          children: const [
            Expanded(flex: 3, child: Text('Class', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.grey))),
            Expanded(flex: 2, child: Text('Total', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.grey), textAlign: TextAlign.center)),
            Expanded(flex: 2, child: Text('Done', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.grey), textAlign: TextAlign.center)),
            Expanded(flex: 2, child: Text('Remaining', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.grey), textAlign: TextAlign.center)),
          ],
        ),
        const Divider(height: 8),
        ...sortedClasses.map((cls) {
          final statuses = byClass[cls]!;
          final total = statuses.length;
          final done = statuses.where((v) => v).length;
          final remaining = total - done;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Expanded(flex: 3, child: Text(cls, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13))),
                Expanded(flex: 2, child: Text('$total', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13))),
                Expanded(
                  flex: 2,
                  child: Text(
                    '$done',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: done == total ? AppTheme.success : Colors.black87, fontWeight: done == total ? FontWeight.bold : FontWeight.normal),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '$remaining',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: remaining > 0 ? AppTheme.accent : AppTheme.success, fontWeight: remaining > 0 ? FontWeight.bold : FontWeight.normal),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
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
              '$doneStudents / $totalStudents students done  •  ${totalStudents - doneStudents} remaining',
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
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _ClassBreakdownTable(studentStatuses: task.studentStatuses),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../theme.dart';
import '../models/staff_task.dart';

/// Shared badge widgets for staff task screens.

class TaskPriorityBadge extends StatelessWidget {
  final TaskPriority priority;
  const TaskPriorityBadge({super.key, required this.priority});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (priority) {
      case TaskPriority.high:
        color = AppTheme.danger;
        break;
      case TaskPriority.medium:
        color = AppTheme.warning;
        break;
      case TaskPriority.low:
        color = AppTheme.success;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(priority.label,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color)),
    );
  }
}

class TaskStatusChip extends StatelessWidget {
  final TaskStatus status;
  const TaskStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case TaskStatus.completed:  color = AppTheme.success; break;
      case TaskStatus.inProgress: color = AppTheme.warning; break;
      case TaskStatus.pending:    color = Colors.grey;      break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(status.label,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color)),
    );
  }
}

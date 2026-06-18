import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../models/staff_task.dart';
import '../../l10n/app_strings.dart';

/// Shared badge widgets for staff task screens.

class TaskPriorityBadge extends StatelessWidget {
  final TaskPriority priority;
  const TaskPriorityBadge({super.key, required this.priority});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (priority) {
      case TaskPriority.high:
        color = AppTheme.danger;
        label = context.tr('priorityHigh');
        break;
      case TaskPriority.medium:
        color = AppTheme.warning;
        label = context.tr('priorityMedium');
        break;
      case TaskPriority.low:
        color = AppTheme.success;
        label = context.tr('priorityLow');
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
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
    String label;
    switch (status) {
      case TaskStatus.completed:
        color = AppTheme.success;
        label = context.tr('completedLabel');
        break;
      case TaskStatus.inProgress:
        color = AppTheme.warning;
        label = context.tr('inProgressLabel');
        break;
      case TaskStatus.pending:
        color = Colors.grey;
        label = context.tr('statusPending');
        break;
      case TaskStatus.overdue:
        color = Colors.red;
        label = context.tr('hwOverdue');
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color)),
    );
  }
}

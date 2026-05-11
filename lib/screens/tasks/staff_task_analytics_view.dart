import 'package:flutter/material.dart';
import '../../models/staff_task.dart';
import '../../services/staff_task_service.dart';
import '../../theme.dart';
import 'package:fl_chart/fl_chart.dart';

class StaffTaskAnalyticsView extends StatelessWidget {
  const StaffTaskAnalyticsView({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<StaffTask>>(
      stream: StaffTaskService().getAllStaffTasks(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final tasks = snapshot.data ?? [];
        if (tasks.isEmpty) {
          return const Center(child: Text('No task data available'));
        }

        final completed = tasks.where((t) => t.status == TaskStatus.completed).length;
        final overdue = tasks.where((t) => t.status == TaskStatus.overdue).length;
        final inProgress = tasks.where((t) => t.status == TaskStatus.inProgress).length;
        final pending = tasks.where((t) => t.status == TaskStatus.pending).length;
        final total = tasks.length;
        final completionRate = total > 0 ? (completed / total) : 0.0;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSummaryCards(completed, overdue, inProgress, pending, total),
            const SizedBox(height: 24),
            const Text('Completion Progress', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildCompletionPieChart(completed, overdue, inProgress, pending),
            const SizedBox(height: 24),
            const Text('Task Distribution by Priority', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildPriorityBreakdown(tasks),
            const SizedBox(height: 24),
            const Text('Assignee Performance', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildAssigneeList(tasks),
          ],
        );
      },
    );
  }

  Widget _buildSummaryCards(int completed, int overdue, int inProgress, int pending, int total) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        _summaryCard('Total Tasks', '$total', Colors.blue),
        _summaryCard('Completed', '$completed', Colors.green),
        _summaryCard('In Progress', '$inProgress', Colors.orange),
        _summaryCard('Overdue', '$overdue', Colors.red),
      ],
    );
  }

  Widget _summaryCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.3))),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _buildCompletionPieChart(int completed, int overdue, int inProgress, int pending) {
    return Container(
      height: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(
            child: PieChart(
              PieChartData(
                sections: [
                  PieChartSectionData(value: completed.toDouble(), color: Colors.green, title: '', radius: 50),
                  PieChartSectionData(value: overdue.toDouble(), color: Colors.red, title: '', radius: 50),
                  PieChartSectionData(value: inProgress.toDouble(), color: Colors.orange, title: '', radius: 50),
                  PieChartSectionData(value: pending.toDouble(), color: Colors.blue, title: '', radius: 50),
                ],
                sectionsSpace: 2,
              ),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _legendItem('Completed', Colors.green),
              _legendItem('Overdue', Colors.red),
              _legendItem('In Progress', Colors.orange),
              _legendItem('Pending', Colors.blue),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      children: [
        Container(width: 12, height: 12, color: color),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildPriorityBreakdown(List<StaffTask> tasks) {
    final high = tasks.where((t) => t.priority == TaskPriority.high).length;
    final medium = tasks.where((t) => t.priority == TaskPriority.medium).length;
    final low = tasks.where((t) => t.priority == TaskPriority.low).length;
    final total = tasks.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          _priorityRow('High Priority', high, total, Colors.red),
          const SizedBox(height: 12),
          _priorityRow('Medium Priority', medium, total, Colors.orange),
          const SizedBox(height: 12),
          _priorityRow('Low Priority', low, total, Colors.green),
        ],
      ),
    );
  }

  Widget _priorityRow(String label, int count, int total, Color color) {
    final pct = total > 0 ? count / total : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 13)),
            Text('$count', style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: pct, backgroundColor: Colors.grey.shade100, color: color, minHeight: 8),
      ],
    );
  }

  Widget _buildAssigneeList(List<StaffTask> tasks) {
    Map<String, List<StaffTask>> userTasks = {};
    for (var task in tasks) {
      for (int i = 0; i < task.assignedToIds.length; i++) {
        String name = task.assignedToNames[i];
        userTasks.putIfAbsent(name, () => []).add(task);
      }
    }

    final sortedUsers = userTasks.keys.toList()..sort((a, b) {
      final aComp = userTasks[a]!.where((t) => t.status == TaskStatus.completed).length;
      final bComp = userTasks[b]!.where((t) => t.status == TaskStatus.completed).length;
      return bComp.compareTo(aComp);
    });

    return Column(
      children: sortedUsers.map((name) {
        final uTasks = userTasks[name]!;
        final completed = uTasks.where((t) => t.status == TaskStatus.completed).length;
        final total = uTasks.length;
        final pct = total > 0 ? completed / total : 0.0;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              CircleAvatar(backgroundColor: AppTheme.primary.withOpacity(0.1), child: Text(name[0].toUpperCase(), style: const TextStyle(color: AppTheme.primary))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(value: pct, backgroundColor: Colors.grey.shade100, color: Colors.green),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text('$completed/$total', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
            ],
          ),
        );
      }).toList(),
    );
  }
}

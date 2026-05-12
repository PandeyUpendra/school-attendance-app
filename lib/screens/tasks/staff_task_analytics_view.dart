import 'package:flutter/material.dart';
import '../../models/staff_task.dart';
import '../../services/staff_task_service.dart';
import '../../theme.dart';
import 'package:fl_chart/fl_chart.dart';

class StaffTaskAnalyticsView extends StatelessWidget {
  final String schoolId;
  const StaffTaskAnalyticsView({super.key, required this.schoolId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<StaffTask>>(
      stream: StaffTaskService().getAllStaffTasks(schoolId),
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

        return ListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            _buildSummaryCards(completed, overdue, inProgress, pending, total),
            const SizedBox(height: 24),
            const Text('Completion Progress', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildCompletionPieChart(completed, overdue, inProgress, pending),
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
      childAspectRatio: 2.5,
      children: [
        _summaryCard('Total', '$total', Colors.blue),
        _summaryCard('Done', '$completed', Colors.green),
        _summaryCard('Ongoing', '$inProgress', Colors.orange),
        _summaryCard('Overdue', '$overdue', Colors.red),
      ],
    );
  }

  Widget _summaryCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.3))),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _buildCompletionPieChart(int completed, int overdue, int inProgress, int pending) {
    return Container(
      height: 150,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(
            child: PieChart(
              PieChartData(
                sections: [
                  PieChartSectionData(value: completed.toDouble(), color: Colors.green, title: '', radius: 40),
                  PieChartSectionData(value: overdue.toDouble(), color: Colors.red, title: '', radius: 40),
                  PieChartSectionData(value: inProgress.toDouble(), color: Colors.orange, title: '', radius: 40),
                  PieChartSectionData(value: pending.toDouble(), color: Colors.blue, title: '', radius: 40),
                ],
                sectionsSpace: 2,
              ),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _legendItem('Done', Colors.green),
              _legendItem('Overdue', Colors.red),
              _legendItem('Ongoing', Colors.orange),
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
        Container(width: 8, height: 8, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
  }
}

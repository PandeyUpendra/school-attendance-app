import 'package:flutter/material.dart';
import '../data/student_data.dart';
import '../services/attendance_service.dart';

class HistoryScreen extends StatefulWidget {
  final String className;

  const HistoryScreen({super.key, required this.className});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<String> _dates = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDates();
  }

  Future<void> _loadDates() async {
    final dates = await AttendanceService.getSavedDates(widget.className);
    setState(() {
      _dates = dates.reversed.toList(); // most recent first
      _loading = false;
    });
  }

  String _formatDate(String dateStr) {
    final parts = dateStr.split('-');
    if (parts.length != 3) return dateStr;
    final months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final day = int.tryParse(parts[2]) ?? 0;
    final month = int.tryParse(parts[1]) ?? 0;
    final year = parts[0];
    return '$day ${months[month]} $year';
  }

  void _showDetail(String dateStr) async {
    final summary = await AttendanceService.loadAttendanceSummary(
      className: widget.className,
      dateStr: dateStr,
    );
    if (summary == null || !mounted) return;

    final students = classStudents[widget.className] ?? [];
    final attendance = summary['attendance'] as Map<int, bool>;

    final absentStudents = students
        .where((s) => attendance[s.roll] == false)
        .map((s) => '${s.roll}. ${s.name}')
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          maxChildSize: 0.9,
          builder: (_, controller) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _formatDate(dateStr),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _statChip(
                        Icons.check_circle,
                        '${summary['present']} Present',
                        Colors.green,
                      ),
                      const SizedBox(width: 8),
                      _statChip(
                        Icons.cancel,
                        '${summary['absent']} Absent',
                        Colors.red,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (absentStudents.isNotEmpty) ...[
                    const Text(
                      'Absent Students:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: ListView.builder(
                        controller: controller,
                        itemCount: absentStudents.length,
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text('• ${absentStudents[i]}'),
                        ),
                      ),
                    ),
                  ] else
                    const Text('All students were present!'),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _statChip(IconData icon, String label, Color color) {
    return Chip(
      avatar: Icon(icon, color: color, size: 18),
      label: Text(label),
      backgroundColor: color.withOpacity(0.1),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('History - ${widget.className}'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _dates.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history, size: 64, color: Colors.grey),
                      SizedBox(height: 12),
                      Text(
                        'No attendance records yet',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _dates.length,
                  itemBuilder: (context, index) {
                    final dateStr = _dates[index];
                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.calendar_today, size: 18),
                        ),
                        title: Text(_formatDate(dateStr)),
                        subtitle: Text(dateStr),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showDetail(dateStr),
                      ),
                    );
                  },
                ),
    );
  }
}

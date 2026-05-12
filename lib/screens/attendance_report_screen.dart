import 'package:flutter/material.dart';
import '../models/student.dart';
import '../services/student_service.dart';
import '../theme.dart';
import 'attendance_screen.dart';

class AttendanceReportScreen extends StatefulWidget {
  final String schoolId;
  final String className;
  final String section;

  const AttendanceReportScreen({
    super.key,
    required this.schoolId,
    required this.className,
    this.section = '',
  });

  @override
  State<AttendanceReportScreen> createState() => _AttendanceReportScreenState();
}

class _AttendanceReportScreenState extends State<AttendanceReportScreen> {
  final _service = StudentService();
  bool _loading = true;
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();

  List<Student> _students = [];
  // Map<Roll, Map<Type, Count>>
  Map<int, Map<String, int>> _studentStats = {};
  int _totalWorkingDays = 0;

  @override
  void initState() {
    super.initState();
    // Default to current month
    _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    
    final students = await _service.getStudentsByClass(schoolId: widget.schoolId, className: widget.className, section: widget.section);
    
    Map<int, Map<String, int>> stats = {};
    for (var s in students) {
      stats[s.roll] = {'present': 0, 'absent': 0, 'leave': 0};
    }

    int workingDaysCount = 0;

    // Fetch for each month in range
    DateTime current = DateTime(_startDate.year, _startDate.month);
    final attKey = widget.section.isEmpty ? widget.className : '${widget.className} ${widget.section}';

    while (current.isBefore(_endDate) || (current.year == _endDate.year && current.month == _endDate.month)) {
      final monthData = await _service.loadMonthAttendance(
        schoolId:  widget.schoolId,
        className: attKey,
        year:      current.year,
        month:     current.month,
      );
      
      monthData.forEach((day, rolls) {
        DateTime date = DateTime(current.year, current.month, day);
        // Only count if within selected range
        if (date.isAfter(_startDate.subtract(const Duration(days: 1))) && 
            date.isBefore(_endDate.add(const Duration(days: 1)))) {
          workingDaysCount++;
          rolls.forEach((roll, status) {
            if (stats.containsKey(roll)) {
              if (status == 'Present') {
                stats[roll]!['present'] = (stats[roll]!['present'] ?? 0) + 1;
              } else if (status == 'Absent') {
                stats[roll]!['absent'] = (stats[roll]!['absent'] ?? 0) + 1;
              } else if (status == 'Leave') {
                stats[roll]!['leave'] = (stats[roll]!['leave'] ?? 0) + 1;
              }
            }
          });
        }
      });
      
      current = DateTime(current.year, current.month + 1);
    }

    if (!mounted) return;
    setState(() {
      _students = students;
      _studentStats = stats;
      _totalWorkingDays = workingDaysCount;
      _loading = false;
    });
  }

  String _getRemark(double pct) {
    if (_totalWorkingDays == 0) return 'N/A';
    if (pct >= 95) return 'Excellent';
    if (pct >= 85) return 'Very Good';
    if (pct >= 75) return 'Good';
    if (pct >= 60) return 'Average';
    return 'Poor';
  }

  Color _getRemarkColor(double pct) {
    if (_totalWorkingDays == 0) return Colors.grey;
    if (pct >= 90) return Colors.green;
    if (pct >= 75) return Colors.blue;
    if (pct >= 60) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Attendance Summary'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: 'Select Period',
            onPressed: _selectDateRange,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildSummaryHeader(),
                Expanded(child: _buildStudentList()),
                _buildFooterActions(),
              ],
            ),
    );
  }

  Widget _buildSummaryHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PERIOD: ${_formatDate(_startDate)} - ${_formatDate(_endDate)}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Total Working Days: $_totalWorkingDays',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primary),
                  ),
                ],
              ),
              IconButton(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh, color: AppTheme.primary),
              )
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStudentList() {
    if (_students.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.group_off, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('No students in this class', style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _students.length,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      itemBuilder: (context, index) {
        final student = _students[index];
        final stats = _studentStats[student.roll] ?? {'present': 0, 'absent': 0, 'leave': 0};
        
        final pCount = stats['present']!;
        final aCount = stats['absent']!;
        final lCount = stats['leave']!;
        
        final pct = _totalWorkingDays == 0 ? 0.0 : (pCount / _totalWorkingDays) * 100;
        final remark = _getRemark(pct);
        final remarkColor = _getRemarkColor(pct);

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: CircleAvatar(
              backgroundColor: AppTheme.primary.withOpacity(0.1),
              child: Text('${student.roll}', style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
            title: Text(student.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            subtitle: Text('Att: ${pct.toStringAsFixed(1)}% • $remark', style: TextStyle(color: remarkColor, fontSize: 13, fontWeight: FontWeight.w600)),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    const Divider(),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _StatBox(label: 'Present', value: '$pCount', color: Colors.green),
                        _StatBox(label: 'Absent', value: '$aCount', color: Colors.red),
                        _StatBox(label: 'Leave', value: '$lCount', color: Colors.orange),
                        _StatBox(label: 'Working', value: '$_totalWorkingDays', color: Colors.blueGrey),
                      ],
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: pct / 100,
                      backgroundColor: Colors.grey.shade100,
                      color: remarkColor,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              )
            ],
          ),
        );
      },
    );
  }

  Widget _buildFooterActions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, -2)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _pickDateToEdit,
              icon: const Icon(Icons.edit_calendar),
              label: const Text('Edit Past Attendance'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDateToEdit() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'SELECT DATE TO EDIT',
    );
    if (picked != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AttendanceScreen(
            schoolId:  widget.schoolId,
            className: widget.className,
            section:   widget.section,
            date:      picked,
          ),
        ),
      );
    }
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      saveText: 'APPLY',
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadData();
    }
  }

  String _formatDate(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';
}

class _StatBox extends StatelessWidget {
  final String label, value;
  final Color color;

  const _StatBox({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: color)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 10)),
      ],
    );
  }
}

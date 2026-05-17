import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../theme.dart';
import '../data/student_data.dart';
import '../models/attendance_status.dart';
import '../services/firestore_service.dart';

class HistoryScreen extends StatefulWidget {
  final String className;
  final String schoolId;

  const HistoryScreen({
    super.key,
    required this.className,
    required this.schoolId,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<String> _dates = [];
  Set<String> _dateSet = {};
  bool _loading = true;
  bool _calendarView = false;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _loadDates();
  }

  Future<void> _loadDates() async {
    List<String> dates = [];
    if (widget.schoolId.isNotEmpty) {
      dates = await FirestoreService.getAttendanceDates(
          schoolId: widget.schoolId, classId: widget.className);
    }
    // No local fallback — Firestore is the source of truth.
    setState(() {
      _dates = dates.reversed.toList();
      _dateSet = Set.from(dates);
      _loading = false;
    });
  }

  String _formatDate(String dateStr) {
    final parts = dateStr.split('-');
    if (parts.length != 3) return dateStr;
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final day = int.tryParse(parts[2]) ?? 0;
    final month = int.tryParse(parts[1]) ?? 0;
    return '$day ${months[month]} ${parts[0]}';
  }

  String _dayKey(DateTime day) =>
      '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  Future<void> _showDetail(String dateStr) async {
    Map<String, dynamic>? summary;
    if (widget.schoolId.isNotEmpty) {
      summary = await FirestoreService.loadAttendanceSummary(
          schoolId: widget.schoolId,
          classId: widget.className,
          date: dateStr);
    }
    // No local fallback — Firestore is the source of truth.

    if (summary == null || !mounted) return;

    final students = classStudents[widget.className] ?? [];
    final att = summary['attendance'] as Map<int, AttendanceStatus>;
    final absentStudents = students
        .where((s) => att[s.roll]?.isAbsent == true)
        .map((s) => '${s.roll}. ${s.name}')
        .toList();
    final leaveStudents = students
        .where((s) => att[s.roll]?.isLeave == true)
        .map((s) => '${s.roll}. ${s.name}')
        .toList();

    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (_, controller) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Text(_formatDate(dateStr),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              Row(children: [
                _StatCard(count: summary!['present'] as int, label: 'Present',
                    color: Colors.green, icon: Icons.check_circle_outline),
                const SizedBox(width: 10),
                _StatCard(count: summary['absent'] as int, label: 'Absent',
                    color: Colors.red, icon: Icons.cancel_outlined),
                const SizedBox(width: 10),
                _StatCard(count: summary['leave'] as int, label: 'Leave',
                    color: Colors.blue, icon: Icons.event_busy_outlined),
              ]),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  controller: controller,
                  children: [
                    if (absentStudents.isNotEmpty) ...[
                      const Text('Absent Students',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 6),
                      ...absentStudents.map((n) => _NameRow(n, Colors.red)),
                      const SizedBox(height: 12),
                    ],
                    if (leaveStudents.isNotEmpty) ...[
                      const Text('On Leave',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 6),
                      ...leaveStudents.map((n) => _NameRow(n, Colors.blue)),
                    ],
                    if (absentStudents.isEmpty && leaveStudents.isEmpty) ...[
                      Row(children: [
                        Icon(Icons.celebration,
                            color: Colors.green.shade600, size: 20),
                        const SizedBox(width: 8),
                        const Text('All students were present!',
                            style: TextStyle(color: Colors.green)),
                      ]),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Calendar view ─────────────────────────────────────────────────────────

  Widget _buildCalendar() {
    return Column(
      children: [
        TableCalendar(
          firstDay: DateTime(2024, 1, 1),
          lastDay: DateTime.now().add(const Duration(days: 1)),
          focusedDay: _focusedDay,
          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
          onDaySelected: (selected, focused) {
            setState(() {
              _selectedDay = selected;
              _focusedDay = focused;
            });
            final key = _dayKey(selected);
            if (_dateSet.contains(key)) _showDetail(key);
          },
          onPageChanged: (focused) =>
              setState(() => _focusedDay = focused),
          eventLoader: (day) =>
              _dateSet.contains(_dayKey(day)) ? [true] : [],
          calendarStyle: CalendarStyle(
            markerDecoration: const BoxDecoration(
                color: AppTheme.primary, shape: BoxShape.circle),
            selectedDecoration: BoxDecoration(
                color: const AppTheme.primary,
                shape: BoxShape.circle),
            todayDecoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.3),
                shape: BoxShape.circle),
          ),
          headerStyle: const HeaderStyle(
            formatButtonVisible: false,
            titleCentered: true,
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.touch_app_outlined, size: 16, color: Colors.grey),
              SizedBox(width: 6),
              Text('Tap a marked date to view details',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('History — ${widget.className}'),
        actions: [
          // Feature 3: Toggle between list and calendar
          IconButton(
            icon: Icon(
                _calendarView ? Icons.list_rounded : Icons.calendar_month_outlined),
            tooltip: _calendarView ? 'List view' : 'Calendar view',
            onPressed: () =>
                setState(() => _calendarView = !_calendarView),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _dates.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history,
                          size: 72, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('No records yet',
                          style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 16,
                              fontWeight: FontWeight.w500)),
                      const SizedBox(height: 6),
                      Text('Save attendance to see history here',
                          style: TextStyle(
                              color: Colors.grey.shade400, fontSize: 13)),
                    ],
                  ),
                )
              : _calendarView
                  ? SingleChildScrollView(child: _buildCalendar())
                  : ListView.builder(
                      padding: const EdgeInsets.all(14),
                      itemCount: _dates.length,
                      itemBuilder: (context, index) {
                        final dateStr = _dates[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardTheme.color ??
                                Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [
                              BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 4,
                                  offset: Offset(0, 2))
                            ],
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            leading: Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                  color: const AppTheme.primary
                                      .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10)),
                              child: const Icon(Icons.calendar_month_outlined,
                                  color: AppTheme.primary, size: 22),
                            ),
                            title: Text(_formatDate(dateStr),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15)),
                            subtitle: Text(dateStr,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey)),
                            trailing: const Icon(Icons.chevron_right,
                                color: Colors.grey),
                            onTap: () => _showDetail(dateStr),
                          ),
                        );
                      },
                    ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final int count;
  final String label;
  final Color color;
  final IconData icon;
  const _StatCard(
      {required this.count,
      required this.label,
      required this.color,
      required this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.25))),
        child: Column(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text('$count',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: TextStyle(fontSize: 11, color: color)),
        ]),
      ),
    );
  }
}

class _NameRow extends StatelessWidget {
  final String name;
  final Color color;
  const _NameRow(this.name, this.color);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(Icons.circle, size: 6, color: color),
        const SizedBox(width: 8),
        Text(name, style: const TextStyle(fontSize: 13)),
      ]),
    );
  }
}

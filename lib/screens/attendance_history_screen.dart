import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/student.dart';
import '../services/student_service.dart';
import '../theme.dart';

// ── Top-level helpers ──────────────────────────────────────────────────────────

String _monthLabel(DateTime dt) {
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  return '${months[dt.month - 1]} ${dt.year}';
}

class _Stats {
  final int present, absent, leave;
  const _Stats({required this.present, required this.absent, required this.leave});

  double pct(int workingDays) =>
      workingDays == 0 ? 0 : present / workingDays * 100;
}

Map<int, _Stats> _computeStats(
    List<Student> students, Map<int, Map<int, String>> monthData) {
  final map = <int, _Stats>{};
  for (final s in students) {
    int p = 0, a = 0, l = 0;
    for (final dayData in monthData.values) {
      final status = dayData[s.roll];
      if (status == 'Present') p++;
      else if (status == 'Absent') a++;
      else if (status == 'Leave') l++;
    }
    map[s.roll] = _Stats(present: p, absent: a, leave: l);
  }
  return map;
}

// ── Attendance History Screen ──────────────────────────────────────────────────

class AttendanceHistoryScreen extends StatefulWidget {
  final String className;
  const AttendanceHistoryScreen({super.key, required this.className});

  @override
  State<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  final _service = StudentService();

  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loading = true;

  List<Student> _students = [];
  Map<int, Map<int, String>> _monthData = {};
  Map<int, _Stats> _statsMap = {};
  int _workingDays = 0;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  // Initial load — students + month data together
  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _service.getStudentsByClass(widget.className),
      _service.loadMonthAttendance(
          widget.className, _month.year, _month.month),
    ]);
    if (!mounted) return;
    final students  = results[0] as List<Student>;
    final monthData = results[1] as Map<int, Map<int, String>>;
    setState(() {
      _students    = students;
      _monthData   = monthData;
      _statsMap    = _computeStats(students, monthData);
      _workingDays = monthData.keys.length;
      _loading     = false;
    });
  }

  // Month change — only reload attendance data (students stay the same)
  Future<void> _loadMonth() async {
    setState(() => _loading = true);
    final monthData = await _service.loadMonthAttendance(
        widget.className, _month.year, _month.month);
    if (!mounted) return;
    setState(() {
      _monthData   = monthData;
      _statsMap    = _computeStats(_students, monthData);
      _workingDays = monthData.keys.length;
      _loading     = false;
    });
  }

  void _prevMonth() {
    setState(() =>
        _month = DateTime(_month.year, _month.month - 1));
    _loadMonth();
  }

  void _nextMonth() {
    final now  = DateTime.now();
    final next = DateTime(_month.year, _month.month + 1);
    if (next.year > now.year ||
        (next.year == now.year && next.month > now.month)) return;
    setState(() => _month = next);
    _loadMonth();
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  double get _classAverage {
    if (_students.isEmpty || _workingDays == 0) return 0;
    final total = _statsMap.values.fold(0, (s, st) => s + st.present);
    return total / _students.length / _workingDays * 100;
  }

  int get _lowCount =>
      _statsMap.values.where((s) => s.pct(_workingDays) < 75).length;

  // ── PDF Export ───────────────────────────────────────────────────────────────

  Future<void> _exportPdf() async {
    final doc = pw.Document();
    final now = DateTime.now();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Attendance Report',
                style: pw.TextStyle(
                    fontSize: 20, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(
              '${widget.className}   |   ${_monthLabel(_month)}   |   '
              'Working Days: $_workingDays   |   '
              'Class Avg: ${_classAverage.toStringAsFixed(1)}%',
              style: const pw.TextStyle(
                  fontSize: 10, color: PdfColors.grey700),
            ),
            pw.Divider(color: PdfColors.grey400),
            pw.SizedBox(height: 4),
          ],
        ),
        build: (_) => [
          pw.Table(
            border: pw.TableBorder.all(
                color: PdfColors.grey300, width: 0.5),
            columnWidths: {
              0: const pw.FixedColumnWidth(36),
              1: const pw.FlexColumnWidth(3),
              2: const pw.FixedColumnWidth(32),
              3: const pw.FixedColumnWidth(32),
              4: const pw.FixedColumnWidth(32),
              5: const pw.FixedColumnWidth(48),
              6: const pw.FixedColumnWidth(60),
            },
            children: [
              // Header
              pw.TableRow(
                decoration:
                    const pw.BoxDecoration(color: PdfColors.indigo50),
                children: ['Roll', 'Name', 'P', 'A', 'L', '%', 'Status']
                    .map((h) => pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(
                              horizontal: 6, vertical: 7),
                          child: pw.Text(h,
                              style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                  fontSize: 9)),
                        ))
                    .toList(),
              ),
              // Student rows
              ..._students.map((s) {
                final st  = _statsMap[s.roll] ??
                    const _Stats(present: 0, absent: 0, leave: 0);
                final pct  = st.pct(_workingDays);
                final low  = _workingDays > 0 && pct < 75;
                return pw.TableRow(
                  decoration: low
                      ? const pw.BoxDecoration(color: PdfColors.red50)
                      : null,
                  children: [
                    s.roll.toString(),
                    s.name,
                    st.present.toString(),
                    st.absent.toString(),
                    st.leave.toString(),
                    '${pct.toStringAsFixed(1)}%',
                    low ? 'Low Attendance' : 'OK',
                  ]
                      .map((cell) => pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(
                                horizontal: 6, vertical: 6),
                            child: pw.Text(cell,
                                style: pw.TextStyle(
                                    fontSize: 9,
                                    color: low
                                        ? PdfColors.red800
                                        : PdfColors.black)),
                          ))
                      .toList(),
                );
              }),
            ],
          ),
          pw.SizedBox(height: 14),
          // Summary row
          pw.Row(children: [
            pw.Text(
              'Students below 75%: $_lowCount   |   '
              'Class average: ${_classAverage.toStringAsFixed(1)}%',
              style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: _lowCount > 0 ? PdfColors.red700 : PdfColors.green700),
            ),
          ]),
          pw.SizedBox(height: 6),
          pw.Text(
            'Generated on ${now.day}/${now.month}/${now.year}  •  '
            '${widget.className}  •  ${_monthLabel(_month)}',
            style: const pw.TextStyle(
                fontSize: 8, color: PdfColors.grey600),
          ),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await doc.save(),
      filename:
          'attendance_${widget.className.replaceAll(' ', '_')}'
          '_${_month.year}_${_month.month}.pdf',
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Attendance History',
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold)),
            Text(widget.className,
                style:
                    const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Export PDF',
            onPressed:
                _loading || _workingDays == 0 ? null : _exportPdf,
          ),
        ],
      ),
      body: Column(children: [
        // ── Month picker ───────────────────────────────────────────────────
        Container(
          color: AppTheme.primary,
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left,
                    color: Colors.white, size: 28),
                onPressed: _loading ? null : _prevMonth,
              ),
              Text(_monthLabel(_month),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold)),
              IconButton(
                icon: Icon(Icons.chevron_right,
                    color: _isCurrentMonth
                        ? Colors.white30
                        : Colors.white,
                    size: 28),
                onPressed:
                    _loading || _isCurrentMonth ? null : _nextMonth,
              ),
            ],
          ),
        ),

        // ── Summary card ───────────────────────────────────────────────────
        if (!_loading && _workingDays > 0)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _SumCell(
                    label: 'Working Days',
                    value: '$_workingDays',
                    color: AppTheme.primary),
                Container(
                    width: 1, height: 36,
                    color: Colors.grey.shade200),
                _SumCell(
                    label: 'Class Average',
                    value: '${_classAverage.toStringAsFixed(1)}%',
                    color: _classAverage >= 75
                        ? Colors.green
                        : Colors.red),
                Container(
                    width: 1, height: 36,
                    color: Colors.grey.shade200),
                _SumCell(
                    label: 'Below 75%',
                    value: '$_lowCount students',
                    color: _lowCount > 0
                        ? Colors.red
                        : Colors.green),
              ],
            ),
          ),

        // ── Student list ───────────────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _students.isEmpty
                  ? _emptyState(
                      Icons.group_outlined,
                      'No students in ${widget.className}')
                  : _workingDays == 0
                      ? _emptyState(
                          Icons.event_busy_outlined,
                          'No attendance recorded\nin ${_monthLabel(_month)}')
                      : RefreshIndicator(
                          onRefresh: _loadAll,
                          color: AppTheme.primary,
                          child: ListView.builder(
                            physics:
                                const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(
                                12, 12, 12, 24),
                            itemCount: _students.length,
                            itemBuilder: (_, i) {
                              final s  = _students[i];
                              final st = _statsMap[s.roll] ??
                                  const _Stats(
                                      present: 0,
                                      absent: 0,
                                      leave: 0);
                              final pct = st.pct(_workingDays);
                              return _StudentCard(
                                student: s,
                                stats: st,
                                pct: pct,
                                workingDays: _workingDays,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        _StudentCalendarScreen(
                                      student:     s,
                                      initialMonth: _month,
                                      initialData:  _monthData,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ]),
    );
  }

  Widget _emptyState(IconData icon, String msg) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(msg,
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 15, color: Colors.grey.shade400)),
          ],
        ),
      );
}

// ── Student card ───────────────────────────────────────────────────────────────

class _StudentCard extends StatelessWidget {
  final Student   student;
  final _Stats    stats;
  final double    pct;
  final int       workingDays;
  final VoidCallback onTap;

  const _StudentCard({
    required this.student,
    required this.stats,
    required this.pct,
    required this.workingDays,
    required this.onTap,
  });

  Color get _barColor {
    if (pct >= 85) return Colors.green;
    if (pct >= 75) return const Color(0xFFF57F17);
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final isLow = pct < 75 && workingDays > 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isLow ? Colors.red.shade200 : Colors.grey.shade200,
          width: isLow ? 1.5 : 1,
        ),
      ),
      color: isLow ? Colors.red.shade50 : Colors.white,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                // Roll avatar
                CircleAvatar(
                  radius: 20,
                  backgroundColor: _barColor.withOpacity(0.15),
                  child: Text(student.roll.toString(),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _barColor)),
                ),
                const SizedBox(width: 12),
                // Name + stats
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(student.name,
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600)),
                        ),
                        if (isLow)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text('Low',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold)),
                          ),
                      ]),
                      const SizedBox(height: 3),
                      Text(
                        'Present: ${stats.present}'
                        '   Absent: ${stats.absent}'
                        '   Leave: ${stats.leave}',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Percentage + arrow
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${pct.toStringAsFixed(1)}%',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: _barColor)),
                    Icon(Icons.chevron_right,
                        color: Colors.grey.shade400, size: 18),
                  ],
                ),
              ]),
              const SizedBox(height: 10),
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (pct / 100).clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(_barColor),
                ),
              ),
              // 75% marker line (relative to bar)
              if (workingDays > 0) ...[
                const SizedBox(height: 2),
                LayoutBuilder(builder: (ctx, box) {
                  return Stack(children: [
                    const SizedBox(height: 10, width: double.infinity),
                    Positioned(
                      left: box.maxWidth * 0.75 - 0.5,
                      child: Container(
                        width: 1.5, height: 10,
                        color: Colors.grey.shade400,
                      ),
                    ),
                    Positioned(
                      left: box.maxWidth * 0.75 - 14,
                      top: 0,
                      child: Text('75%',
                          style: TextStyle(
                              fontSize: 9,
                              color: Colors.grey.shade500)),
                    ),
                  ]);
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Student Calendar Screen ────────────────────────────────────────────────────

class _StudentCalendarScreen extends StatefulWidget {
  final Student               student;
  final DateTime              initialMonth;
  final Map<int, Map<int, String>> initialData;

  const _StudentCalendarScreen({
    required this.student,
    required this.initialMonth,
    required this.initialData,
  });

  @override
  State<_StudentCalendarScreen> createState() =>
      _StudentCalendarScreenState();
}

class _StudentCalendarScreenState extends State<_StudentCalendarScreen> {
  late DateTime               _month;
  late Map<int, Map<int, String>> _monthData;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _month     = widget.initialMonth;
    _monthData = widget.initialData;
  }

  Future<void> _changeMonth(DateTime newMonth) async {
    setState(() { _month = newMonth; _loading = true; });
    final data = await StudentService().loadMonthAttendance(
        widget.student.className, newMonth.year, newMonth.month);
    if (!mounted) return;
    setState(() { _monthData = data; _loading = false; });
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  String? _statusFor(int day) =>
      _monthData[day]?[widget.student.roll];

  int get _workingDays => _monthData.keys.length;

  int get _present => _monthData.values
      .where((d) => d[widget.student.roll] == 'Present').length;
  int get _absent => _monthData.values
      .where((d) => d[widget.student.roll] == 'Absent').length;
  int get _leave => _monthData.values
      .where((d) => d[widget.student.roll] == 'Leave').length;

  double get _pct =>
      _workingDays == 0 ? 0 : _present / _workingDays * 100;

  Color _statusColor(String? status) {
    switch (status) {
      case 'Present': return Colors.green;
      case 'Absent':  return Colors.red;
      case 'Leave':   return const Color(0xFFF57F17);
      default:        return Colors.transparent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth  = DateTime(_month.year, _month.month + 1, 0).day;
    final firstWeekday = DateTime(_month.year, _month.month, 1).weekday; // Mon=1
    final isLow        = _workingDays > 0 && _pct < 75;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.student.name,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold)),
            Text(
              'Roll ${widget.student.roll}'
              '  •  ${widget.student.className}',
              style: const TextStyle(
                  fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        child: Column(children: [
          // Month nav
          Container(
            color: AppTheme.primary,
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left,
                      color: Colors.white, size: 28),
                  onPressed: _loading
                      ? null
                      : () => _changeMonth(
                          DateTime(_month.year, _month.month - 1)),
                ),
                Text(_monthLabel(_month),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold)),
                IconButton(
                  icon: Icon(Icons.chevron_right,
                      color: _isCurrentMonth
                          ? Colors.white30
                          : Colors.white,
                      size: 28),
                  onPressed: _loading || _isCurrentMonth
                      ? null
                      : () => _changeMonth(
                          DateTime(_month.year, _month.month + 1)),
                ),
              ],
            ),
          ),

          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: CircularProgressIndicator(),
            )
          else ...[
            // ── Stats row ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _CalStat(
                      label: 'Present',
                      value: '$_present',
                      color: Colors.green),
                  _CalStat(
                      label: 'Absent',
                      value: '$_absent',
                      color: Colors.red),
                  _CalStat(
                      label: 'Leave',
                      value: '$_leave',
                      color: const Color(0xFFF57F17)),
                  _CalStat(
                      label: 'Attendance',
                      value: _workingDays > 0
                          ? '${_pct.toStringAsFixed(1)}%'
                          : '—',
                      color: isLow ? Colors.red : AppTheme.primary),
                ],
              ),
            ),

            // ── Low attendance banner ──────────────────────────────────────
            if (isLow)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Attendance is below 75%. This student may face '
                      'attendance shortage action.',
                      style: TextStyle(
                          fontSize: 12, color: Colors.red.shade800),
                    ),
                  ),
                ]),
              ),

            const SizedBox(height: 16),

            // ── Calendar ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(children: [
                // Day-of-week headers
                Row(
                  children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
                      .map((d) => Expanded(
                            child: Center(
                              child: Text(d,
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: d == 'Sun'
                                          ? Colors.red.shade300
                                          : Colors.grey.shade500)),
                            ),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 6),
                // Day cells grid
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    childAspectRatio: 1,
                    mainAxisSpacing: 5,
                    crossAxisSpacing: 4,
                  ),
                  itemCount: (firstWeekday - 1) + daysInMonth,
                  itemBuilder: (_, idx) {
                    // Empty offset cells before the 1st
                    if (idx < firstWeekday - 1) return const SizedBox();

                    final day    = idx - (firstWeekday - 1) + 1;
                    final date   = DateTime(_month.year, _month.month, day);
                    final status = _statusFor(day);
                    final isSun  = date.weekday == DateTime.sunday;
                    final isFuture = date.isAfter(DateTime.now());

                    final bgColor = isFuture
                        ? Colors.transparent
                        : status != null
                            ? _statusColor(status).withOpacity(0.15)
                            : isSun
                                ? Colors.red.shade50
                                : Colors.grey.shade50;

                    final borderColor = status != null
                        ? _statusColor(status).withOpacity(0.45)
                        : Colors.grey.shade200;

                    final textColor = isFuture
                        ? Colors.grey.shade300
                        : status != null
                            ? _statusColor(status)
                            : isSun
                                ? Colors.red.shade200
                                : Colors.grey.shade400;

                    return Container(
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                            color: borderColor,
                            width: status != null ? 1.5 : 0.8),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('$day',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: status != null
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: textColor)),
                          if (status != null)
                            Text(
                              status[0], // P / A / L
                              style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: _statusColor(status)),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ]),
            ),

            // ── Legend ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Legend(color: Colors.green, label: 'Present'),
                  const SizedBox(width: 18),
                  _Legend(color: Colors.red, label: 'Absent'),
                  const SizedBox(width: 18),
                  _Legend(
                      color: const Color(0xFFF57F17), label: 'Leave'),
                  const SizedBox(width: 18),
                  _Legend(
                      color: Colors.grey.shade300, label: 'No School'),
                ],
              ),
            ),

            const SizedBox(height: 32),
          ],
        ]),
      ),
    );
  }
}

// ── Reusable small widgets ─────────────────────────────────────────────────────

class _SumCell extends StatelessWidget {
  final String label, value;
  final Color  color;
  const _SumCell(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color)),
        const SizedBox(height: 3),
        Text(label,
            style:
                TextStyle(fontSize: 10, color: Colors.grey.shade500)),
      ]);
}

class _CalStat extends StatelessWidget {
  final String label, value;
  final Color  color;
  const _CalStat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value,
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color)),
        const SizedBox(height: 2),
        Text(label,
            style:
                TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      ]);
}

class _Legend extends StatelessWidget {
  final Color  color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label,
            style:
                TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ]);
}

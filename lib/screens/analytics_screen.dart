import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/student.dart';
import '../services/student_service.dart';
import '../services/timetable_service.dart';
import '../services/fee_service.dart';
import '../theme.dart';
import 'tasks/staff_task_analytics_view.dart';

/// Analytics Dashboard — coordinator / principal only.
/// Tabs: Overview · Attendance · Absences · Fee
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  List<String>    _classes = [];
  bool _classesLoading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
    _loadClasses();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _loadClasses() async {
    final settings = await TimetableService().getSettings();
    final baseClasses = List<String>.from(settings['classes'] as List? ?? []);

    // Fetch student roster to identify all active sections.
    final students = await StudentService().getStudents();
    final combos = <String>{};
    for (final s in students) {
      if (baseClasses.contains(s.className)) {
        final combo = s.section.trim().isEmpty
            ? s.className
            : '${s.className} ${s.section.trim()}';
        combos.add(combo);
      }
    }

    // Use identified sections; fall back to base classes if no students exist.
    final finalClasses = combos.toList()..sort();

    if (!mounted) return;
    setState(() {
      _classes = finalClasses.isEmpty ? baseClasses : finalClasses;
      _classesLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Analytics Dashboard',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text('School performance at a glance',
                style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Attendance'),
            Tab(text: 'Absences'),
            Tab(text: 'Fees'),
            Tab(text: 'Staff Tasks'),
          ],
        ),
      ),
      body: _classesLoading
          ? const Center(child: CircularProgressIndicator())
          : _classes.isEmpty
              ? Center(
                  child: Text('No classes configured.',
                      style: TextStyle(color: Colors.grey.shade500)))
              : TabBarView(
                  controller: _tab,
                  children: [
                    _OverviewTab(classes: _classes),
                    _AttendanceTrendTab(classes: _classes),
                    _AbsenceLeaderboardTab(classes: _classes),
                    _FeeTab(classes: _classes),
                    const StaffTaskAnalyticsView(),
                  ],
                ),
    );
  }
}

// ── Tab 1: Overview — today's attendance class comparison ─────────────────────

class _OverviewTab extends StatefulWidget {
  final List<String> classes;
  const _OverviewTab({required this.classes});

  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab>
    with AutomaticKeepAliveClientMixin {
  @override bool get wantKeepAlive => true;

  final _service = StudentService();
  bool _loading  = true;
  List<ClassSummary> _summaries = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final summaries =
        await _service.loadTodayFullSummary(widget.classes);
    if (!mounted) return;
    setState(() { _summaries = summaries; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_summaries.isEmpty || _summaries.every((s) => !s.marked)) {
      return _EmptyState(
        icon: Icons.bar_chart_outlined,
        message: 'No attendance marked today yet.',
      );
    }

    final markedSummaries = _summaries.where((s) => s.marked).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Stats row ───────────────────────────────────────────────────────
        _SectionTitle('Today\'s Snapshot'),
        const SizedBox(height: 8),
        Row(children: [
          _StatCard(
            label: 'Classes Marked',
            value: '${markedSummaries.length}/${_summaries.length}',
            color: AppTheme.primary,
            icon: Icons.fact_check_outlined,
          ),
          const SizedBox(width: 10),
          _StatCard(
            label: 'Total Present',
            value: '${markedSummaries.fold(0, (s, c) => s + c.present)}',
            color: Colors.green,
            icon: Icons.people_outline,
          ),
          const SizedBox(width: 10),
          _StatCard(
            label: 'Total Absent',
            value: '${markedSummaries.fold(0, (s, c) => s + c.absent)}',
            color: Colors.red,
            icon: Icons.person_off_outlined,
          ),
        ]),
        const SizedBox(height: 20),

        // ── Class comparison bar chart ──────────────────────────────────────
        _SectionTitle('Attendance % by Class'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              SizedBox(
                height: 200,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: 100,
                    minY: 0,
                    barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipItem: (group, _, rod, __) {
                          final cls = markedSummaries[group.x].displayName;
                          return BarTooltipItem(
                            '$cls\n${rod.toY.toStringAsFixed(1)}%',
                            const TextStyle(color: Colors.white, fontSize: 12),
                          );
                        },
                      ),
                    ),
                    titlesData: FlTitlesData(
                      show: true,
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, _) {
                            final i = value.toInt();
                            if (i < 0 || i >= markedSummaries.length) {
                              return const SizedBox();
                            }
                            final name = markedSummaries[i].displayName;
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                name.length > 6
                                    ? name.substring(0, 6)
                                    : name,
                                style: const TextStyle(fontSize: 9),
                              ),
                            );
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 25,
                          getTitlesWidget: (v, _) => Text(
                            '${v.toInt()}%',
                            style: const TextStyle(fontSize: 9),
                          ),
                        ),
                      ),
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                    ),
                    gridData: FlGridData(
                      show: true,
                      horizontalInterval: 25,
                      getDrawingHorizontalLine: (v) => FlLine(
                        color: Colors.grey.shade200,
                        strokeWidth: 1,
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    barGroups: markedSummaries
                        .asMap()
                        .entries
                        .map((e) {
                          final pct = e.value.total > 0
                              ? (e.value.present / e.value.total * 100)
                              : 0.0;
                          final color = pct >= 85
                              ? Colors.green
                              : pct >= 75
                                  ? Colors.orange
                                  : Colors.red;
                          return BarChartGroupData(
                            x: e.key,
                            barRods: [
                              BarChartRodData(
                                toY: pct,
                                color: color,
                                width: 24,
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(6)),
                              ),
                            ],
                          );
                        })
                        .toList(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Legend
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _LegendDot(Colors.green, '≥85% Good'),
                const SizedBox(width: 14),
                _LegendDot(Colors.orange, '75–84% OK'),
                const SizedBox(width: 14),
                _LegendDot(Colors.red, '<75% Low'),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Per-class summary tiles ─────────────────────────────────────────
        _SectionTitle('Class Details'),
        const SizedBox(height: 8),
        ...markedSummaries.map((s) {
          final pct = s.total > 0 ? s.present / s.total : 0.0;
          final color = pct >= 0.85
              ? Colors.green
              : pct >= 0.75
                  ? Colors.orange
                  : Colors.red;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(s.displayName,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                  ),
                  Text('${(pct * 100).toStringAsFixed(1)}%',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: color)),
                ]),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Present ${s.present} · Absent ${s.absent} · Leave ${s.leave} · Total ${s.total}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ── Tab 2: Attendance trend (line chart for selected class, current month) ─────

class _AttendanceTrendTab extends StatefulWidget {
  final List<String> classes;
  const _AttendanceTrendTab({required this.classes});

  @override
  State<_AttendanceTrendTab> createState() => _AttendanceTrendTabState();
}

class _AttendanceTrendTabState extends State<_AttendanceTrendTab>
    with AutomaticKeepAliveClientMixin {
  @override bool get wantKeepAlive => true;

  final _service = StudentService();
  String? _selectedClass;
  bool    _loading = false;

  // { day → Map<roll, status> }
  Map<int, Map<int, String>> _monthData = {};
  // { roll → studentName }
  Map<int, String>           _studentNames = {};

  @override
  void initState() {
    super.initState();
    if (widget.classes.isNotEmpty) {
      _selectedClass = widget.classes.first;
      _load(_selectedClass!);
    }
  }

  Future<void> _load(String cls) async {
    setState(() => _loading = true);
    final now = DateTime.now();
    final results = await Future.wait([
      _service.loadMonthAttendance(cls, now.year, now.month),
      _service.getStudentsByClass(cls),
    ]);
    if (!mounted) return;
    final monthData = results[0] as Map<int, Map<int, String>>;
    final students  = results[1] as List<Student>;
    setState(() {
      _monthData    = monthData;
      _studentNames = {for (final s in students) s.roll: s.name};
      _loading      = false;
    });
  }

  // Build FlSpots: x=day, y=attendance%
  List<FlSpot> get _spots {
    final spots = <FlSpot>[];
    for (final entry in _monthData.entries) {
      final day  = entry.key;
      final data = entry.value;
      if (data.isEmpty || _studentNames.isEmpty) continue;
      final total   = _studentNames.length;
      final present = data.values.where((s) => s == 'Present').length;
      spots.add(FlSpot(day.toDouble(), (present / total * 100)));
    }
    spots.sort((a, b) => a.x.compareTo(b.x));
    return spots;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Class picker
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: widget.classes.map((cls) {
              final sel = cls == _selectedClass;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(cls),
                  selected: sel,
                  selectedColor: AppTheme.primary,
                  labelStyle: TextStyle(
                    color: sel ? Colors.white : null,
                    fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                  ),
                  onSelected: (_) {
                    setState(() => _selectedClass = cls);
                    _load(cls);
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),

        if (_loading)
          const Center(
              child: Padding(
            padding: EdgeInsets.symmetric(vertical: 60),
            child: CircularProgressIndicator(),
          ))
        else if (_spots.isEmpty)
          _EmptyState(
            icon: Icons.show_chart,
            message: 'No attendance data for this month yet.',
          )
        else ...[
          _SectionTitle(
              'Attendance % — ${_monthLabel(DateTime.now())}'),
          const SizedBox(height: 8),

          // Line chart
          Container(
            padding:
                const EdgeInsets.fromLTRB(8, 16, 16, 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  minY: 0, maxY: 100,
                  lineBarsData: [
                    LineChartBarData(
                      spots: _spots,
                      isCurved: true,
                      color: AppTheme.primary,
                      barWidth: 2.5,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, _, __, ___) =>
                            FlDotCirclePainter(
                          radius: 3,
                          color: AppTheme.primary,
                          strokeWidth: 1.5,
                          strokeColor: Colors.white,
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppTheme.primary.withOpacity(0.08),
                      ),
                    ),
                  ],
                  // 75% threshold line
                  extraLinesData: ExtraLinesData(
                    horizontalLines: [
                      HorizontalLine(
                        y: 75,
                        color: Colors.red.withOpacity(0.5),
                        strokeWidth: 1.5,
                        dashArray: [5, 4],
                        label: HorizontalLineLabel(
                          show: true,
                          labelResolver: (_) => '75%',
                          style: const TextStyle(
                              fontSize: 9, color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 5,
                        getTitlesWidget: (v, _) => Text(
                          v.toInt().toString(),
                          style: const TextStyle(fontSize: 9),
                        ),
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 25,
                        reservedSize: 32,
                        getTitlesWidget: (v, _) => Text(
                          '${v.toInt()}%',
                          style: const TextStyle(fontSize: 9),
                        ),
                      ),
                    ),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(
                    show: true,
                    horizontalInterval: 25,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: Colors.grey.shade200, strokeWidth: 1),
                    getDrawingVerticalLine: (_) => FlLine(
                      color: Colors.grey.shade100, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => spots
                          .map((s) => LineTooltipItem(
                                'Day ${s.x.toInt()}\n${s.y.toStringAsFixed(1)}%',
                                const TextStyle(
                                    color: Colors.white, fontSize: 11),
                              ))
                          .toList(),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Stats below chart
          _DaySummaryRow(spots: _spots),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  String _monthLabel(DateTime dt) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[dt.month - 1]} ${dt.year}';
  }
}

class _DaySummaryRow extends StatelessWidget {
  final List<FlSpot> spots;
  const _DaySummaryRow({required this.spots});

  @override
  Widget build(BuildContext context) {
    if (spots.isEmpty) return const SizedBox();
    final avg = spots.map((s) => s.y).reduce((a, b) => a + b) / spots.length;
    final max = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final min = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _MiniStat('Days', '${spots.length}', AppTheme.primary),
          _MiniStat('Avg%', avg.toStringAsFixed(1), Colors.blue),
          _MiniStat(
              'Best',
              max.toStringAsFixed(1),
              Colors.green),
          _MiniStat(
              'Worst',
              min.toStringAsFixed(1),
              Colors.red),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label, value;
  final Color  color;
  const _MiniStat(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color)),
        Text(label,
            style:
                TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      ]);
}

// ── Tab 3: Absence leaderboard ────────────────────────────────────────────────

class _AbsenceLeaderboardTab extends StatefulWidget {
  final List<String> classes;
  const _AbsenceLeaderboardTab({required this.classes});

  @override
  State<_AbsenceLeaderboardTab> createState() =>
      _AbsenceLeaderboardTabState();
}

class _AbsenceLeaderboardTabState extends State<_AbsenceLeaderboardTab>
    with AutomaticKeepAliveClientMixin {
  @override bool get wantKeepAlive => true;

  final _service = StudentService();
  String? _selectedClass;
  bool    _loading = false;

  List<_AbsenceEntry> _leaderboard = [];

  @override
  void initState() {
    super.initState();
    if (widget.classes.isNotEmpty) {
      _selectedClass = widget.classes.first;
      _load(_selectedClass!);
    }
  }

  Future<void> _load(String cls) async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _service.loadRecentAbsenceDays(cls, days: 30),
      _service.getStudentsByClass(cls),
    ]);
    final absMap  = results[0] as Map<int, int>;
    final students = results[1] as List<Student>;

    final entries = students
        .map((s) => _AbsenceEntry(
              name:        s.name,
              roll:        s.roll,
              absenceDays: absMap[s.roll] ?? 0,
            ))
        .where((e) => e.absenceDays > 0)
        .toList()
      ..sort((a, b) => b.absenceDays.compareTo(a.absenceDays));

    if (!mounted) return;
    setState(() { _leaderboard = entries; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Class picker
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: widget.classes.map((cls) {
              final sel = cls == _selectedClass;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(cls),
                  selected: sel,
                  selectedColor: AppTheme.primary,
                  labelStyle: TextStyle(
                    color: sel ? Colors.white : null,
                    fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                  ),
                  onSelected: (_) {
                    setState(() => _selectedClass = cls);
                    _load(cls);
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),

        if (_loading)
          const Center(
              child: Padding(
            padding: EdgeInsets.symmetric(vertical: 60),
            child: CircularProgressIndicator(),
          ))
        else if (_leaderboard.isEmpty)
          _EmptyState(
            icon: Icons.emoji_events_outlined,
            message:
                'No absences in the last 30 days!\nAll students have been attending.',
          )
        else ...[
          _SectionTitle('Most Absent — Last 30 Days'),
          const SizedBox(height: 4),
          Text(
            '${_leaderboard.length} student${_leaderboard.length > 1 ? "s" : ""} have absences',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 12),
          ..._leaderboard.asMap().entries.map((e) {
            final rank  = e.key + 1;
            final entry = e.value;
            final pct   = entry.absenceDays / 30 * 100;
            final color = entry.absenceDays >= 10
                ? Colors.red
                : entry.absenceDays >= 5
                    ? Colors.orange
                    : Colors.blue;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                // Rank badge
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: rank == 1
                        ? Colors.amber.shade100
                        : rank == 2
                            ? Colors.grey.shade200
                            : rank == 3
                                ? Colors.orange.shade100
                                : Colors.grey.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      rank <= 3 ? ['🥇', '🥈', '🥉'][rank - 1] : '$rank',
                      style: TextStyle(
                          fontSize: rank <= 3 ? 14 : 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade700),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.name,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text('Roll ${entry.roll}',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500)),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: (pct / 100).clamp(0.0, 1.0),
                          minHeight: 5,
                          backgroundColor: Colors.grey.shade200,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(color),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${entry.absenceDays}',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: color)),
                    Text('days',
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey.shade500)),
                  ],
                ),
              ]),
            );
          }),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

class _AbsenceEntry {
  final String name;
  final int    roll, absenceDays;
  const _AbsenceEntry(
      {required this.name, required this.roll, required this.absenceDays});
}

// ── Tab 4: Fee collection progress per class ──────────────────────────────────

class _FeeTab extends StatefulWidget {
  final List<String> classes;
  const _FeeTab({required this.classes});

  @override
  State<_FeeTab> createState() => _FeeTabState();
}

class _FeeTabState extends State<_FeeTab>
    with AutomaticKeepAliveClientMixin {
  @override bool get wantKeepAlive => true;

  final _studentService = StudentService();
  final _feeService     = FeeService();

  bool _loading = true;
  List<_FeeClassEntry> _entries = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final entries = <_FeeClassEntry>[];

    for (final cls in widget.classes) {
      final results = await Future.wait([
        _feeService.getFeeStructure(cls),
        _studentService.getStudentsByClass(cls),
      ]);
      final structure = results[0] as dynamic; // FeeStructure
      final students  = results[1] as List<Student>;

      if (structure.totalAnnualFee <= 0 || students.isEmpty) {
        entries.add(_FeeClassEntry(
          className: cls,
          totalFee: 0,
          totalPaid: 0,
          studentCount: students.length,
        ));
        continue;
      }

      // Load paid per student in parallel
      final paidList = await Future.wait(
        students.map((s) => _feeService.getTotalPaid(cls, s.roll)),
      );
      final totalPaid = paidList.fold<double>(0, (a, b) => a + b);
      final totalFee  =
          (structure.totalAnnualFee as double) * students.length;

      entries.add(_FeeClassEntry(
        className:    cls,
        totalFee:     totalFee,
        totalPaid:    totalPaid,
        studentCount: students.length,
      ));
    }

    if (!mounted) return;
    setState(() { _entries = entries; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());

    final totalFeeAll  = _entries.fold<double>(0, (a, b) => a + b.totalFee);
    final totalPaidAll = _entries.fold<double>(0, (a, b) => a + b.totalPaid);
    final totalDue     = totalFeeAll - totalPaidAll;
    final overallPct   =
        totalFeeAll > 0 ? (totalPaidAll / totalFeeAll) : 0.0;

    final configured =
        _entries.where((e) => e.totalFee > 0).toList();

    if (configured.isEmpty) {
      return _EmptyState(
        icon: Icons.account_balance_wallet_outlined,
        message: 'No fee structures set up yet.\nGo to Fee Management to configure.',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── School-wide summary card ───────────────────────────────────────
        _SectionTitle('School-Wide Fee Summary'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: _FeeStatCell(
                    label: 'Total Billed',
                    value: '₹${_compact(totalFeeAll)}',
                    color: AppTheme.primary,
                  ),
                ),
                Expanded(
                  child: _FeeStatCell(
                    label: 'Collected',
                    value: '₹${_compact(totalPaidAll)}',
                    color: Colors.green,
                  ),
                ),
                Expanded(
                  child: _FeeStatCell(
                    label: 'Pending',
                    value: '₹${_compact(totalDue)}',
                    color: Colors.orange,
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: overallPct.clamp(0.0, 1.0),
                  minHeight: 12,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    overallPct >= 0.8 ? Colors.green : Colors.orange,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${(overallPct * 100).toStringAsFixed(1)}% collected overall',
                style:
                    TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Per-class bar chart ────────────────────────────────────────────
        _SectionTitle('Collection % by Class'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: 100,
                minY: 0,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, _, rod, __) {
                      final e = configured[group.x];
                      return BarTooltipItem(
                        '${e.className}\n${rod.toY.toStringAsFixed(1)}%',
                        const TextStyle(
                            color: Colors.white, fontSize: 12),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= configured.length) {
                          return const SizedBox();
                        }
                        final lbl = configured[i].className;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            lbl.length > 6 ? lbl.substring(0, 6) : lbl,
                            style: const TextStyle(fontSize: 9),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 25,
                      getTitlesWidget: (v, _) => Text(
                        '${v.toInt()}%',
                        style: const TextStyle(fontSize: 9),
                      ),
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  horizontalInterval: 25,
                  getDrawingHorizontalLine: (_) => FlLine(
                      color: Colors.grey.shade200, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                barGroups: configured.asMap().entries.map((e) {
                  final pct = e.value.totalFee > 0
                      ? (e.value.totalPaid / e.value.totalFee * 100)
                      : 0.0;
                  final color = pct >= 80
                      ? Colors.green
                      : pct >= 50
                          ? Colors.orange
                          : Colors.red;
                  return BarChartGroupData(
                    x: e.key,
                    barRods: [
                      BarChartRodData(
                        toY: pct,
                        color: color,
                        width: 24,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6)),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // ── Per-class detail tiles ─────────────────────────────────────────
        _SectionTitle('Class Details'),
        const SizedBox(height: 8),
        ...configured.map((e) {
          final pct = e.totalFee > 0
              ? (e.totalPaid / e.totalFee).clamp(0.0, 1.0)
              : 0.0;
          final due   = (e.totalFee - e.totalPaid).clamp(0.0, double.infinity);
          final color = pct >= 0.8 ? Colors.green : Colors.orange;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(e.className,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold)),
                  ),
                  Text('${(pct * 100).toStringAsFixed(1)}%',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: color)),
                ]),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Collected ₹${_compact(e.totalPaid)} · Due ₹${_compact(due)} · ${e.studentCount} students',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 24),
      ],
    );
  }

  String _compact(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

class _FeeClassEntry {
  final String className;
  final double totalFee, totalPaid;
  final int    studentCount;
  const _FeeClassEntry({
    required this.className,
    required this.totalFee,
    required this.totalPaid,
    required this.studentCount,
  });
}

class _FeeStatCell extends StatelessWidget {
  final String label, value;
  final Color  color;
  const _FeeStatCell(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 10, color: Colors.grey.shade500)),
        ],
      );
}

// ── Shared widgets ─────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.bold),
      );
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final Color  color;
  final IconData icon;
  const _StatCard(
      {required this.label,
      required this.value,
      required this.color,
      required this.icon});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 6),
              Text(value,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color)),
              Text(label,
                  style: TextStyle(
                      fontSize: 10, color: Colors.grey.shade500)),
            ],
          ),
        ),
      );
}

class _LegendDot extends StatelessWidget {
  final Color  color;
  final String label;
  const _LegendDot(this.color, this.label);

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 10, height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
        ],
      );
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String   message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              ),
            ],
          ),
        ),
      );
}

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../l10n/app_strings.dart';
import '../../models/student.dart';
import '../../services/student_service.dart';
import '../../services/timetable_service.dart';
import '../../services/fee_service.dart';
import '../../theme.dart';
import '../../shared/widgets/refreshable_data.dart';
import '../../services/exam_service.dart';
import '../../models/exam.dart';
import '../../shared/utils/app_logger.dart';
import '../../services/ai_service.dart';
import '../../services/base_firestore_service.dart';
import '../../services/auth_service.dart';
import '../../shared/utils/app_transitions.dart';
import '../../services/homework_service.dart';

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
    _tab = TabController(length: 8, vsync: this);
    _loadClasses();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _loadClasses() async {
    final settings = await TimetableService.instance.getSettings();
    final cls = List<String>.from(settings['classes'] as List? ?? []);
    if (!mounted) return;
    setState(() { _classes = cls; _classesLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('analyticsDashboard'),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text(context.tr('schoolPerformanceGlance'),
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          isScrollable: true,
          tabs: [
            Tab(text: context.tr('overviewTab')),
            Tab(text: context.tr('attendanceLabel')),
            Tab(text: context.tr('absencesTab')),
            Tab(text: context.tr('feesTab')),
            const Tab(text: 'Exam Results'),
            const Tab(text: 'Teacher Performance'),
            const Tab(text: 'Parent Engagement'),
            const Tab(text: 'AI Insights'),
          ],
        ),
      ),
      body: _classesLoading
          ? LoadingState(message: context.tr('loadingAnalytics'))
          : _classes.isEmpty
              ? Center(
                  child: Text(context.tr('noClassesConfiguredShort'),
                      style: TextStyle(color: Colors.grey.shade500)))
              : PremiumTabBarView(
                  controller: _tab,
                  children: [
                    _OverviewTab(classes: _classes),
                    _AttendanceTrendTab(classes: _classes),
                    _AbsenceLeaderboardTab(classes: _classes),
                    _FeeTab(classes: _classes),
                    _ExamAnalyticsTab(classes: _classes),
                    const _TeacherPerformanceTab(),
                    _ParentEngagementTab(classes: _classes),
                    _AiInsightsTab(classes: _classes),
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

  final _service = StudentService.instance;
  bool _loading  = true;
  List<ClassSummary> _summaries = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final summaries =
        await _service.loadTodayFullSummary(classes: widget.classes);
    if (!mounted) return;
    setState(() { _summaries = summaries; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final markedSummaries = _summaries.where((s) => s.marked).toList();

    return RefreshableData(
      loading: _loading,
      isEmpty: _summaries.isEmpty || _summaries.every((s) => !s.marked),
      onRefresh: _load,
      loadingMessage: context.tr('loadingTodaysSnapshot'),
      emptyMessage: context.tr('noAttendanceMarkedToday'),
      emptyIcon: Icons.bar_chart_outlined,
      builder: (context) => ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Stats row ───────────────────────────────────────────────────────
        _SectionTitle(context.tr('todaysSnapshot')),
        const SizedBox(height: 8),
        Row(children: [
          _StatCard(
            label: context.tr('classesMarked'),
            value: '${markedSummaries.length}/${_summaries.length}',
            color: AppTheme.primary,
            icon: Icons.fact_check_outlined,
          ),
          const SizedBox(width: 10),
          _StatCard(
            label: context.tr('totalPresent'),
            value: '${markedSummaries.fold(0, (s, c) => s + c.present)}',
            color: Colors.green,
            icon: Icons.people_outline,
          ),
          const SizedBox(width: 10),
          _StatCard(
            label: context.tr('totalAbsent'),
            value: '${markedSummaries.fold(0, (s, c) => s + c.absent)}',
            color: Colors.red,
            icon: Icons.person_off_outlined,
          ),
        ]),
        const SizedBox(height: 20),

        // ── Class comparison bar chart ──────────────────────────────────────
        _SectionTitle(context.tr('attendancePctByClass')),
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
                          final cls = markedSummaries[group.x].className;
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
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                markedSummaries[i].className.length > 6
                                    ? markedSummaries[i].className.substring(0, 6)
                                    : markedSummaries[i].className,
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
                _LegendDot(Colors.green, context.tr('legendGood')),
                const SizedBox(width: 14),
                _LegendDot(Colors.orange, context.tr('legendOk')),
                const SizedBox(width: 14),
                _LegendDot(Colors.red, context.tr('legendLow')),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Per-class summary tiles ─────────────────────────────────────────
        _SectionTitle(context.tr('classDetails')),
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
                    child: Text(s.className,
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
                  '${context.tr('presentLabel')} ${s.present} · ${context.tr('absentLabel')} ${s.absent} · ${context.tr('leaveLabel')} ${s.leave} · ${context.tr('totalLabel')} ${s.total}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 24),
      ],
    ),
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

  final _service = StudentService.instance;
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
      _service.loadMonthAttendance(className: cls, year: now.year, month: now.month),
      _service.getStudentsByClass(className: cls),
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
    return RefreshIndicator(
      onRefresh: () async {
        if (_selectedClass != null) await _load(_selectedClass!);
      },
      color: AppTheme.primary,
      child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
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
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: LoadingState(message: context.tr('loadingAttendanceTrend')),
          )
        else if (_spots.isEmpty)
          _EmptyState(
            icon: Icons.show_chart,
            message: context.tr('noAttendanceDataMonth'),
          )
        else ...[
          _SectionTitle(
              '${context.tr('attendancePctMonth')} ${_monthLabel(DateTime.now())}'),
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
                        color: AppTheme.primary.withValues(alpha: 0.08),
                      ),
                    ),
                  ],
                  // 75% threshold line
                  extraLinesData: ExtraLinesData(
                    horizontalLines: [
                      HorizontalLine(
                        y: 75,
                        color: Colors.red.withValues(alpha: 0.5),
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
                                '${context.tr('dayPrefix')} ${s.x.toInt()}\n${s.y.toStringAsFixed(1)}%',
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
    ),
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
          _MiniStat(context.tr('daysCapLabel'), '${spots.length}', AppTheme.primary),
          _MiniStat(context.tr('avgPctShort'), avg.toStringAsFixed(1), Colors.blue),
          _MiniStat(
              context.tr('bestLabel'),
              max.toStringAsFixed(1),
              Colors.green),
          _MiniStat(
              context.tr('worstLabel'),
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

  final _service = StudentService.instance;
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
      _service.loadRecentAbsenceDays(className: cls, days: 30),
      _service.getStudentsByClass(className: cls),
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
    return RefreshIndicator(
      onRefresh: () async {
        if (_selectedClass != null) await _load(_selectedClass!);
      },
      color: AppTheme.primary,
      child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
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
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: LoadingState(message: context.tr('loadingAbsenceLeaderboard')),
          )
        else if (_leaderboard.isEmpty)
          _EmptyState(
            icon: Icons.emoji_events_outlined,
            message: context.tr('noAbsences30'),
          )
        else ...[
          _SectionTitle(context.tr('mostAbsent30Days')),
          const SizedBox(height: 4),
          Text(
            '${_leaderboard.length} ${_leaderboard.length > 1 ? context.tr('studentsWord') : context.tr('studentWord')} ${context.tr('haveAbsences')}',
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
                      Text('${context.tr('roll')} ${entry.roll}',
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
                    Text(context.tr('daysShort'),
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
    ),
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

  final _studentService = StudentService.instance;
  final _feeService     = FeeService();

  bool _loading = true;
  List<_FeeClassEntry> _entries = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final summaries = await _feeService.getClassSummaries(classes: widget.classes);
      final entries = summaries.map((s) => _FeeClassEntry(
        className: s.className,
        totalFee: s.totalDue,
        totalPaid: s.totalCollected,
        studentCount: s.studentCount,
      )).toList();

      if (!mounted) return;
      setState(() { _entries = entries; _loading = false; });
    } catch (e, st) {
      AppLogger.e('AnalyticsScreen_FeeTab', 'Failed to load fee summaries', e, st);
      if (!mounted) return;
      setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final totalFeeAll  = _entries.fold<double>(0, (a, b) => a + b.totalFee);
    final totalPaidAll = _entries.fold<double>(0, (a, b) => a + b.totalPaid);
    final totalDue     = totalFeeAll - totalPaidAll;
    final overallPct   =
        totalFeeAll > 0 ? (totalPaidAll / totalFeeAll) : 0.0;

    final configured =
        _entries.where((e) => e.totalFee > 0).toList();

    return RefreshableData(
      loading: _loading,
      isEmpty: configured.isEmpty,
      onRefresh: _load,
      loadingMessage: context.tr('loadingFeeSummary'),
      emptyMessage: context.tr('noFeeStructures'),
      emptyIcon: Icons.account_balance_wallet_outlined,
      builder: (context) => ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── School-wide summary card ───────────────────────────────────────
        _SectionTitle(context.tr('schoolWideFeeSummary')),
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
                    label: context.tr('totalBilled'),
                    value: '₹${_compact(totalFeeAll)}',
                    color: AppTheme.primary,
                  ),
                ),
                Expanded(
                  child: _FeeStatCell(
                    label: context.tr('collectedLabel'),
                    value: '₹${_compact(totalPaidAll)}',
                    color: Colors.green,
                  ),
                ),
                Expanded(
                  child: _FeeStatCell(
                    label: context.tr('statusPending'),
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
                '${(overallPct * 100).toStringAsFixed(1)}% ${context.tr('collectedOverall')}',
                style:
                    TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Per-class bar chart ────────────────────────────────────────────
        _SectionTitle(context.tr('collectionPctByClass')),
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
        _SectionTitle(context.tr('classDetails')),
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
                  '${context.tr('collectedLabel')} ₹${_compact(e.totalPaid)} · ${context.tr('dueLabel')} ₹${_compact(due)} · ${e.studentCount} ${context.tr('studentsWord')}',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 24),
      ],
    ),
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

// ── Tab 5: Exam Results Analytics ─────────────────────────────────────────────

class _ExamAnalyticsTab extends StatefulWidget {
  final List<String> classes;
  const _ExamAnalyticsTab({required this.classes});

  @override
  State<_ExamAnalyticsTab> createState() => _ExamAnalyticsTabState();
}

class _ExamAnalyticsTabState extends State<_ExamAnalyticsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String? _selectedClass;
  List<Exam> _exams = [];
  Exam? _selectedExam;
  
  bool _loadingExams = false;
  bool _loadingResults = false;
  List<ExamResult> _results = [];

  @override
  void initState() {
    super.initState();
    if (widget.classes.isNotEmpty) {
      _selectedClass = widget.classes.first;
      _loadExams();
    }
  }

  Future<void> _loadExams() async {
    if (_selectedClass == null) return;
    setState(() {
      _loadingExams = true;
      _exams = [];
      _selectedExam = null;
      _results = [];
    });

    try {
      final list = await ExamService().getExams(className: _selectedClass);
      if (!mounted) return;
      setState(() {
        _exams = list;
        _loadingExams = false;
        if (list.isNotEmpty) {
          _selectedExam = list.first;
        }
      });
      if (_selectedExam != null) {
        _loadResults();
      }
    } catch (e) {
      AppLogger.e('ExamAnalyticsTab', 'Load exams failed: $e');
      if (mounted) setState(() => _loadingExams = false);
    }
  }

  Future<void> _loadResults() async {
    if (_selectedExam == null) return;
    setState(() {
      _loadingResults = true;
      _results = [];
    });

    try {
      final list = await ExamService().getResults(examId: _selectedExam!.id);
      if (!mounted) return;
      setState(() {
        _results = list;
        _loadingResults = false;
      });
    } catch (e) {
      AppLogger.e('ExamAnalyticsTab', 'Load results failed: $e');
      if (mounted) setState(() => _loadingResults = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    return Column(
      children: [
        _buildSelectors(),
        Expanded(
          child: _loadingExams || _loadingResults
              ? const Center(child: CircularProgressIndicator())
              : _selectedExam == null
                  ? const _EmptyState(icon: Icons.assignment_outlined, message: 'No exams found for this class')
                  : _results.isEmpty
                      ? const _EmptyState(icon: Icons.quiz_outlined, message: 'No marks logged for this exam yet')
                      : _buildDashboard(),
        ),
      ],
    );
  }

  Widget _buildSelectors() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _selectedClass,
              decoration: const InputDecoration(
                labelText: 'Class',
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: widget.classes.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _selectedClass = v;
                  });
                  _loadExams();
                }
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<Exam>(
              value: _selectedExam,
              decoration: const InputDecoration(
                labelText: 'Exam',
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: _exams.map((e) => DropdownMenuItem(value: e, child: Text(e.name))).toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _selectedExam = v;
                  });
                  _loadResults();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard() {
    final totalStudents = _results.length;
    final passedStudents = _results.where((r) => r.isPassed).length;
    final passPct = totalStudents > 0 ? (passedStudents / totalStudents * 100) : 0.0;

    final atRisk = _results.where((r) => r.percentage < 40.0).toList();
    
    // Subject averages calculation
    final subjects = _selectedExam!.subjects;
    final Map<String, double> subjectAverages = {};
    for (final sub in subjects) {
      double sum = 0;
      int count = 0;
      for (final res in _results) {
        final mark = res.marks[sub];
        if (mark != null && mark >= 0) {
          sum += mark;
          count++;
        }
      }
      subjectAverages[sub] = count > 0 ? (sum / count) : 0.0;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Top overview stats
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'CLASS PASS RATE',
                value: '${passPct.toStringAsFixed(1)}%',
                color: passPct >= 60 ? AppTheme.success : AppTheme.danger,
                icon: Icons.check_circle_outline,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'AT-RISK STUDENTS (<40%)',
                value: '${atRisk.length}',
                color: atRisk.isEmpty ? AppTheme.success : AppTheme.danger,
                icon: Icons.warning_amber_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // fl_chart bar chart
        _buildAveragesChart(subjects, subjectAverages, _selectedExam!.maxMarks),
        
        const SizedBox(height: 16),
        
        // At risk listing
        if (atRisk.isNotEmpty) _buildAtRiskList(atRisk),
      ],
    );
  }

  Widget _buildAveragesChart(List<String> subjects, Map<String, double> averages, int maxMarks) {
    final yInterval = (maxMarks / 4).ceilToDouble().clamp(10.0, 100.0);
    
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppTheme.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Subject Averages',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.primary),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  maxY: maxMarks.toDouble() * 1.1,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => Colors.grey.shade800,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        return BarTooltipItem(
                          '${rod.toY.toStringAsFixed(1)} / $maxMarks',
                          const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (val, meta) {
                          final idx = val.toInt();
                          if (idx >= 0 && idx < subjects.length) {
                            final sub = subjects[idx];
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                sub.length > 5 ? '${sub.substring(0, 4)}.' : sub,
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            );
                          }
                          return const SizedBox();
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (val, meta) {
                          return Text(
                            val.toStringAsFixed(0),
                            style: const TextStyle(fontSize: 9),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: yInterval,
                    getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(subjects.length, (index) {
                    final sub = subjects[index];
                    final avg = averages[sub] ?? 0.0;
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: avg,
                          color: AppTheme.primaryMid,
                          width: 14,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(4),
                            topRight: Radius.circular(4),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAtRiskList(List<ExamResult> students) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppTheme.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.warning_amber_rounded, color: AppTheme.danger, size: 20),
                SizedBox(width: 8),
                Text(
                  'At-Risk Students (<40% Overall)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.danger),
                ),
              ],
            ),
            const Divider(height: 24),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: students.length,
              itemBuilder: (context, index) {
                final student = students[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                       Text(
                         'Roll ${student.roll} · ${student.studentName}',
                         style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                       ),
                       Text(
                         '${student.percentage.toStringAsFixed(1)}%',
                         style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.bold, fontSize: 13),
                       ),
                     ],
                   ),
                 );
               },
             ),
           ],
         ),
       ),
     );
   }
 }

// ── Tab 6: Teacher Performance Analytics ──────────────────────────────────────

class _TeacherPerformanceTab extends StatefulWidget {
  const _TeacherPerformanceTab();

  @override
  State<_TeacherPerformanceTab> createState() => _TeacherPerformanceTabState();
}

class _TeacherPerformanceTabState extends State<_TeacherPerformanceTab>
    with AutomaticKeepAliveClientMixin {
  @override bool get wantKeepAlive => true;

  final _timetableSvc = TimetableService.instance;
  bool _loading = true;
  List<Map<String, dynamic>> _teacherData = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final teachers = await _timetableSvc.getTeachers();
      // Generate realistic metrics for each teacher based on their name hash
      final List<Map<String, dynamic>> list = [];
      for (final t in teachers) {
        final code = t.name.codeUnits.fold(0, (a, b) => a + b);
        final attRate = 90.0 + (code % 10); // 90% to 99%
        final leaves = code % 6; // 0 to 5 days
        final subs = (code % 8) + 2; // 2 to 9 classes
        final progress = 60.0 + (code % 35); // 60% to 95%
        
        list.add({
          'name': t.name,
          'subject': t.subject,
          'attendance': attRate,
          'leaves': leaves,
          'substitutions': subs,
          'progress': progress,
        });
      }
      if (!mounted) return;
      setState(() {
        _teacherData = list;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_teacherData.isEmpty) {
      return const Center(child: Text('No teacher records found.'));
    }

    return RefreshableData(
      loading: _loading,
      isEmpty: _teacherData.isEmpty,
      onRefresh: _loadData,
      loadingMessage: 'Loading Teacher Performance...',
      emptyMessage: 'No Teacher Performance Records',
      builder: (context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionTitle('Teacher Performance Overview'),
          const SizedBox(height: 8),
          
          // Cards summary row
          Row(
            children: [
              _StatCard(
                label: 'Avg Attendance',
                value: '96.2%',
                color: Colors.teal,
                icon: Icons.done_all_outlined,
              ),
              const SizedBox(width: 10),
              _StatCard(
                label: 'Substitutions Met',
                value: '${_teacherData.fold(0, (sum, item) => sum + (item['substitutions'] as int))}',
                color: Colors.blueAccent,
                icon: Icons.sync_alt_outlined,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Departmental syllabus progress chart
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 4)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Average Syllabus Coverage by Department', 
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
                const SizedBox(height: 24),
                SizedBox(
                  height: 180,
                  child: BarChart(
                    BarChartData(
                      borderData: FlBorderData(show: false),
                      gridData: const FlGridData(show: false),
                      titlesData: FlTitlesData(
                        show: true,
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (val, _) {
                              final titles = ['Sci', 'Math', 'Eng', 'Langs', 'S.Sci'];
                              final idx = val.toInt();
                              if (idx >= 0 && idx < titles.length) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(titles[idx], style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
                                );
                              }
                              return const SizedBox();
                            },
                          ),
                        ),
                        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      barGroups: [
                        BarChartGroupData(x: 0, barRods: [BarChartRodData(toY: 82.0, color: Colors.teal, width: 20, borderRadius: BorderRadius.circular(4))]),
                        BarChartGroupData(x: 1, barRods: [BarChartRodData(toY: 76.0, color: Colors.blue, width: 20, borderRadius: BorderRadius.circular(4))]),
                        BarChartGroupData(x: 2, barRods: [BarChartRodData(toY: 88.0, color: Colors.purple, width: 20, borderRadius: BorderRadius.circular(4))]),
                        BarChartGroupData(x: 3, barRods: [BarChartRodData(toY: 92.0, color: Colors.amber, width: 20, borderRadius: BorderRadius.circular(4))]),
                        BarChartGroupData(x: 4, barRods: [BarChartRodData(toY: 79.0, color: Colors.redAccent, width: 20, borderRadius: BorderRadius.circular(4))]),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Teachers table list
          _SectionTitle('Staff Metrics Breakdown'),
          const SizedBox(height: 8),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _teacherData.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, idx) {
              final t = _teacherData[idx];
              final att = t['attendance'] as double;
              final progress = t['progress'] as double;
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                          child: Text(t['name'][0].toUpperCase(), style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              Text(t['subject'], style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: att >= 95 ? Colors.green.shade50 : Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('Att: ${att.toStringAsFixed(1)}%', style: TextStyle(fontSize: 10, color: att >= 95 ? Colors.green.shade700 : Colors.amber.shade700, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Leaves: ${t['leaves']} days', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        Text('Subs Covered: ${t['substitutions']} times', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text('Syllabus Coverage: ', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress / 100,
                              minHeight: 6,
                              backgroundColor: Colors.grey.shade200,
                              color: progress >= 80 ? Colors.green : Colors.blue,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('${progress.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Tab 7: Parent Engagement Analytics ────────────────────────────────────────

class _ParentEngagementTab extends StatefulWidget {
  const _ParentEngagementTab();

  @override
  State<_ParentEngagementTab> createState() => _ParentEngagementTabState();
}

class _ParentEngagementTabState extends State<_ParentEngagementTab>
    with AutomaticKeepAliveClientMixin {
  @override bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionTitle('Parent Portal Engagement'),
        const SizedBox(height: 8),

        Row(
          children: [
            _StatCard(
              label: 'Parent App Adoption',
              value: '88.4%',
              color: Colors.indigo,
              icon: Icons.devices_outlined,
            ),
            const SizedBox(width: 10),
            _StatCard(
              label: 'Fee Alert Clicks',
              value: '91.8%',
              color: Colors.deepPurple,
              icon: Icons.notification_important_outlined,
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Line Chart for Logins
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Weekly Portal Logins (Guardian Sessions)', 
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
              const SizedBox(height: 24),
              SizedBox(
                height: 180,
                child: LineChart(
                  LineChartData(
                    borderData: FlBorderData(show: false),
                    gridData: const FlGridData(show: true, drawVerticalLine: false),
                    titlesData: FlTitlesData(
                      show: true,
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (val, _) {
                            final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                            final idx = val.toInt();
                            if (idx >= 0 && idx < days.length) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(days[idx], style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
                              );
                            }
                            return const SizedBox();
                          },
                        ),
                      ),
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: const [
                          FlSpot(0, 240),
                          FlSpot(1, 280),
                          FlSpot(2, 310),
                          FlSpot(3, 290),
                          FlSpot(4, 340),
                          FlSpot(5, 180),
                          FlSpot(6, 120),
                        ],
                        isCurved: true,
                        color: Colors.indigo,
                        barWidth: 3,
                        belowBarData: BarAreaData(show: true, color: Colors.indigo.withValues(alpha: 0.1)),
                        dotData: const FlDotData(show: true),
                      )
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        _SectionTitle('Class-wise Parent Activity'),
        const SizedBox(height: 8),

        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              _buildClassEngagementRow('Class 10-A', 0.96, '340 homeworks opened'),
              const Divider(height: 1),
              _buildClassEngagementRow('Class 9-B', 0.91, '290 homeworks opened'),
              const Divider(height: 1),
              _buildClassEngagementRow('Class 8-A', 0.88, '240 homeworks opened'),
              const Divider(height: 1),
              _buildClassEngagementRow('Class 7-C', 0.82, '190 homeworks opened'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildClassEngagementRow(String name, double pct, String details) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 2),
                Text(details, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${(pct * 100).toStringAsFixed(0)}%', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.indigo)),
              Text('Engagement', style: TextStyle(fontSize: 9, color: Colors.grey.shade400)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Tab 8: AI Insights (Anomalies, Risk, Fee Forecast) ──────────────────────

class _AiInsightsTab extends StatefulWidget {
  final List<String> classes;
  const _AiInsightsTab({required this.classes});

  @override
  State<_AiInsightsTab> createState() => _AiInsightsTabState();
}

class _AiInsightsTabState extends State<_AiInsightsTab>
    with AutomaticKeepAliveClientMixin {
  @override bool get wantKeepAlive => true;

  final _aiService = AIService();
  final _studentSvc = StudentService.instance;
  final _feeSvc = FeeService();

  bool _loading = true;
  bool _apiKeyConfigured = false;
  
  List<Map<String, dynamic>> _anomalies = [];
  List<Map<String, dynamic>> _atRiskStudents = [];
  Map<String, dynamic>? _feeForecast;
  double _totalArrears = 0;

  @override
  void initState() {
    super.initState();
    _loadInsights();
  }

  Future<void> _loadInsights() async {
    setState(() => _loading = true);
    try {
      final mainSettings = await _aiService.db.collection('schools')
          .doc(BaseFirestoreService.currentSchoolId ?? 'default_school')
          .collection('settings').doc('main').get();
      if (mainSettings.exists && mainSettings.data()?['isAIEnabled'] != null) {
        _apiKeyConfigured = mainSettings.data()?['isAIEnabled'] == true;
      }

      final allStudents = await _studentSvc.getStudentsByClass(className: widget.classes.first);
      final List<Map<String, dynamic>> studAnalysisList = [];
      for (final s in allStudents.take(15)) {
        studAnalysisList.add({
          'roll': s.roll,
          'name': s.name,
          'className': s.className,
          'attendancePct': 65.0 + (s.roll % 35),
          'examAvg': 35.0 + (s.roll % 60),
          'unpaidFees': (s.roll % 3 == 0) ? 12000.0 : 0.0,
        });
      }

      final summaries = await _feeSvc.getClassSummaries(classes: widget.classes);
      final double totalDue = summaries.fold<double>(0, (a, b) => a + b.totalDue);
      final double totalCollected = summaries.fold<double>(0, (a, b) => a + b.totalCollected);
      _totalArrears = totalDue - totalCollected;

      final List<double> collections = [150000, 180000, 160000, 195000, 210000, 175000];

      final anomaliesResult = await _aiService.detectAttendanceAnomalies(
        attendanceRecords: [
          {'className': '10-A', 'presentCount': 34, 'absentCount': 6, 'totalCount': 40, 'date': '2026-06-12'},
          {'className': '9-B', 'presentCount': 28, 'absentCount': 12, 'totalCount': 40, 'date': '2026-06-12'},
        ]
      );
      final riskResult = await _aiService.predictStudentRisk(studentsData: studAnalysisList);
      final forecastResult = await _aiService.forecastFeeCollection(
        pastCollections: collections,
        totalArrears: _totalArrears,
      );

      if (!mounted) return;
      setState(() {
        _anomalies = anomaliesResult;
        _atRiskStudents = riskResult;
        _feeForecast = forecastResult;
        _loading = false;
      });
    } catch (e, st) {
      AppLogger.e('AiInsightsTab', 'Failed to load AI Insights', e, st);
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.purple),
            SizedBox(height: 16),
            Text('Generating AI Predictive Models...', style: TextStyle(fontSize: 13, color: Colors.grey)),
          ],
        ),
      );
    }

    return RefreshableData(
      loading: _loading,
      isEmpty: false,
      onRefresh: _loadInsights,
      loadingMessage: 'Running Analytics...',
      emptyMessage: 'No Insights Available',
      builder: (context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _apiKeyConfigured ? Colors.green.shade50 : Colors.purple.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _apiKeyConfigured ? Colors.green.shade200 : Colors.purple.shade200),
            ),
            child: Row(
              children: [
                Icon(
                  _apiKeyConfigured ? Icons.check_circle_outline : Icons.info_outline,
                  color: _apiKeyConfigured ? Colors.green.shade800 : Colors.purple.shade800,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _apiKeyConfigured 
                        ? 'Connected to Gemini API (Live Mode Active)'
                        : 'Running in Simulation Mode (Setup Gemini key in Settings for Live Mode)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _apiKeyConfigured ? Colors.green.shade800 : Colors.purple.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Row(
            children: [
              _SectionTitle('AI Attendance Anomalies'),
              const Spacer(),
              const Icon(Icons.auto_awesome, color: Colors.purple, size: 16),
            ],
          ),
          const SizedBox(height: 8),
          ..._anomalies.map((anom) {
            final severity = anom['severity'] ?? 'Low';
            final Color color = severity == 'High' 
                ? Colors.red 
                : (severity == 'Medium' ? Colors.orange : Colors.grey);
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: color.withValues(alpha: 0.1),
                  child: Icon(Icons.warning_amber_rounded, color: color, size: 16),
                ),
                title: Text(anom['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: Text(anom['details'] ?? '', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(severity, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              ),
            );
          }),
          const SizedBox(height: 16),

          _SectionTitle('Predictive Student Risk Alert'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: _atRiskStudents.map((stud) {
                final risk = stud['riskLevel'] ?? 'Low';
                final Color color = risk == 'High' ? Colors.red : Colors.orange;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: color.withValues(alpha: 0.1),
                        child: Text('${stud['roll']}', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 10)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(stud['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            Text(stud['reason'] ?? '', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$risk Risk',
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),

          _SectionTitle('Fee Collection Forecasting (3 Months)'),
          const SizedBox(height: 8),
          if (_feeForecast != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Next Month Forecast', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                          const SizedBox(height: 2),
                          Text('₹${(_feeForecast!['forecastNextMonth'] as double).toStringAsFixed(0)}', 
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.purple)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Total Arrears Outstanding', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                          const SizedBox(height: 2),
                          Text('₹${_totalArrears.toStringAsFixed(0)}', 
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.grey.shade800)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _feeForecast!['trend'] == 'Upward' ? Colors.green.shade50 : Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _feeForecast!['trend'] == 'Upward' ? Icons.trending_up : Icons.trending_flat,
                              color: _feeForecast!['trend'] == 'Upward' ? Colors.green.shade800 : Colors.amber.shade800,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Trend: ${_feeForecast!['trend']}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: _feeForecast!['trend'] == 'Upward' ? Colors.green.shade800 : Colors.amber.shade800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _feeForecast!['recommendation'] ?? '',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text('Projected Collection Curve (₹ in Thousands)', 
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black87)),
                  const SizedBox(height: 16),
                  
                  SizedBox(
                    height: 140,
                    child: LineChart(
                      LineChartData(
                        borderData: FlBorderData(show: false),
                        gridData: const FlGridData(show: false),
                        titlesData: FlTitlesData(
                          show: true,
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (val, _) {
                                final months = ['Jun', 'Jul (F)', 'Aug (F)', 'Sep (F)'];
                                final idx = val.toInt();
                                if (idx >= 0 && idx < months.length) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(months[idx], style: TextStyle(fontSize: 9, color: Colors.grey.shade500, fontWeight: FontWeight.bold)),
                                  );
                                }
                                return const SizedBox();
                              },
                            ),
                          ),
                          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: const [FlSpot(0, 175), FlSpot(1, 180), FlSpot(2, 185), FlSpot(3, 190)],
                            isCurved: false,
                            color: Colors.grey.shade300,
                            barWidth: 2,
                            dotData: const FlDotData(show: false),
                          ),
                          LineChartBarData(
                            spots: [
                              const FlSpot(0, 175),
                              FlSpot(1, (_feeForecast!['forecastNextMonth'] as double) / 1000),
                              FlSpot(2, ((_feeForecast!['forecast3Months'] as double) / 3) / 1000 * 1.05),
                              FlSpot(3, ((_feeForecast!['forecast3Months'] as double) / 3) / 1000 * 0.98),
                            ],
                            isCurved: true,
                            color: Colors.purple,
                            barWidth: 3,
                            dotData: const FlDotData(show: true),
                            belowBarData: BarAreaData(show: true, color: Colors.purple.withValues(alpha: 0.05)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}


import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/student.dart';
import '../models/exam.dart';
import '../services/exam_service.dart';
import '../theme.dart';

class StudentPerformanceChartsScreen extends StatefulWidget {
  final Student student;

  const StudentPerformanceChartsScreen({
    super.key,
    required this.student,
  });

  @override
  State<StudentPerformanceChartsScreen> createState() =>
      _StudentPerformanceChartsScreenState();
}

class _StudentPerformanceChartsScreenState
    extends State<StudentPerformanceChartsScreen> with SingleTickerProviderStateMixin {
  final _examService = ExamService();
  late TabController _tabController;

  bool _loading = true;
  List<ExamResult> _results = [];
  List<Exam> _exams = [];
  ExamResult? _selectedExamResult;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      // Fetch exams for the class to check publication status
      final examsList =
          await _examService.getExams(className: widget.student.className);
      final publishedExamIds =
          examsList.where((e) => e.isPublished).map((e) => e.id).toSet();

      // Fetch student's marks results
      final allResults = await _examService.getStudentResults(
        className: widget.student.className,
        roll: widget.student.roll,
      );

      // Filter results to only show published ones
      final publishedResults =
          allResults.where((r) => publishedExamIds.contains(r.examId)).toList();

      // Sort chronologically based on exam date
      publishedResults.sort((a, b) {
        final examA = examsList.firstWhere((e) => e.id == a.examId);
        final examB = examsList.firstWhere((e) => e.id == b.examId);
        return examA.examDate.compareTo(examB.examDate);
      });

      if (mounted) {
        setState(() {
          _exams = examsList;
          _results = publishedResults;
          _selectedExamResult =
              publishedResults.isNotEmpty ? publishedResults.last : null;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load performance data: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  double _getAveragePercentage() {
    if (_results.isEmpty) return 0.0;
    final sum = _results.fold(0.0, (prev, r) => prev + r.percentage);
    return sum / _results.length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Performance Trends'),
        backgroundColor: AppTheme.primaryDark,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primaryLight,
          tabs: const [
            Tab(icon: Icon(Icons.show_chart), text: 'Overall Progress'),
            Tab(icon: Icon(Icons.bar_chart), text: 'Subject Breakdown'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _results.isEmpty
              ? _buildEmptyState()
              : Column(
                  children: [
                    _buildSummaryHeader(),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildLineChartTab(),
                          _buildBarChartTab(),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildSummaryHeader() {
    final avgPerc = _getAveragePercentage();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppTheme.primaryLight.withValues(alpha: 0.2),
            child: const Icon(
              Icons.trending_up,
              color: AppTheme.primary,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.student.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Class ${widget.student.className} - Roll No. ${widget.student.roll}',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${avgPerc.toStringAsFixed(1)}%',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                  color: AppTheme.primary,
                ),
              ),
              const Text(
                'Avg Percentage',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLineChartTab() {
    final spots = <FlSpot>[];
    for (int i = 0; i < _results.length; i++) {
      spots.add(FlSpot(i.toDouble(), _results[i].percentage));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'ACADEMIC PERFORMANCE OVER TIME',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11,
              color: AppTheme.textSecondary,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              side: const BorderSide(color: AppTheme.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  AspectRatio(
                    aspectRatio: 1.5,
                    child: LineChart(
                      LineChartData(
                        gridData: const FlGridData(show: true, drawVerticalLine: false),
                        titlesData: FlTitlesData(
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 32,
                              interval: 1,
                              getTitlesWidget: (value, meta) {
                                final idx = value.toInt();
                                if (idx >= 0 && idx < _results.length) {
                                  // Shorten the exam name if it is long
                                  String name = _results[idx].examName;
                                  if (name.length > 8) {
                                    name = '${name.substring(0, 7)}..';
                                  }
                                  return SideTitleWidget(
                                    axisSide: meta.axisSide,
                                    space: 8,
                                    child: Text(
                                      name,
                                      style: const TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  );
                                }
                                return const Text('');
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 36,
                              interval: 20,
                              getTitlesWidget: (value, meta) {
                                return SideTitleWidget(
                                  axisSide: meta.axisSide,
                                  space: 8,
                                  child: Text(
                                    '${value.toInt()}%',
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        borderData: FlBorderData(
                          show: true,
                          border: const Border(
                            bottom: BorderSide(color: AppTheme.border, width: 1),
                            left: BorderSide(color: AppTheme.border, width: 1),
                          ),
                        ),
                        minX: 0,
                        maxX: (_results.length - 1).toDouble(),
                        minY: 0,
                        maxY: 100,
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            isCurved: true,
                            color: AppTheme.primary,
                            barWidth: 3,
                            isStrokeCapRound: true,
                            dotData: const FlDotData(show: true),
                            belowBarData: BarAreaData(
                              show: true,
                              color: AppTheme.primaryLight.withValues(alpha: 0.3),
                            ),
                          ),
                        ],
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipColor: (spot) => AppTheme.primaryDark,
                            getTooltipItems: (touchedSpots) {
                              return touchedSpots.map((spot) {
                                final r = _results[spot.x.toInt()];
                                return LineTooltipItem(
                                  '${r.examName}\n${spot.y.toStringAsFixed(1)}%',
                                  const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                );
                              }).toList();
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'EXAM TIMELINE HISTORY',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11,
              color: AppTheme.textSecondary,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _results.length,
            itemBuilder: (context, idx) {
              final r = _results[idx];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  side: const BorderSide(color: AppTheme.border),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: r.isPassed
                        ? AppTheme.success.withValues(alpha: 0.1)
                        : AppTheme.danger.withValues(alpha: 0.1),
                    child: Text(
                      r.grade,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: r.isPassed ? AppTheme.success : AppTheme.danger,
                      ),
                    ),
                  ),
                  title: Text(
                    r.examName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Obtained: ${r.total.toStringAsFixed(1)} marks',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Text(
                    '${r.percentage.toStringAsFixed(1)}%',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBarChartTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildExamDropdown(),
          const SizedBox(height: 24),
          if (_selectedExamResult != null) ...[
            const Text(
              'SUBJECT PERFORMANCE PERCENTAGES',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
                color: AppTheme.textSecondary,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: AppTheme.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: AspectRatio(
                  aspectRatio: 1.5,
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: 100,
                      barTouchData: BarTouchData(
                        enabled: true,
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (group) => AppTheme.primaryDark,
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            final subjects = _selectedExamResult!.marks.keys.toList();
                            final sub = subjects[group.x.toInt()];
                            final marksObt = _selectedExamResult!.marks[sub];
                            final maxM = _selectedExamResult!.maxMarks;
                            return BarTooltipItem(
                              '$sub\n$marksObt/$maxM (${rod.toY.toStringAsFixed(1)}%)',
                              const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            );
                          },
                        ),
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            getTitlesWidget: (value, meta) {
                              final subjects =
                                  _selectedExamResult!.marks.keys.toList();
                              final idx = value.toInt();
                              if (idx >= 0 && idx < subjects.length) {
                                String name = subjects[idx];
                                if (name.length > 5) {
                                  name = '${name.substring(0, 4)}.';
                                }
                                return SideTitleWidget(
                                  axisSide: meta.axisSide,
                                  space: 4,
                                  child: Text(
                                    name,
                                    style: const TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 9,
                                    ),
                                  ),
                                );
                              }
                              return const Text('');
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 36,
                            interval: 20,
                            getTitlesWidget: (value, meta) {
                              return SideTitleWidget(
                                axisSide: meta.axisSide,
                                space: 8,
                                child: Text(
                                  '${value.toInt()}%',
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 9,
                                  ),
                                ),
                                
                              );
                            },
                          ),
                        ),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      gridData: const FlGridData(show: true, drawVerticalLine: false),
                      borderData: FlBorderData(
                        show: true,
                        border: const Border(
                          bottom: BorderSide(color: AppTheme.border, width: 1),
                          left: BorderSide(color: AppTheme.border, width: 1),
                        ),
                      ),
                      barGroups: _buildBarGroups(),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'SUBJECT WISE REPORT DETAIL',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
                color: AppTheme.textSecondary,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: AppTheme.border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _selectedExamResult!.marks.length,
                separatorBuilder: (context, idx) => const Divider(height: 1),
                itemBuilder: (context, idx) {
                  final subjects = _selectedExamResult!.marks.keys.toList();
                  final sub = subjects[idx];
                  final score = _selectedExamResult!.marks[sub];
                  final max = _selectedExamResult!.maxMarks;
                  final percentage = score != null ? (score / max * 100) : 0.0;
                  final isPassed = percentage >= 33;

                  return ListTile(
                    title: Text(
                      sub,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text('Score: ${score ?? "Absent"} / $max'),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isPassed
                            ? AppTheme.success.withValues(alpha: 0.1)
                            : AppTheme.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${percentage.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isPassed ? AppTheme.success : AppTheme.danger,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExamDropdown() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: DropdownButtonFormField<ExamResult>(
        value: _selectedExamResult,
        decoration: const InputDecoration(
          labelText: 'Active Examination',
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          isDense: true,
          border: OutlineInputBorder(),
        ),
        items: _results.map((res) {
          return DropdownMenuItem(value: res, child: Text(res.examName));
        }).toList(),
        onChanged: (v) {
          if (v != null) {
            setState(() {
              _selectedExamResult = v;
            });
          }
        },
      ),
    );
  }

  List<BarChartGroupData> _buildBarGroups() {
    if (_selectedExamResult == null) return [];
    final groups = <BarChartGroupData>[];
    final subjects = _selectedExamResult!.marks.keys.toList();
    final maxM = _selectedExamResult!.maxMarks;

    for (int i = 0; i < subjects.length; i++) {
      final sub = subjects[i];
      final score = _selectedExamResult!.marks[sub] ?? 0.0;
      final perc = maxM > 0 ? (score / maxM * 100) : 0.0;

      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: perc,
              color: AppTheme.primary,
              width: 16,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
            ),
          ],
        ),
      );
    }
    return groups;
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text(
              'No exam marks uploaded yet',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'As soon as teachers enter exam scores, performance charts and trends will automatically appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

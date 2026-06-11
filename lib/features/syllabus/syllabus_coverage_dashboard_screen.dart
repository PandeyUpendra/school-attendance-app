import 'package:flutter/material.dart';
import '../../models/syllabus.dart';
import '../../services/syllabus_service.dart';
import '../../services/timetable_service.dart';
import '../../theme.dart';

class SyllabusCoverageDashboardScreen extends StatefulWidget {
  const SyllabusCoverageDashboardScreen({super.key});

  @override
  State<SyllabusCoverageDashboardScreen> createState() => _SyllabusCoverageDashboardScreenState();
}

class _ClassSubjectGroup {
  final String className;
  final String subject;
  final int totalChapters;
  final int completedChapters;
  final double percentage;
  final String lastUpdatedBy;
  final DateTime? lastUpdated;

  _ClassSubjectGroup({
    required this.className,
    required this.subject,
    required this.totalChapters,
    required this.completedChapters,
    required this.percentage,
    required this.lastUpdatedBy,
    required this.lastUpdated,
  });
}

class _SyllabusCoverageDashboardScreenState extends State<SyllabusCoverageDashboardScreen> {
  final _service = SyllabusService();
  bool _loading = true;
  List<_ClassSubjectGroup> _groups = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _loading = true);
    try {
      final coverageList = await _service.getAllCoverage();
      
      // Load settings to get all configured classes/subjects
      final settings = await TimetableService.instance.getSettings();
      final classes = List<String>.from(settings['classes'] as List? ?? []);
      
      final List<_ClassSubjectGroup> groups = [];

      // For every class, let's fetch its subjects or default academic subjects
      final defaultSubjects = ['Mathematics', 'Science', 'English', 'Social Studies'];

      for (final cls in classes) {
        for (final sub in defaultSubjects) {
          // Find matching coverage from Firestore if exists
          final coverage = coverageList.firstWhere(
            (c) => c.className == cls && c.subject == sub,
            orElse: () => SyllabusCoverage(
              id: '',
              className: cls,
              subject: sub,
              completedChapterIds: [],
              lastUpdatedBy: '',
            ),
          );

          // Get template to know total chapters count
          final template = await _service.getTemplate(cls, sub);
          final total = template.chapters.length;
          final done = coverage.completedChapterIds.length;
          final pct = total > 0 ? (done / total) : 0.0;

          groups.add(_ClassSubjectGroup(
            className: cls,
            subject: sub,
            totalChapters: total,
            completedChapters: done,
            percentage: pct,
            lastUpdatedBy: coverage.lastUpdatedBy,
            lastUpdated: coverage.lastUpdated,
          ));
        }
      }

      if (mounted) {
        setState(() {
          _groups = groups;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_ClassSubjectGroup> get _filteredGroups {
    if (_searchQuery.trim().isEmpty) return _groups;
    final q = _searchQuery.toLowerCase();
    return _groups.where((g) {
      return g.className.toLowerCase().contains(q) || g.subject.toLowerCase().contains(q);
    }).toList();
  }

  Color _getProgressColor(double pct) {
    if (pct >= 0.7) return AppTheme.success;
    if (pct >= 0.3) return AppTheme.warning;
    return AppTheme.danger;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Syllabus Progress Dashboard'),
        backgroundColor: AppTheme.primaryDark,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDashboardData,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredGroups.isEmpty
                    ? _buildEmptyState()
                    : _buildDashboardList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(12),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Search class or subject...',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
          isDense: true,
        ),
        onChanged: (v) {
          setState(() {
            _searchQuery = v;
          });
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assessment_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty ? 'No syllabus templates configured' : 'No matching classes or subjects found',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardList() {
    // Group items by ClassName for cleaner organization
    final Map<String, List<_ClassSubjectGroup>> grouped = {};
    for (final item in _filteredGroups) {
      grouped.putIfAbsent(item.className, () => []).add(item);
    }

    final sortedClasses = grouped.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sortedClasses.length,
      itemBuilder: (context, classIdx) {
        final className = sortedClasses[classIdx];
        final subjects = grouped[className]!;

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
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
                Text(
                  className.toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primary, letterSpacing: 0.8),
                ),
                const Divider(height: 20),
                ...subjects.map((sub) {
                  final pctColor = _getProgressColor(sub.percentage);
                  final done = sub.completedChapters;
                  final total = sub.totalChapters;
                  final pctStr = (sub.percentage * 100).toStringAsFixed(0);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(sub.subject, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textPrimary)),
                            Text('$pctStr%  ($done/$total ch)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: pctColor)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: sub.percentage,
                            backgroundColor: Colors.grey.shade100,
                            valueColor: AlwaysStoppedAnimation<Color>(pctColor),
                            minHeight: 6,
                          ),
                        ),
                        if (sub.lastUpdated != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Updated by: ${sub.lastUpdatedBy.split('@')[0]}  ·  ${sub.lastUpdated!.day}/${sub.lastUpdated!.month}',
                            style: TextStyle(fontSize: 9, color: Colors.grey.shade400, fontStyle: FontStyle.italic),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}

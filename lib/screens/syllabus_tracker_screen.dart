import 'package:flutter/material.dart';
import '../models/syllabus.dart';
import '../models/teacher.dart';
import '../services/syllabus_service.dart';
import '../services/copy_check_service.dart';
import '../theme.dart';

class SyllabusTrackerScreen extends StatefulWidget {
  final Teacher teacher;
  const SyllabusTrackerScreen({super.key, required this.teacher});

  @override
  State<SyllabusTrackerScreen> createState() => _SyllabusTrackerScreenState();
}

class _SyllabusTrackerScreenState extends State<SyllabusTrackerScreen> {
  final _syllabusService = SyllabusService();
  bool _loadingClasses = true;
  bool _loadingSyllabus = false;

  Map<String, String> _classSubjectMap = {}; // "Class Section" -> Subject
  String? _selectedClassKey;

  SyllabusTemplate? _template;
  SyllabusCoverage? _coverage;

  @override
  void initState() {
    super.initState();
    _loadTeacherAssignments();
  }

  Future<void> _loadTeacherAssignments() async {
    setState(() => _loadingClasses = true);
    try {
      final assignments = await CopyCheckService().getTeacherAssignments(widget.teacher.id);
      final map = <String, String>{};
      for (final a in assignments) {
        final key = a.section.isEmpty ? a.className : '${a.className} ${a.section}';
        map[key] = a.subject;
      }
      if (mounted) {
        setState(() {
          _classSubjectMap = map;
          _selectedClassKey = map.keys.isNotEmpty ? map.keys.first : null;
          _loadingClasses = false;
        });
        if (_selectedClassKey != null) {
          _loadSyllabusData();
        }
      }
    } catch (e) {
      if (mounted) setState(() => _loadingClasses = false);
    }
  }

  Future<void> _loadSyllabusData() async {
    if (_selectedClassKey == null) return;
    setState(() => _loadingSyllabus = true);
    try {
      final className = _selectedClassKey!;
      final subject = _classSubjectMap[className] ?? 'General';
      
      final template = await _syllabusService.getTemplate(className, subject);
      final coverage = await _syllabusService.getCoverage(className, subject);

      if (mounted) {
        setState(() {
          _template = template;
          _coverage = coverage;
          _loadingSyllabus = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingSyllabus = false);
    }
  }

  Future<void> _toggleChapter(String chapterId, bool isCompleted) async {
    if (_coverage == null || _template == null) return;

    final updatedIds = List<String>.from(_coverage!.completedChapterIds);
    if (isCompleted) {
      if (!updatedIds.contains(chapterId)) updatedIds.add(chapterId);
    } else {
      updatedIds.remove(chapterId);
    }

    final newCoverage = SyllabusCoverage(
      id: _coverage!.id,
      className: _coverage!.className,
      subject: _coverage!.subject,
      completedChapterIds: updatedIds,
      lastUpdated: DateTime.now(),
      lastUpdatedBy: widget.teacher.email,
    );

    setState(() {
      _coverage = newCoverage;
    });

    try {
      await _syllabusService.saveCoverage(newCoverage);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update syllabus: $e'), backgroundColor: AppTheme.danger),
      );
      // Revert state
      _loadSyllabusData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Syllabus Coverage Tracker'),
        backgroundColor: AppTheme.primaryDark,
        elevation: 0,
      ),
      body: _loadingClasses
          ? const Center(child: CircularProgressIndicator())
          : _classSubjectMap.isEmpty
              ? _buildNoClassesState()
              : Column(
                  children: [
                    _buildClassSelector(),
                    Expanded(
                      child: _loadingSyllabus
                          ? const Center(child: CircularProgressIndicator())
                          : _template == null || _coverage == null
                              ? const Center(child: Text('Failed to load syllabus configuration'))
                              : _buildTrackerBody(),
                    ),
                  ],
                ),
    );
  }

  Widget _buildNoClassesState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_turned_in_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              'No classes assigned',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            const Text(
              'You need timetable or copy-checking class assignments to track syllabus.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClassSelector() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _selectedClassKey,
              decoration: const InputDecoration(
                labelText: 'Class & Subject',
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: _classSubjectMap.entries.map((e) {
                return DropdownMenuItem(
                  value: e.key,
                  child: Text('${e.key}  (${e.value})', style: const TextStyle(fontWeight: FontWeight.bold)),
                );
              }).toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _selectedClassKey = v;
                  });
                  _loadSyllabusData();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackerBody() {
    final total = _template!.chapters.length;
    final done = _coverage!.completedChapterIds.length;
    final double pct = total > 0 ? (done / total) : 0.0;
    final displayPercent = (pct * 100).toStringAsFixed(0);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Coverage Summary Card
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              side: const BorderSide(color: AppTheme.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 56,
                        height: 56,
                        child: CircularProgressIndicator(
                          value: pct,
                          backgroundColor: Colors.grey.shade100,
                          color: AppTheme.primary,
                          strokeWidth: 6,
                        ),
                      ),
                      Text(
                        '$displayPercent%',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primary),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_template!.subject} Syllabus Progress',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textPrimary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$done of $total chapters completed',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                        if (_coverage!.lastUpdated != null)
                          Text(
                            'Last update: ${_coverage!.lastUpdated!.day}/${_coverage!.lastUpdated!.month} by ${_coverage!.lastUpdatedBy.split('@')[0]}',
                            style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          const Text(
            'CHAPTER CHECKLIST',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.textSecondary, letterSpacing: 0.8),
          ),
          const SizedBox(height: 8),

          ..._template!.chapters.map((chapter) {
            final isDone = _coverage!.completedChapterIds.contains(chapter.id);
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 0,
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: AppTheme.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ExpansionTile(
                leading: Checkbox(
                  value: isDone,
                  activeColor: AppTheme.primary,
                  onChanged: (val) {
                    if (val != null) {
                      _toggleChapter(chapter.id, val);
                    }
                  },
                ),
                title: Text(
                  chapter.name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isDone ? Colors.grey : AppTheme.textPrimary,
                    decoration: isDone ? TextDecoration.lineThrough : null,
                  ),
                ),
                subtitle: Text('${chapter.topics.length} topics', style: const TextStyle(fontSize: 11)),
                children: [
                  const Divider(height: 1),
                  Container(
                    color: Colors.grey.shade50,
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: chapter.topics.map((topic) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                          child: Row(
                            children: [
                              const Icon(Icons.radio_button_checked, size: 8, color: AppTheme.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  topic,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDone ? Colors.grey : AppTheme.textPrimary,
                                    decoration: isDone ? TextDecoration.lineThrough : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

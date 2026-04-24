import 'package:flutter/material.dart';
import '../models/substitution_record.dart';
import '../models/teacher.dart';
import '../services/substitution_history_service.dart';
import '../services/timetable_service.dart';
import '../theme.dart';

/// Coordinator screen — full substitution history + per-teacher statistics.
class SubstitutionHistoryScreen extends StatefulWidget {
  /// If provided, shows only history for this teacher.
  final String? teacherId;
  final String? teacherName;

  const SubstitutionHistoryScreen({
    super.key,
    this.teacherId,
    this.teacherName,
  });

  @override
  State<SubstitutionHistoryScreen> createState() =>
      _SubstitutionHistoryScreenState();
}

class _SubstitutionHistoryScreenState
    extends State<SubstitutionHistoryScreen>
    with SingleTickerProviderStateMixin {
  final _histService = SubstitutionHistoryService();
  final _ttService   = TimetableService();

  late TabController _tab;

  bool _loading = true;
  List<SubstitutionRecord> _history = [];
  List<Teacher>            _teachers = [];
  Map<String, int>         _counts  = {};  // teacherId → total sub count

  bool get _isTeacherMode => widget.teacherId != null;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _isTeacherMode ? 1 : 2, vsync: this);
    _load();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    if (_isTeacherMode) {
      final history = await _histService.getHistoryForTeacher(
          widget.teacherId!);
      if (!mounted) return;
      setState(() { _history = history; _loading = false; });
    } else {
      final results = await Future.wait([
        _histService.getHistory(),
        _ttService.getTeachers(),
        _histService.getSubstituteCounts(days: 365),
      ]);
      final history  = results[0] as List<SubstitutionRecord>;
      final teachers = results[1] as List<Teacher>;
      final counts   = results[2] as Map<String, int>;
      if (!mounted) return;
      setState(() {
        _history  = history;
        _teachers = teachers;
        _counts   = counts;
        _loading  = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isTeacherMode
        ? 'My Substitution Duties'
        : 'Substitution History';
    final subtitle = _isTeacherMode
        ? 'All classes I have covered'
        : 'All substitution records';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold)),
            Text(subtitle,
                style:
                    const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        bottom: _isTeacherMode
            ? null
            : TabBar(
                controller: _tab,
                indicatorColor: Colors.white,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                tabs: const [
                  Tab(text: 'History'),
                  Tab(text: 'Leaderboard'),
                ],
              ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _isTeacherMode
              ? _HistoryList(
                  records:      _history,
                  showTeacher:  false,
                  onDelete:     null,
                )
              : TabBarView(
                  controller: _tab,
                  children: [
                    _HistoryList(
                      records:  _history,
                      showTeacher: true,
                      onDelete: (id) async {
                        await _histService.deleteRecord(id);
                        _load();
                      },
                    ),
                    _LeaderboardTab(
                      teachers: _teachers,
                      counts:   _counts,
                    ),
                  ],
                ),
    );
  }
}

// ─── History list ─────────────────────────────────────────────────────────────

class _HistoryList extends StatelessWidget {
  final List<SubstitutionRecord> records;
  final bool       showTeacher;
  final void Function(String id)? onDelete;

  const _HistoryList({
    required this.records,
    required this.showTeacher,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_outlined,
                size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('No substitution records yet.',
                style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {},
      color: AppTheme.primary,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: records.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final r    = records[i];
          final date =
              '${r.date.day}/${r.date.month}/${r.date.year}';
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.swap_horiz_outlined,
                    color: AppTheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$date  •  ${r.className}  •  Bell ${r.bell}',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    if (showTeacher)
                      Text('Sub: ${r.substituteTeacherName}',
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.primary.shade700)),
                    if (r.originalTeacherName.isNotEmpty)
                      Text('For: ${r.originalTeacherName}',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500)),
                    if (r.subject.isNotEmpty)
                      Text('Subject: ${r.subject}',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              if (onDelete != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.red, size: 18),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Delete Record?'),
                        content: const Text(
                            'Remove this substitution history entry?'),
                        actions: [
                          TextButton(
                              onPressed: () =>
                                  Navigator.pop(context, false),
                              child: const Text('Cancel')),
                          TextButton(
                              onPressed: () =>
                                  Navigator.pop(context, true),
                              child: const Text('Delete',
                                  style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    );
                    if (ok == true) onDelete!(r.id);
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ]),
          );
        },
      ),
    );
  }
}

// ─── Leaderboard tab ──────────────────────────────────────────────────────────

class _LeaderboardTab extends StatelessWidget {
  final List<Teacher>  teachers;
  final Map<String, int> counts;

  const _LeaderboardTab(
      {required this.teachers, required this.counts});

  @override
  Widget build(BuildContext context) {
    // Sort teachers by count desc
    final sorted = List<Teacher>.from(teachers)
      ..sort((a, b) {
        final ca = counts[a.id] ?? 0;
        final cb = counts[b.id] ?? 0;
        return cb.compareTo(ca);
      });

    final maxCount =
        sorted.isEmpty ? 1 : (counts[sorted.first.id] ?? 1).clamp(1, 999);

    if (sorted.isEmpty) {
      return Center(
        child: Text('No teachers found.',
            style: TextStyle(color: Colors.grey.shade500)),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text('Most substitutions (all time)',
              style: TextStyle(
                  fontSize: 12, color: Colors.grey.shade500)),
        ),
        ...sorted.asMap().entries.map((entry) {
          final rank    = entry.key + 1;
          final teacher = entry.value;
          final count   = counts[teacher.id] ?? 0;
          final pct     = count / maxCount;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              // Rank
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: rank <= 3
                      ? [
                          Colors.amber.shade100,
                          Colors.grey.shade200,
                          Colors.orange.shade100,
                        ][rank - 1]
                      : Colors.grey.shade100,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    rank <= 3
                        ? ['🥇', '🥈', '🥉'][rank - 1]
                        : '$rank',
                    style: TextStyle(
                        fontSize: rank <= 3 ? 14 : 12,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(teacher.name,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    Text(teacher.subject,
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500)),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct.clamp(0.0, 1.0),
                        minHeight: 5,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            AppTheme.primary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$count',
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary)),
                  Text('times',
                      style: TextStyle(
                          fontSize: 10, color: Colors.grey.shade500)),
                ],
              ),
            ]),
          );
        }),
        const SizedBox(height: 24),
      ],
    );
  }
}

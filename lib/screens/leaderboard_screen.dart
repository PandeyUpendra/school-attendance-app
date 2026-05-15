import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../models/leaderboard_entry.dart';
import '../models/student.dart';
import '../services/leaderboard_service.dart';
import '../services/student_service.dart';

class LeaderboardScreen extends StatefulWidget {
  final String className;
  final String section;
  final String schoolId;

  const LeaderboardScreen({
    super.key,
    required this.className,
    required this.section,
    required this.schoolId,
  });

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  final _svc = LeaderboardService();

  static const _autoCategories = [
    _Category(key: LeaderboardService.catAcademics,    label: 'Academics',     icon: Icons.school_outlined),
    _Category(key: LeaderboardService.catAttendance,   label: 'Attendance',    icon: Icons.calendar_today_outlined),
    _Category(key: LeaderboardService.catDiscipline,   label: 'Discipline',    icon: Icons.verified_outlined),
    _Category(key: LeaderboardService.catMostImproved, label: 'Most Improved', icon: Icons.trending_up_outlined),
  ];

  List<_Category>          _categories      = List.from(_autoCategories);
  int                      _selectedIdx     = 0;
  List<LeaderboardEntry>   _entries         = [];
  Map<String, dynamic>?    _meta;
  bool                     _loading         = false;
  String?                  _error;
  StreamSubscription?      _customSub;

  String get _classId =>
      widget.section.trim().isEmpty ? widget.className : '${widget.className} ${widget.section}';

  @override
  void initState() {
    super.initState();
    _watchCustomLeaderboards();
    _loadCategory();
  }

  @override
  void dispose() {
    _customSub?.cancel();
    super.dispose();
  }

  void _watchCustomLeaderboards() {
    _customSub = _svc
        .watchCustomLeaderboards(_classId, schoolId: widget.schoolId)
        .listen((customs) {
      if (!mounted) return;
      setState(() {
        _categories = [
          ..._autoCategories,
          ...customs.map((m) => _Category(
            key:   m['id'] as String,
            label: m['name'] as String? ?? 'Custom',
            icon:  Icons.star_outline,
          )),
        ];
      });
    });
  }

  Future<void> _loadCategory() async {
    setState(() { _loading = true; _error = null; });
    try {
      final cat  = _categories[_selectedIdx];
      final lbId = _isAutoCategory(cat.key)
          ? '${_classId.replaceAll(' ', '_')}_${cat.key}'
          : cat.key;

      final results = await Future.wait([
        _svc.fetchLeaderboard(lbId, schoolId: widget.schoolId),
        _svc.getLeaderboardMeta(lbId, schoolId: widget.schoolId),
      ]);

      if (!mounted) return;
      setState(() {
        _entries = results[0] as List<LeaderboardEntry>;
        _meta    = results[1] as Map<String, dynamic>?;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _refresh() async {
    final cat = _categories[_selectedIdx];
    if (!_isAutoCategory(cat.key)) {
      await _loadCategory();
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      late List<LeaderboardEntry> entries;
      switch (cat.key) {
        case LeaderboardService.catAcademics:
          entries = await _svc.calculateAcademicsRanking(_classId, schoolId: widget.schoolId);
          break;
        case LeaderboardService.catAttendance:
          entries = await _svc.calculateAttendanceRanking(_classId, schoolId: widget.schoolId);
          break;
        case LeaderboardService.catDiscipline:
          entries = await _svc.calculateDisciplineRanking(_classId, schoolId: widget.schoolId);
          break;
        case LeaderboardService.catMostImproved:
          entries = await _svc.calculateMostImprovedRanking(_classId, schoolId: widget.schoolId);
          break;
        default:
          entries = [];
      }
      await _svc.saveLeaderboard(_classId, cat.key, entries, schoolId: widget.schoolId);
      await _loadCategory();
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  bool _isAutoCategory(String key) =>
      key == LeaderboardService.catAcademics ||
      key == LeaderboardService.catAttendance ||
      key == LeaderboardService.catDiscipline ||
      key == LeaderboardService.catMostImproved;

  void _showCreateCustomDialog() {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Custom Leaderboard'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. Spelling Bee',
            labelText: 'Leaderboard name',
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              final lbId = await _svc.createCustomLeaderboard(
                  name, _classId, schoolId: widget.schoolId);
              if (!mounted) return;
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _CustomScoreEntryScreen(
                    leaderboardId: lbId,
                    leaderboardName: name,
                    classId: _classId,
                    schoolId: widget.schoolId,
                  ),
                ),
              );
              await _loadCategory();
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showCategoryMenu(BuildContext context) {
    final cat     = _categories[_selectedIdx];
    final isCustom = !_isAutoCategory(cat.key);
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('Reset & Recalculate'),
              onTap: () { Navigator.pop(ctx); _refresh(); },
            ),
            if (isCustom) ...[
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit Scores'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => _CustomScoreEntryScreen(
                        leaderboardId:   cat.key,
                        leaderboardName: cat.label,
                        classId:         _classId,
                        schoolId:        widget.schoolId,
                      ),
                    ),
                  ).then((_) => _loadCategory());
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete', style: TextStyle(color: Colors.red)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (d) => AlertDialog(
                      title: const Text('Delete leaderboard?'),
                      content: Text('This will permanently delete "${cat.label}".'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                        FilledButton(
                          onPressed: () => Navigator.pop(d, true),
                          style: FilledButton.styleFrom(backgroundColor: Colors.red),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await _svc.deleteLeaderboard(cat.key, schoolId: widget.schoolId);
                    if (!mounted) return;
                    setState(() { _selectedIdx = 0; });
                    await _loadCategory();
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text('${widget.className}${widget.section.isNotEmpty ? " ${widget.section}" : ""} Leaderboard'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => _showCategoryMenu(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateCustomDialog,
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Custom'),
      ),
      body: Column(
        children: [
          // Category chips
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final cat      = _categories[i];
                final selected = i == _selectedIdx;
                return FilterChip(
                  avatar: Icon(cat.icon,
                      size: 16,
                      color: selected ? Colors.white : AppTheme.primary),
                  label: Text(cat.label),
                  selected: selected,
                  onSelected: (_) {
                    if (_selectedIdx == i) return;
                    setState(() { _selectedIdx = i; });
                    _loadCategory();
                  },
                  selectedColor: AppTheme.primary,
                  checkmarkColor: Colors.white,
                  labelStyle: TextStyle(
                      color: selected ? Colors.white : AppTheme.primary,
                      fontWeight: FontWeight.w600),
                  backgroundColor: Colors.white,
                  side: BorderSide(color: AppTheme.primary.withOpacity(0.3)),
                );
              },
            ),
          ),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : _error != null
                    ? _ErrorView(error: _error!, onRetry: _loadCategory)
                    : _LeaderboardBody(
                        entries:  _entries,
                        meta:     _meta,
                        category: _categories[_selectedIdx],
                        onRefresh: _refresh,
                      ),
          ),
        ],
      ),
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────────────────

class _LeaderboardBody extends StatelessWidget {
  final List<LeaderboardEntry> entries;
  final Map<String, dynamic>?  meta;
  final _Category               category;
  final VoidCallback            onRefresh;

  const _LeaderboardBody({
    required this.entries,
    required this.meta,
    required this.category,
    required this.onRefresh,
  });

  String _fmtUpdated() {
    final ts = meta?['updatedAt'];
    if (ts is! Timestamp) return 'Never';
    final dt  = ts.toDate();
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours  < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays   < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final maxScore = entries.isEmpty
        ? 1.0
        : entries.map((e) => e.score).reduce((a, b) => a > b ? a : b);

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      color: AppTheme.primary,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // Last updated row
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Icon(Icons.update, size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text('Last updated: ${_fmtUpdated()}',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Refresh'),
                    style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
                  ),
                ],
              ),
            ),
          ),

          if (entries.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.leaderboard_outlined,
                        size: 64, color: Colors.grey[300]),
                    const SizedBox(height: 12),
                    Text('No data yet',
                        style: TextStyle(color: Colors.grey[500], fontSize: 16)),
                    const SizedBox(height: 8),
                    TextButton(
                        onPressed: onRefresh,
                        child: const Text('Tap Refresh to calculate')),
                  ],
                ),
              ),
            )
          else ...[
            // Top 3 podium
            if (entries.length >= 1)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: _PodiumRow(
                    first:  entries.length > 0 ? entries[0] : null,
                    second: entries.length > 1 ? entries[1] : null,
                    third:  entries.length > 2 ? entries[2] : null,
                    category: category,
                  ),
                ),
              ),

            // Full ranked list
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) {
                    final entry = entries[i];
                    final pct   = maxScore == 0 ? 0.0 : entry.score / maxScore;
                    return _RankRow(entry: entry, progress: pct, category: category);
                  },
                  childCount: entries.length,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Podium row ────────────────────────────────────────────────────────────────

class _PodiumRow extends StatelessWidget {
  final LeaderboardEntry? first;
  final LeaderboardEntry? second;
  final LeaderboardEntry? third;
  final _Category category;

  const _PodiumRow({
    required this.first,
    required this.second,
    required this.third,
    required this.category,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (second != null)
          Expanded(child: _PodiumCard(entry: second!, crownColor: const Color(0xFFC0C0C0), height: 100, category: category)),
        if (second != null) const SizedBox(width: 8),
        if (first != null)
          Expanded(child: _PodiumCard(entry: first!, crownColor: const Color(0xFFFFD700), height: 120, category: category)),
        if (third != null) const SizedBox(width: 8),
        if (third != null)
          Expanded(child: _PodiumCard(entry: third!, crownColor: const Color(0xFFCD7F32), height: 90, category: category)),
      ],
    );
  }
}

class _PodiumCard extends StatelessWidget {
  final LeaderboardEntry entry;
  final Color            crownColor;
  final double           height;
  final _Category        category;

  const _PodiumCard({
    required this.entry,
    required this.crownColor,
    required this.height,
    required this.category,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: crownColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: crownColor.withOpacity(0.4)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.emoji_events, color: crownColor, size: 28),
          const SizedBox(height: 4),
          CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.primary.withOpacity(0.15),
            child: Text(
              entry.studentName.isNotEmpty ? entry.studentName[0].toUpperCase() : '?',
              style: TextStyle(
                  color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              entry.studentName,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            _scoreLabel(entry.score, category.key),
            style: TextStyle(
                fontSize: 11, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

// ── Rank row ─────────────────────────────────────────────────────────────────

class _RankRow extends StatelessWidget {
  final LeaderboardEntry entry;
  final double           progress;
  final _Category        category;

  const _RankRow({
    required this.entry,
    required this.progress,
    required this.category,
  });

  @override
  Widget build(BuildContext context) {
    final badgeColor = entry.badge == 'gold'   ? const Color(0xFFFFD700)
                     : entry.badge == 'silver' ? const Color(0xFFC0C0C0)
                     : entry.badge == 'bronze' ? const Color(0xFFCD7F32)
                     : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: entry.badge != 'none'
                ? Icon(Icons.emoji_events, color: badgeColor, size: 20)
                : Text(
                    '${entry.rank}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[600]),
                  ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 16,
            backgroundColor: AppTheme.primary.withOpacity(0.12),
            child: Text(
              entry.studentName.isNotEmpty ? entry.studentName[0].toUpperCase() : '?',
              style: TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.studentName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 2),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    minHeight: 5,
                    color: AppTheme.primary.withOpacity(0.7),
                    backgroundColor: AppTheme.primary.withOpacity(0.1),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _scoreLabel(entry.score, category.key),
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ── Custom score entry screen ─────────────────────────────────────────────────

class _CustomScoreEntryScreen extends StatefulWidget {
  final String leaderboardId;
  final String leaderboardName;
  final String classId;
  final String schoolId;

  const _CustomScoreEntryScreen({
    required this.leaderboardId,
    required this.leaderboardName,
    required this.classId,
    required this.schoolId,
  });

  @override
  State<_CustomScoreEntryScreen> createState() =>
      _CustomScoreEntryScreenState();
}

class _CustomScoreEntryScreenState extends State<_CustomScoreEntryScreen> {
  final _svc        = LeaderboardService();
  final _studentSvc = StudentService();

  bool            _loading = true;
  List<Student>   _students = [];
  Map<int, TextEditingController> _controllers = {};
  bool            _saving = false;

  // Split classId "8 A" into className + section
  String get _className {
    final parts = widget.classId.trim().split(' ');
    if (parts.length > 1 && parts.last.length <= 2) {
      return parts.sublist(0, parts.length - 1).join(' ');
    }
    return widget.classId;
  }

  String get _section {
    final parts = widget.classId.trim().split(' ');
    if (parts.length > 1 && parts.last.length <= 2) return parts.last;
    return '';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) c.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final students = await _studentSvc.getStudentsByClass(
          schoolId: widget.schoolId, className: _className, section: _section);
      // Pre-fill existing scores if any
      final existing = await _svc.fetchLeaderboard(widget.leaderboardId,
          schoolId: widget.schoolId);
      final existingByRoll = {for (final e in existing) e.roll: e.score};

      final controllers = <int, TextEditingController>{};
      for (final s in students) {
        final score = existingByRoll[s.roll];
        controllers[s.roll] =
            TextEditingController(text: score != null ? score.toStringAsFixed(1) : '');
      }
      setState(() {
        _students    = students;
        _controllers = controllers;
        _loading     = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final entries = <LeaderboardEntry>[];
      for (final s in _students) {
        final raw   = _controllers[s.roll]?.text.trim() ?? '';
        final score = double.tryParse(raw) ?? 0.0;
        entries.add(LeaderboardEntry(
          studentId:   '${widget.classId.replaceAll(' ', '_')}_${s.roll}',
          studentName: s.name,
          roll:        s.roll,
          classId:     widget.classId,
          score:       score,
          rank:        0,
          badge:       'none',
        ));
      }
      await _svc.saveCustomLeaderboard(
          widget.leaderboardId, entries, schoolId: widget.schoolId);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(widget.leaderboardName),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _students.isEmpty
              ? const Center(child: Text('No students found in this class.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _students.length,
                  itemBuilder: (_, i) {
                    final s = _students[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: AppTheme.primary.withOpacity(0.12),
                            child: Text(
                              s.name.isNotEmpty ? s.name[0].toUpperCase() : '?',
                              style: TextStyle(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${s.name}  ·  Roll ${s.roll}',
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                          ),
                          SizedBox(
                            width: 80,
                            child: TextField(
                              controller: _controllers[s.roll],
                              keyboardType:
                                  const TextInputType.numberWithOptions(decimal: true),
                              textAlign: TextAlign.center,
                              decoration: InputDecoration(
                                hintText: '0',
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: AppTheme.primary),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

// ── Error view ────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String      error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, size: 48, color: AppTheme.danger),
        const SizedBox(height: 8),
        Text(error, textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.danger)),
        const SizedBox(height: 12),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _Category {
  final String  key;
  final String  label;
  final IconData icon;
  const _Category({required this.key, required this.label, required this.icon});
}

String _scoreLabel(double score, String categoryKey) {
  switch (categoryKey) {
    case LeaderboardService.catAcademics:
    case LeaderboardService.catAttendance:
      return '${score.toStringAsFixed(1)}%';
    case LeaderboardService.catMostImproved:
      return '${score >= 0 ? '+' : ''}${score.toStringAsFixed(1)}%';
    default:
      return score.toStringAsFixed(1);
  }
}

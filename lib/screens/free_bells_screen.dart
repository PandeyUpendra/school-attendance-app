import 'package:flutter/material.dart';
import '../models/teacher.dart';
import '../models/timetable_entry.dart';
import '../models/substitution_record.dart';
import '../services/timetable_service.dart';
import '../services/substitution_history_service.dart';
import 'substitution_history_screen.dart';

class FreeBellsScreen extends StatefulWidget {
  const FreeBellsScreen({super.key});

  @override
  State<FreeBellsScreen> createState() => _FreeBellsScreenState();
}

class _FreeBellsScreenState extends State<FreeBellsScreen> {
  final _service      = TimetableService();
  final _histService  = SubstitutionHistoryService();

  List<String>  _classes   = [];
  List<Teacher> _teachers  = [];
  Map<String, Map<String, Map<int, TimetableEntry>>> _timetable = {};
  Map<String, String> _substitutions = {}; // '${cls}_$bell' → teacherId
  Map<String, int>    _subCounts     = {}; // teacherId → count (last 30 days)
  int _bellCount = 8;
  bool _loading = true;

  static const _days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'
  ];

  static const List<Color> _palette = [
    Color(0xFF009688), Color(0xFF3F51B5), Color(0xFFFF9800), Color(0xFFE91E63),
    Color(0xFF9C27B0), Color(0xFF4CAF50), Color(0xFFF44336), Color(0xFF795548),
    Color(0xFF00BCD4), Color(0xFF673AB7),
  ];

  String get _today {
    const map = {
      1: 'Monday', 2: 'Tuesday', 3: 'Wednesday',
      4: 'Thursday', 5: 'Friday', 6: 'Saturday',
    };
    return map[DateTime.now().weekday] ?? 'Monday';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _service.getSettings(),
      _service.getTeachers(),
      _service.getTimetable(),
      _service.getTodaySubstitutions(),
      _histService.getSubstituteCounts(days: 30),
    ]);
    if (!mounted) return;
    final settings = results[0] as Map<String, dynamic>;
    final teachers = results[1] as List<Teacher>;
    final tt       = results[2] as Map<String, Map<String, Map<int, TimetableEntry>>>;
    final subs     = results[3] as Map<String, String>;
    final counts   = results[4] as Map<String, int>;
    setState(() {
      _classes       = List<String>.from(settings['classes'] as List);
      _bellCount     = settings['numberOfBells'] as int;
      _teachers      = teachers;
      _timetable     = tt;
      _substitutions = subs;
      _subCounts     = counts;
      _loading       = false;
    });
  }

  Color _teacherColor(String? tid) {
    if (tid == null || tid.isEmpty) return Colors.grey.shade300;
    final idx = _teachers.indexWhere((t) => t.id == tid);
    return idx < 0 ? Colors.grey.shade300 : _palette[idx % _palette.length];
  }

  Teacher? _teacherById(String? id) =>
      id == null ? null : _teachers.where((t) => t.id == id).firstOrNull;

  String _teacherName(String? tid) =>
      _teacherById(tid)?.name ?? (tid?.isEmpty != false ? '—' : '?');

  String _subject(TimetableEntry? e) {
    if (e == null || e.isEmpty) return '';
    if (e.subject?.isNotEmpty == true) return e.subject!;
    return _teacherById(e.teacherId)?.subject ?? '';
  }

  /// Teachers NOT assigned to any class during bell [b] on [_today].
  List<Teacher> _freeTeachersForBell(int b) {
    final busyIds = <String>{};
    for (final cls in _classes) {
      final entry = _timetable[cls]?[_today]?[b];
      if (entry != null && entry.teacherId?.isNotEmpty == true) {
        busyIds.add(entry.teacherId!);
      }
      // Also mark substituted teachers as busy
      final subKey = '${cls}_$b';
      final subId  = _substitutions[subKey];
      if (subId != null && subId.isNotEmpty) busyIds.add(subId);
    }
    return _teachers.where((t) => !busyIds.contains(t.id)).toList();
  }

  /// Effective teacher for a class+bell (substitution overrides timetable).
  String? _effectiveTeacherId(String cls, int b) {
    final subKey = '${cls}_$b';
    final subId  = _substitutions[subKey];
    if (subId != null && subId.isNotEmpty) return subId;
    return _timetable[cls]?[_today]?[b]?.teacherId;
  }

  bool _isSubstituted(String cls, int b) {
    final subKey = '${cls}_$b';
    return _substitutions.containsKey(subKey);
  }

  // ── Assign substitute dialog ──────────────────────────────────────────────

  Future<void> _showAssignSheet(String cls, int bell) async {
    // Sort free teachers: least-covered first (auto-suggest)
    final freeTeachers = List<Teacher>.from(_freeTeachersForBell(bell))
      ..sort((a, b) {
        final ca = _subCounts[a.id] ?? 0;
        final cb = _subCounts[b.id] ?? 0;
        return ca.compareTo(cb);
      });

    final currentSub = _substitutions['${cls}_$bell'];
    String? selectedId = currentSub;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Container(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.75),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Handle
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('Assign Substitute',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                Text('$cls  ·  Bell $bell  ·  $_today',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500)),
                const SizedBox(height: 4),
                Text('★ = Suggested (least covered this month)',
                    style: TextStyle(
                        fontSize: 10, color: Colors.teal.shade600)),
              ]),
            ),
            const Divider(height: 1),

            if (freeTeachers.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No free teachers for this bell.',
                    style: TextStyle(color: Colors.grey)),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: freeTeachers.length,
                  itemBuilder: (_, i) {
                    final t     = freeTeachers[i];
                    final sel   = t.id == selectedId;
                    final cidx  = _teachers.indexOf(t);
                    final clr   = cidx >= 0
                        ? _palette[cidx % _palette.length]
                        : Colors.grey;
                    final count = _subCounts[t.id] ?? 0;
                    // Suggest first teacher (least covered)
                    final isSuggested = i == 0;

                    return ListTile(
                      leading: Stack(
                        children: [
                          CircleAvatar(
                            backgroundColor:
                                sel ? clr : clr.withOpacity(0.2),
                            child: Text(t.name[0].toUpperCase(),
                                style: TextStyle(
                                    color: sel ? Colors.white : clr,
                                    fontWeight: FontWeight.bold)),
                          ),
                          if (isSuggested && currentSub == null)
                            Positioned(
                              right: -2, top: -2,
                              child: Container(
                                width: 14, height: 14,
                                decoration: const BoxDecoration(
                                  color: Colors.teal,
                                  shape: BoxShape.circle,
                                ),
                                child: const Center(
                                  child: Text('★',
                                      style: TextStyle(
                                          fontSize: 8, color: Colors.white)),
                                ),
                              ),
                            ),
                        ],
                      ),
                      title: Text(t.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w500)),
                      subtitle: Text(
                        '${t.subject}  •  $count sub${count == 1 ? '' : 's'} this month',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade600),
                      ),
                      trailing: sel
                          ? Icon(Icons.check_circle, color: clr)
                          : null,
                      selected: sel,
                      selectedTileColor: clr.withOpacity(0.06),
                      onTap: () =>
                          setS(() => selectedId = sel ? null : t.id),
                    );
                  },
                ),
              ),

            // Action bar
            Container(
              padding: EdgeInsets.fromLTRB(
                  20, 10, 20, MediaQuery.of(ctx).padding.bottom + 12),
              decoration: BoxDecoration(
                color: Colors.white,
                border:
                    Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(children: [
                if (currentSub != null)
                  TextButton.icon(
                    onPressed: () {
                      setS(() => selectedId = null);
                      Navigator.pop(ctx, true);
                    },
                    icon: const Icon(Icons.clear,
                        color: Colors.red, size: 16),
                    label: const Text('Remove Sub',
                        style: TextStyle(color: Colors.red)),
                  ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: selectedId == null
                      ? null
                      : () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Assign'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade200,
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );

    if (confirmed != true) return;

    // Save substitution in the daily doc (existing behavior)
    await _service.setSubstitution(cls, bell, selectedId);

    // Also log to history if assigning (not removing)
    // Use a final local so Dart can promote the type (selectedId was in a closure)
    final subId = selectedId;
    if (subId != null && subId.isNotEmpty) {
      final subTeacher   = _teacherById(subId);
      final origTeacherId =
          _timetable[cls]?[_today]?[bell]?.teacherId ?? '';
      final origTeacher  = _teacherById(origTeacherId);
      final subj =
          _subject(_timetable[cls]?[_today]?[bell]);

      final now = DateTime.now();
      await _histService.logSubstitution(
        SubstitutionRecord(
          id:                    '',
          dateKey:               '${now.year}-${now.month}-${now.day}',
          date:                  now,
          className:             cls,
          bell:                  bell,
          substituteTeacherId:   subId,
          substituteTeacherName: subTeacher?.name ?? subId,
          originalTeacherId:     origTeacherId,
          originalTeacherName:   origTeacher?.name ?? '',
          subject:               subj,
          createdAt:             now,
        ),
      );
    }

    _load();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Free Bells  &  Substitution',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(_today,
                style:
                    const TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.history_outlined),
            tooltip: 'Substitution History',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      const SubstitutionHistoryScreen()),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _classes.isEmpty || _teachers.isEmpty
              ? _emptyState()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: Colors.teal,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
                    children: [
                      for (int b = 1; b <= _bellCount; b++)
                        _buildBellCard(b),
                    ],
                  ),
                ),
    );
  }

  Widget _buildBellCard(int bell) {
    final freeTeachers = _freeTeachersForBell(bell);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Bell header
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: Colors.teal.shade50,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(14)),
          ),
          child: Row(children: [
            Container(
              width: 32, height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.teal,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('$bell',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Bell $bell',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            // Free teachers count badge
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: freeTeachers.isEmpty
                    ? Colors.grey.shade100
                    : Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: freeTeachers.isEmpty
                        ? Colors.grey.shade200
                        : Colors.green.shade200),
              ),
              child: Text(
                '${freeTeachers.length} free',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: freeTeachers.isEmpty
                        ? Colors.grey.shade500
                        : Colors.green.shade700),
              ),
            ),
          ]),
        ),

        // Class assignments for this bell
        for (final cls in _classes)
          _buildClassRow(cls, bell),

        // Free teachers
        if (freeTeachers.isNotEmpty) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            child: Text('Free Teachers',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.green.shade600,
                    letterSpacing: 0.4)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: freeTeachers.map((t) {
                final idx = _teachers.indexOf(t);
                final clr =
                    idx >= 0 ? _palette[idx % _palette.length] : Colors.grey;
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: clr.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: clr.withOpacity(0.3)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    CircleAvatar(
                        radius: 8,
                        backgroundColor: clr,
                        child: Text(t.name[0].toUpperCase(),
                            style: const TextStyle(
                                fontSize: 8, color: Colors.white))),
                    const SizedBox(width: 4),
                    Text(t.name,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: clr)),
                  ]),
                );
              }).toList(),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _buildClassRow(String cls, int bell) {
    final tid  = _effectiveTeacherId(cls, bell);
    final isSub = _isSubstituted(cls, bell);
    final clr  = _teacherColor(tid);
    final name = _teacherName(tid);
    final tt   = _timetable[cls]?[_today]?[bell];
    final sub  = _subject(tt);

    return InkWell(
      onTap: () => _showAssignSheet(cls, bell),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
              top: BorderSide(color: Colors.grey.shade100)),
        ),
        child: Row(children: [
          // Class label
          SizedBox(
            width: 80,
            child: Text(cls,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          // Teacher info
          Expanded(
            child: tid == null || tid.isEmpty
                ? Row(children: [
                    Icon(Icons.add_circle_outline,
                        size: 14, color: Colors.grey.shade400),
                    const SizedBox(width: 4),
                    Text('Tap to assign substitute',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade400)),
                  ])
                : Row(children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: clr,
                      child: Text(name[0].toUpperCase(),
                          style: const TextStyle(
                              fontSize: 10, color: Colors.white)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(name,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: clr),
                            overflow: TextOverflow.ellipsis),
                        if (sub.isNotEmpty)
                          Text(sub,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: clr.withOpacity(0.7)),
                              overflow: TextOverflow.ellipsis),
                      ]),
                    ),
                    if (isSub)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: Colors.orange.shade300),
                        ),
                        child: Text('Sub',
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade800)),
                      ),
                  ]),
          ),
          Icon(Icons.edit_outlined,
              size: 14, color: Colors.grey.shade400),
        ]),
      ),
    );
  }

  Widget _emptyState() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.schedule_outlined,
          size: 64, color: Colors.grey.shade300),
      const SizedBox(height: 16),
      Text('Timetable not set up',
          style: TextStyle(fontSize: 16, color: Colors.grey.shade400)),
      const SizedBox(height: 6),
      Text('Configure timetable in Timetable & Settings',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
    ]),
  );
}

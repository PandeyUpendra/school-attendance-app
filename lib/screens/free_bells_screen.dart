import 'package:flutter/material.dart';
import '../models/teacher.dart';
import '../models/timetable_entry.dart';
import '../models/substitution_record.dart';
import '../services/timetable_service.dart';
import '../services/substitution_history_service.dart';
import '../theme.dart';
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

  Teacher? _teacherById(String? id) =>
      id == null ? null : _teachers.where((t) => t.id == id).firstOrNull;

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

  bool _isSubstituted(String cls, int b) {
    final subKey = '${cls}_$b';
    return _substitutions.containsKey(subKey);
  }

  // ── Assign substitute (inline dropdown save) ─────────────────────────────

  Future<void> _assignSubstitute(String cls, int bell, String? teacherId) async {
    await _service.setSubstitution(cls, bell, teacherId);

    if (teacherId != null && teacherId.isNotEmpty) {
      final subTeacher    = _teacherById(teacherId);
      final origTeacherId = _timetable[cls]?[_today]?[bell]?.teacherId ?? '';
      final origTeacher   = _teacherById(origTeacherId);
      final subj          = _subject(_timetable[cls]?[_today]?[bell]);
      final now           = DateTime.now();
      await _histService.logSubstitution(SubstitutionRecord(
        id:                    '',
        dateKey:               '${now.year}-${now.month}-${now.day}',
        date:                  now,
        className:             cls,
        bell:                  bell,
        substituteTeacherId:   teacherId,
        substituteTeacherName: subTeacher?.name ?? teacherId,
        originalTeacherId:     origTeacherId,
        originalTeacherName:   origTeacher?.name ?? '',
        subject:               subj,
        createdAt:             now,
      ));
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
                  color: AppTheme.primary,
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
            color: AppTheme.primary.withOpacity(0.06),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(14)),
          ),
          child: Row(children: [
            Container(
              width: 32, height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.primary,
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

      ]),
    );
  }

  Widget _buildClassRow(String cls, int bell) {
    final isSub        = _isSubstituted(cls, bell);
    final tt           = _timetable[cls]?[_today]?[bell];
    final origSubject  = _subject(tt);
    final currentSubId = isSub ? _substitutions['${cls}_$bell'] : null;

    // Sort free teachers: least-covered first (preserves auto-suggest order)
    final sortedFree = List<Teacher>.from(_freeTeachersForBell(bell))
      ..sort((a, b) {
        final ca = _subCounts[a.id] ?? 0;
        final cb = _subCounts[b.id] ?? 0;
        return ca.compareTo(cb);
      });

    // Ensure the current sub appears in items even if they're "busy" elsewhere
    final currentSubTeacher =
        (currentSubId != null && currentSubId.isNotEmpty)
            ? _teacherById(currentSubId)
            : null;
    final itemTeachers = <Teacher>[];
    if (currentSubTeacher != null &&
        !sortedFree.any((t) => t.id == currentSubId)) {
      itemTeachers.add(currentSubTeacher);
    }
    itemTeachers.addAll(sortedFree);

    final validValue =
        (currentSubId != null &&
                currentSubId.isNotEmpty &&
                itemTeachers.any((t) => t.id == currentSubId))
            ? currentSubId
            : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(children: [
        SizedBox(
          width: 72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(cls,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              if (origSubject.isNotEmpty)
                Text(origSubject,
                    style: TextStyle(
                        fontSize: 10, color: Colors.grey.shade500),
                    overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<String>(
            value: validValue,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Select Teacher',
              labelStyle:
                  const TextStyle(fontSize: 11, color: AppTheme.primary),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                    color: isSub
                        ? Colors.orange.shade400
                        : AppTheme.primary.withOpacity(0.6)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: AppTheme.primary, width: 2),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              isDense: true,
            ),
            hint: const Text('Select Teacher',
                style: TextStyle(fontSize: 11)),
            items: [
              if (validValue != null)
                const DropdownMenuItem<String>(
                  value: '',
                  child: Text('— Remove substitute —',
                      style: TextStyle(fontSize: 11, color: Colors.red)),
                ),
              ...itemTeachers.asMap().entries.map((e) {
                final t     = e.value;
                final isTop = e.key == 0 && validValue == null;
                final count = _subCounts[t.id] ?? 0;
                return DropdownMenuItem<String>(
                  value: t.id,
                  child: Text(
                    '${isTop ? '★ ' : ''}${t.name}  ·  ${t.subject}'
                    '${isTop ? '  ($count subs)' : ''}',
                    style: const TextStyle(fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }),
            ],
            onChanged: (val) async {
              await _assignSubstitute(
                  cls, bell, (val == null || val.isEmpty) ? null : val);
            },
          ),
        ),
      ]),
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

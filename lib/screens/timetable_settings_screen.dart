import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/teacher.dart';
import '../models/timetable_entry.dart';
import '../services/timetable_service.dart';
import '../services/base_firestore_service.dart';
import '../theme.dart';

// ── Bell model ────────────────────────────────────────────────────────────────

class _Bell {
  int startMinutes; // absolute minutes from midnight (e.g. 8*60 = 480 = 08:00)
  int durationMinutes;
  bool isLunch;
  String name; // custom label, e.g. "Diary Bell" or "Assembly"

  _Bell({
    required this.startMinutes,
    required this.durationMinutes,
    this.isLunch = false,
    this.name = '',
  });
}

// ── Teacher picker wrapper ────────────────────────────────────────────────────

class _Pick {
  final String? teacherId;
  final List<String> days;
  final String? subject;
  const _Pick(this.teacherId, {this.days = const [], this.subject});
}

// ── Main screen ───────────────────────────────────────────────────────────────

class TimetableSettingsScreen extends StatefulWidget {
  const TimetableSettingsScreen({super.key});

  @override
  State<TimetableSettingsScreen> createState() =>
      _TimetableSettingsScreenState();
}

class _TimetableSettingsScreenState extends State<TimetableSettingsScreen>
    with SingleTickerProviderStateMixin {
  final _service = TimetableService();
  late final TabController _tabCtrl;
  final _classCtrl = TextEditingController();

  List<_Bell> _bells = [];
  List<String> _classes = [];
  List<Teacher> _teachers = [];
  Map<String, Map<String, Map<int, TimetableEntry>>> _timetable = {};
  bool _loading = true;
  bool _settingsEditing = false;
  bool _timetableEditing = false;
  static const _days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'
  ];
  static const _dayAbbr = {
    'Monday': 'Mon', 'Tuesday': 'Tue', 'Wednesday': 'Wed',
    'Thursday': 'Thu', 'Friday': 'Fri', 'Saturday': 'Sat',
  };

  static const _palette = [
    Color(0xFF009688), Color(0xFF3F51B5), Color(0xFFFF9800),
    Color(0xFFE91E63), Color(0xFF9C27B0), Color(0xFF4CAF50),
    Color(0xFFF44336), Color(0xFF795548), Color(0xFF00BCD4),
    Color(0xFF673AB7),
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _classCtrl.dispose();
    super.dispose();
  }

  // ── Data loading ───────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() => _loading = true);
    final settings = await _service.getSettings();
    final teachers = await _service.getTeachers();
    final tt = await _service.getTimetable();
    if (!mounted) return;

    final bellsRaw = settings['bells'] as List? ?? [];
    final ftStr = settings['firstBellTime'] as String? ?? '08:00';
    final ftParts = ftStr.split(':');
    int defaultStart =
        (int.tryParse(ftParts[0]) ?? 8) * 60 + (int.tryParse(ftParts.length > 1 ? ftParts[1] : '0') ?? 0);

    List<_Bell> bells;
    if (bellsRaw.isNotEmpty) {
      bells = [];
      int cursor = defaultStart;
      for (final b in bellsRaw) {
        final m = b as Map<String, dynamic>;
        final dur = m['duration'] as int? ?? 45;
        // Use stored 'start' if available, else cascade from cursor
        int start = cursor;
        if (m['start'] != null) {
          final sp = (m['start'] as String).split(':');
          start = (int.tryParse(sp[0]) ?? cursor ~/ 60) * 60 +
              (int.tryParse(sp.length > 1 ? sp[1] : '0') ?? 0);
        }
        bells.add(_Bell(
          startMinutes: start,
          durationMinutes: dur,
          isLunch: m['isLunch'] as bool? ?? false,
          name: m['name'] as String? ?? '',
        ));
        cursor = start + dur;
      }
    } else {
      final n = settings['numberOfBells'] as int? ?? 8;
      bells = List.generate(
        n,
        (i) => _Bell(startMinutes: defaultStart + i * 45, durationMinutes: 45),
      );
    }

    setState(() {
      _bells = bells;
      _classes = List<String>.from(settings['classes'] as List);
      _teachers = teachers;
      _timetable = tt;
      _loading = false;
    });
  }

  // ── Bell time helpers ──────────────────────────────────────────────────────

  /// Cascade start times for all bells AFTER idx based on their durations.
  void _cascadeFrom(int idx) {
    for (int i = idx + 1; i < _bells.length; i++) {
      _bells[i].startMinutes =
          _bells[i - 1].startMinutes + _bells[i - 1].durationMinutes;
    }
  }

  TimeOfDay _startOf(int idx) {
    final m = _bells[idx].startMinutes;
    return TimeOfDay(hour: (m ~/ 60) % 24, minute: m % 60);
  }

  TimeOfDay _endOf(int idx) {
    final m = _bells[idx].startMinutes + _bells[idx].durationMinutes;
    return TimeOfDay(hour: (m ~/ 60) % 24, minute: m % 60);
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _fmt12(TimeOfDay t) {
    final h = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
    final m = t.minute.toString().padLeft(2, '0');
    final period = t.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $period';
  }

  /// Returns the sequential bell number for display, skipping lunch bells.
  /// e.g. if bells are [bell, bell, bell, lunch, bell], index 4 returns 4 not 5.
  int _bellDisplayNumber(int idx) {
    int count = 0;
    for (int i = 0; i <= idx; i++) {
      if (!_bells[i].isLunch) count++;
    }
    return count;
  }

  /// Returns the display label for a bell: custom name if set, else default.
  String _bellLabel(int idx) {
    final bell = _bells[idx];
    if (bell.isLunch) return 'Lunch Break';
    if (bell.name.trim().isNotEmpty) return bell.name.trim();
    return 'Bell ${_bellDisplayNumber(idx)}';
  }

  // ── Settings actions ───────────────────────────────────────────────────────

  /// Edit a custom name for a bell.
  Future<void> _editBellName(int idx) async {
    final ctrl = TextEditingController(text: _bells[idx].name);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Name for Bell ${_bellDisplayNumber(idx)}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'e.g. Diary Bell, Assembly…',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(_, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(_, ''),
            child: const Text('Clear'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(_, ctrl.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (result != null && mounted) {
      setState(() => _bells[idx].name = result);
    }
  }

  /// Pick start time for any bell — cascades all subsequent bells.
  Future<void> _pickBellStartTime(int idx) async {
    final current = _startOf(idx);
    final picked = await showTimePicker(
      context: context,
      initialTime: current,
      helpText: '${_bellLabel(idx)} Start Time',
    );
    if (picked == null || !mounted) return;

    setState(() {
      final newStart = picked.hour * 60 + picked.minute;
      final delta = newStart - _bells[idx].startMinutes;
      // Shift this bell and all subsequent bells by the same delta
      for (int i = idx; i < _bells.length; i++) {
        _bells[i].startMinutes += delta;
      }
    });
  }

  Future<void> _editBellDuration(int idx) async {
    final isLunchBell = _bells[idx].isLunch;
    final firstNonLunchIdx = _bells.indexWhere((b) => !b.isLunch);
    final isFirstBell = !isLunchBell && idx == firstNonLunchIdx;

    final result = await showDialog<int>(
      context: context,
      builder: (_) => _DurationDialog(
        bellNumber: isLunchBell ? 0 : _bellDisplayNumber(idx),
        initialMinutes: _bells[idx].durationMinutes,
        isLunch: isLunchBell,
        applyToAll: isFirstBell,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        if (isFirstBell) {
          // Propagate duration to ALL non-lunch bells, then cascade everything
          for (int i = 0; i < _bells.length; i++) {
            if (!_bells[i].isLunch) _bells[i].durationMinutes = result;
          }
          _cascadeFrom(0);
        } else {
          _bells[idx].durationMinutes = result;
          _cascadeFrom(idx);
        }
      });
    }
  }

  Future<void> _addBell() async {
    // Next bell number (counting only non-lunch bells including the new one)
    final nextNum = _bells.where((b) => !b.isLunch).length + 1;
    final ctrl = TextEditingController(text: 'Bell $nextNum');
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New Bell'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Bell Name',
            hintText: 'e.g. Bell 5, Diary Bell, Assembly…',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(_, v.trim().isEmpty ? 'Bell $nextNum' : v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(_, null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(
                _, ctrl.text.trim().isEmpty ? 'Bell $nextNum' : ctrl.text.trim()),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name == null || !mounted) return;
    setState(() {
      final last = _bells.isEmpty
          ? 480 // 08:00 default
          : _bells.last.startMinutes + _bells.last.durationMinutes;
      _bells.add(_Bell(startMinutes: last, durationMinutes: 45, name: name));
    });
  }

  void _removeBell(int idx) {
    if (_bells.length <= 1) return;
    setState(() {
      _bells.removeAt(idx);
      // Cascade from the bell before the removed one (or 0 if first)
      if (idx > 0) _cascadeFrom(idx - 1);
    });
  }

  bool get _hasLunchBell => _bells.any((b) => b.isLunch);

  Future<void> _addLunchBell() async {
    final nonLunchIndices = <int>[];
    for (int i = 0; i < _bells.length; i++) {
      if (!_bells[i].isLunch) nonLunchIndices.add(i);
    }
    if (nonLunchIndices.isEmpty) return;

    final result = await showDialog<_LunchConfig>(
      context: context,
      builder: (_) => _LunchDialog(
        bells: _bells,
        nonLunchIndices: nonLunchIndices,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        final lunchStart = _bells[result.afterIdx].startMinutes +
            _bells[result.afterIdx].durationMinutes;
        _bells.insert(
          result.afterIdx + 1,
          _Bell(
            startMinutes: lunchStart,
            durationMinutes: result.duration,
            isLunch: true,
          ),
        );
        _cascadeFrom(result.afterIdx + 1);
      });
    }
  }

  void _addClass() {
    final name = _classCtrl.text.trim();
    if (name.isEmpty) return;
    if (_classes.contains(name)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Class already exists')));
      return;
    }
    setState(() => _classes.add(name));
    _classCtrl.clear();
  }

  void _removeClass(String cls) => setState(() => _classes.remove(cls));

  Future<void> _saveSettings() async {
    final bellsData = List.generate(_bells.length, (i) => {
          'duration': _bells[i].durationMinutes,
          'isLunch': _bells[i].isLunch,
          'start': _fmt(_startOf(i)),
          'name': _bells[i].name,
        });
    final firstBell = _bells.isNotEmpty ? _fmt(_startOf(0)) : '08:00';

    await _service.saveSettings(BaseFirestoreService.currentSchoolId ?? 'default_school', {
      'numberOfBells': _bells.length,
      'classes': _classes,
      'firstBellTime': firstBell,
      'bells': bellsData,
    });
    if (!mounted) return;
    setState(() => _settingsEditing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Settings saved ✓'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2)),
    );
  }

  // ── Timetable actions ──────────────────────────────────────────────────────

  Color _colorFor(String? tid) {
    if (tid == null || tid.isEmpty) return Colors.transparent;
    final idx = _teachers.indexWhere((t) => t.id == tid);
    return idx < 0 ? Colors.grey : _palette[idx % _palette.length];
  }

  Teacher? _teacherById(String? id) =>
      id == null ? null : _teachers.where((t) => t.id == id).firstOrNull;

  String _shortName(String? tid) {
    final t = _teacherById(tid);
    if (t == null) return '';
    final p = t.name.trim().split(RegExp(r'\s+'));
    return p.length >= 2 ? '${p.first[0]}. ${p.last}' : p.first;
  }

  Future<void> _editCell(String cls, int bell) async {
    if (_teachers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add teachers first in Manage Teachers')));
      return;
    }
    final bellIdx = bell - 1;
    final bellLabel = _bellLabel(bellIdx);
    final timeRange = bellIdx < _bells.length
        ? '${_fmt12(_startOf(bellIdx))} – ${_fmt12(_endOf(bellIdx))}'
        : '';
    // Collect per-day entries for this class+bell
    final cellEntries = <String, TimetableEntry?>{
      for (final day in _days) day: _timetable[cls]?[day]?[bell],
    };

    final result = await showModalBottomSheet<_Pick>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _CellPickerSheet(
        className: cls,
        bellLabel: bellLabel,
        timeRange: timeRange,
        cellEntries: cellEntries,
        teachers: _teachers,
        palette: _palette,
        days: _days,
        dayAbbr: _dayAbbr,
      ),
    );

    if (result == null || !mounted) return;
    if (result.days.isEmpty) return;

    final error = await _service.assignTeacher(
      className: cls,
      days: result.days,
      bell: bell,
      teacherId: result.teacherId,
      subject: result.subject,
    );
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3)));
      return;
    }
    setState(() {
      _timetable.putIfAbsent(cls, () => {});
      for (final day in result.days) {
        _timetable[cls]!.putIfAbsent(day, () => {});
        _timetable[cls]![day]![bell] =
            TimetableEntry(teacherId: result.teacherId, subject: result.subject);
      }
    });
  }

  void _saveTimetableMode() {
    setState(() => _timetableEditing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Timetable saved ✓'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Timetable & Settings'),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.tune, size: 18), text: 'Settings'),
            Tab(
                icon: Icon(Icons.table_chart_outlined, size: 18),
                text: 'Timetable'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _buildSettingsTab(),
                _buildTimetableTab(),
              ],
            ),
    );
  }

  // ── Tab 1: Settings ────────────────────────────────────────────────────────

  Widget _buildSettingsTab() {
    return Stack(children: [
      ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          _buildBellSection(),
          const SizedBox(height: 20),
          _buildClassSection(),
        ],
      ),
      Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: _settingsEditing
              ? ElevatedButton.icon(
                  onPressed: _saveSettings,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save Settings',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                )
              : OutlinedButton.icon(
                  onPressed: () => setState(() => _settingsEditing = true),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit Settings',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: const BorderSide(color: AppTheme.primary),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
        ),
      ),
    ]);
  }

  Widget _buildBellSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Bell Schedule',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(
              _settingsEditing
                  ? 'Tap a time to edit it directly'
                  : 'Press Edit to modify schedule',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ]),
        ),
        if (_settingsEditing && !_hasLunchBell)
          TextButton.icon(
            onPressed: _addLunchBell,
            icon: const Icon(Icons.restaurant, size: 16),
            label: const Text('Lunch'),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
          ),
        if (_settingsEditing)
          TextButton.icon(
            onPressed: _addBell,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Bell'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
          ),
      ]),
      const SizedBox(height: 10),
      ...List.generate(_bells.length, (i) => _bellRow(i)),
    ]);
  }

  Widget _bellRow(int i) {
    final bell = _bells[i];
    final start = _startOf(i);
    final end = _endOf(i);
    final isLunch = bell.isLunch;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isLunch ? Colors.orange.shade50 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isLunch ? Colors.orange.shade200 : Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(children: [
          // Bell number / lunch icon badge
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isLunch ? Colors.orange : AppTheme.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: isLunch
                ? const Icon(Icons.restaurant, color: Colors.white, size: 18)
                : Text('${_bellDisplayNumber(i)}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
          ),
          const SizedBox(width: 8),

          // Time range (tappable only in edit mode)
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Bell label row — tappable to edit name in edit mode
                  GestureDetector(
                    onTap: _settingsEditing && !isLunch
                        ? () => _editBellName(i)
                        : null,
                    child: Row(children: [
                      Text(
                        _bellLabel(i),
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isLunch
                                ? Colors.orange.shade800
                                : Colors.black87),
                      ),
                      if (_settingsEditing && !isLunch) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.edit, size: 10, color: Colors.grey.shade400),
                      ],
                    ]),
                  ),
                  // Time row — tappable to edit time
                  GestureDetector(
                    onTap: _settingsEditing ? () => _pickBellStartTime(i) : null,
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isLunch
                              ? Colors.orange.shade100
                              : AppTheme.primary.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(_fmt12(start),
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isLunch
                                    ? Colors.orange.shade700
                                    : AppTheme.primary)),
                      ),
                      Text('  –  ${_fmt12(end)}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade500)),
                      if (_settingsEditing) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.access_time, size: 10, color: Colors.grey.shade400),
                      ],
                    ]),
                  ),
                ]),
          ),

          // Duration chip (tappable only in edit mode)
          GestureDetector(
            onTap: _settingsEditing ? () => _editBellDuration(i) : null,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('${bell.durationMinutes}m',
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w500)),
                const SizedBox(width: 3),
                Icon(Icons.timer_outlined,
                    size: 11, color: Colors.grey.shade400),
              ]),
            ),
          ),
          const SizedBox(width: 6),

          // Remove — only visible in edit mode
          if (_settingsEditing)
            GestureDetector(
              onTap: _bells.length > 1 ? () => _removeBell(i) : null,
              child: Icon(Icons.remove_circle_outline,
                  size: 20,
                  color: _bells.length > 1
                      ? Colors.red.shade300
                      : Colors.grey.shade200),
            )
          else
            const SizedBox(width: 20),
        ]),
      ),
    );
  }

  Widget _buildClassSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Classes (${_classes.length})',
          style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Text(
        _settingsEditing
            ? 'Drag to reorder · tap × to remove'
            : 'Press Edit to add or remove classes',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
      ),
      const SizedBox(height: 12),

      if (_settingsEditing) ...[
        Row(children: [
          Expanded(
            child: TextField(
              controller: _classCtrl,
              decoration: InputDecoration(
                hintText: 'e.g. Class 6A',
                prefixIcon: const Icon(Icons.class_outlined),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              textCapitalization: TextCapitalization.words,
              onSubmitted: (_) => _addClass(),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _addClass,
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            child: const Text('Add'),
          ),
        ]),
        const SizedBox(height: 12),
      ],

      if (_classes.isEmpty)
        Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('No classes added',
                style: TextStyle(color: Colors.grey.shade400)),
          ),
        )
      else if (_settingsEditing)
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _classes.length,
          onReorder: (old, neu) {
            if (neu > old) neu--;
            setState(() {
              final item = _classes.removeAt(old);
              _classes.insert(neu, item);
            });
          },
          itemBuilder: (_, i) {
            final cls = _classes[i];
            return Container(
              key: ValueKey(cls),
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: ListTile(
                dense: true,
                leading:
                    const Icon(Icons.drag_handle, color: Colors.grey),
                title: Text(cls,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                trailing: IconButton(
                  icon: const Icon(Icons.close,
                      color: Colors.red, size: 18),
                  onPressed: () => _removeClass(cls),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ),
            );
          },
        )
      else
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _classes.length,
          itemBuilder: (_, i) {
            final cls = _classes[i];
            return Container(
              key: ValueKey(cls),
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: ListTile(
                dense: true,
                leading: Icon(Icons.class_outlined,
                    color: AppTheme.primary.withOpacity(0.6)),
                title: Text(cls,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
              ),
            );
          },
        ),
    ]);
  }

  // ── Tab 2: Timetable ───────────────────────────────────────────────────────

  Widget _buildTimetableTab() {
    if (_classes.isEmpty) {
      return _hint('No classes configured',
          'Go to Settings tab to add classes', Icons.class_outlined);
    }
    if (_teachers.isEmpty) {
      return _hint('No teachers added',
          'Go to Manage Teachers to add teachers', Icons.people_outline);
    }
    return Stack(children: [
      Column(children: [
        const Divider(height: 1),
        Expanded(child: _buildGrid()),
        const SizedBox(height: 72),
      ]),
      Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: _timetableEditing
              ? ElevatedButton.icon(
                  onPressed: _saveTimetableMode,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save Timetable',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                )
              : OutlinedButton.icon(
                  onPressed: () => setState(() => _timetableEditing = true),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit Timetable',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: const BorderSide(color: AppTheme.primary),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
        ),
      ),
    ]);
  }

  Widget _hint(String title, String sub, IconData icon) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 64, color: Colors.grey.shade300),
        const SizedBox(height: 12),
        Text(title,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(sub,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
      ]),
    );
  }

  Widget _buildGrid() {
    const clsW = 86.0, cellW = 112.0, cellH = 92.0, hdrH = 50.0;
    final n = _bells.length;

    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                _hdrCell('Class', clsW, hdrH, isCorner: true),
                for (int b = 1; b <= n; b++) _bellHdrCell(b - 1, cellW, hdrH),
              ]),
              for (int i = 0; i < _classes.length; i++)
                Row(children: [
                  Container(
                    width: clsW,
                    height: cellH,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i.isEven
                          ? AppTheme.primary.withOpacity(0.07)
                          : Colors.white,
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Text(_classes[i],
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 12)),
                  ),
                  for (int b = 1; b <= n; b++)
                    _dataCell(_classes[i], b, cellW, cellH, i.isEven),
                ]),
            ]),
      ),
    );
  }

  Widget _hdrCell(String label, double w, double h,
      {bool isCorner = false}) {
    return Container(
      width: w,
      height: h,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color:
            isCorner ? AppTheme.primaryDark : AppTheme.primary,
        border: Border.all(color: AppTheme.primaryDark),
      ),
      child: Text(label,
          style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13)),
    );
  }

  Widget _bellHdrCell(int idx, double w, double h) {
    final isLunch = idx < _bells.length && _bells[idx].isLunch;
    final start = idx < _bells.length ? _fmt12(_startOf(idx)) : '';
    final end = idx < _bells.length ? _fmt12(_endOf(idx)) : '';
    return Container(
      width: w,
      height: h,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isLunch
            ? Colors.orange.shade700
            : AppTheme.primary,
        border: Border.all(
            color: isLunch
                ? Colors.orange.shade900
                : AppTheme.primaryDark),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(isLunch ? '🍽 Lunch' : 'Bell ${_bellDisplayNumber(idx)}',
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 11)),
        if (start.isNotEmpty)
          Text('$start–$end',
              style: const TextStyle(color: Colors.white70, fontSize: 9)),
      ]),
    );
  }

  Widget _dataCell(String cls, int bell, double w, double h, bool even) {
    final bellIdx = bell - 1;
    final isLunch = bellIdx < _bells.length && _bells[bellIdx].isLunch;

    // Aggregate across all days — use the first teacher found (Mon → Sat priority)
    Teacher? teacher;
    Color color = Colors.transparent;
    String subject = '';
    int assignedDayCount = 0;
    final dayDots = <String>[];
    for (final day in _days) {
      final entry = _timetable[cls]?[day]?[bell];
      if (entry != null && !entry.isEmpty) {
        assignedDayCount++;
        final t = _teacherById(entry.teacherId);
        if (t != null) {
          if (teacher == null) {
            teacher = t;
            color = _colorFor(entry.teacherId);
            subject = (entry.subject?.isNotEmpty == true)
                ? entry.subject!
                : t.subject;
          }
          if (t.id == teacher.id) dayDots.add(_dayAbbr[day]!);
        }
      }
    }
    final isPartial = teacher != null && assignedDayCount < _days.length;

    if (isLunch) {
      return Container(
        width: w,
        height: h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          border: Border.all(color: Colors.orange.shade100),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.restaurant, color: Colors.orange.shade300, size: 20),
          Text('Lunch',
              style: TextStyle(fontSize: 10, color: Colors.orange.shade400)),
        ]),
      );
    }

    return GestureDetector(
      onTap: _timetableEditing ? () => _editCell(cls, bell) : null,
      child: Stack(children: [
        Container(
          width: w,
          height: h,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: teacher != null
                ? color.withOpacity(0.14)
                : (even ? Colors.grey.shade50 : Colors.white),
            border: Border.all(
                color: teacher != null
                    ? color.withOpacity(0.35)
                    : Colors.grey.shade200),
          ),
          child: teacher != null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: color,
                      child: Text(teacher.name[0].toUpperCase(),
                          style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 2),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        teacher.name,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: color),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    if (subject.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          subject,
                          style: TextStyle(
                              fontSize: 9, color: color.withOpacity(0.75)),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    const SizedBox(height: 3),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: dayDots.map((abbr) => Container(
                            margin: const EdgeInsets.only(right: 2),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 3, vertical: 1),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(abbr.substring(0, 2),
                                style: TextStyle(
                                    fontSize: 7,
                                    fontWeight: FontWeight.bold,
                                    color: color)),
                          )).toList(),
                    ),
                  ],
                )
              : _timetableEditing
                  ? Icon(Icons.add_circle_outline,
                      size: 20, color: Colors.grey.shade400)
                  : const SizedBox.shrink(),
        ),
        // Partial assignment indicator (orange dot top-right)
        if (isPartial)
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.orange,
                shape: BoxShape.circle,
              ),
            ),
          ),
        // Edit mode lock-open indicator (bottom-right when editing)
        if (_timetableEditing && teacher != null)
          Positioned(
            bottom: 3,
            right: 3,
            child: Icon(Icons.edit, size: 9, color: color.withOpacity(0.5)),
          ),
      ]),
    );
  }
}

// ── Cell picker bottom sheet ──────────────────────────────────────────────────

class _CellPickerSheet extends StatefulWidget {
  final String className;
  final String bellLabel;
  final String timeRange;
  /// day → existing TimetableEntry (null = no assignment for that day)
  final Map<String, TimetableEntry?> cellEntries;
  final List<Teacher> teachers;
  final List<Color> palette;
  final List<String> days;
  final Map<String, String> dayAbbr;

  const _CellPickerSheet({
    required this.className,
    required this.bellLabel,
    required this.timeRange,
    required this.cellEntries,
    required this.teachers,
    required this.palette,
    required this.days,
    required this.dayAbbr,
  });

  @override
  State<_CellPickerSheet> createState() => _CellPickerSheetState();
}

class _CellPickerSheetState extends State<_CellPickerSheet> {
  late Set<String> _selectedDays;
  String? _teacherId;
  late final TextEditingController _subjectCtrl;
  String? _selectedSubjectPreset; // null = nothing, 'Custom...' = free-type

  static const _commonSubjects = [
    'Mathematics', 'English', 'Hindi', 'Science', 'Social Studies',
    'Computer', 'Physical Education', 'Art', 'Music', 'Sanskrit',
    'Moral Science', 'General Knowledge', 'EVS', 'History',
    'Geography', 'Civics', 'Biology', 'Physics', 'Chemistry',
  ];

  @override
  void initState() {
    super.initState();

    // Determine which days are already assigned
    final assignedDays = <String>{
      for (final day in widget.days)
        if (widget.cellEntries[day] != null &&
            !widget.cellEntries[day]!.isEmpty)
          day,
    };
    final unassignedDays =
        widget.days.where((d) => !assignedDays.contains(d)).toSet();

    if (assignedDays.isNotEmpty && unassignedDays.isNotEmpty) {
      // Partial assignment: pre-select the unassigned days so the coordinator
      // can immediately fill in the remaining slots.
      _teacherId = null;
      _selectedDays = unassignedDays;
      _subjectCtrl = TextEditingController();
      _selectedSubjectPreset = null;
      return;
    }

    // All days assigned or none: use dominant-teacher pre-selection
    final dayCounts = <String, int>{};
    for (final day in widget.days) {
      final tid = widget.cellEntries[day]?.teacherId;
      if (tid != null && tid.isNotEmpty) {
        dayCounts[tid] = (dayCounts[tid] ?? 0) + 1;
      }
    }

    String existingSubject = '';
    if (dayCounts.isNotEmpty) {
      _teacherId =
          dayCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      _selectedDays = {
        for (final day in widget.days)
          if (widget.cellEntries[day]?.teacherId == _teacherId) day,
      };
      final firstEntry = widget.cellEntries.values
          .firstWhere((e) => e?.teacherId == _teacherId, orElse: () => null);
      existingSubject = firstEntry?.subject?.isNotEmpty == true
          ? firstEntry!.subject!
          : _defaultSubjectFor(_teacherId);
    } else {
      _teacherId = null;
      _selectedDays = {};
    }

    _subjectCtrl = TextEditingController(text: existingSubject);
    _initSubjectPreset(existingSubject);
  }

  void _initSubjectPreset(String subject) {
    if (subject.isEmpty) {
      _selectedSubjectPreset = null;
    } else if (_commonSubjects.contains(subject)) {
      _selectedSubjectPreset = subject;
    } else {
      _selectedSubjectPreset = 'Custom...';
    }
  }

  String _defaultSubjectFor(String? tid) {
    if (tid == null) return '';
    return widget.teachers.where((t) => t.id == tid).firstOrNull?.subject ?? '';
  }

  bool get _hasAnyAssignment =>
      widget.cellEntries.values.any((e) => e != null && !e.isEmpty);

  @override
  void dispose() {
    _subjectCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      maxChildSize: 0.92,
      minChildSize: 0.45,
      builder: (ctx, sc) => Column(children: [
        // Drag handle
        Center(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
          ),
        ),

        // Title
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${widget.className} — ${widget.bellLabel}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
            if (widget.timeRange.isNotEmpty)
              Text(widget.timeRange,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          ]),
        ),

        // Current assignments summary (shown only for partial cells)
        Builder(builder: (ctx) {
          final assignedDays = widget.days
              .where((d) =>
                  widget.cellEntries[d] != null &&
                  !widget.cellEntries[d]!.isEmpty)
              .toList();
          final unassignedDays = widget.days
              .where((d) =>
                  widget.cellEntries[d] == null ||
                  widget.cellEntries[d]!.isEmpty)
              .toList();
          if (assignedDays.isEmpty || unassignedDays.isEmpty) {
            return const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.info_outline,
                          size: 13, color: Colors.orange.shade700),
                      const SizedBox(width: 5),
                      Text('Partially assigned',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.orange.shade800)),
                    ]),
                    const SizedBox(height: 4),
                    Text(
                      'Already filled: ${assignedDays.map((d) => widget.dayAbbr[d]).join(', ')}',
                      style: TextStyle(
                          fontSize: 11, color: Colors.orange.shade700),
                    ),
                    Text(
                      'Remaining: ${unassignedDays.map((d) => widget.dayAbbr[d]).join(', ')}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange.shade800),
                    ),
                  ]),
            ),
          );
        }),

        // Day multi-select chips
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Select days for new assignment',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                // "All" chip
                GestureDetector(
                  onTap: () => setState(() {
                    if (_selectedDays.length == widget.days.length) {
                      _selectedDays.clear();
                    } else {
                      _selectedDays = Set.from(widget.days);
                    }
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: _selectedDays.length == widget.days.length
                          ? AppTheme.primaryDark
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: _selectedDays.length == widget.days.length
                              ? AppTheme.primaryDark
                              : Colors.grey.shade300),
                    ),
                    child: Text('All',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _selectedDays.length == widget.days.length
                                ? Colors.white
                                : Colors.grey.shade600)),
                  ),
                ),
                // Individual day chips with existing-assignment indicators
                ...widget.days.map((d) {
                  final sel = _selectedDays.contains(d);
                  final existingEntry = widget.cellEntries[d];
                  final hasAssignment =
                      existingEntry != null && !existingEntry.isEmpty;
                  final existingTeacher = hasAssignment
                      ? widget.teachers
                          .where((t) => t.id == existingEntry.teacherId)
                          .firstOrNull
                      : null;
                  final tIdx = existingTeacher != null
                      ? widget.teachers.indexOf(existingTeacher)
                      : -1;
                  final existingColor = tIdx >= 0
                      ? widget.palette[tIdx % widget.palette.length]
                      : null;

                  return GestureDetector(
                    onTap: () => setState(() {
                      if (sel) {
                        _selectedDays.remove(d);
                      } else {
                        _selectedDays.add(d);
                      }
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: sel
                            ? AppTheme.primary
                            : (hasAssignment
                                ? existingColor!.withOpacity(0.10)
                                : Colors.grey.shade100),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: sel
                                ? AppTheme.primary
                                : (hasAssignment
                                    ? existingColor!.withOpacity(0.4)
                                    : Colors.grey.shade300)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(widget.dayAbbr[d]!,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: sel
                                    ? Colors.white
                                    : (hasAssignment
                                        ? existingColor!
                                        : Colors.grey.shade700))),
                        if (hasAssignment && existingTeacher != null) ...[
                          const SizedBox(width: 4),
                          CircleAvatar(
                            radius: 7,
                            backgroundColor: sel
                                ? Colors.white.withOpacity(0.3)
                                : existingColor,
                            child: Text(
                              existingTeacher.name[0].toUpperCase(),
                              style: TextStyle(
                                  fontSize: 7,
                                  color:
                                      sel ? Colors.white : Colors.white,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ]),
                    ),
                  );
                }),
              ],
            ),
          ]),
        ),

        const SizedBox(height: 10),

        // Subject dropdown
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Subject for this slot',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _selectedSubjectPreset,
              isExpanded: true,
              hint: const Text('Select subject…'),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.book_outlined, size: 20),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 12),
              ),
              items: [
                ..._commonSubjects.map((s) => DropdownMenuItem(
                      value: s,
                      child: Text(s),
                    )),
                const DropdownMenuItem(
                  value: 'Custom...',
                  child: Row(children: [
                    Icon(Icons.add, size: 16, color: AppTheme.primary),
                    SizedBox(width: 6),
                    Text('Add new subject…',
                        style: TextStyle(color: AppTheme.primary)),
                  ]),
                ),
              ],
              onChanged: (val) {
                setState(() {
                  _selectedSubjectPreset = val;
                  if (val != null && val != 'Custom...') {
                    _subjectCtrl.text = val;
                  } else if (val == 'Custom...') {
                    _subjectCtrl.clear();
                  }
                });
              },
            ),
            // Custom text field — shown only when "Custom..." is selected
            if (_selectedSubjectPreset == 'Custom...') ...[
              const SizedBox(height: 8),
              TextField(
                controller: _subjectCtrl,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Type subject name…',
                  prefixIcon: const Icon(Icons.edit_outlined, size: 20),
                  suffixIcon: _subjectCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () =>
                              setState(() => _subjectCtrl.clear()),
                        )
                      : null,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
                textCapitalization: TextCapitalization.words,
              ),
            ],
          ]),
        ),

        const Divider(height: 1),

        // Teacher list
        Expanded(
          child: ListView.builder(
            controller: sc,
            itemCount: widget.teachers.length,
            itemBuilder: (_, i) {
              final t = widget.teachers[i];
              final color = widget.palette[i % widget.palette.length];
              final selected = t.id == _teacherId;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      selected ? color : color.withOpacity(0.2),
                  child: Text(t.name[0].toUpperCase(),
                      style: TextStyle(
                          color: selected ? Colors.white : color,
                          fontWeight: FontWeight.bold)),
                ),
                title: Text(t.name,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                subtitle: Text(t.subject,
                    style: TextStyle(
                        color: Colors.grey.shade600, fontSize: 12)),
                trailing: selected
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
                selected: selected,
                selectedTileColor: color.withOpacity(0.06),
                onTap: () {
                  setState(() {
                    if (_teacherId == t.id) {
                      _teacherId = null;
                      _subjectCtrl.clear();
                      _selectedSubjectPreset = null;
                    } else {
                      final prev = _defaultSubjectFor(_teacherId);
                      _teacherId = t.id;
                      if (_subjectCtrl.text.isEmpty ||
                          _subjectCtrl.text == prev) {
                        _subjectCtrl.text = t.subject;
                        _initSubjectPreset(t.subject);
                      }
                    }
                  });
                },
              );
            },
          ),
        ),

        // Action bar
        Container(
          padding: EdgeInsets.fromLTRB(
              16, 10, 16, MediaQuery.of(ctx).padding.bottom + 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(children: [
            if (_hasAnyAssignment)
              TextButton.icon(
                onPressed: () => Navigator.pop(
                  ctx,
                  _Pick(null, days: widget.days, subject: null),
                ),
                icon: const Icon(Icons.clear, size: 16, color: Colors.red),
                label: const Text('Clear All',
                    style: TextStyle(color: Colors.red)),
              ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: (_teacherId == null || _selectedDays.isEmpty)
                  ? null
                  : () {
                      final sub = _subjectCtrl.text.trim();
                      Navigator.pop(
                        ctx,
                        _Pick(
                          _teacherId,
                          days: _selectedDays.toList(),
                          subject: sub.isEmpty ? null : sub,
                        ),
                      );
                    },
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Assign'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade200,
                disabledForegroundColor: Colors.grey.shade500,
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ── Duration dialog – owns its TextEditingController ─────────────────────────

class _DurationDialog extends StatefulWidget {
  final int bellNumber;
  final int initialMinutes;
  final bool isLunch;
  final bool applyToAll;
  const _DurationDialog({
    required this.bellNumber,
    required this.initialMinutes,
    this.isLunch = false,
    this.applyToAll = false,
  });

  @override
  State<_DurationDialog> createState() => _DurationDialogState();
}

class _DurationDialogState extends State<_DurationDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: '${widget.initialMinutes}');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = int.tryParse(_ctrl.text.trim());
    if (v != null && v > 0 && v <= 300) Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isLunch
          ? 'Lunch Break Duration'
          : 'Bell ${widget.bellNumber} Duration'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.applyToAll)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Duration will be applied to all regular bells',
                style: TextStyle(fontSize: 12, color: AppTheme.primaryMid),
              ),
            ),
          TextField(
            controller: _ctrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Duration in minutes',
              suffixText: 'min',
              border: OutlineInputBorder(),
              hintText: 'e.g. 45',
            ),
            autofocus: true,
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white),
          child: const Text('Set'),
        ),
      ],
    );
  }
}

// ── Lunch config result ───────────────────────────────────────────────────────

class _LunchConfig {
  final int afterIdx;
  final int duration;
  _LunchConfig(this.afterIdx, this.duration);
}

// ── Lunch bell dialog ─────────────────────────────────────────────────────────

class _LunchDialog extends StatefulWidget {
  final List<_Bell> bells;
  final List<int> nonLunchIndices;
  const _LunchDialog({required this.bells, required this.nonLunchIndices});

  @override
  State<_LunchDialog> createState() => _LunchDialogState();
}

class _LunchDialogState extends State<_LunchDialog> {
  late int _selectedAfterIdx;
  late final TextEditingController _durationCtrl;

  @override
  void initState() {
    super.initState();
    // Default: after the middle non-lunch bell
    final midPos = (widget.nonLunchIndices.length - 1) ~/ 2;
    _selectedAfterIdx = widget.nonLunchIndices[midPos];
    _durationCtrl = TextEditingController(text: '30');
  }

  @override
  void dispose() {
    _durationCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final dur = int.tryParse(_durationCtrl.text.trim());
    if (dur != null && dur > 0 && dur <= 120) {
      Navigator.pop(context, _LunchConfig(_selectedAfterIdx, dur));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Build "After Bell N" dropdown items counting only non-lunch bells
    int nonLunchNum = 0;
    final dropdownItems = <DropdownMenuItem<int>>[];
    for (int i = 0; i < widget.bells.length; i++) {
      if (!widget.bells[i].isLunch) {
        nonLunchNum++;
        dropdownItems.add(DropdownMenuItem(
          value: i,
          child: Text('After Bell $nonLunchNum'),
        ));
      }
    }

    return AlertDialog(
      title: const Text('Add Lunch Break'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Insert lunch after:',
              style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 8),
          DropdownButton<int>(
            value: _selectedAfterIdx,
            isExpanded: true,
            items: dropdownItems,
            onChanged: (v) {
              if (v != null) setState(() => _selectedAfterIdx = v);
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _durationCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Duration (minutes)',
              suffixText: 'min',
              border: OutlineInputBorder(),
              hintText: 'e.g. 30',
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white),
          child: const Text('Add Lunch'),
        ),
      ],
    );
  }
}

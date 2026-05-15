import 'package:flutter/material.dart';
import '../models/teacher.dart';
import '../models/timetable_entry.dart';
import '../services/timetable_service.dart';
import '../theme.dart';

/// Wrapper so we can distinguish "dismissed" (null) from "cleared" (teacherId=null).
class _PickResult {
  final String? teacherId;
  const _PickResult(this.teacherId);
}

class TimetableEditorScreen extends StatefulWidget {
  const TimetableEditorScreen({super.key});

  @override
  State<TimetableEditorScreen> createState() => _TimetableEditorScreenState();
}

class _TimetableEditorScreenState extends State<TimetableEditorScreen> {
  final _service = TimetableService();

  List<Teacher> _teachers = [];
  List<String> _classes = [];
  int _bellCount = 8;
  Map<String, Map<String, Map<int, TimetableEntry>>> _timetable = {};
  bool _loading = true;
  String _selectedDay = 'Monday';
  String? _filterTeacherId; // null = show all

  static const _days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'
  ];
  static const _dayAbbr = {
    'Monday': 'Mon', 'Tuesday': 'Tue', 'Wednesday': 'Wed',
    'Thursday': 'Thu', 'Friday': 'Fri', 'Saturday': 'Sat',
  };

  static const _palette = [
    Color(0xFF009688), // teal
    Color(0xFF3F51B5), // indigo
    Color(0xFFFF9800), // orange
    Color(0xFFE91E63), // pink
    Color(0xFF9C27B0), // purple
    Color(0xFF4CAF50), // green
    Color(0xFFF44336), // red
    Color(0xFF795548), // brown
    Color(0xFF00BCD4), // cyan
    Color(0xFF673AB7), // deep purple
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final teachers = await _service.getTeachers();
    final settings = await _service.getSettings();
    final tt = await _service.getTimetable();
    if (!mounted) return;
    setState(() {
      _teachers = teachers;
      _classes = List<String>.from(settings['classes'] as List);
      _bellCount = settings['numberOfBells'] as int;
      _timetable = tt;
      _loading = false;
    });
  }

  Color _colorFor(String? teacherId) {
    if (teacherId == null) return Colors.transparent;
    final idx = _teachers.indexWhere((t) => t.id == teacherId);
    return idx < 0 ? Colors.grey : _palette[idx % _palette.length];
  }

  Teacher? _teacherById(String? id) =>
      id == null ? null : _teachers.where((t) => t.id == id).firstOrNull;

  String _shortName(String? teacherId) {
    final t = _teacherById(teacherId);
    if (t == null) return '';
    final parts = t.name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) return '${parts.first[0]}. ${parts.last}';
    return parts.first;
  }

  Future<void> _editCell(String className, int bell) async {
    if (_teachers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add teachers first in Teacher Management')),
      );
      return;
    }

    final current = _timetable[className]?[_selectedDay]?[bell]?.teacherId;

    final result = await showModalBottomSheet<_PickResult>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.85,
        minChildSize: 0.35,
        builder: (_, scrollCtrl) => Column(
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$className — Bell $bell',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      const Text('Select a teacher for this slot',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
                if (current != null)
                  TextButton.icon(
                    onPressed: () => Navigator.pop(ctx, const _PickResult(null)),
                    icon: const Icon(Icons.clear, color: Colors.red, size: 18),
                    label: const Text('Clear', style: TextStyle(color: Colors.red)),
                  ),
              ]),
            ),
            const Divider(height: 1),
            // Teacher list
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                itemCount: _teachers.length,
                itemBuilder: (_, i) {
                  final t = _teachers[i];
                  final color = _palette[i % _palette.length];
                  final selected = t.id == current;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: selected ? color : color.withOpacity(0.2),
                      child: Text(t.name[0].toUpperCase(),
                          style: TextStyle(
                              color: selected ? Colors.white : color,
                              fontWeight: FontWeight.bold)),
                    ),
                    title: Text(t.name,
                        style: const TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Text(t.subject),
                    trailing: selected
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : null,
                    selected: selected,
                    selectedTileColor: color.withOpacity(0.06),
                    onTap: () => Navigator.pop(ctx, _PickResult(t.id)),
                  );
                },
              ),
            ),
            SizedBox(height: MediaQuery.of(ctx).padding.bottom + 12),
          ],
        ),
      ),
    );

    if (result == null || !mounted) return;

    final error = await _service.assignTeacher(
      className: className,
      days: [_selectedDay],
      bell: bell,
      teacherId: result.teacherId,
    );

    if (!mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() {
      _timetable.putIfAbsent(className, () => {});
      _timetable[className]!.putIfAbsent(_selectedDay, () => {});
      _timetable[className]![_selectedDay]![bell] =
          TimetableEntry(teacherId: result.teacherId);
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Timetable Editor'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _load,
              tooltip: 'Reload'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _classes.isEmpty
              ? _emptyHint(
                  'No classes configured',
                  'Go to Bell & Class Settings to add classes',
                  Icons.class_)
              : _teachers.isEmpty
                  ? _emptyHint(
                      'No teachers added',
                      'Go to Teacher Management to add teachers',
                      Icons.people_outline)
                  : Column(children: [
                      _buildLegend(),
                      const Divider(height: 1),
                      Expanded(child: _buildGrid()),
                    ]),
    );
  }

  Widget _emptyHint(String title, String sub, IconData icon) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 64, color: Colors.grey[300]),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(sub, style: TextStyle(color: Colors.grey[500], fontSize: 13)),
      ]),
    );
  }

  Widget _buildLegend() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      color: Colors.grey.shade50,
      child: Row(children: [
        // Day selector
        Expanded(
          child: DropdownButtonFormField<String>(
            value: _selectedDay,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Day',
              labelStyle: TextStyle(fontSize: 11, color: Colors.grey[600]),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              isDense: true,
            ),
            items: _days.map((d) => DropdownMenuItem<String>(
              value: d,
              child: Text(_dayAbbr[d] ?? d,
                  style: const TextStyle(fontSize: 12)),
            )).toList(),
            onChanged: (d) {
              if (d != null) setState(() => _selectedDay = d);
            },
          ),
        ),
        const SizedBox(width: 8),
        // Teacher filter
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<String?>(
            value: _filterTeacherId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Filter teacher',
              labelStyle: TextStyle(fontSize: 11, color: Colors.grey[600]),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All teachers',
                    style: TextStyle(fontSize: 12)),
              ),
              ..._teachers.asMap().entries.map((e) {
                final color = _palette[e.key % _palette.length];
                return DropdownMenuItem<String?>(
                  value: e.value.id,
                  child: Row(children: [
                    CircleAvatar(
                      radius: 8,
                      backgroundColor: color,
                      child: Text(e.value.name[0].toUpperCase(),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 8)),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(e.value.name,
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                );
              }),
            ],
            onChanged: (v) => setState(() => _filterTeacherId = v),
          ),
        ),
      ]),
    );
  }

  Widget _buildGrid() {
    const classColW = 86.0;
    const cellW = 112.0;
    const cellH = 62.0;
    const headerH = 42.0;

    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ─────────────────────────────────────────────────
            Row(children: [
              _headerCell('Class', classColW, headerH, isCorner: true),
              for (int b = 1; b <= _bellCount; b++)
                _headerCell('Bell $b', cellW, headerH),
            ]),
            // ── Data rows ──────────────────────────────────────────────────
            for (int i = 0; i < _classes.length; i++)
              Row(children: [
                // Class name cell
                Container(
                  width: classColW,
                  height: cellH,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i.isEven ? AppTheme.primary.withOpacity(0.05) : Colors.white,
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Text(_classes[i],
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 12)),
                ),
                // Bell cells
                for (int b = 1; b <= _bellCount; b++)
                  _buildCell(_classes[i], b, cellW, cellH, i.isEven),
              ]),
          ],
        ),
      ),
    );
  }

  Widget _headerCell(String label, double w, double h, {bool isCorner = false}) {
    return Container(
      width: w,
      height: h,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isCorner ? AppTheme.primaryDark : AppTheme.primary,
        border: Border.all(color: AppTheme.primaryDark),
      ),
      child: Text(label,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }

  Widget _buildCell(String cls, int bell, double w, double h, bool evenRow) {
    final teacherId = _timetable[cls]?[_selectedDay]?[bell]?.teacherId;
    final color = _colorFor(teacherId);
    final teacher = _teacherById(teacherId);
    final hasTeacher = teacher != null;

    // Dim this cell if a teacher filter is active and this cell's teacher doesn't match
    final filtered = _filterTeacherId != null;
    final matches = filtered && teacherId == _filterTeacherId;
    final dimmed  = filtered && !matches;

    return GestureDetector(
      onTap: () => _editCell(cls, bell),
      child: Opacity(
        opacity: dimmed ? 0.25 : 1.0,
        child: Container(
          width: w,
          height: h,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hasTeacher
                ? color.withOpacity(matches ? 0.22 : 0.14)
                : (evenRow ? Colors.grey.shade50 : Colors.white),
            border: Border.all(
                color: matches
                    ? color
                    : (hasTeacher
                        ? color.withOpacity(0.35)
                        : Colors.grey.shade200),
                width: matches ? 2 : 1),
          ),
          child: hasTeacher
              ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: color,
                    child: Text(teacher.name[0].toUpperCase(),
                        style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 3),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      _shortName(teacherId),
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: color),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ])
              : Icon(Icons.add_circle_outline,
                  size: 20, color: Colors.grey.shade400),
        ),
      ),
    );
  }
}

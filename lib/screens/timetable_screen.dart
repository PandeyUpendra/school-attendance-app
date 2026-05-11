import 'package:flutter/material.dart';
import '../services/firestore_service.dart';

class TimetableScreen extends StatefulWidget {
  final String className;
  final String schoolId;
  /// When true: save button is hidden and period cells are not tappable.
  final bool readOnly;

  const TimetableScreen({
    super.key,
    required this.className,
    required this.schoolId,
    this.readOnly = false,
  });

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  static const List<String> _days = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'
  ];

  static const List<String> _subjects = [
    'Math', 'English', 'Science', 'Hindi', 'Social Studies',
    'Computer', 'Art', 'PE', 'Music', 'Free Period',
  ];

  /// timetable[day] = list of subject strings (one per period)
  Map<String, List<String>> _timetable = {};
  bool _loading = true;
  bool _saving = false;
  int _periods = 6;

  @override
  void initState() {
    super.initState();
    _loadTimetable();
  }

  Future<void> _loadTimetable() async {
    Map<String, List<String>>? loaded;
    if (widget.schoolId.isNotEmpty) {
      loaded = await FirestoreService.loadTimetable(
          schoolId: widget.schoolId, classId: widget.className);
    }
    if (loaded != null && loaded.isNotEmpty) {
      _periods =
          loaded.values.map((v) => v.length).fold(0, (a, b) => a > b ? a : b);
      if (_periods < 1) _periods = 6;
      setState(() {
        _timetable = loaded!;
        _loading = false;
      });
    } else {
      // Default empty timetable
      setState(() {
        _timetable = {
          for (final day in _days) day: List.filled(_periods, 'Free Period'),
        };
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (widget.schoolId.isEmpty) return;
    setState(() => _saving = true);
    await FirestoreService.saveTimetable(
        schoolId: widget.schoolId,
        classId: widget.className,
        timetable: _timetable);
    setState(() => _saving = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Timetable saved!'),
        backgroundColor: Color(0xFF1565C0),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _editPeriod(String day, int periodIndex) {
    String selected = _timetable[day]?[periodIndex] ?? 'Free Period';
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('$day — Period ${periodIndex + 1}'),
        content: StatefulBuilder(
          builder: (ctx, setInner) => SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: _subjects.map((subj) {
                return RadioListTile<String>(
                  dense: true,
                  title: Text(subj),
                  value: subj,
                  groupValue: selected,
                  onChanged: (v) {
                    if (v != null) setInner(() => selected = v);
                  },
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _timetable[day]![periodIndex] = selected;
              });
              Navigator.pop(context);
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
  }

  Color _subjectColor(String subject) {
    const colors = {
      'Math': Color(0xFF1565C0),
      'English': Color(0xFF00897B),
      'Science': Color(0xFF6A1B9A),
      'Hindi': Color(0xFFE65100),
      'Social Studies': Color(0xFF283593),
      'Computer': Color(0xFF00838F),
      'Art': Color(0xFFAD1457),
      'PE': Color(0xFF2E7D32),
      'Music': Color(0xFF6D4C41),
      'Free Period': Color(0xFF757575),
    };
    return colors[subject] ?? const Color(0xFF1565C0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Timetable — ${widget.className}'),
        actions: [
          if (!_loading && widget.schoolId.isNotEmpty && !widget.readOnly)
            _saving
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.save_rounded),
                    tooltip: 'Save timetable',
                    onPressed: _save,
                  ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Period header row
                Container(
                  color: const Color(0xFF1565C0),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  child: Row(
                    children: [
                      const SizedBox(width: 44), // day label width
                      ...List.generate(_periods, (i) {
                        return Expanded(
                          child: Center(
                            child: Text(
                              'P${i + 1}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: _days.map((day) {
                      final periods = _timetable[day] ??
                          List.filled(_periods, 'Free Period');
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardTheme.color ??
                              Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(
                                color: Colors.black12,
                                blurRadius: 4,
                                offset: Offset(0, 2))
                          ],
                        ),
                        child: Row(
                          children: [
                            // Day label
                            Container(
                              width: 44,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1565C0).withOpacity(0.1),
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(12),
                                  bottomLeft: Radius.circular(12),
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  day,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Color(0xFF1565C0),
                                  ),
                                ),
                              ),
                            ),
                            // Periods
                            ...List.generate(periods.length, (i) {
                              final subject = periods[i];
                              final color = _subjectColor(subject);
                              return Expanded(
                                child: GestureDetector(
                                  onTap: widget.readOnly
                                      ? null
                                      : () => _editPeriod(day, i),
                                  child: Container(
                                    margin: const EdgeInsets.all(4),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 8, horizontal: 2),
                                    decoration: BoxDecoration(
                                      color: color.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: color.withOpacity(0.3)),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          subject.length > 7
                                              ? subject.substring(0, 6) + '.'
                                              : subject,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w600,
                                            color: color,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
                // Info hint
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.touch_app_outlined,
                          size: 14, color: Colors.grey.shade400),
                      const SizedBox(width: 6),
                      Text(
                        'Tap any period to change subject',
                        style: TextStyle(
                            color: Colors.grey.shade400, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

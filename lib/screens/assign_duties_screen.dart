import 'package:flutter/material.dart';
import '../models/teacher.dart';
import '../services/timetable_service.dart';
import '../theme.dart';

class AssignDutiesScreen extends StatefulWidget {
  const AssignDutiesScreen({super.key});

  @override
  State<AssignDutiesScreen> createState() => _AssignDutiesScreenState();
}

class _AssignDutiesScreenState extends State<AssignDutiesScreen> {
  final _service = TimetableService();

  List<Teacher>       _teachers = [];
  Map<String, String> _duties   = {}; // teacherId → duty
  bool _loading = true;
  bool _dirty   = false;
  bool _saving  = false;

  static const _commonDuties = [
    'Assembly',
    'Lunch Bell Duty',
    'Gate Duty',
    'Morning Duty',
    'Exam Duty',
    'Library Duty',
  ];

  static const _colors = [
    AppTheme.primary, AppTheme.primaryDark, AppTheme.primaryMid, AppTheme.accent,
    Colors.purple, Colors.green, Colors.red, Colors.brown,
    Colors.cyan, Colors.deepPurple,
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final teachers = await _service.getTeachers();
    final saved    = await _service.getTodayDuties();
    if (!mounted) return;
    setState(() {
      _teachers = teachers;
      _duties   = Map.from(saved);
      _loading  = false;
      _dirty    = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    // Only save non-empty duties
    final toSave = Map<String, String>.from(_duties)
      ..removeWhere((_, v) => v.isEmpty);
    await _service.saveTodayDuties(toSave);
    if (!mounted) return;
    setState(() { _saving = false; _dirty = false; });
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: AppTheme.primaryDark,
          duration: const Duration(seconds: 2),
          content: const Row(children: [
            Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
            SizedBox(width: 10),
            Text('Duties saved for today'),
          ]),
        ),
      );
  }

  void _assignDuty(String teacherId, String duty) {
    setState(() {
      if (duty.isEmpty) {
        _duties.remove(teacherId);
      } else {
        _duties[teacherId] = duty;
      }
      _dirty = true;
    });
  }

  Future<void> _pickCustomDuty(Teacher teacher) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Custom Duty — ${teacher.name}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: 'Enter duty name…',
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: AppTheme.primary, width: 1.5),
            ),
          ),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final t = ctrl.text.trim();
              if (t.isNotEmpty) Navigator.pop(ctx, t);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white),
            child: const Text('Assign'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      _assignDuty(teacher.id, result);
    }
  }

  String _dateLabel() {
    final d = DateTime.now();
    const mo = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    const dy = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return '${dy[d.weekday-1]}, ${d.day} ${mo[d.month-1]}';
  }

  @override
  Widget build(BuildContext context) {
    final assigned   = _duties.length;
    final unassigned = _teachers.length - assigned;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Assign Duties',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text(_dateLabel(),
                style:
                    const TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        actions: [
          if (_dirty)
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _teachers.isEmpty
              ? _emptyState()
              : Column(children: [
                  // Stats strip
                  Container(
                    color: AppTheme.primary,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: Row(children: [
                      _StatBadge('${_teachers.length}', 'Teachers'),
                      const SizedBox(width: 8),
                      _StatBadge('$assigned',   'Assigned'),
                      const SizedBox(width: 8),
                      _StatBadge('$unassigned', 'Free'),
                    ]),
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _load,
                      color: AppTheme.primary,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(0, 8, 0, 80),
                        itemCount: _teachers.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 70),
                        itemBuilder: (_, i) {
                          final t     = _teachers[i];
                          final color = _colors[i % _colors.length];
                          final duty  = _duties[t.id] ?? '';
                          return _TeacherDutyRow(
                            teacher:      t,
                            color:        color,
                            currentDuty:  duty,
                            commonDuties: _commonDuties,
                            onDutyChanged: (d) => _assignDuty(t.id, d),
                            onCustomDuty:  () => _pickCustomDuty(t),
                          );
                        },
                      ),
                    ),
                  ),
                ]),
    );
  }

  Widget _emptyState() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.people_outline, size: 72, color: Colors.grey.shade300),
      const SizedBox(height: 16),
      Text('No teachers added yet',
          style: TextStyle(fontSize: 16, color: Colors.grey.shade400)),
      const SizedBox(height: 6),
      Text('Add teachers in Manage Teachers first',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
    ]),
  );
}

// ── Teacher duty row ───────────────────────────────────────────────────────────

class _TeacherDutyRow extends StatelessWidget {
  final Teacher  teacher;
  final Color    color;
  final String   currentDuty;
  final List<String> commonDuties;
  final ValueChanged<String> onDutyChanged;
  final VoidCallback onCustomDuty;

  const _TeacherDutyRow({
    required this.teacher,
    required this.color,
    required this.currentDuty,
    required this.commonDuties,
    required this.onDutyChanged,
    required this.onCustomDuty,
  });

  @override
  Widget build(BuildContext context) {
    final hasDuty = currentDuty.isNotEmpty;

    return Container(
      color: hasDuty ? color.withOpacity(0.04) : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Avatar
          CircleAvatar(
            radius: 22,
            backgroundColor: color,
            child: Text(
              teacher.name[0].toUpperCase(),
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16),
            ),
          ),
          const SizedBox(width: 12),

          // Name + subject
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(teacher.name,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                Text(teacher.subject,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500)),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Duty dropdown
          _DutyDropdown(
            value: currentDuty,
            commonDuties: commonDuties,
            color: color,
            onChanged: onDutyChanged,
            onCustom: onCustomDuty,
          ),
        ],
      ),
    );
  }
}

// ── Duty dropdown button ──────────────────────────────────────────────────────

class _DutyDropdown extends StatelessWidget {
  final String   value;
  final List<String> commonDuties;
  final Color    color;
  final ValueChanged<String> onChanged;
  final VoidCallback onCustom;

  const _DutyDropdown({
    required this.value,
    required this.commonDuties,
    required this.color,
    required this.onChanged,
    required this.onCustom,
  });

  @override
  Widget build(BuildContext context) {
    final hasDuty = value.isNotEmpty;

    return GestureDetector(
      onTap: () => _showPicker(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: hasDuty ? color.withOpacity(0.12) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: hasDuty ? color.withOpacity(0.4) : Colors.grey.shade300),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            hasDuty ? Icons.work_outline : Icons.add,
            size: 14,
            color: hasDuty ? color : Colors.grey.shade500,
          ),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 110),
            child: Text(
              hasDuty ? value : 'Assign Duty',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: hasDuty ? color : Colors.grey.shade600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.arrow_drop_down,
              size: 16,
              color: hasDuty ? color : Colors.grey.shade400),
        ]),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom + 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 36, height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Select Duty',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          const Divider(height: 1),
          // Clear option
          if (value.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.clear, color: Colors.red, size: 20),
              title: const Text('Remove duty',
                  style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                onChanged('');
              },
            ),
          // Common duties
          for (final duty in commonDuties)
            ListTile(
              leading: Icon(
                Icons.work_outline,
                color: duty == value ? color : Colors.grey.shade400,
                size: 20,
              ),
              title: Text(duty),
              trailing: duty == value
                  ? Icon(Icons.check, color: color, size: 18)
                  : null,
              onTap: () {
                Navigator.pop(context);
                onChanged(duty);
              },
            ),
          // Custom option
          ListTile(
            leading: Icon(Icons.add_circle_outline,
                color: AppTheme.primary, size: 20),
            title: const Text('Custom duty…',
                style: TextStyle(color: AppTheme.primary)),
            onTap: () {
              Navigator.pop(context);
              onCustom();
            },
          ),
        ]),
      ),
    );
  }
}

// ── Stat badge ────────────────────────────────────────────────────────────────

class _StatBadge extends StatelessWidget {
  final String value, label;
  const _StatBadge(this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          Text(label,
              style:
                  const TextStyle(fontSize: 11, color: Colors.white70)),
        ]),
      ),
    );
  }
}

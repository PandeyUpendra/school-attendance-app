import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/copy_check.dart';
import '../models/student.dart';
import '../models/teacher.dart';
import '../services/copy_check_service.dart';
import '../services/student_service.dart';
import '../theme.dart';

/// Teacher's copy-checking screen.
/// Shows all classes the teacher teaches → create sessions → mark students.
class CopyCheckingScreen extends StatefulWidget {
  final Teacher teacher;

  const CopyCheckingScreen({super.key, required this.teacher});

  @override
  State<CopyCheckingScreen> createState() => _CopyCheckingScreenState();
}

class _CopyCheckingScreenState extends State<CopyCheckingScreen>
    with SingleTickerProviderStateMixin {
  final _service = CopyCheckService();

  bool _loading = true;
  /// className → subject
  Map<String, String> _teacherClasses = {};
  String? _selectedClass;
  List<CopyCheck> _checks = [];

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadClasses();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadClasses() async {
    setState(() => _loading = true);
    final classes = await _service.getClassesForTeacher(widget.teacher.id);
    if (!mounted) return;
    setState(() { _teacherClasses = classes; });

    if (classes.isNotEmpty) {
      await _selectClass(classes.keys.first);
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _selectClass(String cls) async {
    setState(() { _selectedClass = cls; _loading = true; });
    final checks = await _service.getChecks(
        teacherId: widget.teacher.id, className: cls);
    if (!mounted) return;
    setState(() { _checks = checks; _loading = false; });
  }

  Future<void> _createSession() async {
    if (_selectedClass == null) return;
    final subject = _teacherClasses[_selectedClass!] ?? widget.teacher.subject;

    DateTime date = DateTime.now();
    bool saving   = false;

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          title: const Text('New Copy Checking Session'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today_outlined),
                title: Text(
                    '${date.day}/${date.month}/${date.year}'),
                subtitle: const Text('Tap to change date'),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(
                        const Duration(days: 7)),
                  );
                  if (picked != null) setS(() => date = picked);
                },
              ),
              Text(
                'Class: $_selectedClass  •  Subject: $subject',
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      setS(() => saving = true);
                      final check = CopyCheck(
                        id:          '',
                        teacherId:   widget.teacher.id,
                        teacherName: widget.teacher.name,
                        className:   _selectedClass!,
                        subject:     subject,
                        checkDate:   date,
                        createdAt:   DateTime.now(),
                      );
                      await _service.createCheck(check);
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );

    if (created == true && _selectedClass != null) {
      _selectClass(_selectedClass!);
    }
  }

  Future<void> _openSession(CopyCheck check) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _CheckSessionScreen(
          check:       check,
          teacherName: widget.teacher.name,
        ),
      ),
    );
    // Refresh list after returning
    if (_selectedClass != null) _selectClass(_selectedClass!);
  }

  Future<void> _deleteSession(CopyCheck check) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
        title: const Text('Delete Session?'),
        content: Text(
          'Delete checking session for ${check.className} '
          'on ${check.checkDate.day}/${check.checkDate.month}/'
          '${check.checkDate.year}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _service.deleteCheck(check.id);
    if (_selectedClass != null) _selectClass(_selectedClass!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Copy Checking',
                style:
                    TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text('Mark student copies per session',
                style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
      ),
      floatingActionButton: _selectedClass != null && !_loading
          ? FloatingActionButton.extended(
              onPressed: _createSession,
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('New Session'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _teacherClasses.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.class_outlined,
                          size: 56, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          'You are not assigned to any class in the timetable yet.\n'
                          'Please ask the coordinator to assign you.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Class chips
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _teacherClasses.keys.map((cls) {
                            final selected = cls == _selectedClass;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(cls),
                                selected: selected,
                                selectedColor: Colors.indigo,
                                labelStyle: TextStyle(
                                  color: selected ? Colors.white : null,
                                  fontWeight: selected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                                onSelected: (_) => _selectClass(cls),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const Divider(height: 1),

                    // Session list
                    Expanded(
                      child: _checks.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.menu_book_outlined,
                                      size: 56,
                                      color: Colors.grey.shade300),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No sessions yet.\nTap + to create one.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: Colors.grey.shade500),
                                  ),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: () =>
                                  _selectClass(_selectedClass!),
                              color: Colors.indigo,
                              child: ListView.separated(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.all(12),
                                itemCount: _checks.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (_, i) => _SessionCard(
                                  check:    _checks[i],
                                  onTap:    () => _openSession(_checks[i]),
                                  onDelete: () => _deleteSession(_checks[i]),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }
}

// ─── Session card ─────────────────────────────────────────────────────────────

class _SessionCard extends StatelessWidget {
  final CopyCheck    check;
  final VoidCallback onTap, onDelete;

  const _SessionCard({
    required this.check,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final c = check;
    final date =
        '${c.checkDate.day}/${c.checkDate.month}/${c.checkDate.year}';
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: Colors.indigo.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.menu_book_outlined,
                color: Colors.indigo, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$date  •  ${c.subject}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(c.className,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                color: Colors.redAccent, size: 20),
            onPressed: onDelete,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right,
              color: Colors.grey.shade400, size: 20),
        ]),
      ),
    );
  }
}

// ─── Session detail — mark students ──────────────────────────────────────────

class _CheckSessionScreen extends StatefulWidget {
  final CopyCheck check;
  final String    teacherName;

  const _CheckSessionScreen({
    required this.check,
    required this.teacherName,
  });

  @override
  State<_CheckSessionScreen> createState() => _CheckSessionScreenState();
}

class _CheckSessionScreenState extends State<_CheckSessionScreen>
    with SingleTickerProviderStateMixin {
  final _service        = CopyCheckService();
  final _studentService = StudentService();

  late TabController _tab;
  bool _loading = true;
  bool _saving  = false;

  List<Student> _students    = [];
  List<CopyStatus> _statuses = [];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _studentService.getStudentsByClass(widget.check.className),
      _service.getStatuses(widget.check.id),
    ]);
    final students = results[0] as List<Student>;
    final saved    = results[1] as List<CopyStatus>;

    // Build status list: pre-fill from saved, default to 'not_done'
    final savedMap = {for (final s in saved) s.roll: s};
    final statuses = students.map((s) {
      return savedMap[s.roll] ??
          CopyStatus(
            roll:          s.roll,
            studentName:   s.name,
            guardianPhone: s.phone,
            status:        'not_done',
          );
    }).toList();

    if (!mounted) return;
    setState(() {
      _students  = students;
      _statuses  = statuses;
      _loading   = false;
    });
  }

  Future<void> _saveAll() async {
    setState(() => _saving = true);
    await _service.saveStatuses(widget.check.id, _statuses);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Saved ✓'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _setStatus(int roll, String status) {
    setState(() {
      final idx = _statuses.indexWhere((s) => s.roll == roll);
      if (idx >= 0) {
        _statuses[idx] = _statuses[idx].copyWith(status: status);
      }
    });
  }

  Future<void> _call(String phone) async {
    if (phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _whatsapp(CopyStatus s) async {
    if (s.guardianPhone.isEmpty) return;
    final msg = Uri.encodeComponent(
      'Dear Parent, ${s.studentName}\'s copy was '
      '${s.status == "not_done" ? "not submitted" : "incomplete"} '
      'for ${widget.check.subject} on '
      '${widget.check.checkDate.day}/${widget.check.checkDate.month}/'
      '${widget.check.checkDate.year}. '
      'Please ensure it is completed by the next class.',
    );
    final uri = Uri.parse('https://wa.me/${s.guardianPhone}?text=$msg');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  List<CopyStatus> get _pending => _statuses
      .where((s) => s.status == 'incomplete' || s.status == 'not_done')
      .toList();

  @override
  Widget build(BuildContext context) {
    final c = widget.check;
    final date =
        '${c.checkDate.day}/${c.checkDate.month}/${c.checkDate.year}';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.subject,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            Text('${c.className}  •  $date',
                style:
                    const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              ),
            )
          else
            TextButton(
              onPressed: _saveAll,
              child: const Text('Save',
                  style: TextStyle(color: Colors.white)),
            ),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            const Tab(text: 'All Students'),
            Tab(text: 'Pending (${_loading ? "…" : "${_pending.length}"})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tab,
              children: [
                // ── All Students Tab ──
                _AllStudentsTab(
                  statuses:  _statuses,
                  onStatus:  _setStatus,
                  onSave:    _saveAll,
                  saving:    _saving,
                ),
                // ── Pending Tab ──
                _PendingTab(
                  pending:   _pending,
                  onCall:    _call,
                  onWhatsApp: _whatsapp,
                ),
              ],
            ),
    );
  }
}

// ─── All Students Tab ─────────────────────────────────────────────────────────

class _AllStudentsTab extends StatelessWidget {
  final List<CopyStatus> statuses;
  final void Function(int roll, String status) onStatus;
  final VoidCallback onSave;
  final bool saving;

  const _AllStudentsTab({
    required this.statuses,
    required this.onStatus,
    required this.onSave,
    required this.saving,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Quick summary bar
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _SumChip(
                count: statuses.where((s) => s.status == 'checked').length,
                label: 'Checked',
                color: Colors.green,
              ),
              _SumChip(
                count: statuses
                    .where((s) => s.status == 'incomplete')
                    .length,
                label: 'Incomplete',
                color: Colors.orange,
              ),
              _SumChip(
                count:
                    statuses.where((s) => s.status == 'not_done').length,
                label: 'Not Done',
                color: Colors.red,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: statuses.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, indent: 72),
            itemBuilder: (_, i) {
              final s = statuses[i];
              return _StudentStatusTile(
                status:   s,
                onStatus: (newStatus) => onStatus(s.roll, newStatus),
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: saving ? null : onSave,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save All'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SumChip extends StatelessWidget {
  final int    count;
  final String label;
  final Color  color;
  const _SumChip(
      {required this.count, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$count',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color)),
          const SizedBox(height: 2),
          Text(label,
              style:
                  TextStyle(fontSize: 10, color: Colors.grey.shade600)),
        ],
      );
}

class _StudentStatusTile extends StatelessWidget {
  final CopyStatus status;
  final void Function(String) onStatus;

  const _StudentStatusTile(
      {required this.status, required this.onStatus});

  Color get _color {
    switch (status.status) {
      case 'checked':    return Colors.green;
      case 'incomplete': return Colors.orange;
      default:           return Colors.red;
    }
  }

  IconData get _icon {
    switch (status.status) {
      case 'checked':    return Icons.check_circle_outline;
      case 'incomplete': return Icons.warning_amber_rounded;
      default:           return Icons.cancel_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(children: [
        // Avatar
        CircleAvatar(
          radius: 18,
          backgroundColor: _color.withOpacity(0.12),
          child: Text(
            status.studentName.isNotEmpty
                ? status.studentName[0].toUpperCase()
                : '?',
            style: TextStyle(
                color: _color, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(status.studentName,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              Text('Roll ${status.roll}',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade500)),
            ],
          ),
        ),
        // Status buttons
        Row(children: [
          _StatusBtn(
            icon: Icons.check_circle_outline,
            color: Colors.green,
            active: status.status == 'checked',
            onTap: () => onStatus('checked'),
            tooltip: 'Checked',
          ),
          _StatusBtn(
            icon: Icons.warning_amber_rounded,
            color: Colors.orange,
            active: status.status == 'incomplete',
            onTap: () => onStatus('incomplete'),
            tooltip: 'Incomplete',
          ),
          _StatusBtn(
            icon: Icons.cancel_outlined,
            color: Colors.red,
            active: status.status == 'not_done',
            onTap: () => onStatus('not_done'),
            tooltip: 'Not Done',
          ),
        ]),
      ]),
    );
  }
}

class _StatusBtn extends StatelessWidget {
  final IconData icon;
  final Color    color;
  final bool     active;
  final VoidCallback onTap;
  final String   tooltip;

  const _StatusBtn({
    required this.icon,
    required this.color,
    required this.active,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(left: 6),
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: active
                ? color.withOpacity(0.15)
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? color : Colors.grey.shade300,
              width: active ? 1.5 : 1,
            ),
          ),
          child: Icon(icon,
              size: 18,
              color: active ? color : Colors.grey.shade400),
        ),
      ),
    );
  }
}

// ─── Pending Tab ──────────────────────────────────────────────────────────────

class _PendingTab extends StatelessWidget {
  final List<CopyStatus> pending;
  final Future<void> Function(String phone) onCall;
  final Future<void> Function(CopyStatus) onWhatsApp;

  const _PendingTab({
    required this.pending,
    required this.onCall,
    required this.onWhatsApp,
  });

  @override
  Widget build(BuildContext context) {
    if (pending.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline,
                size: 56, color: Colors.green.shade300),
            const SizedBox(height: 12),
            Text('All copies checked!',
                style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: pending.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final s = pending[i];
        final isNotDone = s.status == 'not_done';
        final color = isNotDone ? Colors.red : Colors.orange;
        final label = isNotDone ? 'Not Done' : 'Incomplete';

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isNotDone
                    ? Icons.cancel_outlined
                    : Icons.warning_amber_rounded,
                color: color, size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.studentName,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold)),
                  Text(
                    'Roll ${s.roll}  •  $label',
                    style: TextStyle(
                        fontSize: 12, color: color),
                  ),
                ],
              ),
            ),
            // Action buttons
            if (s.guardianPhone.isNotEmpty) ...[
              IconButton(
                icon: const Icon(Icons.call_outlined,
                    color: Colors.green, size: 22),
                onPressed: () => onCall(s.guardianPhone),
                tooltip: 'Call Guardian',
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              IconButton(
                icon: Icon(Icons.chat_outlined,
                    color: Colors.green.shade700, size: 22),
                onPressed: () => onWhatsApp(s),
                tooltip: 'WhatsApp',
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ]),
        );
      },
    );
  }
}

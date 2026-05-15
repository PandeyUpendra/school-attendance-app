import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
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
  List<TeacherAssignment> _assignments = [];
  List<CopyCheck> _checks = [];

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadClasses() async {
    setState(() => _loading = true);
    final assignments = await _service.getTeacherAssignments(widget.teacher.id);
    if (!mounted) return;
    setState(() { _assignments = assignments; });
    await _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() { _loading = true; });
    // Load ALL sessions for this teacher
    final checks = await _service.getChecks(teacherId: widget.teacher.id);
    if (!mounted) return;
    setState(() { _checks = checks; _loading = false; });
  }

  Future<void> _createSession() async {
    if (_assignments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No classes assigned to you in the timetable.')),
      );
      return;
    }

    // Get unique classes
    final classes = _assignments.map((a) => a.className).toSet().toList()..sort();

    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _CascadingSessionDialog(
        assignments: _assignments,
        teacher: widget.teacher,
        onCreated: (check) async {
          await _service.createCheck(check);
          if (mounted) {
            Navigator.pop(ctx, true);
            _loadSessions();
          }
        },
      ),
    );
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
    _loadSessions();
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
    _loadSessions();
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
      floatingActionButton: !_loading
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
          : Column(
                  children: [
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
                              onRefresh: () => _loadSessions(),
                              color: AppTheme.primary,
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

// ── Cascading Dialog Widget ──────────────────────────────────────────────────

class _CascadingSessionDialog extends StatefulWidget {
  final List<TeacherAssignment> assignments;
  final Teacher teacher;
  final Function(CopyCheck) onCreated;

  const _CascadingSessionDialog({
    required this.assignments,
    required this.teacher,
    required this.onCreated,
  });

  @override
  State<_CascadingSessionDialog> createState() => _CascadingSessionDialogState();
}

class _CascadingSessionDialogState extends State<_CascadingSessionDialog> {
  final _customSubjectCtrl = TextEditingController();
  
  String? _selectedClass;
  String? _selectedSection;
  String? _selectedSubject;
  DateTime _date = DateTime.now();
  bool _isCustomSubject = false;
  bool _saving = false;

  List<String> get _classes => widget.assignments
      .map((a) => a.className)
      .toSet()
      .toList()
    ..sort();

  List<String> get _sections => _selectedClass == null
      ? []
      : widget.assignments
          .where((a) => a.className == _selectedClass)
          .map((a) => a.section)
          .toSet()
          .toList()
    ..sort();

  List<String> get _subjects => (_selectedClass == null || _selectedSection == null)
      ? []
      : widget.assignments
          .where((a) =>
              a.className == _selectedClass && a.section == _selectedSection)
          .map((a) => a.subject)
          .toSet()
          .toList()
    ..sort();

  @override
  void initState() {
    super.initState();
    _customSubjectCtrl.addListener(() => setState(() {}));

    // Auto-select first class if available
    if (_classes.isNotEmpty) {
      // Prioritize class where they are class teacher
      final teacherOf = widget.teacher.classTeacherOf;
      if (teacherOf != null && _classes.contains(teacherOf)) {
        _selectedClass = teacherOf;
      } else {
        _selectedClass = _classes.first;
      }

      // Auto-select section
      final sects = _sections;
      if (sects.contains(widget.teacher.section)) {
        _selectedSection = widget.teacher.section;
      } else if (sects.isNotEmpty) {
        _selectedSection = sects.first;
      }

      // Auto-select subject
      final subjs = _subjects;
      if (subjs.isNotEmpty) {
        _selectedSubject = subjs.first;
      }
    }
  }

  bool get _canProceed =>
      _selectedClass != null &&
      (_isCustomSubject
          ? _customSubjectCtrl.text.trim().isNotEmpty
          : _selectedSubject != null);

  void _showValidationError() {
    String message = 'Please fill out all details.';
    if (_selectedClass == null) {
      message = 'Please select a class.';
    } else if (_isCustomSubject && _customSubjectCtrl.text.trim().isEmpty) {
      message = 'Please enter a custom subject name.';
    } else if (_selectedSubject == null && !_isCustomSubject) {
      message = 'Please select a subject.';
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.menu_book_outlined, color: AppTheme.primary),
          const SizedBox(width: 10),
          const Text('New Session', style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date Picker
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 7)),
                );
                if (picked != null) setState(() => _date = picked);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 18, color: Colors.grey),
                    const SizedBox(width: 10),
                    Text(
                      '${_date.day}/${_date.month}/${_date.year}',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    const Text('Change', style: TextStyle(color: AppTheme.primary, fontSize: 12)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Class Dropdown
            _label('Select Class'),
            DropdownButtonFormField<String>(
              value: _selectedClass,
              isExpanded: true,
              decoration: _inputDeco(),
              items: _classes.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (val) {
                setState(() {
                  _selectedClass = val;
                  _selectedSection = null;
                  _selectedSubject = null;
                  _isCustomSubject = false;
                  final sects = _sections;
                  if (sects.isNotEmpty) {
                    _selectedSection = sects.contains(widget.teacher.section)
                        ? widget.teacher.section
                        : sects.first;
                    final subjs = _subjects;
                    if (subjs.isNotEmpty) _selectedSubject = subjs.first;
                  }
                });
              },
            ),
            const SizedBox(height: 16),

            // Subject Dropdown
            _label('Select Subject'),
            DropdownButtonFormField<String>(
              value: _isCustomSubject ? 'OTHER' : _selectedSubject,
              isExpanded: true,
              decoration: _inputDeco(enabled: _selectedClass != null),
              items: [
                ..._subjects.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                const DropdownMenuItem(value: 'OTHER', child: Text('Type custom subject...')),
              ],
              onChanged: _selectedClass == null ? null : (val) {
                setState(() {
                  if (val == 'OTHER') {
                    _isCustomSubject = true;
                  } else {
                    _isCustomSubject = false;
                    _selectedSubject = val;
                  }
                });
              },
            ),

            if (_isCustomSubject) ...[
              const SizedBox(height: 16),
              _label('Custom Subject'),
              TextField(
                controller: _customSubjectCtrl,
                autofocus: true,
                decoration: _inputDeco().copyWith(hintText: 'Enter subject name'),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('CANCEL', style: TextStyle(color: Colors.grey.shade600)),
        ),
        ElevatedButton(
          onPressed: _saving
              ? null
              : () {
                  if (!_canProceed) {
                    _showValidationError();
                    return;
                  }
                  final finalSubject = _isCustomSubject
                      ? _customSubjectCtrl.text.trim()
                      : _selectedSubject;

                  setState(() => _saving = true);
                  final check = CopyCheck(
                    id: '',
                    teacherId: widget.teacher.id,
                    teacherName: widget.teacher.name,
                    className: _selectedClass!,
                    section: _selectedSection!,
                    subject: finalSubject!,
                    checkDate: _date,
                    createdAt: DateTime.now(),
                  );
                  widget.onCreated(check);
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: _canProceed ? AppTheme.primary : Colors.grey.shade400,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('PROCEED'),
        ),
      ],
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
      );

  InputDecoration _inputDeco({bool enabled = true}) => InputDecoration(
        filled: true,
        fillColor: enabled ? Colors.white : Colors.grey.shade100,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
      );
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
              color: AppTheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.menu_book_outlined,
                color: AppTheme.primary, size: 22),
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
                Text('${c.className}${c.section.isNotEmpty ? " ${c.section}" : ""}',
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
      _studentService.getStudentsByClass(className: widget.check.className,
          section: widget.check.section),
      _service.getStatuses(widget.check.id),
    ]);
    final students = results[0] as List<Student>;
    final saved    = results[1] as List<CopyStatus>;

    assert(students.length == {for (final s in students) s.roll: s}.length,
        'Duplicate rolls detected in class ${widget.check.className}');

    // Build status list using live student name/phone; preserve saved status+remarks.
    final savedMap = {for (final s in saved) s.roll: s};
    final statuses = students.map((s) {
      final existing = savedMap[s.roll];
      return CopyStatus(
        roll:          s.roll,
        studentName:   s.name,        // always live from students/ collection
        guardianPhone: s.phone,       // always live from students/ collection
        status:        existing?.status  ?? 'not_done',
        remarks:       existing?.remarks,
      );
    }).toList();

    if (!mounted) return;
    setState(() {
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

  void _checkAll() {
    setState(() {
      _statuses = _statuses
          .map((s) => s.copyWith(status: 'checked'))
          .toList();
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
                  statuses:   _statuses,
                  onStatus:   _setStatus,
                  onSave:     _saveAll,
                  onCheckAll: _checkAll,
                  saving:     _saving,
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
  final VoidCallback onCheckAll;
  final bool saving;

  const _AllStudentsTab({
    required this.statuses,
    required this.onStatus,
    required this.onSave,
    required this.onCheckAll,
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
            children: [
              _SumChip(
                count: statuses.where((s) => s.status == 'not_done').length,
                label: 'Not Done',
                color: Colors.red,
              ),
              const SizedBox(width: 8),
              _SumChip(
                count: statuses
                    .where((s) => s.status == 'incomplete')
                    .length,
                label: 'Incomplete',
                color: Colors.orange,
              ),
              const SizedBox(width: 8),
              _SumChip(
                count: statuses.where((s) => s.status == 'checked').length,
                label: 'Checked',
                color: Colors.green,
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onCheckAll,
                icon: const Icon(Icons.check_circle_outline,
                    size: 16, color: Colors.green),
                label: const Text('All Check',
                    style: TextStyle(
                        color: Colors.green,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.green.shade50,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
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

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(children: [
            Container(width: 5, color: _color),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(status.studentName,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('ROLL ${status.roll}',
                          style: const TextStyle(
                              fontSize: 10, color: AppTheme.primaryDark, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
            ),
            // Status buttons
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(children: [
                _StatusBtn(
                  icon: Icons.cancel_outlined,
                  color: Colors.red,
                  active: status.status == 'not_done',
                  onTap: () => onStatus('not_done'),
                  tooltip: 'Not Done',
                ),
                _StatusBtn(
                  icon: Icons.warning_amber_rounded,
                  color: Colors.orange,
                  active: status.status == 'incomplete',
                  onTap: () => onStatus('incomplete'),
                  tooltip: 'Incomplete',
                ),
                _StatusBtn(
                  icon: Icons.check_circle_outline,
                  color: Colors.green,
                  active: status.status == 'checked',
                  onTap: () => onStatus('checked'),
                  tooltip: 'Checked',
                ),
              ]),
            ),
          ]),
        ),
      ),
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
                icon: const Icon(FontAwesomeIcons.whatsapp,
                    color: Colors.green, size: 20),
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

import 'dart:async';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/guardian_student_details.dart';
import '../models/student.dart';
import '../services/student_service.dart';
import '../services/timetable_service.dart';
import '../theme.dart';
import 'add_student_screen.dart';
import 'attendance_certificate_screen.dart';

/// Pre-defined reasons shown in the deletion-request dropdown.
const _kDeletionReasons = [
  'Transferred to another school',
  'Left school / Dropped out',
  'Relocated to another city',
  'Family reasons',
  'Admission cancelled',
  'Completed studies / Passed out',
  'Medical reasons',
  'Financial reasons',
  'Other (specify below)',
];

class StudentListScreen extends StatefulWidget {
  final String className;
  final String section;
  final bool isClassTeacher;
  /// When set, student queries are filtered to this teacher's records only.
  /// Pass the logged-in class teacher's ID; omit for coordinator/principal views.
  final String? teacherId;
  /// Teacher's display name — shown in the deletion request sent to the principal.
  final String teacherName;
  /// Teacher's email — used to identify the requestor in deletion requests.
  final String teacherEmail;
  const StudentListScreen({
    super.key,
    required this.className,
    this.section = '',
    this.isClassTeacher = false,
    this.teacherId,
    this.teacherName = '',
    this.teacherEmail = '',
  });

  @override
  State<StudentListScreen> createState() => _StudentListScreenState();
}

class _StudentListScreenState extends State<StudentListScreen> {
  final _service = StudentService();
  StreamSubscription<List<Student>>? _studentSub;
  List<Student> _students = [];
  bool _loading = true;

  Set<int> _selectedRolls = {};
  bool     _selectMode    = false;

  String get _effectiveTitle {
    if (widget.section.trim().isEmpty) return widget.className;
    return '${widget.className} — Section ${widget.section}';
  }

  @override
  void initState() {
    super.initState();
    _studentSub = _service
        .watchStudentsByClass(className: widget.className,
            section: widget.section, teacherId: widget.teacherId)
        .listen((list) {
      if (!mounted) return;
      setState(() {
        _students = list;
        _loading  = false;
      });
    });
  }

  @override
  void dispose() {
    _studentSub?.cancel();
    super.dispose();
  }

  // Pull-to-refresh is a no-op: the live stream already keeps data current.
  Future<void> _refresh() async {}

  void _enterSelectMode(Student s) {
    setState(() { _selectMode = true; _selectedRolls = {s.roll}; });
  }

  void _exitSelectMode() {
    setState(() { _selectMode = false; _selectedRolls = {}; });
  }

  void _toggleSelect(Student s) {
    setState(() {
      if (_selectedRolls.contains(s.roll)) {
        _selectedRolls.remove(s.roll);
        if (_selectedRolls.isEmpty) _selectMode = false;
      } else {
        _selectedRolls.add(s.roll);
      }
    });
  }

  bool get _allSelected =>
      _students.isNotEmpty &&
      _students.every((s) => _selectedRolls.contains(s.roll));

  void _toggleSelectAll() {
    setState(() {
      if (_allSelected) {
        _selectedRolls.removeAll(_students.map((s) => s.roll));
        if (_selectedRolls.isEmpty) _selectMode = false;
      } else {
        _selectedRolls.addAll(_students.map((s) => s.roll));
      }
    });
  }

  /// Instead of deleting directly, teachers must submit a deletion request
  /// that the principal must approve. Actual deletion happens on approval.
  Future<void> _deleteSelected() async {
    final count    = _selectedRolls.length;
    final toDelete = _students
        .where((s) => _selectedRolls.contains(s.roll))
        .toList();

    final reasonCtrl    = TextEditingController();
    String? dropReason;
    bool    showCustom  = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (_, setLocal) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.pending_actions_outlined, color: AppTheme.warning),
            SizedBox(width: 8),
            Text('Request Deletion', style: TextStyle(fontSize: 17)),
          ]),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You are requesting to delete $count '
                  'student${count == 1 ? '' : 's'}. The principal must '
                  'approve before records are permanently removed.',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 10),
                // Scrollable student list
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: toDelete.length,
                    itemBuilder: (_, i) {
                      final s = toDelete[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(children: [
                          Container(
                            width: 26, height: 26,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('${s.roll}',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(s.name,
                                style: const TextStyle(fontSize: 13)),
                          ),
                        ]),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                // Reason dropdown
                DropdownButtonFormField<String>(
                  value: dropReason,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Reason (optional)',
                    prefixIcon: const Icon(Icons.info_outline, size: 18),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  hint: const Text('Select a reason',
                      style: TextStyle(fontSize: 13)),
                  items: _kDeletionReasons
                      .map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 13))))
                      .toList(),
                  onChanged: (v) => setLocal(() {
                    dropReason = v;
                    showCustom = v == 'Other (specify below)';
                    if (!showCustom) reasonCtrl.clear();
                  }),
                ),
                if (showCustom) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: reasonCtrl,
                    maxLines: 2,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Specify reason',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.all(10),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(_, false),
                child: const Text('Cancel')),
            ElevatedButton.icon(
              icon: const Icon(Icons.send_outlined, size: 16, color: Colors.white),
              label: const Text('Send Request',
                  style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              onPressed: () {
                if (!showCustom) reasonCtrl.text = dropReason ?? '';
                Navigator.pop(_, true);
              },
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;

    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();

    await StudentService().submitDeletionRequest(
      teacherId:    widget.teacherId ?? '',
      teacherName:  widget.teacherName,
      teacherEmail: widget.teacherEmail,
      students: toDelete
          .map((s) => {
                'roll':          s.roll,
                'name':          s.name,
                'className':     s.className,
                'section':       s.section,
                'guardianEmail': s.guardianEmail ?? '',
              })
          .toList(),
      reason: reason,
    );

    if (!mounted) return;
    setState(() { _selectMode = false; _selectedRolls = {}; });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Deletion request sent for $count '
            'student${count == 1 ? '' : 's'}. Awaiting principal approval.'),
        backgroundColor: AppTheme.primary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }



  Future<void> _openAdd() async {
    await Navigator.push<Student>(
      context,
      MaterialPageRoute(
          builder: (_) => AddStudentScreen(
              className: widget.className,
              section: widget.section,
              teacherId: widget.teacherId)),
    );
    // Stream auto-refreshes after a student is added.
  }

  Future<void> _importCSV() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt'],
    );
    if (result == null || result.files.isEmpty || !mounted) return;

    final path = result.files.first.path;
    if (path == null) return;

    final content = await File(path).readAsString();
    List<List<dynamic>> rows;
    try {
      rows = const CsvToListConverter(eol: '\n').convert(content);
    } catch (_) {
      rows = const CsvToListConverter(eol: '\r\n').convert(content);
    }
    if (rows.isEmpty || !mounted) return;

    // Detect header row — first row with a non-numeric first cell
    int dataStart = 0;
    Map<String, int> colMap = {};
    final firstRow = rows[0].map((e) => e.toString().trim().toLowerCase()).toList();
    if (firstRow.any((c) => ['roll', 'name', 'student'].any((k) => c.contains(k)))) {
      dataStart = 1;
      final headers = ['roll', 'name', 'father', 'mother', 'phone', 'fee'];
      for (final h in headers) {
        final idx = firstRow.indexWhere((c) => c.contains(h));
        if (idx >= 0) colMap[h] = idx;
      }
    }

    // Build student list from CSV rows
    final students = <Student>[];
    for (int i = dataStart; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty) continue;

      String get(String key) {
        final idx = colMap[key];
        if (idx == null || idx >= row.length) return '';
        return row[idx].toString().trim();
      }

      // Try to find roll number — use column index 0 if no header mapping
      final rollStr = colMap.containsKey('roll')
          ? get('roll')
          : (row.isNotEmpty ? row[0].toString().trim() : '');
      final roll = int.tryParse(rollStr);
      if (roll == null || roll <= 0) continue;

      final name = colMap.containsKey('name')
          ? get('name')
          : (row.length > 1 ? row[1].toString().trim() : '');
      if (name.isEmpty) continue;

      students.add(Student(
        id: '', // Unique ID will be generated in addStudent
        roll: roll,
        name: name,
        className: widget.className,
        section: widget.section,
        fatherName: get('father'),
        motherName: get('mother').isNotEmpty ? get('mother') : null,
        phone: get('phone'),
        feeStatus: get('fee').isNotEmpty ? get('fee') : 'Pending',
        teacherId: widget.teacherId,
      ));
    }

    if (students.isEmpty || !mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No valid students found in CSV')));
      return;
    }

    // Preview dialog before import
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Import ${students.length} Students'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: students.length,
            itemBuilder: (_, i) {
              final s = students[i];
              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                  child: Text('${s.roll}',
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.primary)),
                ),
                title: Text(s.name,
                    style: const TextStyle(fontSize: 13)),
                subtitle: s.fatherName.isNotEmpty
                    ? Text('Father: ${s.fatherName}',
                        style: const TextStyle(fontSize: 11))
                    : null,
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(_, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(_, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    int added = 0, skipped = 0;
    for (final s in students) {
      final err = await _service.addStudent(student: s);
      if (err == null) {
        added++;
      } else {
        skipped++;
      }
    }
    if (!mounted) return;
    // Stream auto-refreshes after the import.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Imported $added students${skipped > 0 ? ', $skipped skipped (duplicate roll)' : ''}'),
      backgroundColor: Colors.green,
    ));
  }

  Future<void> _openDetail(Student student) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentDetailPage(
          student:      student,
          canEdit:      widget.isClassTeacher,
          teacherName:  widget.teacherName,
          teacherEmail: widget.teacherEmail,
          teacherId:    widget.teacherId,
        ),
      ),
    );
    // Stream auto-refreshes after edit or delete.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: _selectMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitSelectMode,
              )
            : null,
        title: _selectMode
            ? Text('${_selectedRolls.length} selected')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Student List',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold)),
                  Text(_effectiveTitle,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.white70)),
                ],
              ),
        actions: _selectMode
            ? [
                TextButton(
                  onPressed: _students.isNotEmpty ? _toggleSelectAll : null,
                  child: Text(
                    _allSelected ? 'None' : 'All',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete selected',
                  onPressed:
                      _selectedRolls.isNotEmpty ? _deleteSelected : null,
                ),
              ]
            : widget.isClassTeacher
                ? [
                    IconButton(
                      icon: const Icon(Icons.upload_file_outlined),
                      tooltip: 'Import from CSV',
                      onPressed: _importCSV,
                    ),
                  ]
                : null,
      ),
      floatingActionButton: !_selectMode && widget.isClassTeacher
          ? FloatingActionButton.extended(
              onPressed: _openAdd,
              backgroundColor: AppTheme.primary,
              icon: const Icon(Icons.person_add, color: Colors.white),
              label: const Text('Add Student',
                  style: TextStyle(color: Colors.white)),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _students.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.group_add,
                          size: 72, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('No students in $_effectiveTitle',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade400)),
                      const SizedBox(height: 6),
                      Text('Tap + Add Student to get started',
                          style: TextStyle(
                              color: Colors.grey.shade400)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _refresh,
                  color: AppTheme.primary,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 100),
                    itemCount: _students.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 80),
                    itemBuilder: (_, i) {
                      final s = _students[i];
                      return _StudentCard(
                        student: s,
                        selected: _selectedRolls.contains(s.roll),
                        selectMode: _selectMode,
                        onTap: _selectMode
                            ? () => _toggleSelect(s)
                            : () => _openDetail(s),
                        onLongPress: widget.isClassTeacher && !_selectMode
                            ? () => _enterSelectMode(s)
                            : null,
                      );
                    },
                  ),
                ),
    );
  }
}

// ── Student list card ──────────────────────────────────────────────────────────

class _StudentCard extends StatelessWidget {
  final Student       student;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool          selected;
  final bool          selectMode;
  const _StudentCard({
    required this.student,
    this.onTap,
    this.onLongPress,
    this.selected   = false,
    this.selectMode = false,
  });

  Color get _feeColor {
    switch (student.feeStatus) {
      case 'Paid':
        return Colors.green;
      case 'Partial':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                if (selectMode)
                  SizedBox(
                    width: 48,
                    child: Checkbox(
                      value: selected,
                      onChanged: (_) => onTap?.call(),
                      activeColor: AppTheme.primary,
                      shape: const CircleBorder(),
                    ),
                  )
                else
                  Hero(
                    tag: 'student_photo_${student.className}_${student.section}_${student.roll}',
                    child: Container(
                      width: 54, height: 54,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.1), width: 2),
                      ),
                      child: ClipOval(
                        child: student.photoUrl != null
                            ? CachedNetworkImage(
                                imageUrl: student.photoUrl!,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(color: Colors.grey.shade100),
                                errorWidget: (context, url, error) => Icon(Icons.person, color: Colors.grey.shade300),
                              )
                            : student.photoPath != null
                                ? Image.file(File(student.photoPath!), fit: BoxFit.cover)
                                : Container(
                                    color: Colors.grey.shade100,
                                    child: Icon(Icons.person, color: Colors.grey.shade300),
                                  ),
                      ),
                    ),
                  ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(student.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('ROLL ${student.roll}', 
                                style: const TextStyle(fontSize: 10, color: AppTheme.primaryDark, fontWeight: FontWeight.w800)),
                          ),
                          const SizedBox(width: 8),
                          Text(student.fatherName, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _feeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(student.feeStatus, 
                      style: TextStyle(fontSize: 10, color: _feeColor, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                if (!selectMode)
                  Icon(Icons.chevron_right, color: Colors.grey.shade300, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Student detail page ────────────────────────────────────────────────────────

class StudentDetailPage extends StatefulWidget {
  final Student student;
  final bool canEdit;
  final String teacherName;
  final String teacherEmail;
  final String? teacherId;
  const StudentDetailPage({super.key, 
    required this.student,
    this.canEdit = false,
    this.teacherName = '',
    this.teacherEmail = '',
    this.teacherId,
  });

  @override
  State<StudentDetailPage> createState() => _StudentDetailPageState();
}

class _StudentDetailPageState extends State<StudentDetailPage> {
  late Student _student;

  @override
  void initState() {
    super.initState();
    _student = widget.student;
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  Future<void> _edit() async {
    final updated = await Navigator.push<Student>(
      context,
      MaterialPageRoute(
        builder: (_) => AddStudentScreen(
            className: _student.className,
            section: _student.section,
            existing: _student),
      ),
    );
    if (updated != null) setState(() => _student = updated);
  }

  /// Submits a principal-approval request instead of deleting immediately.
  Future<void> _delete() async {
    final reasonCtrl   = TextEditingController();
    String? dropReason;
    bool    showCustom = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.pending_actions_outlined, color: AppTheme.warning),
          SizedBox(width: 8),
          Text('Request Deletion', style: TextStyle(fontSize: 17)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Removing ${_student.name} requires principal approval. '
              'A request will be sent and the record deleted once approved.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: dropReason,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Reason (optional)',
                prefixIcon: const Icon(Icons.info_outline, size: 18),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
              ),
              hint: const Text('Select a reason',
                  style: TextStyle(fontSize: 13)),
              items: _kDeletionReasons
                  .map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 13))))
                  .toList(),
              onChanged: (v) => setLocal(() {
                dropReason = v;
                showCustom = v == 'Other (specify below)';
                if (!showCustom) reasonCtrl.clear();
              }),
            ),
            if (showCustom) ...[
              const SizedBox(height: 8),
              TextField(
                controller: reasonCtrl,
                maxLines: 2,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Specify reason',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.all(10),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton.icon(
            icon: const Icon(Icons.send_outlined, size: 16,
                color: Colors.white),
            label: const Text('Send Request',
                style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            onPressed: () {
              if (!showCustom) reasonCtrl.text = dropReason ?? '';
              Navigator.pop(ctx, true);
            },
          ),
        ],
      ),
      ),
    );
    if (ok != true || !mounted) return;
    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();

    await StudentService().submitDeletionRequest(
      teacherId:    widget.teacherId ?? '',
      teacherName:  widget.teacherName,
      teacherEmail: widget.teacherEmail,
      students: [
        {
          'roll':          _student.roll,
          'name':          _student.name,
          'className':     _student.className,
          'section':       _student.section,
          'guardianEmail': _student.guardianEmail ?? '',
        }
      ],
      reason: reason,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text(
          'Deletion request sent. Awaiting principal approval.'),
      backgroundColor: AppTheme.primary,
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: 4),
    ));
    Navigator.pop(context);
  }

  Future<void> _call() async {
    if (_student.phone.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: _student.phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _whatsapp() async {
    if (_student.phone.isEmpty) return;
    final digits = _student.phone.replaceAll(RegExp(r'\D'), '');
    final uri = Uri.parse('https://wa.me/$digits');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  String _fmtDob(DateTime d) {
    const mo = ['Jan','Feb','Mar','Apr','May','Jun',
                 'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day.toString().padLeft(2,'0')} ${mo[d.month-1]} ${d.year}';
  }

  Future<void> _setGuardianEmail(BuildContext ctx) async {
    final ctrl = TextEditingController(text: _student.guardianEmail ?? '');
    String? savedEmail;

    await showDialog<void>(
      context: ctx,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Guardian Email'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter the guardian\'s email. A login password will be auto-generated.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.emailAddress,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Guardian email address',
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
              onPressed: () async {
                final email = ctrl.text.trim().toLowerCase();
                if (email.isEmpty || !email.contains('@')) return;
                await StudentService().setGuardianEmail(
                  _student.className, _student.roll, email,
                  section: _student.section,
                  studentName: _student.name,
                );
                try {
                  await TimetableService().provisionGuardianLoginAccess(
                    email:        email,
                    studentClass: _student.className,
                    studentRoll:  _student.roll,
                    studentName:  _student.name,
                  );
                } catch (_) {}
                savedEmail = email;
                if (dCtx.mounted) Navigator.pop(dCtx);
                savedEmail = email;
                if (dCtx.mounted) Navigator.pop(dCtx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();

    if (!mounted) return;
    if (savedEmail != null) {
      setState(() {
        _student = _student.copyWith(guardianEmail: savedEmail);
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Invite email sent to $savedEmail'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ));
    }
  }

  Future<void> _resendInvite() async {
    final email = _student.guardianEmail ?? '';
    if (email.isEmpty) return;
    try {
      await TimetableService().resendInvitationEmail(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Invite email resent to $email'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Failed to resend invite. Check internet connection.'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Copied to clipboard'),
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: 2),
    ));
  }

  Future<void> _shareGuardianAppInfo() async {
    final email = _student.guardianEmail ?? '';
    final msg   = Uri.encodeComponent(
      'Hello! Your child ${_student.name}\'s school portal is ready.\n'
      'Login email: $email\n'
      'Please check your email for a link to set up your password, then open the School App and sign in.',
    );
    final uri = Uri.parse('https://wa.me/?text=$msg');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Color get _feeColor {
    switch (_student.feeStatus) {
      case 'Paid':
        return Colors.green;
      case 'Partial':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  IconData get _feeIcon {
    switch (_student.feeStatus) {
      case 'Paid':
        return Icons.check_circle_outline;
      case 'Partial':
        return Icons.timelapse;
      default:
        return Icons.cancel_outlined;
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Student Profile'),
        actions: [
          if (widget.canEdit) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit',
              onPressed: _edit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remove',
              onPressed: _delete,
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.primaryDark, AppTheme.primaryMid],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              child: Column(children: [
                CircleAvatar(
                  radius: 54,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  backgroundImage: _student.photoUrl != null
                      ? NetworkImage(_student.photoUrl!)
                      : (_student.photoPath != null
                          ? FileImage(File(_student.photoPath!))
                          : null) as ImageProvider?,
                  child: (_student.photoUrl == null && _student.photoPath == null)
                      ? Text(
                          _student.name.isNotEmpty
                              ? _student.name[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                              fontSize: 42,
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                        )
                      : null,
                ),
                const SizedBox(height: 12),
                Text(
                  _student.name,
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _Chip('Roll ${_student.roll}'),
                  const SizedBox(width: 8),
                  _Chip(_student.className),
                  if (_student.section.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _Chip('Sec ${_student.section}'),
                  ],
                ]),
              ]),
            ),

            const SizedBox(height: 8),

            // ── Basic Info ───────────────────────────────────────────────────
            const _SectionHeader('BASIC INFO'),
            _InfoRow(Icons.person_outline, 'Name', _student.name),
            _InfoRow(Icons.cake_outlined, 'Date of Birth',
                _student.dateOfBirth != null
                    ? _fmtDob(_student.dateOfBirth!.toDate())
                    : '—'),
            _InfoRow(Icons.wc_outlined, 'Gender',
                _student.gender?.isNotEmpty == true ? _student.gender! : '—'),
            _InfoRow(Icons.school_outlined, 'Class / Section',
                '${_student.className} ${_student.section}'.trim()),
            _InfoRow(Icons.tag, 'Roll Number', '${_student.roll}'),
            const Divider(height: 1),

            // ── Family ──────────────────────────────────────────────────────
            const _SectionHeader('FAMILY'),
            _InfoRow(Icons.man_outlined, "Father's Name",
                _student.fatherName.isNotEmpty ? _student.fatherName : '—'),
            _InfoRow(Icons.woman_outlined, "Mother's Name",
                _student.motherName?.isNotEmpty == true ? _student.motherName! : '—'),
            const Divider(height: 1),

            // ── Contact ─────────────────────────────────────────────────────
            const _SectionHeader('CONTACT'),
            _InfoRow(Icons.phone_outlined, 'Primary Contact',
                _student.phone.isEmpty ? '—' : _student.phone),
            if (_student.phone.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(children: [
                  Expanded(
                    child: _ActionBtn(
                      icon: Icons.call,
                      label: 'Call',
                      color: Colors.green,
                      onTap: _call,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ActionBtn(
                      iconWidget: const FaIcon(
                        FontAwesomeIcons.whatsapp,
                        color: Color(0xFF25D366),
                        size: 24,
                      ),
                      label: 'WhatsApp',
                      color: const Color(0xFF25D366),
                      onTap: _whatsapp,
                    ),
                  ),
                ]),
              ),
            _InfoRow(Icons.phone_android_outlined, 'Secondary Contact',
                _student.parentPhone?.isNotEmpty == true ? _student.parentPhone! : '—'),
            _InfoRow(Icons.home_outlined, 'Address',
                _student.address?.isNotEmpty == true ? _student.address! : '—'),
            _InfoRow(Icons.contact_emergency_outlined, 'Emergency Contact',
                _student.emergencyContact?.isNotEmpty == true
                    ? _student.emergencyContact!
                    : '—'),
            const Divider(height: 1),

            // ── Academic & Medical ───────────────────────────────────────────
            const _SectionHeader('ACADEMIC & MEDICAL'),
            _InfoRow(Icons.account_balance_outlined, 'Previous School',
                _student.previousSchool?.isNotEmpty == true ? _student.previousSchool! : '—'),
            _InfoRow(Icons.bloodtype_outlined, 'Blood Group',
                _student.bloodGroup?.isNotEmpty == true ? _student.bloodGroup! : '—'),
            _InfoRow(Icons.medical_information_outlined, 'Allergies / Conditions',
                _student.allergies?.isNotEmpty == true ? _student.allergies! : '—'),
            _InfoRow(Icons.directions_bus_outlined, 'Transport Mode',
                _student.transportMode?.isNotEmpty == true ? _student.transportMode! : '—'),
            _InfoRow(Icons.photo_outlined, 'Photo Status',
                (_student.photoPath != null && _student.photoPath!.isNotEmpty) ||
                    (_student.photoUrl != null && _student.photoUrl!.isNotEmpty)
                    ? 'Uploaded'
                    : 'Not Uploaded'),
            const Divider(height: 1),

            // ── Fee Status ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _feeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _feeColor.withValues(alpha: 0.4)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_feeIcon, color: _feeColor, size: 18),
                  const SizedBox(width: 6),
                  Text(_student.feeStatus,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _feeColor,
                          fontSize: 14)),
                ]),
              ),
            ),
            const Divider(height: 1),

            // ── Documents ────────────────────────────────────────────────────
            const _SectionHeader('DOCUMENTS'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.workspace_premium_outlined),
                  label: const Text('Generate Attendance Certificate'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: const BorderSide(color: AppTheme.primary),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AttendanceCertificateScreen(student: _student),
                    ),
                  ),
                ),
              ),
            ),

            // ── Guardian Portal Access ─────────────────────────────────────
            const _SectionHeader('GUARDIAN PORTAL ACCESS'),
            if (_student.guardianEmail == null || _student.guardianEmail!.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.people_outlined),
                  label: const Text('Set Guardian Email'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: const BorderSide(color: AppTheme.primary),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => _setGuardianEmail(context),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Email row
                      Row(children: [
                        const Icon(Icons.email_outlined, size: 16, color: AppTheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _student.guardianEmail!,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _setGuardianEmail(context),
                          child: const Icon(Icons.edit_outlined,
                              size: 16, color: AppTheme.primary),
                        ),
                        GestureDetector(
                          onTap: () => _copyToClipboard(_student.guardianEmail!),
                          child: const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Icon(Icons.copy_outlined,
                                size: 16, color: AppTheme.primary),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      Text(
                        'Guardian can sign in with this email. They set their own password via the invite email.',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 10),
                      // Resend invite + WhatsApp row
                      Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.send_outlined, size: 15),
                            label: const Text('Resend Invite', style: TextStyle(fontSize: 13)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.primary,
                              side: const BorderSide(color: AppTheme.primary),
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: _resendInvite,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const FaIcon(FontAwesomeIcons.whatsapp,
                                size: 15, color: Color(0xFF25D366)),
                            label: const Text('WhatsApp', style: TextStyle(fontSize: 13)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF25D366).withValues(alpha: 0.1),
                              foregroundColor: const Color(0xFF128C7E),
                              elevation: 0,
                              side: const BorderSide(color: Color(0xFF25D366)),
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: _shareGuardianAppInfo,
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),

            // ── Details provided by guardian ─────────────────────────
            if (_student.guardianDetails != null)
              _GuardianDetailsSection(details: _student.guardianDetails!),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ── Reusable sub-widgets ───────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Text(title,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade500,
              letterSpacing: 0.8)),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(this.icon, this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Icon(icon, size: 20, color: Colors.grey.shade400),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w500)),
              ]),
        ),
      ]),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData? icon;
  final Widget?   iconWidget;
  final String    label;
  final Color     color;
  final VoidCallback onTap;
  const _ActionBtn({
    this.icon,
    this.iconWidget,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(children: [
          iconWidget ?? Icon(icon, color: color, size: 26),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ]),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  const _Chip(this.text);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: const TextStyle(fontSize: 13, color: Colors.white)),
    );
  }
}

// ── Details Provided by Guardian section ──────────────────────────────────────

class _GuardianDetailsSection extends StatelessWidget {
  final GuardianStudentDetails details;
  const _GuardianDetailsSection({required this.details});

  @override
  Widget build(BuildContext context) {
    final d = details;

    // Build list of non-empty rows
    final rows = <_GRow>[
      if (d.dob.isNotEmpty)
        _GRow(Icons.cake_outlined, 'Date of Birth', d.dob),
      if (d.gender.isNotEmpty)
        _GRow(Icons.wc_outlined, 'Gender', d.gender),
      if (d.address.isNotEmpty)
        _GRow(Icons.home_outlined, 'Address', d.address),
      if (d.bloodGroup.isNotEmpty)
        _GRow(Icons.bloodtype_outlined, 'Blood Group', d.bloodGroup),
      if (d.emergencyContactName.isNotEmpty)
        _GRow(Icons.contact_phone_outlined, 'Emergency Contact',
            d.emergencyContactPhone.isNotEmpty
                ? '${d.emergencyContactName}  ·  ${d.emergencyContactPhone}'
                : d.emergencyContactName),
      if (d.allergies.isNotEmpty)
        _GRow(Icons.medical_services_outlined, 'Allergies / Conditions',
            d.allergies),
      if (d.transportMode.isNotEmpty)
        _GRow(Icons.directions_bus_outlined, 'Transport Mode',
            d.transportMode),
      if (d.previousSchool.isNotEmpty)
        _GRow(Icons.school_outlined, 'Previous School', d.previousSchool),
    ];

    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        // Section header styled like the others
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Row(children: [
            Text(
              'DETAILS PROVIDED BY GUARDIAN',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade500,
                  letterSpacing: 0.8),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('Guardian supplied',
                  style: TextStyle(
                      fontSize: 9,
                      color: AppTheme.primary,
                      fontWeight: FontWeight.bold)),
            ),
          ]),
        ),
        ...rows.map((r) => _InfoRow(r.icon, r.label, r.value)),
        if (d.lastUpdated != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
            child: Text(
              'Last updated by guardian: ${d.lastUpdated!.split('T')[0]}',
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade400,
                  fontStyle: FontStyle.italic),
            ),
          )
        else
          const SizedBox(height: 8),
      ],
    );
  }
}

class _GRow {
  final IconData icon;
  final String   label;
  final String   value;
  const _GRow(this.icon, this.label, this.value);
}

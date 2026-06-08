import 'dart:async';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/guardian_student_details.dart';
import '../models/guardian_provided_details.dart';
import '../models/student.dart';
import '../services/student_service.dart';
import '../services/timetable_service.dart';
import '../utils/phone_utils.dart';
import '../utils/csv_export.dart';
import '../utils/consent_gate.dart';
import '../services/consent_service.dart';
import '../widgets/consent_pending_banner.dart';
import '../theme.dart';
import '../utils/app_logger.dart';
import '../utils/validators.dart';
import '../widgets/email_text_form_field.dart';
import 'add_student_screen.dart';
import 'attendance_certificate_screen.dart';
import '../widgets/refreshable_data.dart';

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

  // Consent visibility (#17): which students have active parental consent, so
  // staff can see at a glance who is missing it. Loaded once per roster refresh
  // via the batch API; until loaded, no badge is shown (avoids a flash).
  Set<String> _consentedIds = {};
  bool _consentLoaded = false;

  Future<void> _loadConsent(List<Student> students) async {
    if (students.isEmpty) {
      if (mounted) setState(() { _consentedIds = {}; _consentLoaded = true; });
      return;
    }
    final ids = students
        .map((s) => Student.buildDocId(s.roll, s.className, s.section))
        .toList();
    try {
      final consented = await ConsentService().filterHasActiveConsent(ids);
      if (mounted) {
        setState(() { _consentedIds = consented; _consentLoaded = true; });
      }
    } catch (_) {/* visibility only — never block the roster */}
  }

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
      _loadConsent(list); // consent visibility (#17)
    });
  }

  @override
  void dispose() {
    _studentSub?.cancel();
    super.dispose();
  }

  // Pull-to-refresh is a no-op: the live stream already keeps data current.
  Future<void> _refresh() async {}

  /// Students that can still be selected for deletion (not already pending).
  List<Student> get _selectableStudents =>
      _students.where((s) => !s.deletionPending).toList();

  void _enterSelectMode(Student s) {
    if (s.deletionPending) return; // already awaiting approval
    setState(() { _selectMode = true; _selectedRolls = {s.roll}; });
  }

  void _exitSelectMode() {
    setState(() { _selectMode = false; _selectedRolls = {}; });
  }

  void _toggleSelect(Student s) {
    if (s.deletionPending) return; // can't re-request a pending student
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
      _selectableStudents.isNotEmpty &&
      _selectableStudents.every((s) => _selectedRolls.contains(s.roll));

  void _toggleSelectAll() {
    final selectable = _selectableStudents.map((s) => s.roll);
    setState(() {
      if (_allSelected) {
        _selectedRolls.removeAll(selectable);
        if (_selectedRolls.isEmpty) _selectMode = false;
      } else {
        _selectedRolls.addAll(selectable);
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
    // Dispose after the dialog's close animation finishes. Disposing the
    // controller synchronously while its TextField is still unmounting trips
    // framework.dart's `_dependents.isEmpty` assertion (red error screen).
    // Scheduled before the early-return so Cancel doesn't leak it either.
    Future.delayed(const Duration(milliseconds: 350), reasonCtrl.dispose);

    if (ok != true || !mounted) return;

    final reason = reasonCtrl.text.trim();

    final studentMaps = toDelete
        .map((s) => {
              'roll':          s.roll,
              'name':          s.name,
              'className':     s.className,
              'section':       s.section,
              'guardianEmail': s.guardianEmail ?? '',
            })
        .toList();

    await StudentService().submitDeletionRequest(
      teacherId:    widget.teacherId ?? '',
      teacherName:  widget.teacherName,
      teacherEmail: widget.teacherEmail,
      students:     studentMaps,
      reason:       reason,
    );
    // Flag the records as deactivated until the principal acts. The live stream
    // re-renders them greyed-out.
    await StudentService().markStudentsDeletionPending(studentMaps, true);

    if (!mounted) return;
    setState(() { _selectMode = false; _selectedRolls = {}; });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Deletion request sent for ${_namesLabel(toDelete)}. '
            'Awaiting principal approval.'),
        backgroundColor: AppTheme.primary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Comma-separated student names for the confirmation message, capped so a
  /// bulk request (e.g. 50 students) stays readable: "A, B, C +47 more".
  String _namesLabel(List<Student> list) {
    final names = list.map((s) => s.name).toList();
    if (names.length <= 3) return names.join(', ');
    return '${names.take(3).join(', ')} +${names.length - 3} more';
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

  /// Exports the current roster to a CSV and opens the share sheet (#71).
  Future<void> _exportCSV() async {
    final students = [..._students]..sort((a, b) => a.roll.compareTo(b.roll));
    if (students.isEmpty) return;
    final rows = <List<dynamic>>[
      ['Roll', 'Name', 'Father', 'Mother', 'Phone', 'Guardian Email', 'Section', 'Fee Status'],
      for (final s in students)
        [
          s.roll,
          s.name,
          s.fatherName,
          s.motherName ?? '',
          s.phone,
          s.guardianEmail ?? '',
          s.section,
          s.feeStatus,
        ],
    ];
    final cls = widget.className.replaceAll(' ', '_');
    final sec = widget.section.trim().isEmpty ? '' : '_${widget.section.trim()}';
    try {
      await CsvExport.share(
        filename: 'students_$cls$sec.csv',
        rows: rows,
        shareText: '${widget.className} student list (${students.length})',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')));
    }
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
      final headers = ['roll', 'name', 'father', 'mother', 'phone', 'email', 'fee'];
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
        guardianEmail: get('email').isNotEmpty ? get('email').toLowerCase() : null,
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
            : [
                if (_students.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.download_outlined),
                    tooltip: 'Export to CSV',
                    onPressed: _exportCSV,
                  ),
                if (widget.isClassTeacher)
                  IconButton(
                    icon: const Icon(Icons.upload_file_outlined),
                    tooltip: 'Import from CSV',
                    onPressed: _importCSV,
                  ),
              ],
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
          ? const LoadingState()
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
                        pendingDeletion: s.deletionPending,
                        // No badge until consent has loaded (avoids a flash).
                        hasConsent: !_consentLoaded ||
                            _consentedIds.contains(Student.buildDocId(
                                s.roll, s.className, s.section)),
                        // In select mode a pending student can still be tapped
                        // to view detail (but not toggled); otherwise normal tap
                        // opens detail.
                        onTap: _selectMode
                            ? (s.deletionPending
                                ? () => _openDetail(s)
                                : () => _toggleSelect(s))
                            : () => _openDetail(s),
                        onLongPress: widget.isClassTeacher &&
                                !_selectMode &&
                                !s.deletionPending
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
  final bool          pendingDeletion;
  final bool          hasConsent;
  const _StudentCard({
    required this.student,
    this.onTap,
    this.onLongPress,
    this.selected        = false,
    this.selectMode      = false,
    this.pendingDeletion = false,
    this.hasConsent      = true,
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
        color: pendingDeletion ? const Color(0xFFF1EEF4) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: pendingDeletion
            ? Border.all(color: AppTheme.warning.withValues(alpha: 0.4))
            : null,
        boxShadow: pendingDeletion
            ? null
            : [
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
                      Row(
                        children: [
                          Flexible(
                            child: Text(student.name,
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: pendingDeletion
                                        ? Colors.grey.shade500
                                        : null)),
                          ),
                          // Consent-missing badge (#17) — self-hides when consent
                          // is present.
                          const SizedBox(width: 6),
                          ConsentMissingBadge(hasConsent: hasConsent),
                        ],
                      ),
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
                      if (pendingDeletion) ...[
                        const SizedBox(height: 4),
                        const Text('Deletion requested — awaiting approval',
                            style: TextStyle(
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                                color: AppTheme.warning)),
                      ],
                    ],
                  ),
                ),
                if (pendingDeletion)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.hourglass_top, size: 11, color: AppTheme.warning),
                      SizedBox(width: 3),
                      Text('Deactivated',
                          style: TextStyle(fontSize: 10, color: AppTheme.warning, fontWeight: FontWeight.bold)),
                    ]),
                  )
                else
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
    // Dispose after the dialog's close animation finishes (see _deleteSelected)
    // — synchronous disposal mid-teardown trips the `_dependents.isEmpty`
    // assertion; scheduling before the early-return also avoids a Cancel leak.
    Future.delayed(const Duration(milliseconds: 350), reasonCtrl.dispose);

    if (ok != true || !mounted) return;
    final reason = reasonCtrl.text.trim();

    final studentMaps = [
      {
        'roll':          _student.roll,
        'name':          _student.name,
        'className':     _student.className,
        'section':       _student.section,
        'guardianEmail': _student.guardianEmail ?? '',
      }
    ];

    await StudentService().submitDeletionRequest(
      teacherId:    widget.teacherId ?? '',
      teacherName:  widget.teacherName,
      teacherEmail: widget.teacherEmail,
      students:     studentMaps,
      reason:       reason,
    );
    await StudentService().markStudentsDeletionPending(studentMaps, true);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          'Deletion request sent for ${_student.name}. '
          'Awaiting principal approval.'),
      backgroundColor: AppTheme.primary,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
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
    // Consent gate (#108): WhatsApp sends the child's data to a third party.
    if (!await ConsentGate.allowsThirdPartyShare(context,
        roll: _student.roll,
        className: _student.className,
        section: _student.section)) {
      return;
    }
    final digits = PhoneUtils.whatsAppNumber(_student.phone);
    if (digits.isEmpty) return;
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
    String? emailErr;
    bool    inviteSent  = false;
    Object? inviteError;

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
              EmailTextFormField(
                controller: ctrl,
                decoration: InputDecoration(
                  labelText: 'Guardian email address',
                  errorText: emailErr,
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
                if (!Validators.isValidEmail(email)) {
                  setS(() => emailErr = 'Enter a valid email address');
                  return;
                }
                setS(() => emailErr = null);
                // Persist the email on the student record + provision the
                // guardian's allowed_users / Firebase Auth account.
                await StudentService().setGuardianEmail(
                  _student.className, _student.roll, email,
                  section: _student.section,
                  studentName: _student.name,
                );
                savedEmail = email;
                // Actually send the password-setup / invite email and capture
                // the real result — do NOT assume success.
                try {
                  await TimetableService().resendInvitationEmail(email);
                  inviteSent = true;
                } catch (e) {
                  inviteError = e;
                }
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
      if (inviteSent) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Invite email sent to $savedEmail'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Guardian saved, but the invite email to $savedEmail could not '
              'be sent. Use "Resend Invite" to try again.'),
          backgroundColor: AppTheme.warning,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 8),
        ));
        AppLogger.e('StudentList',
            'Guardian invite send failed for $savedEmail: $inviteError',
            inviteError);
      }
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

  Timestamp? _parseDob(String dob) {
    try {
      final parts = dob.split('/');
      if (parts.length == 3) {
        final day = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final year = int.parse(parts[2]);
        return Timestamp.fromDate(DateTime(year, month, day));
      }
    } catch (_) {}
    return null;
  }

  Future<void> _acceptGuardianDetails(GuardianProvidedDetails details) async {
    try {
      final newDetails = GuardianStudentDetails(
        dob: details.dob,
        gender: details.gender,
        address: details.address,
        bloodGroup: details.bloodGroup,
        emergencyContactName: details.emergencyContactName,
        emergencyContactPhone: details.emergencyContactPhone,
        allergies: details.allergies,
        transportMode: details.transportMode,
        previousSchool: details.previousSchool,
        lastUpdated: DateTime.now().toIso8601String(),
      );

      final updatedStudent = _student.copyWith(
        name: details.name,
        fatherName: details.fatherName,
        motherName: details.motherName,
        phone: details.phone,
        parentPhone: details.parentPhone,
        guardianDetails: newDetails,
        dateOfBirth: _parseDob(details.dob),
        gender: details.gender,
        address: details.address,
        previousSchool: details.previousSchool,
        bloodGroup: details.bloodGroup,
        allergies: details.allergies,
        transportMode: details.transportMode,
        emergencyContact: details.emergencyContactName.isNotEmpty || details.emergencyContactPhone.isNotEmpty
            ? '${details.emergencyContactName} (${details.emergencyContactPhone})'
            : null,
      );

      await StudentService().updateStudent(updated: updatedStudent);
      await StudentService().updateGuardianProvidedDetailsStatus(_student.id, details.id, 'accepted');

      setState(() {
        _student = updatedStudent;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Guardian updates accepted and applied')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to accept updates: $e')),
      );
    }
  }

  Future<void> _requestGuardianClarification(GuardianProvidedDetails details) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Request Clarification'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter why clarification is needed...',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Submit'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      try {
        await StudentService().updateGuardianProvidedDetailsStatus(
          _student.id,
          details.id,
          'clarification_requested',
          remarks: result,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Clarification request sent to guardian')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to request clarification: $e')),
        );
      }
    }
  }

  Widget _buildGuardianDetailsSection(GuardianProvidedDetails details) {
    final diffs = <String, List<String>>{};

    void compare(String fieldName, String currentValue, String newValue) {
      if (newValue.trim().isNotEmpty && currentValue.trim() != newValue.trim()) {
        diffs[fieldName] = [currentValue, newValue];
      }
    }

    final s = _student;
    final d = s.guardianDetails;

    compare('Full Name', s.name, details.name);
    compare('Date of Birth', d?.dob ?? '', details.dob);
    compare('Gender', d?.gender ?? '', details.gender);
    compare("Father's Name", s.fatherName, details.fatherName);
    compare("Mother's Name", s.motherName ?? '', details.motherName);
    compare('Primary Phone', s.phone, details.phone);
    compare('Secondary Phone', s.parentPhone ?? '', details.parentPhone);
    compare('Address', d?.address ?? '', details.address);
    compare('Previous School', d?.previousSchool ?? '', details.previousSchool);
    compare('Blood Group', d?.bloodGroup ?? '', details.bloodGroup);
    compare('Emergency Contact Name', d?.emergencyContactName ?? '', details.emergencyContactName);
    compare('Emergency Contact Phone', d?.emergencyContactPhone ?? '', details.emergencyContactPhone);
    compare('Allergies', d?.allergies ?? '', details.allergies);
    compare('Transport Mode', d?.transportMode ?? '', details.transportMode);

    if (diffs.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade800),
                const SizedBox(width: 8),
                Text(
                  'Details provided by guardian',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...diffs.entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(color: Colors.black87, fontSize: 14),
                    children: [
                      TextSpan(
                        text: '${entry.key}: ',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(
                        text: entry.value[0].isEmpty ? '[Empty]' : entry.value[0],
                        style: const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.red),
                      ),
                      const TextSpan(text: '  ➔  '),
                      TextSpan(
                        text: entry.value[1],
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade700),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
            if (details.remarks.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Remarks: ${details.remarks}',
                style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.black54),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _requestGuardianClarification(details),
                  child: Text(
                    'Request Clarification',
                    style: TextStyle(color: Colors.blue.shade900),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _acceptGuardianDetails(details),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade800,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Accept Changes'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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
      body: StreamBuilder<List<GuardianProvidedDetails>>(
        stream: StudentService().watchGuardianProvidedDetails(_student.id),
        builder: (context, snapshot) {
          final list = snapshot.data ?? [];
          final pendingGuardianDetails = list.firstWhere(
            (d) => d.status == 'pending',
            orElse: () => const GuardianProvidedDetails(id: ''),
          );

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──────────────────────────────────────────────────────
            Container(
              decoration: const BoxDecoration(
                color: AppTheme.primaryDark,
              ),
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              child: Column(children: [
                CircleAvatar(
                  radius: 54,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  backgroundImage: _student.photoUrl != null
                      ? CachedNetworkImageProvider(_student.photoUrl!)
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

            if (pendingGuardianDetails.id.isNotEmpty)
              _buildGuardianDetailsSection(pendingGuardianDetails),

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
                child: SizedBox(
                  width: double.infinity,
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
      );
    },
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

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryDark, letterSpacing: 0.5),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onLongPress: value != '—' ? () {
        Clipboard.setData(ClipboardData(text: value));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Copied to clipboard'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ));
      } : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: Colors.grey.shade400),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                  const SizedBox(height: 2),
                  Text(value, style: const TextStyle(fontSize: 14)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData? icon;
  final Widget?   iconWidget;
  final String    label;
  final Color     color;
  final VoidCallback? onTap;
  const _ActionBtn({
    this.icon,
    this.iconWidget,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.5)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      onPressed: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (iconWidget != null) iconWidget! else Icon(icon, size: 20),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
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

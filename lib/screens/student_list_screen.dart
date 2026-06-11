import 'dart:async';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/school_settings_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../utils/pdf_theme.dart';
import '../services/auth_service.dart';
import '../l10n/app_strings.dart';
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
import 'consent/parental_consent_flow.dart';
import '../models/parental_consent.dart';

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

/// Localised display label for a deletion reason. Stored values stay English
/// (they're sent to the principal), so only the display is translated.
String _localizedReason(BuildContext context, String reason) {
  const keys = {
    'Transferred to another school':   'reasonTransferred',
    'Left school / Dropped out':       'reasonLeftSchool',
    'Relocated to another city':       'reasonRelocated',
    'Family reasons':                  'reasonFamily',
    'Admission cancelled':             'reasonAdmissionCancelled',
    'Completed studies / Passed out':  'reasonCompleted',
    'Medical reasons':                 'reasonMedical',
    'Financial reasons':               'reasonFinancial',
    'Other (specify below)':           'reasonOtherSpecify',
  };
  final key = keys[reason];
  return key == null ? reason : context.tr(key);
}

/// Localised display label for a stored fee-status value (kept English on disk).
String _localizedFeeStatus(BuildContext context, String status) {
  switch (status) {
    case 'Paid':    return context.tr('paidLabel');
    case 'Partial': return context.tr('partialLabel');
    case 'Pending': return context.tr('statusPending');
    default:        return status;
  }
}

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
  final _service = StudentService.instance;
  final _scrollController = ScrollController();
  List<Student> _students = [];
  bool _loading = true;
  bool _isPrincipal = false;

  // Pagination state
  static const _pageSize = 30;
  dynamic _cursor;
  bool _hasMore = true;
  bool _loadingMore = false;

  Future<void> _loadUserRole() async {
    final session = await AuthService().getSession();
    if (session != null && mounted) {
      setState(() {
        _isPrincipal = session['role'] == 'principal';
      });
    }
  }

  // Consent visibility (#17): which students have active parental consent, so
  // staff can see at a glance who is missing it. Loaded once per roster refresh
  // via the batch API; until loaded, no badge is shown (avoids a flash).
  final Set<String> _consentedIds = {};
  bool _consentLoaded = false;

  Future<void> _loadConsent(List<Student> students) async {
    if (students.isEmpty) {
      if (mounted) setState(() { _consentLoaded = true; });
      return;
    }
    final ids = students
        .map((s) => Student.buildDocId(s.roll, s.className, s.section))
        .toList();
    try {
      final consented = await ConsentService().filterHasActiveConsent(ids);
      if (mounted) {
        setState(() {
          _consentedIds.addAll(consented);
          _consentLoaded = true;
        });
      }
    } catch (_) {/* visibility only — never block the roster */}
  }

  Set<int> _selectedRolls = {};
  bool     _selectMode    = false;

  String get _effectiveTitle {
    if (widget.section.trim().isEmpty) return widget.className;
    return '${widget.className} — ${context.tr('sectionWord')} ${widget.section}';
  }

  Future<void> _fetchPage({bool reset = false}) async {
    if (_loadingMore || (!reset && !_hasMore)) return;
    if (mounted) {
      setState(() {
        _loadingMore = true;
        if (reset) {
          _loading = true;
        }
      });
    }

    try {
      final page = await _service.getStudentsByClassPaginated(
        className: widget.className,
        section: widget.section,
        teacherId: null,
        limit: _pageSize,
        startAfter: reset ? null : _cursor,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _students = page.entries;
          _consentedIds.clear();
        } else {
          _students.addAll(page.entries);
        }
        _cursor = page.cursor;
        _hasMore = page.entries.length >= _pageSize;
        _loading = false;
        _loadingMore = false;
      });
      _loadConsent(page.entries);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.tr('loadErrorPrefix')} $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _fetchPage();
    }
  }

  @override
  void initState() {
    super.initState();
    _loadUserRole();
    _scrollController.addListener(_onScroll);
    _fetchPage(reset: true);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    await _fetchPage(reset: true);
  }

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
          title: Row(children: [
            const Icon(Icons.pending_actions_outlined, color: AppTheme.warning),
            const SizedBox(width: 8),
            Text(context.tr('requestDeletion'), style: const TextStyle(fontSize: 17)),
          ]),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${context.tr('requestingToDelete')} $count '
                  '${context.tr('studentsWord')}. ${context.tr('principalMustApprove')}',
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
                    labelText: context.tr('reasonLabel'),
                    prefixIcon: const Icon(Icons.info_outline, size: 18),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  hint: Text(context.tr('selectReason'),
                      style: const TextStyle(fontSize: 13)),
                  items: _kDeletionReasons
                      .map((r) => DropdownMenuItem(value: r, child: Text(_localizedReason(context, r), style: const TextStyle(fontSize: 13))))
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
                      labelText: context.tr('specifyReason'),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.all(10),
                    ),
                    onChanged: (v) => setLocal(() {}),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(_, false),
                child: Text(context.tr('cancel'))),
            ElevatedButton.icon(
              icon: const Icon(Icons.send_outlined, size: 16, color: Colors.white),
              label: Text(context.tr('sendRequest'),
                  style: const TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              onPressed: (dropReason == null || (dropReason == 'Other (specify below)' && reasonCtrl.text.trim().isEmpty))
                  ? null
                  : () {
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

    await StudentService.instance.submitDeletionRequest(
      teacherId:    widget.teacherId ?? '',
      teacherName:  widget.teacherName,
      teacherEmail: widget.teacherEmail,
      students:     studentMaps,
      reason:       reason,
    );
    // Flag the records as deactivated until the principal acts. The live stream
    // re-renders them greyed-out.
    await StudentService.instance.markStudentsDeletionPending(studentMaps, true);

    if (!mounted) return;
    setState(() { _selectMode = false; _selectedRolls = {}; });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            '${context.tr('deletionRequestSentFor')} ${_namesLabel(toDelete)}. '
            '${context.tr('awaitingPrincipalApproval')}'),
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
    return '${names.take(3).join(', ')} +${names.length - 3} ${context.tr('moreWord')}';
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
    // Refresh the roster after adding a student.
    await _fetchPage(reset: true);
  }

  /// Exports the current roster to a CSV and opens the share sheet (#71).
  Future<void> _exportCSV() async {
    final students = [..._students]..sort((a, b) => a.roll.compareTo(b.roll));
    if (students.isEmpty) return;
    final rows = <List<dynamic>>[
      ['Roll', 'Name', 'Father', 'Mother', 'Phone', 'Guardian Email', 'Section', 'Fee Status'],
      for (final s in students)
        (() {
          final hasConsent = _consentedIds.contains(Student.buildDocId(s.roll, s.className, s.section));
          return [
            s.roll,
            s.name,
            hasConsent ? s.fatherName : '[Consent Missing]',
            hasConsent ? (s.motherName ?? '') : '[Consent Missing]',
            hasConsent ? s.phone : '[Consent Missing]',
            hasConsent ? (s.guardianEmail ?? '') : '[Consent Missing]',
            s.section,
            hasConsent ? s.feeStatus : '[Consent Missing]',
          ];
        }())
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
          SnackBar(content: Text('${context.tr('exportFailed')} $e')));
    }
  }

  Future<void> _exportPDF() async {
    final students = [..._students]..sort((a, b) => a.roll.compareTo(b.roll));
    if (students.isEmpty) return;

    final doc = pw.Document();
    final now = DateTime.now();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Student List Report',
                style: pw.TextStyle(
                    fontSize: 20, fontWeight: pw.FontWeight.bold,
                    color: PdfTheme.primary)),
            pw.SizedBox(height: 4),
            pw.Text(
              'Class: ${widget.className}   |   Section: ${widget.section.isEmpty ? 'N/A' : widget.section}   |   '
              'Total Students: ${students.length}   |   '
              'Date: ${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.Divider(color: PdfTheme.primary, thickness: 1),
            pw.SizedBox(height: 8),
          ],
        ),
        footer: (context) => pw.Column(
          children: [
            pw.Divider(color: PdfColors.grey300, thickness: 0.5),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'School Management System  •  Confidential',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
                ),
                pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
                ),
              ],
            ),
          ],
        ),
        build: (_) => [
          pw.Table(
            border: pw.TableBorder.all(
                color: PdfTheme.primaryLight, width: 0.5),
            columnWidths: {
              0: const pw.FixedColumnWidth(40),  // Roll
              1: const pw.FlexColumnWidth(3),    // Name
              2: const pw.FlexColumnWidth(2.5),  // Father's Name
              3: const pw.FixedColumnWidth(90),  // Phone
              4: const pw.FixedColumnWidth(70),  // Fee Status
            },
            children: [
              // Header
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfTheme.primaryTint),
                children: [
                  'Roll',
                  'Student Name',
                  "Father's Name",
                  'Phone',
                  'Fee Status'
                ].map((h) => pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  child: pw.Text(
                    h,
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 9,
                      color: PdfTheme.primaryDark,
                    ),
                  ),
                )).toList(),
              ),
              // Rows
              ...students.map((s) {
                final hasConsent = _consentedIds.contains(Student.buildDocId(s.roll, s.className, s.section));
                return pw.TableRow(
                  children: [
                    s.roll.toString(),
                    s.name,
                    hasConsent ? s.fatherName : '[Consent Missing]',
                    hasConsent ? s.phone : '[Consent Missing]',
                    hasConsent ? s.feeStatus : '[Consent Missing]',
                  ].map((cell) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                    child: pw.Text(
                      cell,
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  )).toList(),
                );
              }),
            ],
          ),
        ],
      ),
    );

    final cls = widget.className.replaceAll(' ', '_');
    final sec = widget.section.trim().isEmpty ? '' : '_${widget.section.trim()}';
    try {
      await Printing.sharePdf(
        bytes: await doc.save(),
        filename: 'students_$cls$sec.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.tr('exportFailed')} $e')));
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
          SnackBar(content: Text(context.tr('noValidStudentsCsv'))));
      return;
    }

    // Preview dialog before import
    final dialogResult = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (_) {
        bool assertConsent = false;
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text('${context.tr('importStudentsTitlePrefix')} ${students.length} ${context.tr('studentsWord')}'),
              content: SizedBox(
                width: double.maxFinite,
                height: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Expanded(
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
                                ? Text('${context.tr('fatherColon')} ${s.fatherName}',
                                    style: const TextStyle(fontSize: 11))
                                : null,
                          );
                        },
                      ),
                    ),
                    const Divider(),
                    CheckboxListTile(
                      title: const Text(
                        'Assert physical parental consent is on record',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text(
                        'Confirm that signed physical consent forms are collected for these students in compliance with DPDP.',
                        style: TextStyle(fontSize: 10),
                      ),
                      value: assertConsent,
                      onChanged: (val) {
                        setStateDialog(() {
                          assertConsent = val ?? false;
                        });
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(_, null),
                    child: Text(context.tr('cancel'))),
                ElevatedButton(
                  onPressed: () => Navigator.pop(_, {'import': true, 'assertConsent': assertConsent}),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white),
                  child: Text(context.tr('importLabel')),
                ),
              ],
            );
          }
        );
      }
    );
    if (dialogResult == null || dialogResult['import'] != true || !mounted) return;
    final bool assertConsent = dialogResult['assertConsent'] ?? false;

    int added = 0, skipped = 0;
    for (final s in students) {
      final err = await _service.addStudent(student: s);
      if (err == null) {
        added++;
        if (assertConsent) {
          try {
            final docId = Student.buildDocId(s.roll, s.className, s.section);
            await ConsentService().createConsent(
              studentDocId: docId,
              guardianName: s.fatherName.isNotEmpty ? s.fatherName : 'Parent',
              guardianPhone: s.phone.isNotEmpty ? s.phone : '0000000000',
              guardianEmail: s.guardianEmail,
              method: ConsentMethod.inPersonSigned,
              scopes: ParentalConsent.defaultScopes(),
            );
          } catch (e) {
            AppLogger.e('CSV Import', 'Failed to create bulk consent for ${s.name}: $e', e);
          }
        }
      } else {
        skipped++;
      }
    }
    if (!mounted) return;
    // Stream auto-refreshes after the import.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${context.tr('importedWord')} $added ${context.tr('studentsWord')}${skipped > 0 ? ', $skipped ${context.tr('skippedDuplicateRoll')}' : ''}'),
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
            ? Text('${_selectedRolls.length} ${context.tr('selectedLower')}')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.tr('studentList'),
                      style: const TextStyle(
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
                    _allSelected ? context.tr('noneLabel') : context.tr('allCount'),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: context.tr('deleteSelected'),
                  onPressed:
                      _selectedRolls.isNotEmpty ? _deleteSelected : null,
                ),
              ]
            : [
                if (_students.isNotEmpty)
                  _isPrincipal
                      ? PopupMenuButton<String>(
                          icon: const Icon(Icons.download_outlined),
                          tooltip: 'Export options',
                          onSelected: (value) {
                            if (value == 'csv') {
                              _exportCSV();
                            } else if (value == 'pdf') {
                              _exportPDF();
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'csv',
                              child: Row(
                                children: [
                                  const Icon(Icons.description_outlined, size: 20),
                                  const SizedBox(width: 8),
                                  Text(context.tr('exportCsv')),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'pdf',
                              child: Row(
                                children: [
                                  const Icon(Icons.picture_as_pdf_outlined, size: 20),
                                  const SizedBox(width: 8),
                                  Text(context.tr('exportPdf')),
                                ],
                              ),
                            ),
                          ],
                        )
                      : IconButton(
                          icon: const Icon(Icons.download_outlined),
                          tooltip: context.tr('exportToCsv'),
                          onPressed: _exportCSV,
                        ),
                if (widget.isClassTeacher)
                  IconButton(
                    icon: const Icon(Icons.upload_file_outlined),
                    tooltip: context.tr('importFromCsv'),
                    onPressed: _importCSV,
                  ),
              ],
      ),
      floatingActionButton: !_selectMode && widget.isClassTeacher
          ? FloatingActionButton.extended(
              onPressed: _openAdd,
              backgroundColor: AppTheme.primary,
              icon: const Icon(Icons.person_add, color: Colors.white),
              label: Text(context.tr('addStudent'),
                  style: const TextStyle(color: Colors.white)),
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
                      Text('${context.tr('noStudentsIn')} $_effectiveTitle',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade400)),
                      const SizedBox(height: 6),
                      Text(context.tr('tapAddStudentStart'),
                          style: TextStyle(
                              color: Colors.grey.shade400)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _refresh,
                  color: AppTheme.primary,
                  child: ListView.separated(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 100),
                    itemCount: _students.length + (_loadingMore ? 1 : 0),
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 80),
                    itemBuilder: (_, i) {
                      if (i == _students.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: SizedBox(
                              width: 24, height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            ),
                          ),
                        );
                      }
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
        color: pendingDeletion ? AppTheme.dangerLight : Colors.white,
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
                            child: Text('${context.tr('roll').toUpperCase()} ${student.roll}',
                                style: const TextStyle(fontSize: 10, color: AppTheme.primaryDark, fontWeight: FontWeight.w800)),
                          ),
                          const SizedBox(width: 8),
                          Text(student.fatherName, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                        ],
                      ),
                      if (pendingDeletion) ...[
                        const SizedBox(height: 4),
                        Text(context.tr('deletionRequestedAwaiting'),
                            style: const TextStyle(
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
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.hourglass_top, size: 11, color: AppTheme.warning),
                      const SizedBox(width: 3),
                      Text(context.tr('deactivated'),
                          style: const TextStyle(fontSize: 10, color: AppTheme.warning, fontWeight: FontWeight.bold)),
                    ]),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _feeColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(_localizedFeeStatus(context, student.feeStatus),
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
  bool _hasConsent = true;
  bool _isReConsent = false;

  @override
  void initState() {
    super.initState();
    _student = widget.student;
    _checkConsent();
  }

  Future<void> _checkConsent() async {
    try {
      final consentSvc = ConsentService();
      final hasActive = await consentSvc.hasActiveConsent(_student.id);
      final isRe = await consentSvc.needsReConsent(_student.id);
      if (mounted) {
        setState(() {
          _hasConsent = hasActive;
          _isReConsent = isRe;
        });
      }
    } catch (e, st) {
      AppLogger.e('StudentDetailPage', 'Failed to load consent status', e, st);
    }
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
    if (updated != null) {
      setState(() => _student = updated);
      _checkConsent();
    }
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
        title: Row(children: [
          const Icon(Icons.pending_actions_outlined, color: AppTheme.warning),
          const SizedBox(width: 8),
          Text(context.tr('requestDeletion'), style: const TextStyle(fontSize: 17)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${context.tr('removingRequiresApprovalPrefix')} ${_student.name} '
              '${context.tr('removingRequiresApprovalSuffix')}',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: dropReason,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: context.tr('reasonLabel'),
                prefixIcon: const Icon(Icons.info_outline, size: 18),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
              ),
              hint: Text(context.tr('selectReason'),
                  style: const TextStyle(fontSize: 13)),
              items: _kDeletionReasons
                  .map((r) => DropdownMenuItem(value: r, child: Text(_localizedReason(context, r), style: const TextStyle(fontSize: 13))))
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
                  labelText: context.tr('specifyReason'),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.all(10),
                ),
                onChanged: (v) => setLocal(() {}),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.tr('cancel'))),
          ElevatedButton.icon(
            icon: const Icon(Icons.send_outlined, size: 16,
                color: Colors.white),
            label: Text(context.tr('sendRequest'),
                style: const TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            onPressed: (dropReason == null || (dropReason == 'Other (specify below)' && reasonCtrl.text.trim().isEmpty))
                ? null
                : () {
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

    await StudentService.instance.submitDeletionRequest(
      teacherId:    widget.teacherId ?? '',
      teacherName:  widget.teacherName,
      teacherEmail: widget.teacherEmail,
      students:     studentMaps,
      reason:       reason,
    );
    await StudentService.instance.markStudentsDeletionPending(studentMaps, true);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          '${context.tr('deletionRequestSentFor')} ${_student.name}. '
          '${context.tr('awaitingPrincipalApproval')}'),
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
    final uri = PhoneUtils.whatsAppUri(_student.phone);
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
          title: Text(context.tr('guardianEmailTitle')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('guardianEmailIntro'),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              EmailTextFormField(
                controller: ctrl,
                decoration: InputDecoration(
                  labelText: context.tr('guardianEmailAddress'),
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
              child: Text(context.tr('cancel')),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
              onPressed: () async {
                final email = ctrl.text.trim().toLowerCase();
                if (!Validators.isValidEmail(email)) {
                  setS(() => emailErr = context.tr('enterValidEmail'));
                  return;
                }
                setS(() => emailErr = null);
                // Persist the email on the student record + provision the
                // guardian's allowed_users / Firebase Auth account.
                await StudentService.instance.setGuardianEmail(
                  _student.className, _student.roll, email,
                  section: _student.section,
                  studentName: _student.name,
                );
                savedEmail = email;
                // Actually send the password-setup / invite email and capture
                // the real result — do NOT assume success.
                try {
                  await TimetableService.instance.resendInvitationEmail(email);
                  inviteSent = true;
                } catch (e) {
                  inviteError = e;
                }
                if (dCtx.mounted) Navigator.pop(dCtx);
              },
              child: Text(context.tr('save')),
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
          content: Text('${context.tr('inviteEmailSentTo')} $savedEmail'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${context.tr('guardianSavedInviteFailedPrefix')} $savedEmail '
              '${context.tr('guardianSavedInviteFailedSuffix')}'),
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
      await TimetableService.instance.resendInvitationEmail(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${context.tr('inviteEmailResentTo')} $email'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr('failedResendInvite')),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(context.tr('copiedToClipboard')),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _shareGuardianAppInfo() async {
    final email = _student.guardianEmail ?? '';
    final msg =
      'Hello! Your child ${_student.name}\'s school portal is ready.\n'
      'Login email: $email\n'
      'Please check your email for a link to set up your password, then open the School App and sign in.';
    final uri = PhoneUtils.whatsAppUri(_student.phone, text: msg);
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

      await StudentService.instance.updateStudent(updated: updatedStudent);
      await StudentService.instance.updateGuardianProvidedDetailsStatus(_student.id, details.id, 'accepted');

      setState(() {
        _student = updatedStudent;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('guardianUpdatesAccepted'))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${context.tr('failedAcceptUpdates')} $e')),
      );
    }
  }

  Future<void> _requestGuardianClarification(GuardianProvidedDetails details) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('requestClarification')),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: context.tr('enterClarificationHint'),
            border: const OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(context.tr('submitAction')),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      try {
        await StudentService.instance.updateGuardianProvidedDetailsStatus(
          _student.id,
          details.id,
          'clarification_requested',
          remarks: result,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('clarificationSent'))),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.tr('failedRequestClarification')} $e')),
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

    compare(context.tr('fullName'), s.name, details.name);
    compare(context.tr('dateOfBirthLabel'), d?.dob ?? '', details.dob);
    compare(context.tr('genderLabel'), d?.gender ?? '', details.gender);
    compare(context.tr('fathersName'), s.fatherName, details.fatherName);
    compare(context.tr('mothersNameLabel'), s.motherName ?? '', details.motherName);
    compare(context.tr('primaryPhone'), s.phone, details.phone);
    compare(context.tr('secondaryPhone'), s.parentPhone ?? '', details.parentPhone);
    compare(context.tr('addressLabel'), d?.address ?? '', details.address);
    compare(context.tr('previousSchoolLabel'), d?.previousSchool ?? '', details.previousSchool);
    compare(context.tr('bloodGroupLabel'), d?.bloodGroup ?? '', details.bloodGroup);
    compare(context.tr('emergencyContactName'), d?.emergencyContactName ?? '', details.emergencyContactName);
    compare(context.tr('emergencyContactPhone'), d?.emergencyContactPhone ?? '', details.emergencyContactPhone);
    compare(context.tr('allergiesConditionsLabel'), d?.allergies ?? '', details.allergies);
    compare(context.tr('transportModeLabel'), d?.transportMode ?? '', details.transportMode);

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
                  context.tr('detailsProvidedByGuardian'),
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
                        text: entry.value[0].isEmpty ? context.tr('emptyBracket') : entry.value[0],
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
            }),
            if (details.remarks.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${context.tr('remarksColon')} ${details.remarks}',
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
                    context.tr('requestClarification'),
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
                  child: Text(context.tr('acceptChanges')),
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
        title: Text(context.tr('studentProfile')),
        actions: [
          if (widget.canEdit) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: context.tr('edit'),
              onPressed: _edit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: context.tr('removeAction'),
              onPressed: _delete,
            ),
          ],
        ],
      ),
      body: StreamBuilder<List<GuardianProvidedDetails>>(
        stream: StudentService.instance.watchGuardianProvidedDetails(_student.id),
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
                ConsentPendingBanner(
                  hasConsent: _hasConsent,
                  isReConsent: _isReConsent,
                  onTapAction: () async {
                    final res = await Navigator.push<ParentalConsent?>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ParentalConsentFlow(
                          studentDocId: _student.id,
                          studentName: _student.name,
                          prefillGuardianName: _student.fatherName.isNotEmpty
                              ? _student.fatherName
                              : null,
                          prefillGuardianPhone: (_student.parentPhone?.isNotEmpty == true)
                              ? _student.parentPhone
                              : (_student.phone.isNotEmpty
                                  ? _student.phone
                                  : null),
                          isReConsent: _isReConsent,
                        ),
                        fullscreenDialog: true,
                      ),
                    );
                    if (res != null) {
                      _checkConsent();
                    }
                  },
                ),
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
                  _Chip('${context.tr('roll')} ${_student.roll}'),
                  const SizedBox(width: 8),
                  _Chip(_student.className),
                  if (_student.section.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _Chip('${context.tr('secPrefix')} ${_student.section}'),
                  ],
                ]),
              ]),
            ),

            const SizedBox(height: 8),

            if (pendingGuardianDetails.id.isNotEmpty)
              _buildGuardianDetailsSection(pendingGuardianDetails),

            // ── Basic Info ───────────────────────────────────────────────────
            _SectionHeader(context.tr('secBasicInfo')),
            _InfoRow(Icons.person_outline, context.tr('nameLabel'), _student.name),
            _InfoRow(Icons.cake_outlined, context.tr('dateOfBirthLabel'),
                _student.dateOfBirth != null
                    ? _fmtDob(_student.dateOfBirth!.toDate())
                    : '—'),
            _InfoRow(Icons.wc_outlined, context.tr('genderLabel'),
                _student.gender?.isNotEmpty == true ? _student.gender! : '—'),
            _InfoRow(Icons.school_outlined, context.tr('classSection'),
                '${_student.className} ${_student.section}'.trim()),
            _InfoRow(Icons.tag, context.tr('rollNumber'), '${_student.roll}'),
            const Divider(height: 1),

            // ── Family ──────────────────────────────────────────────────────
            _SectionHeader(context.tr('secFamily')),
            _InfoRow(Icons.man_outlined, context.tr('fathersName'),
                _student.fatherName.isNotEmpty ? _student.fatherName : '—'),
            _InfoRow(Icons.woman_outlined, context.tr('mothersNameLabel'),
                _student.motherName?.isNotEmpty == true ? _student.motherName! : '—'),
            const Divider(height: 1),

            // ── Contact ─────────────────────────────────────────────────────
            _SectionHeader(context.tr('secContact')),
            _InfoRow(Icons.phone_outlined, context.tr('primaryContact'),
                _student.phone.isEmpty ? '—' : _student.phone),
            if (_student.phone.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(children: [
                  Expanded(
                    child: _ActionBtn(
                      icon: Icons.call,
                      label: context.tr('callAction'),
                      color: Colors.green,
                      onTap: _call,
                    ),
                  ),
                  if (Provider.of<SchoolSettingsProvider>(context, listen: false).whatsappEnabled) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionBtn(
                        iconWidget: const FaIcon(
                          FontAwesomeIcons.whatsapp,
                          color: AppTheme.whatsapp,
                          size: 24,
                        ),
                        label: 'WhatsApp',
                        color: AppTheme.whatsapp,
                        onTap: _whatsapp,
                      ),
                    ),
                  ],
                ]),
              ),
            _InfoRow(Icons.phone_android_outlined, context.tr('secondaryContact'),
                _student.parentPhone?.isNotEmpty == true ? _student.parentPhone! : '—'),
            _InfoRow(Icons.home_outlined, context.tr('addressLabel'),
                _student.address?.isNotEmpty == true ? _student.address! : '—'),
            _InfoRow(Icons.contact_emergency_outlined, context.tr('emergencyContactLabel'),
                _student.emergencyContact?.isNotEmpty == true
                    ? _student.emergencyContact!
                    : '—'),
            const Divider(height: 1),

            // ── Academic & Medical ───────────────────────────────────────────
            _SectionHeader(context.tr('secAcademicMedical')),
            _InfoRow(Icons.account_balance_outlined, context.tr('previousSchoolLabel'),
                _student.previousSchool?.isNotEmpty == true ? _student.previousSchool! : '—'),
            _InfoRow(Icons.bloodtype_outlined, context.tr('bloodGroupLabel'),
                _student.bloodGroup?.isNotEmpty == true ? _student.bloodGroup! : '—'),
            _InfoRow(Icons.medical_information_outlined, context.tr('allergiesConditionsLabel'),
                _student.allergies?.isNotEmpty == true ? _student.allergies! : '—'),
            _InfoRow(Icons.directions_bus_outlined, context.tr('transportModeLabel'),
                _student.transportMode?.isNotEmpty == true ? _student.transportMode! : '—'),
            _InfoRow(Icons.photo_outlined, context.tr('photoStatus'),
                (_student.photoPath != null && _student.photoPath!.isNotEmpty) ||
                    (_student.photoUrl != null && _student.photoUrl!.isNotEmpty)
                    ? context.tr('uploaded')
                    : context.tr('notUploaded')),
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
                  Text(_localizedFeeStatus(context, _student.feeStatus),
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _feeColor,
                          fontSize: 14)),
                ]),
              ),
            ),
            const Divider(height: 1),

            // ── Documents ────────────────────────────────────────────────────
            _SectionHeader(context.tr('secDocuments')),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.workspace_premium_outlined),
                  label: Text(context.tr('generateAttendanceCertificate')),
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
            _SectionHeader(context.tr('secGuardianPortal')),
            if (_student.guardianEmail == null || _student.guardianEmail!.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.people_outlined),
                    label: Text(context.tr('setGuardianEmail')),
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
                        context.tr('guardianCanSignIn'),
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 10),
                      // Resend invite + WhatsApp row
                      Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.send_outlined, size: 15),
                            label: Text(context.tr('resendInvite'), style: const TextStyle(fontSize: 13)),
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
                        if (Provider.of<SchoolSettingsProvider>(context, listen: false).whatsappEnabled) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const FaIcon(FontAwesomeIcons.whatsapp,
                                  size: 15, color: AppTheme.whatsapp),
                              label: const Text('WhatsApp', style: TextStyle(fontSize: 13)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.whatsapp.withValues(alpha: 0.1),
                                foregroundColor: AppTheme.primary,
                                elevation: 0,
                                side: const BorderSide(color: AppTheme.whatsapp),
                                padding: const EdgeInsets.symmetric(vertical: 9),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: _shareGuardianAppInfo,
                            ),
                          ),
                        ],
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr('copiedToClipboard')),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
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
        _GRow(Icons.cake_outlined, context.tr('dateOfBirthLabel'), d.dob),
      if (d.gender.isNotEmpty)
        _GRow(Icons.wc_outlined, context.tr('genderLabel'), d.gender),
      if (d.address.isNotEmpty)
        _GRow(Icons.home_outlined, context.tr('addressLabel'), d.address),
      if (d.bloodGroup.isNotEmpty)
        _GRow(Icons.bloodtype_outlined, context.tr('bloodGroupLabel'), d.bloodGroup),
      if (d.emergencyContactName.isNotEmpty)
        _GRow(Icons.contact_phone_outlined, context.tr('emergencyContactLabel'),
            d.emergencyContactPhone.isNotEmpty
                ? '${d.emergencyContactName}  ·  ${d.emergencyContactPhone}'
                : d.emergencyContactName),
      if (d.allergies.isNotEmpty)
        _GRow(Icons.medical_services_outlined, context.tr('allergiesConditionsLabel'),
            d.allergies),
      if (d.transportMode.isNotEmpty)
        _GRow(Icons.directions_bus_outlined, context.tr('transportModeLabel'),
            d.transportMode),
      if (d.previousSchool.isNotEmpty)
        _GRow(Icons.school_outlined, context.tr('previousSchoolLabel'), d.previousSchool),
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
              context.tr('secDetailsByGuardian'),
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
              child: Text(context.tr('guardianSupplied'),
                  style: const TextStyle(
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
              '${context.tr('lastUpdatedByGuardian')} ${d.lastUpdated!.split('T')[0]}',
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

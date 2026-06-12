import '../../l10n/app_strings.dart';
import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/teacher.dart';
import '../../models/timetable_entry.dart';
import '../../services/timetable_service.dart';
import '../../services/teacher_deletion_service.dart';
import '../../services/base_firestore_service.dart';
import '../../shared/utils/app_logger.dart';
import '../../shared/utils/image_utils.dart';
import '../../shared/utils/validators.dart';
import '../../theme.dart';
import '../../shared/widgets/email_text_form_field.dart';
import '../../shared/widgets/refreshable_data.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Predefined subject list for teacher dialog
// ─────────────────────────────────────────────────────────────────────────────

const List<String> _kSubjects = [
  'English',
  'Hindi',
  'Mathematics',
  'Science',
  'Social Science',
  'Environmental Science (EVS)',
  'Physics',
  'Chemistry',
  'Biology',
  'History',
  'Geography',
  'Civics / Political Science',
  'Economics',
  'Computer Science',
  'Information Technology (IT)',
  'Physical Education (P.E.)',
  'Sanskrit',
  'Urdu',
  'French',
  'German',
  'Accountancy',
  'Business Studies',
  'Art & Craft',
  'Music',
  'General Knowledge (GK)',
  'Moral Science / Value Education',
  'Library',
  'Other (specify)',
];

const List<String> _kTeacherDeletionReasons = [
  'Resigned / Left the school',
  'Retired',
  'Terminated',
  'Duplicate account / Wrong entry',
  'Other (specify reason)',
];

// ─────────────────────────────────────────────────────────────────────────────
//  Teacher Management List
// ─────────────────────────────────────────────────────────────────────────────

class TeacherManagementScreen extends StatefulWidget {
  const TeacherManagementScreen({super.key});

  @override
  State<TeacherManagementScreen> createState() =>
      _TeacherManagementScreenState();
}

class _TeacherManagementScreenState extends State<TeacherManagementScreen> {
  final _service          = TimetableService.instance;
  final _deletionService  = TeacherDeletionService();
  List<Teacher> _teachers = [];
  bool _loading = true;

  // Current session — drives the coordinator-needs-approval vs principal/
  // owner-can-delete-direct UX branch. Loaded async on init; until it lands
  // we hide destructive actions to avoid acting under the wrong role.
  String _role  = '';
  String _email = '';
  String _name  = '';

  // teacherId → requestId for currently-pending deletion requests. Drives
  // the orange "Deletion requested" badge on each card, and powers the
  // "Cancel request" affordance for the coordinator who filed it.
  Map<String, String> _pendingByTeacherId = const {};
  StreamSubscription<Map<String, String>>? _pendingSub;

  Set<String> _selectedIds = {};
  bool        _selectMode  = false;

  bool get _isCoordinator => _role == 'coordinator';
  String get _schoolId =>
      BaseFirestoreService.currentSchoolId ?? 'default_school';

  static const _colors = [
    AppTheme.primary, AppTheme.primaryDark, AppTheme.primaryMid, AppTheme.accent,
    AppTheme.primaryLight, Colors.green, Colors.red, Colors.brown,
    Colors.cyan, AppTheme.primaryDark,
  ];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _pendingSub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final session = await TeacherDeletionService.sessionUser();
    if (!mounted) return;
    setState(() {
      _role  = session['role']  ?? '';
      _email = session['email'] ?? '';
      _name  = session['name']  ?? '';
    });
    // Subscribe to pending requests so badges update live as principal/owner
    // approves or rejects.
    _pendingSub = _deletionService
        .streamPendingByTeacherId(_schoolId)
        .listen((m) {
      if (!mounted) return;
      setState(() => _pendingByTeacherId = m);
    }, onError: (e) {
      // Non-fatal — badge just won't update. Debug-only (no release stdout).
      AppLogger.e('TeacherManagement', 'pending stream error', e);
    });
    await _load();
  }

  Future<void> _load() async {
    final list = await _service.getTeachers();
    if (!mounted) return;
    setState(() {
      _teachers = list;
      _loading  = false;
    });
  }

  // ── Multi-select helpers ─────────────────────────────────────────────────

  void _enterSelectMode(Teacher t) {
    setState(() { _selectMode = true; _selectedIds = {t.id}; });
  }

  void _exitSelectMode() {
    setState(() { _selectMode = false; _selectedIds = {}; });
  }

  void _toggleSelect(Teacher t) {
    setState(() {
      if (_selectedIds.contains(t.id)) {
        _selectedIds.remove(t.id);
        if (_selectedIds.isEmpty) _selectMode = false;
      } else {
        _selectedIds.add(t.id);
      }
    });
  }

  Future<void> _deleteSelected() async {
    // Coordinator flow: each selected teacher becomes a pending deletion
    // request. We collect a single shared reason in one dialog, then file
    // N requests so the approval queue stays itemised (the principal can
    // approve/reject each on its own merits).
    if (_isCoordinator) {
      await _requestDeletionForSelected();
      return;
    }

    final count = _selectedIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Teachers'),
        content: Text(
            'Remove $count teacher${count == 1 ? '' : 's'}? '
            'Their timetable assignments will be cleared.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    for (final id in _selectedIds) {
      await _service.removeTeacher(_schoolId, id);
    }
    if (!mounted) return;
    setState(() { _selectMode = false; _selectedIds = {}; });
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              '$count teacher${count == 1 ? '' : 's'} removed')),
    );
  }

  /// Coordinator multi-select → file one deletion request per selected
  /// teacher (skipping any that already have a pending request).
  Future<void> _requestDeletionForSelected() async {
    final selected = _teachers
        .where((t) => _selectedIds.contains(t.id))
        .where((t) => !_pendingByTeacherId.containsKey(t.id))
        .toList();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('All selected teachers already have pending requests.'),
      ));
      return;
    }
    final reason = await _promptReason(
      title: 'Request Deletion (${selected.length})',
      message:
          'These ${selected.length} teacher accounts will be queued for the '
          'principal or owner to review. Add an optional reason:',
    );
    if (reason == null || !mounted) return;
    var ok = 0;
    var fail = 0;
    for (final t in selected) {
      try {
        await _deletionService.requestDeletion(
          schoolId:        _schoolId,
          teacher:         t,
          requestedBy:     _email,
          requestedByName: _name,
          reason:          reason,
        );
        ok++;
      } catch (_) {
        fail++;
      }
    }
    if (!mounted) return;
    setState(() { _selectMode = false; _selectedIds = {}; });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(fail == 0
          ? '$ok deletion request${ok == 1 ? '' : 's'} sent for approval.'
          : '$ok sent · $fail failed.'),
      backgroundColor: fail == 0 ? AppTheme.success : AppTheme.warning,
    ));
  }

  /// Shared bottom prompt for "Reason for deletion". Returns the entered
  /// text (possibly empty), or null if the user cancelled.
  Future<String?> _promptReason({
    required String title,
    required String message,
  }) async {
    final ctrl = TextEditingController();
    String? dropReason;
    bool showCustom = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message,
                  style: const TextStyle(fontSize: 13, color: Colors.black54)),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: dropReason,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Reason',
                  prefixIcon: const Icon(Icons.info_outline, size: 18),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
                hint: const Text('Select a reason',
                    style: TextStyle(fontSize: 13)),
                items: _kTeacherDeletionReasons
                    .map((r) => DropdownMenuItem(
                          value: r,
                          child: Text(r, style: const TextStyle(fontSize: 13)),
                        ))
                    .toList(),
                onChanged: (v) => setLocal(() {
                  dropReason = v;
                  showCustom = v == 'Other (specify reason)';
                  if (!showCustom) ctrl.clear();
                }),
              ),
              if (showCustom) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: ctrl,
                  maxLines: 2,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Specify reason',
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
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white),
              onPressed: (dropReason == null ||
                      (dropReason == 'Other (specify reason)' &&
                          ctrl.text.trim().isEmpty))
                  ? null
                  : () {
                      if (!showCustom) ctrl.text = dropReason ?? '';
                      Navigator.pop(ctx, true);
                    },
              child: const Text('Send for Approval'),
            ),
          ],
        ),
      ),
    );

    Future.delayed(const Duration(milliseconds: 350), ctrl.dispose);

    final text = ctrl.text.trim();
    return ok == true ? text : null;
  }

  /// Asks the user to confirm before adding a teacher whose details match an
  /// existing record (same name + same email, or same name + same subject when
  /// no email is given). Returns true to proceed, false to cancel.
  Future<bool> _confirmTeacherNotDuplicate(Teacher teacher) async {
    String norm(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final name    = norm(teacher.name);
    final email   = norm(teacher.email);
    final subject = norm(teacher.subject);
    if (name.isEmpty) return true;

    Teacher? match;
    for (final t in _teachers) {
      if (norm(t.name) != name) continue;
      final sameEmail   = email.isNotEmpty && norm(t.email) == email;
      final sameSubject = email.isEmpty && norm(t.subject) == subject;
      if (sameEmail || sameSubject) { match = t; break; }
    }
    final m = match;
    if (m == null || !mounted) return m == null;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange),
          SizedBox(width: 8),
          Text('Possible duplicate', style: TextStyle(fontSize: 16)),
        ]),
        content: Text(
          'A teacher with the same details already appears to be saved:\n\n'
          '${m.name}${m.email.isNotEmpty ? " (${m.email})" : ""}.\n\n'
          'Please check before adding again. Save anyway?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save anyway'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  // ── Open the Add/Edit dialog ─────────────────────────────────────────────

  Future<void> _openDialog({Teacher? existing}) async {
    final teacher = await Navigator.push<Teacher>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _TeacherFormScreen(existing: existing),
      ),
    );
    if (teacher == null) return;

    // Duplicate class-teacher check (same class, regardless of section)
    if (teacher.isClassTeacher && teacher.classTeacherOf != null) {
      final duplicate = _teachers.firstWhere(
        (t) =>
            t.id != teacher.id &&
            t.isClassTeacher &&
            t.classTeacherOf == teacher.classTeacherOf,
        orElse: () =>
            const Teacher(id: '', name: '', subject: '', email: '', schoolId: 'default_school'),
      );
      if (duplicate.id.isNotEmpty) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: const Row(children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('Conflict', style: TextStyle(fontSize: 16)),
            ]),
            content: Text(
              '${duplicate.name} is already the class teacher of '
              '${teacher.classTeacherOf!}.\n\n'
              'Please remove them as class teacher first.',
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange),
                child: const Text('OK',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
        return;
      }
    }

    // Warn before adding a teacher whose details match one already saved.
    if (existing == null && !await _confirmTeacherNotDuplicate(teacher)) return;

    final schoolId = BaseFirestoreService.currentSchoolId ?? 'default_school';

    if (existing == null) {
      await _service.addTeacher(schoolId, teacher);
      // Create login credentials and send invite email to the new teacher.
      // Pass '' as password so addAllowedUser auto-generates a cryptographically
      // secure temp password via generateSecurePassword() — never hardcoded.
      if (teacher.email.isNotEmpty) {
        await _service.addAllowedUser(
          teacher.email,
          '', // auto-generates a secure temp password
          'teacher',
          name:     teacher.name,
          schoolId: schoolId,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Invite email sent to ${teacher.email}'),
            backgroundColor: Colors.green.shade700,
          ));
        }
      }
    } else {
      await _service.updateTeacher(schoolId, teacher);
      final oldEmail = existing.email.trim().toLowerCase();
      final newEmail = teacher.email.trim().toLowerCase();
      // If the email changed, migrate the login credentials to the new address.
      if (newEmail.isNotEmpty && oldEmail != newEmail) {
        // Remove old allowed_users entry so the old email can no longer log in.
        if (oldEmail.isNotEmpty) {
          await _service.removeAllowedUser(oldEmail);
        }
        // Create Firebase Auth account + allowed_users doc + send invite.
        // Pass '' so a new secure random temp password is generated.
        await _service.addAllowedUser(
          newEmail,
          '', // auto-generates a secure temp password
          'teacher',
          name:     teacher.name,
          schoolId: schoolId,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Email updated — invite sent to $newEmail'),
            backgroundColor: Colors.green.shade700,
          ));
        }
      }
    }
    _load();
  }

  // ── Confirm + remove ─────────────────────────────────────────────────────

  Future<void> _confirmRemove(Teacher teacher) async {
    // Coordinator: file a deletion request instead of removing directly.
    // If they already have a pending request for this teacher, the badge
    // path handles cancel; this method is reached only when no pending
    // request exists yet.
    if (_isCoordinator) {
      if (_pendingByTeacherId.containsKey(teacher.id)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'A deletion request for ${teacher.name} is already pending.'),
        ));
        return;
      }
      final reason = await _promptReason(
        title: 'Request Deletion',
        message:
            '${teacher.name} will be queued for the principal or owner to '
            'review. Add an optional reason:',
      );
      if (reason == null || !mounted) return;
      try {
        await _deletionService.requestDeletion(
          schoolId:        _schoolId,
          teacher:         teacher,
          requestedBy:     _email,
          requestedByName: _name,
          reason:          reason,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Deletion request sent for ${teacher.name}. The principal will review it.'),
          backgroundColor: AppTheme.success,
        ));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not send request: $e'),
          backgroundColor: Colors.red,
        ));
      }
      return;
    }

    // Principal / admin / owner: direct delete as before.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Teacher'),
        content: Text(
            'Remove ${teacher.name}? Their timetable assignments will be cleared.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _service.removeTeacher(_schoolId, teacher.id);
      _load();
    }
  }

  /// Coordinator-only: cancel the caller's own pending request for [teacher].
  /// Triggered from the pending badge on the teacher card.
  Future<void> _cancelMyRequest(Teacher teacher) async {
    final requestId = _pendingByTeacherId[teacher.id];
    if (requestId == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(context.tr('cancelDeletionRequest')),
        content: Text(
            'Withdraw your deletion request for ${teacher.name}? '
            'The principal will no longer see it in their queue.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.tr('keepRequest'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.warning,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _deletionService.cancelMyRequest(
          schoolId: _schoolId, requestId: requestId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Request for ${teacher.name} withdrawn.'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not cancel: $e'),
        backgroundColor: Colors.red,
      ));
    }
  }

  // ── CSV import ────────────────────────────────────────────────────────────

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

    // Detect header row
    int dataStart = 0;
    Map<String, int> colMap = {};
    final firstRow =
        rows[0].map((e) => e.toString().trim().toLowerCase()).toList();
    if (firstRow.any((c) => ['name', 'teacher'].any((k) => c.contains(k)))) {
      dataStart = 1;
      for (final h in ['name', 'subject', 'email', 'section', 'phone']) {
        final idx = firstRow.indexWhere((c) => c.contains(h));
        if (idx >= 0) colMap[h] = idx;
      }
    }

    String get(List<dynamic> row, String key) {
      final idx = colMap[key];
      if (idx == null || idx >= row.length) return '';
      return row[idx].toString().trim();
    }

    final teachers = <Teacher>[];
    for (int i = dataStart; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty) continue;
      final name = colMap.containsKey('name')
          ? get(row, 'name')
          : row[0].toString().trim();
      if (name.isEmpty) continue;
      teachers.add(Teacher(
        id: '${DateTime.now().millisecondsSinceEpoch}_$i',
        name: name,
        subject: get(row, 'subject'),
        email: get(row, 'email'),
        section: get(row, 'section'),
        schoolId: BaseFirestoreService.currentSchoolId ?? 'default_school',
      ));
    }

    if (teachers.isEmpty || !mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No valid teachers found in CSV')));
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Import ${teachers.length} Teachers'),
        content: SizedBox(
          width: double.maxFinite,
          height: 260,
          child: ListView.builder(
            itemCount: teachers.length,
            itemBuilder: (_, i) {
              final t = teachers[i];
              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                  child: Text(t.name[0].toUpperCase(),
                      style: const TextStyle(
                          fontSize: 13, color: AppTheme.primary)),
                ),
                title: Text(t.name,
                    style: const TextStyle(fontSize: 13)),
                subtitle: t.subject.isNotEmpty
                    ? Text(t.subject,
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

    final sid = BaseFirestoreService.currentSchoolId ?? 'default_school';
    int imported = 0;
    int skipped  = 0;
    for (final t in teachers) {
      // Validate email format before inserting (Issue 9).
      if (t.email.isNotEmpty && !Validators.isValidEmail(t.email)) {
        AppLogger.w('TeacherManagement',
            'CSV import skipped "${t.name}" — invalid email: ${t.email}');
        skipped++;
        continue;
      }
      // Duplicate-check: skip if email already registered in allowed_users.
      if (t.email.isNotEmpty) {
        try {
          final existing = await _service.getAllowedUserDoc(t.email);
          if (existing != null) {
            AppLogger.w('TeacherManagement',
                'CSV import skipped "${t.name}" — email already registered: ${t.email}');
            skipped++;
            continue;
          }
        } catch (e) {
          // If we can't read, proceed and let the write rules be the authority.
          AppLogger.w('TeacherManagement', 'Duplicate check read failed for ${t.email}: $e');
        }
      }
      await _service.addTeacher(sid, t);
      // Create Auth account with secure auto-generated temp password.
      if (t.email.isNotEmpty) {
        try {
          await _service.addAllowedUser(
            t.email,
            '', // auto-generates a secure temp password
            'teacher',
            name:     t.name,
            schoolId: sid,
          );
        } catch (e) {
          AppLogger.e('TeacherManagement',
              'addAllowedUser failed for ${t.email} during CSV import: $e', e);
        }
      }
      imported++;
    }
    await _load();
    if (!mounted) return;
    final msg = skipped > 0
        ? 'Imported $imported teachers ($skipped skipped — invalid/duplicate email)'
        : 'Imported $imported teachers';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: imported > 0 ? Colors.green : Colors.orange,
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

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
            ? Text('${_selectedIds.length} selected')
            : const Text('Manage Teachers'),
        actions: _selectMode
            ? [
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove selected',
                  onPressed:
                      _selectedIds.isNotEmpty ? _deleteSelected : null,
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.upload_file_outlined),
                  tooltip: 'Import from CSV',
                  onPressed: _importCSV,
                ),
              ],
      ),
      floatingActionButton: _selectMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openDialog(),
              icon: const Icon(Icons.person_add),
              label: Text(context.tr('addTeacher')),
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
      body: _loading
          ? const LoadingState()
          : RefreshIndicator(
              onRefresh: _load,
              color: AppTheme.primary,
              child: _teachers.isEmpty
                  // AlwaysScrollableScrollPhysics + a single LayoutBuilder-sized
                  // box make the empty state participate in the pull gesture
                  // (a non-scrollable Column would swallow it).
                  ? LayoutBuilder(
                      builder: (_, c) => SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: c.maxHeight),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.people_outline,
                                    size: 72, color: Colors.grey[300]),
                                const SizedBox(height: 16),
                                Text(context.tr('noTeachersYet'),
                                    style: TextStyle(
                                        fontSize: 16, color: Colors.grey[500])),
                                const SizedBox(height: 6),
                                Text(context.tr('tapToAddTeacher')),
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 100),
                  itemCount: _teachers.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 72),
                  itemBuilder: (_, i) {
                    final t        = _teachers[i];
                    final color    = _colors[i % _colors.length];
                    final selected = _selectedIds.contains(t.id);
                    return Container(
                      color: selected
                          ? AppTheme.primary.withValues(alpha: 0.08)
                          : Colors.white,
                      child: InkWell(
                        onTap: _selectMode
                            ? () => _toggleSelect(t)
                            : () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => TeacherDetailScreen(
                                      teacher: t,
                                      color:   color,
                                      onEdit: () async {
                                        Navigator.pop(context);
                                        await _openDialog(existing: t);
                                      },
                                      onDelete: () async {
                                        Navigator.pop(context);
                                        await _confirmRemove(t);
                                      },
                                    ),
                                  ),
                                );
                                _load();
                              },
                        onLongPress: _selectMode
                            ? null
                            : () => _enterSelectMode(t),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Row(children: [
                            _selectMode
                                ? SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: Center(
                                      child: Checkbox(
                                        value:       selected,
                                        onChanged:   (_) => _toggleSelect(t),
                                        activeColor: AppTheme.primary,
                                        shape:       const CircleBorder(),
                                      ),
                                    ),
                                  )
                                : CircleAvatar(
                                    radius: 24,
                                    backgroundColor: color,
                                    child: Text(t.name[0].toUpperCase(),
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18)),
                                  ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                Row(children: [
                                  Expanded(
                                    child: Text(t.name,
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600)),
                                  ),
                                  if (t.isClassTeacher)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primary
                                            .withValues(alpha: 0.08),
                                        borderRadius:
                                            BorderRadius.circular(20),
                                        border: Border.all(
                                            color: AppTheme.primary
                                                .withValues(alpha: 0.3)),
                                      ),
                                      child: const Text('Class Teacher',
                                          style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.primary)),
                                    ),
                                  // Deletion-requested pill — visible to all
                                  // management so principal/owner know which
                                  // cards already have a request in flight.
                                  // For the requesting coordinator it doubles
                                  // as a tap target to withdraw the request.
                                  if (_pendingByTeacherId.containsKey(t.id))
                                    Padding(
                                      padding: const EdgeInsets.only(left: 4),
                                      child: InkWell(
                                        borderRadius:
                                            BorderRadius.circular(20),
                                        onTap: _isCoordinator
                                            ? () => _cancelMyRequest(t)
                                            : null,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 7, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: AppTheme.warning
                                                .withValues(alpha: 0.10),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            border: Border.all(
                                                color: AppTheme.warning
                                                    .withValues(alpha: 0.4)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                  Icons.hourglass_top_outlined,
                                                  size: 11,
                                                  color: AppTheme.warning),
                                              const SizedBox(width: 3),
                                              Text(
                                                _isCoordinator
                                                    ? 'Pending · tap to cancel'
                                                    : 'Deletion requested',
                                                style: const TextStyle(
                                                    fontSize: 10,
                                                    fontWeight:
                                                        FontWeight.w600,
                                                    color: AppTheme.warning),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                ]),
                                const SizedBox(height: 2),
                                Text(
                                  [
                                    t.subject,
                                    if (t.section.isNotEmpty)
                                      'Sec ${t.section}',
                                    if (t.isClassTeacher &&
                                        t.classTeacherOf != null)
                                      t.classTeacherOf!,
                                  ].join('  ·  '),
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600),
                                ),
                                if (t.email.isNotEmpty)
                                  Text(t.email,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade400)),
                              ]),
                            ),
                            if (!_selectMode)
                              Icon(Icons.chevron_right,
                                  color: Colors.grey.shade400, size: 20),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Teacher Detail Screen
// ─────────────────────────────────────────────────────────────────────────────

class TeacherDetailScreen extends StatefulWidget {
  final Teacher      teacher;
  final Color        color;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const TeacherDetailScreen({
    super.key,
    required this.teacher,
    required this.color,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<TeacherDetailScreen> createState() => _TeacherDetailScreenState();
}

class _TeacherDetailScreenState extends State<TeacherDetailScreen> {
  final _service = TimetableService.instance;

  List<String>  _classes   = [];
  int           _bellCount = 8;
  Map<String, Map<String, Map<int, TimetableEntry>>> _timetable = {};
  List<Teacher> _allTeachers = [];
  bool   _loading     = true;
  String _selectedDay = _currentDay();

  static const _days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'
  ];
  static const _dayAbbr = {
    'Monday': 'Mon', 'Tuesday': 'Tue', 'Wednesday': 'Wed',
    'Thursday': 'Thu', 'Friday': 'Fri', 'Saturday': 'Sat',
  };

  static String _currentDay() {
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
    final settings = await _service.getSettings();
    final tt       = await _service.getTimetable();
    final teachers = await _service.getTeachers();
    if (!mounted) return;
    setState(() {
      _classes     = List<String>.from(settings['classes'] as List);
      _bellCount   = settings['numberOfBells'] as int;
      _timetable   = tt;
      _allTeachers = teachers;
      _loading     = false;
    });
  }

  String _subjectLabel(TimetableEntry? e) {
    if (e == null || e.isEmpty) return '';
    if (e.subject?.isNotEmpty == true) return e.subject!;
    final t = _allTeachers.firstWhere((t) => t.id == e.teacherId,
        orElse: () =>
            const Teacher(id: '', name: '', subject: '', email: ''));
    return t.subject;
  }

  List<_Slot> get _mySlots {
    final tid = widget.teacher.id;
    final slots = <_Slot>[];
    for (final cls in _classes) {
      for (int b = 1; b <= _bellCount; b++) {
        final entry = _timetable[cls]?[_selectedDay]?[b];
        if (entry?.teacherId == tid) {
          slots.add(_Slot(
            bell:      b,
            className: cls,
            subject:   _subjectLabel(entry),
          ));
        }
      }
    }
    slots.sort((a, b) => a.bell.compareTo(b.bell));
    return slots;
  }

  Future<void> _sendLoginInvite(BuildContext ctx) async {
    final email = widget.teacher.email.trim().toLowerCase();
    if (email.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Send Login Invite'),
        content: Text(
            'This will create a login account for ${widget.teacher.name} '
            'and send a password-setup link to $email.\n\n'
            'They can use it to set their password and sign in.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(_, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(_, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      await _service.provisionTeacherLoginAccess(widget.teacher);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Invite sent to $email'),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to send invite: $e'),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.teacher;
    final c = widget.color;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(t.name,
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.bold)),
        backgroundColor: c,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: widget.onEdit,
          ),
        ],
      ),
      body: _loading
          ? const LoadingState()
          : ListView(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 32),
              children: [
                // ── Hero header ────────────────────────────────────────────
                Container(
                  color: c,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Column(children: [
                    CircleAvatar(
                      radius: 38,
                      backgroundColor: Colors.white.withValues(alpha: 0.25),
                      child: Text(
                        t.name[0].toUpperCase(),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 30),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(t.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(t.subject,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 14)),
                  ]),
                ),

                const SizedBox(height: 12),

                // ── Info card ──────────────────────────────────────────────
                _infoCard([
                  if (t.email.isNotEmpty)
                    _InfoRow(
                        Icons.email_outlined, 'Email', t.email),
                  if (t.isClassTeacher &&
                      t.classTeacherOf != null) ...[
                    _InfoRow(Icons.class_outlined, 'Class Teacher of',
                        t.classTeacherOf!),
                    if (t.section.isNotEmpty)
                      _InfoRow(Icons.group_work_outlined, 'Section',
                          t.section),
                  ],
                  if (!t.isClassTeacher)
                    const _InfoRow(Icons.person_outline, 'Role',
                        'Subject Teacher'),
                ]),

                const SizedBox(height: 12),

                // ── Timetable section ──────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text('TIMETABLE',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade500,
                          letterSpacing: 0.8)),
                ),

                // Day selector
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: _days.map((d) {
                        final sel = d == _selectedDay;
                        return GestureDetector(
                          onTap: () =>
                              setState(() => _selectedDay = d),
                          child: AnimatedContainer(
                            duration:
                                const Duration(milliseconds: 150),
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 7),
                            decoration: BoxDecoration(
                              color: sel ? c : Colors.grey.shade100,
                              borderRadius:
                                  BorderRadius.circular(20),
                              border: Border.all(
                                  color: sel
                                      ? c
                                      : Colors.grey.shade300),
                            ),
                            child: Text(_dayAbbr[d]!,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: sel
                                        ? Colors.white
                                        : Colors.grey.shade600)),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

                const Divider(height: 1),

                // Slots
                Builder(builder: (_) {
                  final slots = _mySlots;
                  if (slots.isEmpty) {
                    return Container(
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          vertical: 28),
                      child: Column(children: [
                        Icon(Icons.event_available_outlined,
                            size: 40, color: Colors.grey.shade300),
                        const SizedBox(height: 8),
                        Text(
                            'No classes on ${_dayAbbr[_selectedDay]}',
                            style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade400)),
                      ]),
                    );
                  }
                  return Container(
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Column(
                      children: [
                        for (int i = 0; i < slots.length; i++) ...[
                          _SlotRow(slot: slots[i], color: c),
                          if (i < slots.length - 1)
                            const Divider(height: 20),
                        ],
                      ],
                    ),
                  );
                }),

                const SizedBox(height: 24),

                // ── Send Login Invite ──────────────────────────────────────
                if (widget.teacher.email.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: OutlinedButton.icon(
                      onPressed: () => _sendLoginInvite(context),
                      icon: const Icon(Icons.email_outlined,
                          color: AppTheme.primary),
                      label: const Text('Send Login Invite',
                          style: TextStyle(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppTheme.primary),
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // ── Delete button ──────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: OutlinedButton.icon(
                    onPressed: widget.onDelete,
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.red),
                    label: Text(context.tr('deleteTeacher'),
                        style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _infoCard(List<Widget> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(children: [
        for (int i = 0; i < rows.length; i++) ...[
          rows[i],
          if (i < rows.length - 1) const Divider(height: 16),
        ],
      ]),
    );
  }
}

// ── Info row ──────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String   label, value;
  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 18, color: Colors.grey.shade400),
      const SizedBox(width: 10),
      Text('$label: ',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
      Expanded(
        child: Text(value,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis),
      ),
    ]);
  }
}

// ── Slot row ──────────────────────────────────────────────────────────────────

class _Slot {
  final int    bell;
  final String className;
  final String subject;
  const _Slot(
      {required this.bell,
      required this.className,
      required this.subject});
}

class _SlotRow extends StatelessWidget {
  final _Slot slot;
  final Color color;
  const _SlotRow({required this.slot, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 36, height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text('${slot.bell}',
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15)),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(slot.className,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600)),
          if (slot.subject.isNotEmpty)
            Text(slot.subject,
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade500)),
        ]),
      ),
      Text('Bell ${slot.bell}',
          style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w500)),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Add / Edit Teacher Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _TeacherFormScreen extends StatefulWidget {
  final Teacher? existing;
  const _TeacherFormScreen({this.existing});

  @override
  State<_TeacherFormScreen> createState() => _TeacherFormScreenState();
}

class _TeacherFormScreenState extends State<_TeacherFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _subjectCtrl;  // used for "Other" custom input
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _designationCtrl;
  late final TextEditingController _qualificationCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _emergencyCtrl;
  final TextEditingController _newClassCtrl = TextEditingController();
  late bool _isClassTeacher;
  String? _classTeacherOf;
  String? _selectedSubject;   // selected from dropdown
  DateTime? _dateOfBirth;
  DateTime? _joiningDate;
  String? _photoUrl;          // existing remote photo
  String? _photoPath;         // newly-picked local photo
  bool _saving = false;
  List<String> _classes = [];
  bool _loadingClasses = true;
  bool _showAddClass   = false;

  bool get _isEdit => widget.existing != null;
  bool get _isOtherSubject => _selectedSubject == 'Other (specify)';

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    _nameCtrl          = TextEditingController(text: t?.name ?? '');
    _emailCtrl         = TextEditingController(text: t?.email ?? '');
    _phoneCtrl         = TextEditingController(text: t?.phone ?? '');
    _designationCtrl   = TextEditingController(text: t?.designation ?? '');
    _qualificationCtrl = TextEditingController(text: t?.qualification ?? '');
    _addressCtrl       = TextEditingController(text: t?.address ?? '');
    _emergencyCtrl     = TextEditingController(text: t?.emergencyContact ?? '');
    _isClassTeacher = t?.isClassTeacher ?? false;
    _classTeacherOf = t?.classTeacherOf;
    _dateOfBirth    = t?.dateOfBirth?.toDate();
    _joiningDate    = t?.joiningDate?.toDate();
    _photoUrl       = t?.photoUrl;

    // Pre-select subject from dropdown, or fall back to "Other (specify)"
    final existingSubject = t?.subject ?? '';
    if (existingSubject.isEmpty) {
      _selectedSubject = null;
      _subjectCtrl = TextEditingController();
    } else if (_kSubjects.contains(existingSubject)) {
      _selectedSubject = existingSubject;
      _subjectCtrl = TextEditingController();
    } else {
      _selectedSubject = 'Other (specify)';
      _subjectCtrl = TextEditingController(text: existingSubject);
    }

    _loadClasses();
  }

  Future<void> _loadClasses() async {
    final settings = await TimetableService.instance.getSettings();
    if (!mounted) return;
    final classes = List<String>.from(settings['classes'] as List);
    setState(() {
      _classes = classes;
      if (_classTeacherOf != null &&
          !classes.contains(_classTeacherOf)) {
        _classTeacherOf = null;
      }
      _loadingClasses = false;
    });
  }

  Future<void> _addNewClass() async {
    final name = _newClassCtrl.text.trim();
    if (name.isEmpty) return;
    if (_classes.contains(name)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.tr('classAlreadyExists'))));
      return;
    }
    final settings = await TimetableService.instance.getSettings();
    final classes =
        List<String>.from(settings['classes'] as List)..add(name);
    settings['classes']        = classes;
    settings['numberOfBells']  =
        (settings['bells'] as List? ?? []).length;
    await TimetableService.instance.saveSettings(BaseFirestoreService.currentSchoolId ?? 'default_school', settings);
    if (!mounted) return;
    setState(() {
      _classes        = classes;
      _classTeacherOf = name;
      _newClassCtrl.clear();
      _showAddClass   = false;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _subjectCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _designationCtrl.dispose();
    _qualificationCtrl.dispose();
    _addressCtrl.dispose();
    _emergencyCtrl.dispose();
    _newClassCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDOB() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(1985, 6, 15),
      firstDate: DateTime(1940),
      lastDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
      helpText: 'Select Date of Birth',
    );
    if (picked != null) setState(() => _dateOfBirth = picked);
  }

  Future<void> _pickJoiningDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _joiningDate ?? DateTime.now(),
      firstDate: DateTime(1980),
      lastDate: DateTime.now(),
      helpText: 'Select Joining Date',
    );
    if (picked != null) setState(() => _joiningDate = picked);
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: const Text('Take Photo'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Choose from Gallery'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null) return;
    final picked =
        await ImagePicker().pickImage(source: source, imageQuality: 70);
    if (picked != null && mounted) {
      setState(() => _photoPath = picked.path);
    }
  }

  void _removePhoto() => setState(() {
        _photoPath = null;
        _photoUrl  = null;
      });

  /// Upload a newly-picked photo to Firebase Storage and return its URL.
  /// Returns the existing URL when no new photo was picked.
  Future<String?> _resolvePhotoUrl(String teacherId) async {
    if (_photoPath == null) return _photoUrl;
    final schoolId = BaseFirestoreService.currentSchoolId ?? 'default_school';
    final ref = FirebaseStorage.instance
        .ref('schools/$schoolId/teachers/$teacherId.jpg');
    final bytes = await ImageUtils.compressAndStripExif(File(_photoPath!), quality: 70);
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return await ref.getDownloadURL();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final teacherId = widget.existing?.id ??
          DateTime.now().millisecondsSinceEpoch.toString();
      final photoUrl = await _resolvePhotoUrl(teacherId);
      final classTeacherOfVal = _isClassTeacher ? _classTeacherOf : null;
      String sectionVal = widget.existing?.section ?? '';
      if (_isClassTeacher && classTeacherOfVal != null) {
        sectionVal = Teacher.extractSection(classTeacherOfVal);
      }
      final teacher = Teacher(
        id: teacherId,
        name:    _nameCtrl.text.trim(),
        subject: _isOtherSubject
            ? _subjectCtrl.text.trim()
            : (_selectedSubject ?? ''),
        email:   _emailCtrl.text.trim().toLowerCase(),
        section: sectionVal,
        isClassTeacher: _isClassTeacher,
        classTeacherOf: classTeacherOfVal,
        schoolId: BaseFirestoreService.currentSchoolId ?? 'default_school',
        assignedClasses: widget.existing?.assignedClasses ?? const [],
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        dateOfBirth: _dateOfBirth != null
            ? Timestamp.fromDate(_dateOfBirth!)
            : null,
        photoUrl: photoUrl,
        designation: _designationCtrl.text.trim().isEmpty
            ? null
            : _designationCtrl.text.trim(),
        joiningDate: _joiningDate != null
            ? Timestamp.fromDate(_joiningDate!)
            : null,
        qualification: _qualificationCtrl.text.trim().isEmpty
            ? null
            : _qualificationCtrl.text.trim(),
        address: _addressCtrl.text.trim().isEmpty
            ? null
            : _addressCtrl.text.trim(),
        emergencyContact: _emergencyCtrl.text.trim().isEmpty
            ? null
            : _emergencyCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, teacher);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not save: $e'),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Teacher Details' : 'Add Teacher'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Profile photo ───────────────────────────────────────────
              Center(child: _buildPhotoPicker()),
              const SizedBox(height: 20),

              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.person_outline)),
                textCapitalization: TextCapitalization.words,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z ]')),
                ],
                maxLength: 50,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedSubject,
                decoration: const InputDecoration(
                  labelText: 'Subject',
                  prefixIcon: Icon(Icons.book_outlined),
                ),
                isExpanded: true,
                hint: Text(context.tr('selectASubject')),
                items: _kSubjects.map((s) => DropdownMenuItem(
                  value: s,
                  child: Text(s, overflow: TextOverflow.ellipsis),
                )).toList(),
                onChanged: (v) => setState(() {
                  _selectedSubject = v;
                  if (v != 'Other (specify)') _subjectCtrl.clear();
                }),
                validator: (_) =>
                    _selectedSubject == null ? 'Please select a subject' : null,
              ),
              // Custom subject field shown only when "Other (specify)" is chosen
              if (_isOtherSubject) ...[
                const SizedBox(height: 10),
                TextFormField(
                  controller: _subjectCtrl,
                  decoration: InputDecoration(
                    labelText: context.tr('specifySubject'),
                    prefixIcon: Icon(Icons.edit_outlined),
                  ),
                  textCapitalization: TextCapitalization.words,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z /&()]')),
                  ],
                  maxLength: 40,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  autofocus: true,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ],
              const SizedBox(height: 12),
              EmailTextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(
                    labelText: 'Email Address',
                    prefixIcon: Icon(Icons.email_outlined)),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneCtrl,
                decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    prefixIcon: Icon(Icons.phone_outlined)),
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 10,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null; // optional
                  if (v.trim().length != 10) return 'Must be 10 digits';
                  return null;
                },
              ),
              const SizedBox(height: 8),
              // Date of Birth picker
              GestureDetector(
                onTap: _pickDOB,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Date of Birth',
                    prefixIcon: const Icon(Icons.cake_outlined),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    suffixIcon: _dateOfBirth != null
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () =>
                                setState(() => _dateOfBirth = null),
                          )
                        : null,
                  ),
                  child: Text(
                    _dateOfBirth != null
                        ? '${_dateOfBirth!.day.toString().padLeft(2, '0')} / '
                            '${_dateOfBirth!.month.toString().padLeft(2, '0')} / '
                            '${_dateOfBirth!.year}'
                        : 'Tap to select',
                    style: TextStyle(
                        fontSize: 15,
                        color: _dateOfBirth != null
                            ? Colors.black87
                            : Colors.grey.shade500),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── Designation ─────────────────────────────────────────────
              TextFormField(
                controller: _designationCtrl,
                decoration: InputDecoration(
                    labelText: context.tr('designation'),
                    hintText: context.tr('designationHint'),
                    prefixIcon: Icon(Icons.badge_outlined),
                    counterText: ''),
                textCapitalization: TextCapitalization.words,
                maxLength: 40,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
              ),
              const SizedBox(height: 12),

              // ── Qualification ───────────────────────────────────────────
              TextFormField(
                controller: _qualificationCtrl,
                decoration: InputDecoration(
                    labelText: context.tr('qualification'),
                    hintText: 'e.g. M.Sc, B.Ed',
                    prefixIcon: Icon(Icons.school_outlined),
                    counterText: ''),
                textCapitalization: TextCapitalization.characters,
                maxLength: 60,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
              ),
              const SizedBox(height: 12),

              // ── Joining date picker ─────────────────────────────────────
              GestureDetector(
                onTap: _pickJoiningDate,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: context.tr('joiningDate'),
                    prefixIcon: const Icon(Icons.event_available_outlined),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    suffixIcon: _joiningDate != null
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () =>
                                setState(() => _joiningDate = null),
                          )
                        : null,
                  ),
                  child: Text(
                    _joiningDate != null
                        ? '${_joiningDate!.day.toString().padLeft(2, '0')} / '
                            '${_joiningDate!.month.toString().padLeft(2, '0')} / '
                            '${_joiningDate!.year}'
                        : 'Tap to select',
                    style: TextStyle(
                        fontSize: 15,
                        color: _joiningDate != null
                            ? Colors.black87
                            : Colors.grey.shade500),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── Emergency contact ───────────────────────────────────────
              TextFormField(
                controller: _emergencyCtrl,
                decoration: const InputDecoration(
                    labelText: 'Emergency Contact',
                    prefixIcon: Icon(Icons.contact_phone_outlined),
                    counterText: ''),
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 10,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null; // optional
                  if (v.trim().length != 10) return 'Must be 10 digits';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // ── Address ─────────────────────────────────────────────────
              TextFormField(
                controller: _addressCtrl,
                decoration: const InputDecoration(
                    labelText: 'Address',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.home_outlined)),
                textCapitalization: TextCapitalization.sentences,
                maxLines: 2,
                maxLength: 150,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
              ),
              const SizedBox(height: 8),

              // ── Class Teacher toggle ────────────────────────────────────
              Container(
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: _isClassTeacher
                      ? AppTheme.primary.withValues(alpha: 0.07)
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: _isClassTeacher
                          ? AppTheme.primary.withValues(alpha: 0.3)
                          : Colors.grey.shade300),
                ),
                child: SwitchListTile(
                  value: _isClassTeacher,
                  onChanged: (v) => setState(() {
                    _isClassTeacher = v;
                    if (!v) {
                      _classTeacherOf = null;
                    }
                  }),
                  activeColor: AppTheme.primary,
                  title: Text(
                    'Class Teacher',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _isClassTeacher
                            ? AppTheme.primaryDark
                            : Colors.grey.shade700),
                  ),
                  subtitle: Text(
                    _isClassTeacher
                        ? 'Can add & manage students'
                        : 'Cannot add students',
                    style: TextStyle(
                        fontSize: 11,
                        color: _isClassTeacher
                            ? AppTheme.primaryMid
                            : Colors.grey.shade500),
                  ),
                  dense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 2),
                ),
              ),

              // ── Class Teacher fields ────────────────────────────────────
              if (_isClassTeacher) ...[
                const SizedBox(height: 10),
                if (_loadingClasses)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else ...[
                  if (_classes.isNotEmpty && !_showAddClass)
                    DropdownButtonFormField<String>(
                      value: _classTeacherOf,
                      decoration: InputDecoration(
                        labelText: context.tr('classTeacherOf'),
                        prefixIcon: const Icon(Icons.class_outlined),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                      hint: Text(context.tr('selectClass')),
                      items: _classes
                          .map((c) => DropdownMenuItem(
                              value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _classTeacherOf = v),
                      validator: (_) =>
                          _isClassTeacher &&
                                  _classTeacherOf == null &&
                                  _classes.isNotEmpty &&
                                  !_showAddClass
                              ? 'Select a class'
                              : null,
                    ),

                  if (_showAddClass || _classes.isEmpty) ...[
                    if (_classes.isNotEmpty) const SizedBox(height: 6),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _newClassCtrl,
                          decoration: InputDecoration(
                            labelText: context.tr('newClassName'),
                            hintText: 'e.g. Class 6A',
                            prefixIcon: const Icon(
                                Icons.add_circle_outline,
                                color: AppTheme.primary),
                            border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                          ),
                          textCapitalization: TextCapitalization.words,
                          onSubmitted: (_) => _addNewClass(),
                          autofocus: _classes.isEmpty,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _addNewClass,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 15),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(10))),
                        child: const Text('Add'),
                      ),
                    ]),
                    if (_showAddClass && _classes.isNotEmpty)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => setState(() {
                            _showAddClass = false;
                            _newClassCtrl.clear();
                          }),
                          child: const Text('Cancel',
                              style: TextStyle(fontSize: 12)),
                        ),
                      ),
                  ],
                ],

              ],

              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(_isEdit ? 'Save Changes' : 'Add Teacher',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Profile photo picker ─────────────────────────────────────────────────
  Widget _buildPhotoPicker() {
    ImageProvider? image;
    if (_photoPath != null) {
      image = FileImage(File(_photoPath!));
    } else if (_photoUrl != null && _photoUrl!.isNotEmpty) {
      image = NetworkImage(_photoUrl!);
    }
    final hasPhoto = image != null;

    return Column(
      children: [
        Stack(
          children: [
            CircleAvatar(
              radius: 52,
              backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
              backgroundImage: image,
              child: hasPhoto
                  ? null
                  : const Icon(Icons.person,
                      size: 52, color: AppTheme.primary),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: GestureDetector(
                onTap: _pickPhoto,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.camera_alt,
                      size: 16, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: hasPhoto ? _removePhoto : _pickPhoto,
          child: Text(hasPhoto ? 'Remove Photo' : 'Add Photo',
              style: TextStyle(
                  fontSize: 12,
                  color: hasPhoto ? Colors.red : AppTheme.primary)),
        ),
      ],
    );
  }
}

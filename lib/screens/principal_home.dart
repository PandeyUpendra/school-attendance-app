import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../data/student_data.dart';
import '../services/auth_service.dart';
import 'role_selection_screen.dart';
import '../services/firestore_service.dart';
import '../services/role_permission_service.dart';
import '../services/timetable_service.dart';
import '../theme.dart';
import 'birthdays/birthdays_screen.dart';

class PrincipalHome extends StatefulWidget {
  const PrincipalHome({super.key});

  @override
  State<PrincipalHome> createState() => _PrincipalHomeState();
}

class _PrincipalHomeState extends State<PrincipalHome> {
  static const Color _accent = Color(0xFF1565C0);
  static const _categories = ['Academic', 'Sports', 'Cultural', 'Other'];
  static const _statuses = ['All', 'Open', 'In Progress', 'Resolved'];

  String _schoolId = '';
  String _principalName = '';

  // ── Overview ──
  bool _overviewLoading = true;
  double _todayAttendancePct = 0.0;
  int _totalTeachers = 0;
  int _totalStudents = 0;
  double _totalFeesCollected = 0.0;

  // ── Complaints ──
  bool _complaintsLoading = true;
  List<Map<String, dynamic>> _allComplaints = [];
  String _statusFilter = 'All';

  // ── Teacher activity ──
  bool _activityLoading = true;
  List<Map<String, dynamic>> _teacherActivity = [];

  // ── Leaderboard ──
  bool _lbLoading = false;
  String _lbCategory = 'Academic';
  List<Map<String, dynamic>> _lbEntries = [];

  // ── Attendance card ──
  bool _cardLoading = true;
  bool _cardError = false;
  int _cardPresent = 0;
  int _cardTotal = 0;
  List<Map<String, dynamic>> _classBreakdown = [];

  // ── Events ──
  bool _eventsLoading = true;
  List<Map<String, dynamic>> _events = [];
  bool _eventUploading = false;

  final _scrollCtrl = ScrollController();

  // My-created coordinators list
  List<Map<String, dynamic>> _myCoordinators = [];
  bool _coordListLoading = false;
  String _myEmail = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initUser());
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _initUser() async {
    final session = await AuthService().getSession();
    _myEmail = session?['email'] as String? ?? '';
    if (_myEmail.isNotEmpty) _principalName = _myEmail;

    await _loadAll();
    await _loadMyCoordinators();
  }

  Future<void> _loadMyCoordinators() async {
    if (_myEmail.isEmpty) return;
    setState(() => _coordListLoading = true);
    final users = await TimetableService().getUsersCreatedBy(_myEmail);
    if (!mounted) return;
    setState(() {
      _myCoordinators = users
          .where((u) => (u['role'] as String) == 'coordinator')
          .toList();
      _coordListLoading = false;
    });
  }

  void _showCreateCoordinatorSheet() {
    final nameCtrl  = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl  = TextEditingController();
    bool showPass   = false;
    bool saving     = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.admin_panel_settings_outlined,
                        color: AppTheme.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Text('Create Coordinator',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 20),
                _sheetField(nameCtrl, 'Full Name', Icons.person_outline),
                const SizedBox(height: 12),
                _sheetField(emailCtrl, 'Email Address', Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress),
                const SizedBox(height: 12),
                StatefulBuilder(
                  builder: (_, setSub) => TextField(
                    controller: passCtrl,
                    obscureText: !showPass,
                    maxLength: 50,
                    maxLengthEnforcement: MaxLengthEnforcement.enforced,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline,
                          color: AppTheme.primary),
                      suffixIcon: IconButton(
                        icon: Icon(
                            showPass
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.grey.shade400, size: 18),
                        onPressed: () {
                          setLocal(() => showPass = !showPass);
                        },
                      ),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                            color: AppTheme.primary, width: 1.5),
                      ),
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: saving
                        ? null
                        : () async {
                            final name  = nameCtrl.text.trim();
                            final email = emailCtrl.text.trim().toLowerCase();
                            final pass  = passCtrl.text.trim();
                            if (name.isEmpty) return;
                            if (email.isEmpty ||
                                !RegExp(r'^[^@]+@[^@]+\.[^@]+$')
                                    .hasMatch(email)) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Enter a valid email')));
                              return;
                            }
                            if (pass.length < 6) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Password must be at least 6 characters')));
                              return;
                            }
                            setLocal(() => saving = true);
                            try {
                              await TimetableService().addAllowedUser(
                                email, pass, 'coordinator',
                                createdByEmail: _myEmail,
                                createdByRole:  'principal',
                              );
                              await FirebaseFirestore.instance
                                  .collection('allowed_users')
                                  .doc(email)
                                  .update({'name': name});
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (mounted) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(
                                  content:
                                      Text('Coordinator $email created'),
                                  backgroundColor: AppTheme.success,
                                ));
                                await _loadMyCoordinators();
                              }
                            } catch (e) {
                              setLocal(() => saving = false);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error: $e')));
                              }
                            }
                          },
                    child: saving
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Create Coordinator Account',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sheetField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppTheme.primary),
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
        ),
      ),
    );
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadAttendanceCard(),
      _loadOverview(),
      _loadComplaints(),
      _loadTeacherActivity(),
      _loadLeaderboard(),
      _loadEvents(),
    ]);
  }

  // ── Attendance card ───────────────────────────────────────────────────────

  Future<void> _loadAttendanceCard() async {
    if (mounted) setState(() { _cardLoading = true; _cardError = false; });
    try {
      final db = FirebaseFirestore.instance;
      final snap = await db.collection('students').get();

      final Map<String, int> classTotals = {};
      for (final doc in snap.docs) {
        final data = doc.data();
        final cls = data['className'] as String? ?? '';
        if (cls.isEmpty) continue;
        classTotals[cls] = (classTotals[cls] ?? 0) + 1;
      }

      final today = _dateKey(DateTime.now());
      final Map<String, int> classPresent = {};
      for (final cls in classTotals.keys) {
        try {
          final summary = await FirestoreService.loadAttendanceSummary(
              schoolId: _schoolId, classId: cls, date: today);
          classPresent[cls] = summary != null ? (summary['present'] as int? ?? 0) : 0;
        } catch (_) {
          classPresent[cls] = 0;
        }
      }

      final int totalStudents = classTotals.values.fold(0, (s, v) => s + v);
      final int totalPresent = classPresent.values.fold(0, (s, v) => s + v);

      final breakdown = classTotals.entries.map((e) => {
        'className': e.key,
        'total': e.value,
        'present': classPresent[e.key] ?? 0,
      }).toList()
        ..sort((a, b) {
          final at = a['total'] as int;
          final bt = b['total'] as int;
          final aPct = at > 0 ? (a['present'] as int) / at : 0.0;
          final bPct = bt > 0 ? (b['present'] as int) / bt : 0.0;
          return aPct.compareTo(bPct);
        });

      if (mounted) {
        setState(() {
          _cardPresent = totalPresent;
          _cardTotal = totalStudents;
          _classBreakdown = breakdown;
          _cardLoading = false;
          _cardError = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _cardLoading = false; _cardError = true; });
    }
  }

  // ── Overview ──────────────────────────────────────────────────────────────

  Future<void> _loadOverview() async {
    if (mounted) setState(() => _overviewLoading = true);
    try {
      final users = await FirestoreService.getUsersBySchool(_schoolId);
      final teacherCount = users.where((u) {
        final r = u['role'] as String? ?? '';
        return r == 'teacher' || r == 'subjectTeacher';
      }).length;
      final studentCount =
          classStudents.values.fold(0, (s, l) => s + l.length);

      final today = _dateKey(DateTime.now());
      int present = 0, total = 0;
      for (final cls in classStudents.keys) {
        final summary = await FirestoreService.loadAttendanceSummary(
            schoolId: _schoolId, classId: cls, date: today);
        if (summary != null) {
          present += (summary['present'] as int? ?? 0);
          total += classStudents[cls]!.length;
        }
      }

      double feesTotal = 0.0;
      for (final cls in classStudents.keys) {
        for (final st in classStudents[cls]!) {
          try {
            final profile = await FirestoreService.loadStudentProfile(
                schoolId: _schoolId, classId: cls, roll: st.roll);
            if (profile != null && profile['feesPaid'] == true) {
              feesTotal +=
                  (profile['feesAmount'] as num? ?? 5000).toDouble();
            }
          } catch (_) {}
        }
      }

      if (mounted) {
        setState(() {
          _totalTeachers = teacherCount;
          _totalStudents = studentCount;
          _todayAttendancePct = total > 0 ? present / total : 0.0;
          _totalFeesCollected = feesTotal;
          _overviewLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _overviewLoading = false);
    }
  }

  // ── Complaints ────────────────────────────────────────────────────────────

  Future<void> _loadComplaints() async {
    if (mounted) setState(() => _complaintsLoading = true);
    try {
      final list =
          await FirestoreService.getSchoolComplaints(schoolId: _schoolId);
      if (mounted) setState(() => _allComplaints = list);
    } catch (_) {}
    if (mounted) setState(() => _complaintsLoading = false);
  }

  List<Map<String, dynamic>> get _filteredComplaints {
    if (_statusFilter == 'All') return _allComplaints;
    return _allComplaints
        .where((c) => (c['status'] as String? ?? 'Open') == _statusFilter)
        .toList();
  }

  // ── Teacher Activity ──────────────────────────────────────────────────────

  Future<void> _loadTeacherActivity() async {
    if (mounted) setState(() => _activityLoading = true);
    try {
      final users = await FirestoreService.getUsersBySchool(_schoolId);
      final teachers = users.where((u) {
        final r = u['role'] as String? ?? '';
        return r == 'teacher' || r == 'subjectTeacher';
      }).toList();

      final today = _dateKey(DateTime.now());
      final List<Map<String, dynamic>> activity = [];
      for (final t in teachers) {
        final classIds = List<String>.from(t['classIds'] as List? ?? []);
        int classesTaken = 0;
        for (final cls in classIds) {
          try {
            final att = await FirestoreService.loadAttendance(
                schoolId: _schoolId, classId: cls, date: today);
            if (att != null) classesTaken++;
          } catch (_) {}
        }
        activity.add({...t, 'classesTaken': classesTaken});
      }
      if (mounted) setState(() => _teacherActivity = activity);
    } catch (_) {}
    if (mounted) setState(() => _activityLoading = false);
  }

  // ── Leaderboard ───────────────────────────────────────────────────────────

  Future<void> _loadLeaderboard() async {
    if (mounted) setState(() => _lbLoading = true);
    try {
      final entries = await FirestoreService.getLeaderboardEntries(
          schoolId: _schoolId, category: _lbCategory);
      if (mounted) setState(() => _lbEntries = entries);
    } catch (_) {}
    if (mounted) setState(() => _lbLoading = false);
  }

  // ── Events ────────────────────────────────────────────────────────────────

  Future<void> _loadEvents() async {
    if (mounted) setState(() => _eventsLoading = true);
    try {
      final evs =
          await FirestoreService.getSchoolEvents(schoolId: _schoolId);
      if (mounted) setState(() => _events = evs);
    } catch (_) {}
    if (mounted) setState(() => _eventsLoading = false);
  }

  // ── Event upload / delete ─────────────────────────────────────────────────

  Future<void> _pickAndUploadEvent() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(imageQuality: 75);
    if (picked.isEmpty) return;

    String? title;
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: const Text('Event Title'),
          content: TextField(
            controller: ctrl,
            textCapitalization: TextCapitalization.words,
            decoration:
                const InputDecoration(hintText: 'e.g. Annual Sports Day'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: _accent, foregroundColor: Colors.white),
              onPressed: () {
                title = ctrl.text.trim();
                Navigator.pop(ctx);
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
    if (title == null || title!.isEmpty) return;

    setState(() => _eventUploading = true);
    try {
      final List<String> urls = [];
      for (final f in picked) {
        final ref = FirebaseStorage.instance.ref(
            'schools/$_schoolId/events/${DateTime.now().millisecondsSinceEpoch}_${f.name}');
        await ref.putFile(File(f.path));
        urls.add(await ref.getDownloadURL());
      }
      await FirestoreService.addSchoolEvent(
        schoolId: _schoolId,
        event: {
          'title': title,
          'photoUrls': urls,
          'date': Timestamp.fromDate(DateTime.now()),
        },
      );
      await _loadEvents();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Upload failed: $e'),
            behavior: SnackBarBehavior.floating));
      }
    }
    if (mounted) setState(() => _eventUploading = false);
  }

  Future<void> _deleteEvent(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Event?'),
        content:
            const Text('This will permanently remove this event and its photos.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await FirestoreService.deleteSchoolEvent(
        schoolId: _schoolId, eventId: id);
    await _loadEvents();
  }

  // ── Leaderboard sheet ─────────────────────────────────────────────────────

  void _showAddEntrySheet([Map<String, dynamic>? existing]) {
    final nameCtrl =
        TextEditingController(text: existing?['name'] as String? ?? '');
    final clsCtrl =
        TextEditingController(text: existing?['class'] as String? ?? '');
    final scoreCtrl = TextEditingController(
        text: (existing?['score'] as num?)?.toString() ?? '');
    final rankCtrl = TextEditingController(
        text: (existing?['rank'] as num?)?.toString() ?? '');
    String cat = existing?['category'] as String? ?? _lbCategory;
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('Leaderboard Entry',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    const Spacer(),
                    IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: cat,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: _categories
                      .map((c) =>
                          DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setInner(() => cat = v);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Student Name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: clsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Class',
                    prefixIcon: Icon(Icons.class_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: scoreCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Score',
                          prefixIcon: Icon(Icons.score_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: rankCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Rank',
                          prefixIcon: Icon(Icons.military_tech_outlined),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: saving
                        ? null
                        : () async {
                            final name = nameCtrl.text.trim();
                            if (name.isEmpty) return;
                            setInner(() => saving = true);
                            final data = {
                              'category': cat,
                              'name': name,
                              'class': clsCtrl.text.trim(),
                              'score': int.tryParse(scoreCtrl.text) ?? 0,
                              'rank': int.tryParse(rankCtrl.text) ?? 0,
                            };
                            try {
                              if (existing != null &&
                                  existing['id'] != null) {
                                await FirestoreService
                                    .updateLeaderboardEntry(
                                  schoolId: _schoolId,
                                  docId: existing['id'] as String,
                                  data: data,
                                );
                              } else {
                                await FirestoreService.addLeaderboardEntry(
                                  schoolId: _schoolId,
                                  entry: data,
                                );
                              }
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (mounted) setState(() => _lbCategory = cat);
                              await _loadLeaderboard();
                            } catch (_) {
                              setInner(() => saving = false);
                            }
                          },
                    child: saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : Text(existing != null
                            ? 'Update Entry'
                            : 'Add Entry'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Complaint detail sheet ─────────────────────────────────────────────────

  void _showComplaintDetail(Map<String, dynamic> complaint) {
    final id = complaint['id'] as String? ?? '';
    String status = complaint['status'] as String? ?? 'Open';
    final noteCtrl = TextEditingController(
        text: complaint['resolutionNote'] as String? ?? '');
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.report_outlined, color: Colors.red),
                    const SizedBox(width: 8),
                    const Text('Complaint Detail',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    const Spacer(),
                    IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const Divider(),
                _detailRow(
                    'Student', complaint['studentName'] as String? ?? '—'),
                _detailRow(
                    'Class', complaint['className'] as String? ?? '—'),
                _detailRow(
                    'To', complaint['recipientRole'] as String? ?? '—'),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Text(complaint['complaintText'] as String? ?? '',
                      style:
                          const TextStyle(fontSize: 14, height: 1.5)),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: status,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    prefixIcon: Icon(Icons.flag_outlined),
                    isDense: true,
                  ),
                  items: ['Open', 'In Progress', 'Resolved']
                      .map((s) =>
                          DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setInner(() => status = v);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Resolution Note (optional)',
                    alignLabelWithHint: true,
                    prefixIcon: Padding(
                      padding: EdgeInsets.only(bottom: 48),
                      child: Icon(Icons.note_outlined),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.save_rounded),
                    label: const Text('Save Changes'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: saving
                        ? null
                        : () async {
                            setInner(() => saving = true);
                            await FirestoreService.updateComplaint(
                              schoolId: _schoolId,
                              complaintId: id,
                              data: {
                                'status': status,
                                if (noteCtrl.text.trim().isNotEmpty)
                                  'resolutionNote': noteCtrl.text.trim(),
                              },
                            );
                            final idx = _allComplaints
                                .indexWhere((c) => c['id'] == id);
                            if (idx != -1) {
                              setState(() {
                                _allComplaints[idx]['status'] = status;
                                if (noteCtrl.text.trim().isNotEmpty) {
                                  _allComplaints[idx]['resolutionNote'] =
                                      noteCtrl.text.trim();
                                }
                              });
                            }
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                          },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _dateKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  Widget _detailRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 72,
              child: Text('$label:',
                  style:
                      const TextStyle(color: Colors.grey, fontSize: 13)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ],
        ),
      );

  ({Color color, IconData icon}) _statusInfo(String status) {
    switch (status) {
      case 'Resolved':
        return (
          color: Colors.green.shade600,
          icon: Icons.check_circle_outline
        );
      case 'In Progress':
        return (
          color: Colors.amber.shade700,
          icon: Icons.hourglass_bottom_outlined
        );
      default:
        return (
          color: Colors.red.shade600,
          icon: Icons.radio_button_unchecked
        );
    }
  }

  Widget _sectionHeader(String title, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                color: _accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1565C0))),
            const Spacer(),
            if (trailing != null) trailing,
          ],
        ),
      );

  Widget _pCard({required Widget child, EdgeInsets? margin}) => Container(
        margin: margin ??
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color ?? Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
                color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
          ],
        ),
        child: child,
      );

  void _confirmSignOut() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out?'),
        content: const Text('You will be returned to the login screen.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await AuthService().clearSession();
              if (!mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                    builder: (_) => const RoleSelectionScreen()),
                (_) => false,
              );
            },
            child:
                const Text('Sign Out', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ── Attendance card sheet ─────────────────────────────────────────────────

  void _showClassBreakdownSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, ctrl) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  const Text('Class-wise Attendance',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const Spacer(),
                  Text('Worst first',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: _classBreakdown.isEmpty
                  ? Center(
                      child: Text('No data available',
                          style: TextStyle(color: Colors.grey.shade500)))
                  : ListView.builder(
                      controller: ctrl,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: _classBreakdown.length,
                      itemBuilder: (_, i) {
                        final c = _classBreakdown[i];
                        final cls = c['className'] as String;
                        final total = c['total'] as int;
                        final present = c['present'] as int;
                        final pct = total > 0 ? present / total * 100 : 0.0;
                        final color = pct >= 90
                            ? Colors.green.shade600
                            : pct >= 75
                                ? Colors.amber.shade700
                                : Colors.red.shade600;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(cls,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600, fontSize: 13)),
                              ),
                              Text('$present / $total',
                                  style: TextStyle(
                                      fontSize: 13, color: Colors.grey.shade600)),
                              const SizedBox(width: 12),
                              Container(
                                width: 58,
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${pct.toStringAsFixed(0)}%',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: color,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceCard() {
    if (_cardLoading) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        height: 148,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))
          ],
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_cardError) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))
          ],
        ),
        child: Column(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 36),
            const SizedBox(height: 8),
            Text('Could not load data. Pull to refresh.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      );
    }

    final pct = _cardTotal > 0 ? _cardPresent / _cardTotal * 100 : 0.0;
    final Color pctColor = pct >= 90
        ? Colors.green.shade600
        : pct >= 75
            ? Colors.amber.shade700
            : Colors.red.shade600;

    return GestureDetector(
      onTap: _showClassBreakdownSheet,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [pctColor.withOpacity(0.80), pctColor],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: pctColor.withOpacity(0.30),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ],
        ),
        child: Column(
          children: [
            Text(
              '$_cardPresent / $_cardTotal',
              style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
            ),
            const SizedBox(height: 4),
            const Text(
              'Students Present Today',
              style: TextStyle(
                  fontSize: 14,
                  color: Colors.white,
                  fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.25),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${pct.toStringAsFixed(1)}% attendance',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
              ),
            ),
            const SizedBox(height: 8),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Tap to see class-wise breakdown',
                    style: TextStyle(fontSize: 12, color: Colors.white70)),
                SizedBox(width: 4),
                Icon(Icons.arrow_forward_ios, size: 10, color: Colors.white70),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── My Coordinators ───────────────────────────────────────────────────────

  Widget _buildMyCoordinatorsSection() {
    if (_coordListLoading) {
      return const _ShimmerList(
          count: 2, margin: EdgeInsets.symmetric(horizontal: 16));
    }
    if (_myCoordinators.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.person_add_alt_1_outlined,
                  size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 8),
              Text('No coordinators created yet',
                  style: TextStyle(color: Colors.grey.shade500)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Create Coordinator'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accent,
                  side: BorderSide(color: _accent.withOpacity(0.4)),
                ),
                onPressed: _showCreateCoordinatorSheet,
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _myCoordinators.length,
      itemBuilder: (_, i) {
        final u = _myCoordinators[i];
        final email     = u['email'] as String;
        final createdAt = u['createdAt'];
        String dateStr  = '';
        if (createdAt is Timestamp) {
          final dt = createdAt.toDate();
          dateStr = '${dt.day}/${dt.month}/${dt.year}';
        }
        return _pCard(
          margin: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: _accent.withOpacity(0.12),
                child: Text(
                  email.isNotEmpty ? email[0].toUpperCase() : 'C',
                  style: const TextStyle(
                      color: _accent, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(email,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
                        overflow: TextOverflow.ellipsis),
                    if (dateStr.isNotEmpty)
                      Text('Created: $dateStr',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _accent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Coordinator',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _accent)),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Principal Dashboard',
                style:
                    TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text(_principalName,
                style:
                    const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh all',
            onPressed: _loadAll,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: _confirmSignOut,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateCoordinatorSheet,
        backgroundColor: AppTheme.accent,
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Create Coordinator'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: CustomScrollView(
          controller: _scrollCtrl,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildAttendanceCard()),

            // ── Birthday banner + tile ─────────────────────────────────────
            SliverToBoxAdapter(
              child: BirthdayBanner(
                role: 'principal',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const BirthdaysScreen(role: 'principal'),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: _BirthdayTile(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          const BirthdaysScreen(role: 'principal'),
                    ),
                  ),
                ),
              ),
            ),

            SliverToBoxAdapter(
                child: _sectionHeader('School Overview')),
            SliverToBoxAdapter(child: _buildOverviewSection()),

            SliverToBoxAdapter(
              child: _sectionHeader(
                'Complaints',
                trailing: Text(
                  '${_filteredComplaints.length} shown',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
            ),
            SliverToBoxAdapter(child: _buildComplaintsSection()),

            SliverToBoxAdapter(
                child: _sectionHeader('Teacher Activity Today')),
            SliverToBoxAdapter(child: _buildTeacherActivitySection()),

            SliverToBoxAdapter(
              child: _sectionHeader(
                'Leaderboard',
                trailing: IconButton(
                  icon: const Icon(Icons.add_circle_outline,
                      color: _accent, size: 22),
                  tooltip: 'Add entry',
                  onPressed: _showAddEntrySheet,
                ),
              ),
            ),
            SliverToBoxAdapter(child: _buildLeaderboardSection()),

            SliverToBoxAdapter(
              child: _sectionHeader(
                'School Events',
                trailing: _eventUploading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: _accent)))
                    : IconButton(
                        icon: const Icon(
                            Icons.add_photo_alternate_outlined,
                            color: _accent,
                            size: 22),
                        tooltip: 'Upload event photos',
                        onPressed: _pickAndUploadEvent,
                      ),
              ),
            ),
            SliverToBoxAdapter(child: _buildEventsSection()),

            SliverToBoxAdapter(
                child: _sectionHeader('My Coordinators',
                    trailing: IconButton(
                      icon: const Icon(Icons.add_circle_outline,
                          color: _accent, size: 22),
                      tooltip: 'Create Coordinator',
                      onPressed: _showCreateCoordinatorSheet,
                    ))),
            SliverToBoxAdapter(child: _buildMyCoordinatorsSection()),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Section builders
  // ══════════════════════════════════════════════════════════════════════════

  // ── Overview 2×2 grid ─────────────────────────────────────────────────────

  Widget _buildOverviewSection() {
    if (_overviewLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.55,
          children:
              List.generate(4, (_) => const _ShimmerBox(height: 80, radius: 12)),
        ),
      );
    }

    final cards = [
      _OverviewCard(
        icon: Icons.how_to_reg_outlined,
        label: "Today's Attendance",
        value: '${(_todayAttendancePct * 100).toStringAsFixed(1)}%',
        color: _accent,
        sub: _todayAttendancePct >= 0.9
            ? 'Excellent'
            : _todayAttendancePct >= 0.75
                ? 'Good'
                : 'Needs Attention',
      ),
      _OverviewCard(
        icon: Icons.people_outline,
        label: 'Active Teachers',
        value: '$_totalTeachers',
        color: const Color(0xFF6A1B9A),
        sub: 'Across all classes',
      ),
      _OverviewCard(
        icon: Icons.school_outlined,
        label: 'Total Students',
        value: '$_totalStudents',
        color: const Color(0xFF00897B),
        sub: '${classStudents.length} classes',
      ),
      _OverviewCard(
        icon: Icons.currency_rupee_outlined,
        label: 'Fees Collected',
        value: '₹${_totalFeesCollected.toStringAsFixed(0)}',
        color: const Color(0xFFE65100),
        sub: 'This month',
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.55,
        children: cards,
      ),
    );
  }

  // ── Complaints ────────────────────────────────────────────────────────────

  Widget _buildComplaintsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Filter chips
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _statuses.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final s = _statuses[i];
              final selected = _statusFilter == s;
              return FilterChip(
                label: Text(s,
                    style: TextStyle(
                        fontSize: 12,
                        color: selected ? Colors.white : _accent,
                        fontWeight: FontWeight.w600)),
                selected: selected,
                selectedColor: _accent,
                backgroundColor: _accent.withOpacity(0.08),
                checkmarkColor: Colors.white,
                onSelected: (_) => setState(() => _statusFilter = s),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        if (_complaintsLoading)
          const _ShimmerList(
              count: 3,
              margin: EdgeInsets.symmetric(horizontal: 16))
        else if (_filteredComplaints.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.inbox_outlined,
                      size: 52, color: Colors.grey.shade300),
                  const SizedBox(height: 10),
                  Text(
                    _statusFilter == 'All'
                        ? 'No complaints yet'
                        : 'No $_statusFilter complaints',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _filteredComplaints.length,
            itemBuilder: (_, i) {
              final c = _filteredComplaints[i];
              final status = c['status'] as String? ?? 'Open';
              final si = _statusInfo(status);
              final createdAt = c['createdAt'];
              String dateStr = '';
              if (createdAt != null) {
                try {
                  final dt =
                      (createdAt as dynamic).toDate() as DateTime;
                  dateStr = '${dt.day}/${dt.month}/${dt.year}';
                } catch (_) {}
              }
              return GestureDetector(
                onTap: () => _showComplaintDetail(c),
                child: _pCard(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c['studentName'] as String? ?? '—',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14)),
                            Text(
                              '${c['className'] ?? ''} · To: ${c['recipientRole'] ?? ''}',
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12),
                            ),
                            if (dateStr.isNotEmpty)
                              Text(dateStr,
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 11)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: si.color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: si.color.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(si.icon,
                                size: 11, color: si.color),
                            const SizedBox(width: 3),
                            Text(status,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: si.color,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  // ── Teacher Activity ──────────────────────────────────────────────────────

  Widget _buildTeacherActivitySection() {
    if (_activityLoading) {
      return const _ShimmerList(
          count: 4,
          margin: EdgeInsets.symmetric(horizontal: 16));
    }
    if (_teacherActivity.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.people_outline,
                  size: 52, color: Colors.grey.shade300),
              const SizedBox(height: 10),
              Text('No teachers found',
                  style: TextStyle(color: Colors.grey.shade500)),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _teacherActivity.length,
      itemBuilder: (_, i) {
        final t = _teacherActivity[i];
        final name = t['name'] as String? ?? 'Teacher';
        final email = t['email'] as String? ?? '';
        final role = t['role'] as String? ?? 'teacher';
        final classesTaken = t['classesTaken'] as int? ?? 0;
        final classIds = List<String>.from(t['classIds'] as List? ?? []);
        final lastActiveDt = t['lastActive'];

        String lastActiveStr = 'No recent activity';
        if (lastActiveDt != null) {
          try {
            final dt = (lastActiveDt as dynamic).toDate() as DateTime;
            final diff = DateTime.now().difference(dt);
            if (diff.inMinutes < 60) {
              lastActiveStr = '${diff.inMinutes}m ago';
            } else if (diff.inHours < 24) {
              lastActiveStr = '${diff.inHours}h ago';
            } else {
              lastActiveStr = '${diff.inDays}d ago';
            }
          } catch (_) {}
        }

        final isActive = classesTaken > 0;
        final roleColor =
            role == 'subjectTeacher' ? Colors.teal : _accent;

        return _pCard(
          margin: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: roleColor.withOpacity(0.12),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'T',
                  style: TextStyle(
                      color: roleColor, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14)),
                        ),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isActive
                                ? Colors.green
                                : Colors.grey.shade300,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isActive ? 'Active' : 'Inactive',
                          style: TextStyle(
                              fontSize: 11,
                              color: isActive
                                  ? Colors.green
                                  : Colors.grey),
                        ),
                      ],
                    ),
                    Text(email,
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.access_time,
                            size: 12, color: Colors.grey.shade400),
                        const SizedBox(width: 4),
                        Text(lastActiveStr,
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500)),
                        const SizedBox(width: 12),
                        Icon(
                          Icons.check_circle_outline,
                          size: 12,
                          color: classesTaken > 0
                              ? Colors.green
                              : Colors.grey.shade300,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$classesTaken/${classIds.length} classes today',
                          style: TextStyle(
                              fontSize: 11,
                              color: classesTaken > 0
                                  ? Colors.green
                                  : Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Leaderboard ───────────────────────────────────────────────────────────

  Widget _buildLeaderboardSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category filter chips
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final cat = _categories[i];
              final sel = _lbCategory == cat;
              return FilterChip(
                label: Text(cat,
                    style: TextStyle(
                        fontSize: 12,
                        color: sel ? Colors.white : _accent,
                        fontWeight: FontWeight.w600)),
                selected: sel,
                selectedColor: _accent,
                backgroundColor: _accent.withOpacity(0.08),
                checkmarkColor: Colors.white,
                onSelected: (_) async {
                  setState(() => _lbCategory = cat);
                  await _loadLeaderboard();
                },
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        if (_lbLoading)
          const _ShimmerList(
              count: 3,
              margin: EdgeInsets.symmetric(horizontal: 16))
        else if (_lbEntries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.emoji_events_outlined,
                      size: 52, color: Colors.grey.shade300),
                  const SizedBox(height: 10),
                  Text('No $_lbCategory entries yet',
                      style: TextStyle(color: Colors.grey.shade500)),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add First Entry'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _accent,
                      side: BorderSide(color: _accent.withOpacity(0.4)),
                    ),
                    onPressed: _showAddEntrySheet,
                  ),
                ],
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _lbEntries.length,
            itemBuilder: (_, i) {
              final e = _lbEntries[i];
              final rank = e['rank'] as int? ?? (i + 1);
              final name = e['name'] as String? ?? '—';
              final cls = e['class'] as String? ?? '';
              final score = e['score'] as int? ?? 0;

              final medalColors = [
                const Color(0xFFFFD700),
                const Color(0xFFC0C0C0),
                const Color(0xFFCD7F32),
              ];
              final medalText = [
                const Color(0xFFB8860B),
                Colors.grey,
                const Color(0xFF8B4513),
              ];

              final isTop = rank >= 1 && rank <= 3;
              final medalBg =
                  isTop ? medalColors[rank - 1] : _accent;
              final medalFg =
                  isTop ? medalText[rank - 1] : _accent;

              return _pCard(
                margin: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: medalBg.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text('#$rank',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: medalFg)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14)),
                          if (cls.isNotEmpty)
                            Text(cls,
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    ),
                    Text('$score pts',
                        style: const TextStyle(
                            color: Color(0xFF1565C0),
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                    const SizedBox(width: 4),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert,
                          size: 18, color: Colors.grey),
                      onSelected: (v) async {
                        if (v == 'edit') {
                          _showAddEntrySheet(e);
                        } else if (v == 'delete') {
                          await FirestoreService.deleteLeaderboardEntry(
                              schoolId: _schoolId,
                              docId: e['id'] as String);
                          await _loadLeaderboard();
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete',
                                style: TextStyle(color: Colors.red))),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  // ── Events ────────────────────────────────────────────────────────────────

  Widget _buildEventsSection() {
    if (_eventsLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.2,
          children: List.generate(
              4, (_) => const _ShimmerBox(height: 100, radius: 12)),
        ),
      );
    }
    if (_events.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.event_outlined,
                  size: 52, color: Colors.grey.shade300),
              const SizedBox(height: 10),
              Text('No events yet',
                  style: TextStyle(color: Colors.grey.shade500)),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Upload Event'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accent,
                  side: BorderSide(color: _accent.withOpacity(0.4)),
                ),
                onPressed: _pickAndUploadEvent,
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _events.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final ev = _events[i];
          final title = ev['title'] as String? ?? 'Event';
          final urls = List<String>.from(ev['photoUrls'] as List? ?? []);
          final id = ev['id'] as String;
          final evDate = ev['date'];
          String dateStr = '';
          if (evDate != null) {
            try {
              final dt = (evDate as dynamic).toDate() as DateTime;
              dateStr = '${dt.day}/${dt.month}/${dt.year}';
            } catch (_) {}
          }

          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color ?? Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    offset: Offset(0, 2))
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.event_rounded,
                          size: 18, color: _accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14)),
                            if (dateStr.isNotEmpty)
                              Text(dateStr,
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            size: 20, color: Colors.red),
                        onPressed: () => _deleteEvent(id),
                        tooltip: 'Delete event',
                      ),
                    ],
                  ),
                ),
                if (urls.isNotEmpty)
                  SizedBox(
                    height: 100,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: urls.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(width: 8),
                      itemBuilder: (_, j) => ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          urls[j],
                          width: 90,
                          height: 90,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 90,
                            height: 90,
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.broken_image_outlined,
                                color: Colors.grey),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// Overview stat card
// ══════════════════════════════════════════════════════════════════════════

class _OverviewCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final String sub;

  const _OverviewCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color ?? Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
              color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const Spacer(),
              Text(value,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: color)),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 11)),
              Text(sub,
                  style: TextStyle(
                      color: Colors.grey.shade500, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// Shimmer widgets
// ══════════════════════════════════════════════════════════════════════════

class _ShimmerBox extends StatefulWidget {
  final double height;
  final double width;
  final double radius;

  const _ShimmerBox({
    this.height = 16,
    this.width = double.infinity,
    this.radius = 8,
  });

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          color: Colors.grey.shade300.withOpacity(_anim.value),
        ),
      ),
    );
  }
}

class _ShimmerList extends StatelessWidget {
  final int count;
  final EdgeInsets margin;

  const _ShimmerList({required this.count, required this.margin});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        count,
        (_) => Container(
          margin: margin.copyWith(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color ?? Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, 2))
            ],
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ShimmerBox(height: 14, width: 140, radius: 4),
              SizedBox(height: 8),
              _ShimmerBox(height: 12, width: 220, radius: 4),
              SizedBox(height: 6),
              _ShimmerBox(height: 12, width: 100, radius: 4),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Birthday tile for principal home ─────────────────────────────────────────

class _BirthdayTile extends StatelessWidget {
  final VoidCallback onTap;
  const _BirthdayTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFD81B60).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text('🎂', style: TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Birthdays',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 2),
                Text(
                  'Staff and student birthday wishes & calendar',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right,
              color: Colors.grey, size: 20),
        ]),
      ),
    );
  }
}

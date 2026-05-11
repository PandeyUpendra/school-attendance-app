import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import '../theme.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/student.dart';
import '../services/auth_service.dart';
import '../services/student_service.dart';
import '../services/timetable_service.dart';
import '../services/notification_service.dart';
import '../services/offline_queue_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  AttendanceScreen
// ─────────────────────────────────────────────────────────────────────────────

class AttendanceScreen extends StatefulWidget {
  final String className;
  final String section;
  const AttendanceScreen({
    super.key,
    required this.className,
    this.section = '',
  });

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final _service      = StudentService();
  final _offlineQueue = OfflineQueueService();
  final _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectSub;
  StreamSubscription<List<Student>>? _studentSub;

  List<Student>    _students   = [];
  Map<int, String> _attendance = {}; // roll → 'Present' | 'Leave' | 'Absent'
  bool   _loading        = true;
  bool   _dirty          = false;
  bool   _isOnline       = true;   // current connectivity status
  bool   _savedOffline   = false;  // pending offline records queued
  int    _pendingCount   = 0;      // items waiting to sync
  String _search         = '';
  bool   _alreadySaved   = false; // today's attendance doc exists
  bool   _isMarking      = false; // user is actively marking attendance
  bool   _noAssignment   = false; // teacher has no assigned class/section

  // Effective class, section, and teacher — fetched from Firestore on load,
  // so the screen always uses the teacher's actual assignment.
  String  _className = '';
  String  _section   = '';
  String? _teacherId;

  // When section is set, use a section-scoped key for attendance storage
  // so Section A and Section B never overwrite each other's attendance doc.
  String get _attendanceKey =>
      _section.trim().isEmpty
          ? _className
          : '$_className ${_section.trim()}';

  // ── Derived counts ──────────────────────────────────────────────────────────
  int get _total   => _students.length;
  int get _present => _attendance.values.where((v) => v == 'Present').length;
  int get _leave   => _attendance.values.where((v) => v == 'Leave').length;
  int get _absent  => _attendance.values.where((v) => v == 'Absent').length;

  List<Student> get _filtered {
    if (_search.trim().isEmpty) return _students;
    final q = _search.toLowerCase();
    return _students.where((s) =>
        s.name.toLowerCase().contains(q) ||
        s.roll.toString().contains(q)).toList();
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _className = widget.className;
    _section   = widget.section;
    _checkConnectivity();
    _connectSub = _connectivity.onConnectivityChanged.listen(_onConnectivityChanged);
    _load();
  }

  @override
  void dispose() {
    _connectSub?.cancel();
    _studentSub?.cancel();
    super.dispose();
  }

  Future<void> _checkConnectivity() async {
    final results = await _connectivity.checkConnectivity();
    final online  = results.any((r) => r != ConnectivityResult.none);
    final pending = await _offlineQueue.pendingCount();
    if (!mounted) return;
    setState(() {
      _isOnline     = online;
      _pendingCount = pending;
    });
    // Auto-sync if we just came online
    if (online && pending > 0) _syncOfflineQueue();
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) async {
    final online = results.any((r) => r != ConnectivityResult.none);
    if (!mounted) return;
    final wasOffline = !_isOnline;
    setState(() => _isOnline = online);
    // Coming back online → auto-sync
    if (online && wasOffline) {
      final synced = await _syncOfflineQueue();
      if (synced > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Synced $synced offline record${synced > 1 ? "s" : ""} to server'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<int> _syncOfflineQueue() async {
    final synced = await _offlineQueue.syncAll();
    final pending = await _offlineQueue.pendingCount();
    if (!mounted) return synced;
    setState(() {
      _pendingCount  = pending;
      _savedOffline  = pending > 0;
    });
    return synced;
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    // Fetch teacher's assigned class AND section from Firestore teachers collection.
    // Always prefer fresh Firestore data over widget params.
    final session   = await AuthService().getSession();
    final teacherId = session?['teacherId'] as String?;
    if (teacherId != null) {
      final teacher         = await TimetableService().getTeacherById(teacherId);
      final assignedClass   = teacher?.classTeacherOf ?? '';
      final assignedSection = teacher?.section ?? '';
      if (assignedClass.isEmpty || assignedSection.isEmpty) {
        if (!mounted) return;
        setState(() { _noAssignment = true; _loading = false; });
        return;
      }
      _className  = assignedClass;
      _section    = assignedSection;
      _teacherId  = teacherId;
    }

    // Hard guard: section must be set — without it we cannot distinguish
    // between sections and would show ALL students in the class.
    if (_section.trim().isEmpty) {
      if (!mounted) return;
      setState(() { _noAssignment = true; _loading = false; });
      return;
    }

    // Students list — try Firestore; if offline, use cached list from queue
    List<Student> students = [];
    Map<int, String> saved = {};

    if (_isOnline) {
      students = await _service.getStudentsByClass(_className,
          section: _section, teacherId: _teacherId);
      saved    = await _service.loadTodayAttendance(_attendanceKey);
      // If Firestore has nothing, check local queue too
      if (saved.isEmpty) {
        final cached = await _offlineQueue.getCachedAttendance(_attendanceKey);
        if (cached != null) saved = cached;
      }
    } else {
      // Offline: load students from Firestore best-effort; load attendance from local queue
      try {
        students = await _service.getStudentsByClass(_className,
                section: _section, teacherId: _teacherId)
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        students = [];
      }
      final cached = await _offlineQueue.getCachedAttendance(_attendanceKey);
      if (cached != null) saved = cached;
    }

    assert(students.length == {for (final s in students) s.roll: s}.length,
        'Duplicate rolls detected in class $_className');
    debugPrint('[StudentList][$_className] count=${students.length}');

    final pending = await _offlineQueue.pendingCount();
    if (!mounted) return;
    setState(() {
      _students     = students;
      _pendingCount = pending;
      _alreadySaved = saved.isNotEmpty;
      for (final s in students) {
        _attendance[s.roll] = saved[s.roll] ?? '';
      }
      _loading = false;
      _dirty   = false;
    });
    _subscribeStudents();
  }

  /// Subscribes to live student updates after the initial load.
  /// Skips the first emission (identical to what _load() just fetched) and
  /// responds to subsequent changes: removes deleted students from the
  /// attendance map and adds new ones with a default of 'Absent'.
  void _subscribeStudents() {
    _studentSub?.cancel();
    bool isFirst = true;
    _studentSub = _service
        .watchStudentsByClass(_className, section: _section, teacherId: _teacherId)
        .listen((list) {
      if (isFirst) { isFirst = false; return; }
      if (!mounted) return;
      setState(() {
        _attendance.removeWhere(
            (roll, _) => !list.any((s) => s.roll == roll));
        for (final s in list) {
          _attendance.putIfAbsent(s.roll, () => '');
        }
        _students = list;
      });
    });
  }

  /// Pull-to-refresh — silent (no full-screen spinner)
  Future<void> _refresh() async {
    final connectivity = await _connectivity.checkConnectivity();
    final online = connectivity.any((r) => r != ConnectivityResult.none);
    setState(() => _isOnline = online);

    List<Student>    students = _students;
    Map<int, String> saved    = {};

    if (online) {
      students = await _service.getStudentsByClass(_className,
          section: _section, teacherId: _teacherId);
      saved    = await _service.loadTodayAttendance(_attendanceKey);
    } else {
      final cached = await _offlineQueue.getCachedAttendance(_attendanceKey);
      if (cached != null) saved = cached;
    }

    final pending = await _offlineQueue.pendingCount();
    if (!mounted) return;
    setState(() {
      _students     = students;
      _pendingCount = pending;
      _alreadySaved = saved.isNotEmpty || _alreadySaved;
      for (final s in students) {
        _attendance[s.roll] = saved[s.roll] ?? _attendance[s.roll] ?? '';
      }
      _dirty = false;
    });
  }

  // ── Actions ─────────────────────────────────────────────────────────────────
  void _setStatus(int roll, String status) =>
      setState(() { _attendance[roll] = status; _dirty = true; });

  void _markAll(String status) =>
      setState(() {
        for (final s in _students) _attendance[s.roll] = status;
        _dirty = true;
      });

  Future<void> _save() async {
    // Re-check connectivity right before saving
    final results = await _connectivity.checkConnectivity();
    final online  = results.any((r) => r != ConnectivityResult.none);
    setState(() => _isOnline = online);

    if (!online) {
      // ── OFFLINE PATH ────────────────────────────────────────────────────
      final toQueue = Map<int, String>.fromEntries(
          _attendance.entries.where((e) => e.value.isNotEmpty));
      await _offlineQueue.enqueue(
        className:  _attendanceKey,
        attendance: toQueue,
      );
      final pending = await _offlineQueue.pendingCount();
      if (!mounted) return;
      setState(() {
        _dirty        = false;
        _savedOffline = true;
        _pendingCount = pending;
        _alreadySaved = true;
        _isMarking    = false;
      });
      // Show offline-save dialog instead of normal one
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(children: [
            Icon(Icons.cloud_off_outlined, color: Colors.orange, size: 24),
            SizedBox(width: 10),
            Text('Saved Offline', style: TextStyle(fontSize: 16)),
          ]),
          content: const Text(
            'No internet connection. Attendance has been saved locally '
            'and will sync automatically when you go online.',
            style: TextStyle(fontSize: 13),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    // ── ONLINE PATH ──────────────────────────────────────────────────────
    final toSave = Map<int, String>.fromEntries(
        _attendance.entries.where((e) => e.value.isNotEmpty));
    await _service.saveAttendance(_attendanceKey, toSave);

    // Fire off guardian notifications for every absent / leave student.
    // These are "fire and forget" — we don't await to keep save fast.
    for (final s in _students) {
      final status = _attendance[s.roll];
      if (status == 'Absent' || status == 'Leave') {
        NotificationService().addAbsenceNotice(
          className:   _className,
          roll:        s.roll,
          studentName: s.name,
          status:      status!,
        );
      }
    }

    if (!mounted) return;
    setState(() {
      _dirty        = false;
      _alreadySaved = true;
      _isMarking    = false;
    });

    // ── Attendance summary dialog ────────────────────────────────────────────
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
        title: const Row(children: [
          Icon(Icons.check_circle, color: Colors.green, size: 24),
          SizedBox(width: 10),
          Text('Attendance Saved', style: TextStyle(fontSize: 16)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _SummaryRow('Total Students', '$_total', Colors.grey),
          _SummaryRow('Present', '$_present', const Color(0xFF2E7D32)),
          _SummaryRow('On Leave', '$_leave', const Color(0xFFF57F17)),
          _SummaryRow('Absent', '$_absent', const Color(0xFFC62828)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _total == 0 ? 0 : _present / _total,
              minHeight: 6,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                  _total > 0 && _present == _total
                      ? Colors.green
                      : AppTheme.primary),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _total == 0
                ? 'No students'
                : '${(_present / _total * 100).round()}% attendance today',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ]),
        actions: [
          if (_absent + _leave > 0)
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _showWhatsAppSheet();
              },
              icon: const Icon(Icons.message, size: 16, color: Colors.green),
              label: const Text('Notify Guardians via WhatsApp',
                  style: TextStyle(color: Colors.green)),
            ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _showWhatsAppSheet() {
    final followUp = _students
        .where((s) =>
            _attendance[s.roll] == 'Absent' ||
            _attendance[s.roll] == 'Leave')
        .toList();
    if (followUp.isEmpty || !mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WhatsAppNotifySheet(
        students: followUp,
        attendance: Map.from(_attendance),
        className: _className,
      ),
    );
  }

  Future<void> _removeStudent(Student s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Student'),
        content: Text('Remove ${s.name} (Roll ${s.roll})?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _service.removeStudent(s.roll, _className, section: _section);
    setState(() { _students.remove(s); _attendance.remove(s.roll); });
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────
  Color _accentColor(String status) {
    switch (status) {
      case 'Present': return const Color(0xFF2E7D32);
      case 'Leave':   return const Color(0xFFF57F17);
      case 'Absent':  return const Color(0xFFC62828);
      default:        return Colors.grey.shade300; // unmarked
    }
  }

  Color _rowBg(String status) {
    switch (status) {
      case 'Present': return Colors.green.withOpacity(0.05);
      case 'Leave':   return Colors.amber.withOpacity(0.07);
      default:        return Colors.white;
    }
  }

  String _dateLabel() {
    final d = DateTime.now();
    const mo = ['Jan','Feb','Mar','Apr','May','Jun',
                 'Jul','Aug','Sep','Oct','Nov','Dec'];
    const dy = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return '${dy[d.weekday-1]}, ${d.day} ${mo[d.month-1]} ${d.year}';
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !(_isMarking && _alreadySaved),
      onPopInvoked: (didPop) {
        if (!didPop) setState(() => _isMarking = false);
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: _buildAppBar(),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _noAssignment
                ? _noAssignmentState()
                : _students.isEmpty
                    ? _emptyState()
                    : _alreadySaved && !_isMarking
                        ? _buildSummaryView()
                        : !_alreadySaved && !_isMarking
                            ? _buildEntryView()
                            : _buildBody(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final dateStr = _dateLabel();
    final subtitle = (_alreadySaved && !_isMarking)
        ? 'Attendance Taken  ·  $dateStr'
        : '$dateStr${_students.isNotEmpty ? "  ·  $_total students" : ""}';
    return AppBar(
      leading: (_isMarking && _alreadySaved)
          ? IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => setState(() => _isMarking = false),
            )
          : null,
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_className,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        Text(subtitle,
            style: const TextStyle(fontSize: 11, color: Colors.white60)),
      ]),
    );
  }

  Widget _buildBody() {
    return Stack(
      children: [
        Column(children: [
          // ── Offline / pending-sync banner ─────────────────────────────────
          if (!_isOnline)
            Container(
              width: double.infinity,
              color: Colors.orange.shade700,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              child: Row(children: [
                const Icon(Icons.cloud_off_outlined,
                    color: Colors.white, size: 16),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'No internet — attendance will be saved locally',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ]),
            )
          else if (_pendingCount > 0)
            GestureDetector(
              onTap: () async {
                final synced = await _syncOfflineQueue();
                if (mounted && synced > 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✓ Synced $synced record${synced > 1 ? "s" : ""}'),
                      backgroundColor: Colors.green,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              child: Container(
                width: double.infinity,
                color: AppTheme.primaryMid,
                padding: const EdgeInsets.symmetric(
                    vertical: 6, horizontal: 16),
                child: Row(children: [
                  const Icon(Icons.sync_outlined,
                      color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$_pendingCount offline record${_pendingCount > 1 ? "s" : ""} waiting — Tap to sync now',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ]),
              ),
            ),

          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              color: AppTheme.primary,
              child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 90),
                  itemCount: _students.length + 2,
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return _AttendanceHeroCard(
                        className: _className,
                        total: _total,
                        present: _present,
                        leave: _leave,
                        absent: _absent,
                        dateLabel: _dateLabel(),
                      );
                    }
                    if (i == 1) {
                      return _MarkAllRow(onMarkAll: _markAll);
                    }
                    final idx = i - 2;
                    return _StudentRow(
                      student:     _students[idx],
                      status:      _attendance[_students[idx].roll] ?? '',
                      accentColor: _accentColor(_attendance[_students[idx].roll] ?? ''),
                      rowBg:       _rowBg(_attendance[_students[idx].roll] ?? ''),
                      onChanged:   (v) => _setStatus(_students[idx].roll, v),
                      onRemove:    () => _removeStudent(_students[idx]),
                      isLast:      idx == _students.length - 1,
                    );
                  },
                ),
            ),
          ),
        ]),
        // Floating Save button
        Positioned(
          bottom: 16, left: 20, right: 20,
          child: _SaveButton(
              dirty: _dirty, isOnline: _isOnline, onTap: _save),
        ),
      ],
    );
  }

  Widget _buildStatsCard() {
    final progress = _total == 0 ? 0.0 : _present / _total;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Row(children: [
            _StatBubble(_total,   'Total',   const Color(0xFF546E7A)),
            _StatBubble(_present, 'Present', const Color(0xFF2E7D32)),
            _StatBubble(_leave,   'Leave',   const Color(0xFFF57F17)),
            _StatBubble(_absent,  'Absent',  const Color(0xFFC62828)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    progress == 1.0
                        ? Colors.green.shade600
                        : AppTheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                _total == 0
                    ? 'No students'
                    : '$_present of $_total marked present (${(_present / _total * 100).round()}%)',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _buildSearchBar() {
    if (_students.length < 10) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: TextField(
        onChanged: (v) => setState(() => _search = v),
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search by name or roll…',
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
          prefixIcon: Icon(Icons.search, color: Colors.grey.shade400, size: 20),
          suffixIcon: _search.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: Colors.grey.shade400, size: 18),
                  onPressed: () => setState(() => _search = ''),
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
          ),
        ),
      ),
    );
  }

  // ── Entry view: attendance not yet taken today ──────────────────────────────
  Widget _buildEntryView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96, height: 96,
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.edit_calendar_outlined,
                  size: 48, color: AppTheme.primary),
            ),
            const SizedBox(height: 24),
            Text(
              _className,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              _dateLabel(),
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$_total students',
                style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 36),
            ElevatedButton.icon(
              onPressed: () => setState(() => _isMarking = true),
              icon: const Icon(Icons.how_to_reg_outlined, size: 22),
              label: const Text('Take Attendance for Today',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 2,
              ),
            ),
            if (!_isOnline) ...[
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.cloud_off_outlined,
                    size: 14, color: Colors.orange.shade600),
                const SizedBox(width: 6),
                Text('Offline — attendance will be saved locally',
                    style: TextStyle(
                        fontSize: 12, color: Colors.orange.shade600)),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  // ── Summary view: attendance already saved today ────────────────────────────
  Widget _buildSummaryView() {
    final progress = _total == 0 ? 0.0 : _present / _total;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Connectivity banners
          if (!_isOnline)
            Container(
              color: Colors.orange.shade700,
              padding:
                  const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              child: Row(children: [
                const Icon(Icons.cloud_off_outlined,
                    color: Colors.white, size: 16),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'No internet — attendance saved locally',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ]),
            )
          else if (_pendingCount > 0)
            GestureDetector(
              onTap: () async {
                final synced = await _syncOfflineQueue();
                if (mounted && synced > 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✓ Synced $synced record${synced > 1 ? "s" : ""}'),
                      backgroundColor: Colors.green,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              child: Container(
                color: AppTheme.primaryMid,
                padding: const EdgeInsets.symmetric(
                    vertical: 6, horizontal: 16),
                child: Row(children: [
                  const Icon(Icons.sync_outlined,
                      color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$_pendingCount offline record${_pendingCount > 1 ? "s" : ""} waiting — Tap to sync',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ]),
              ),
            ),

          // Hero stats card
          _AttendanceHeroCard(
            className: _className,
            total: _total,
            present: _present,
            leave: _leave,
            absent: _absent,
            dateLabel: _dateLabel(),
          ),

          const SizedBox(height: 16),

          // Summary stats row
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2)),
              ],
            ),
            child: Column(children: [
              Row(children: [
                _StatBubble(_total,   'Total',   const Color(0xFF546E7A)),
                _StatBubble(_present, 'Present', const Color(0xFF2E7D32)),
                _StatBubble(_leave,   'Leave',   const Color(0xFFF57F17)),
                _StatBubble(_absent,  'Absent',  const Color(0xFFC62828)),
              ]),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    progress == 1.0 ? Colors.green.shade600 : AppTheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                _total == 0
                    ? 'No students'
                    : '$_present of $_total present · ${(progress * 100).round()}%',
                style: TextStyle(
                    fontSize: 11, color: Colors.grey.shade500),
              ),
            ]),
          ),

          const SizedBox(height: 12),

          // "Saved" badge
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(children: [
                Icon(Icons.check_circle,
                    color: Colors.green.shade600, size: 20),
                const SizedBox(width: 10),
                Text(
                  'Attendance saved for today',
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w600),
                ),
              ]),
            ),
          ),

          const SizedBox(height: 16),

          // Edit button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _isMarking = true),
              icon: const Icon(Icons.edit_outlined, size: 20),
              label: const Text('Edit Attendance',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                minimumSize: const Size(double.infinity, 50),
                side: const BorderSide(color: AppTheme.primary, width: 1.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),

          if (_absent + _leave > 0) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton.icon(
                onPressed: _showWhatsAppSheet,
                icon: const Icon(Icons.message,
                    size: 20, color: Color(0xFF25D366)),
                label: const Text('Notify Guardians via WhatsApp',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF25D366))),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF25D366),
                  minimumSize: const Size(double.infinity, 48),
                  side: const BorderSide(
                      color: Color(0xFF25D366), width: 1.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _noAssignmentState() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        width: 88, height: 88,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.class_outlined, size: 44, color: Colors.grey.shade400),
      ),
      const SizedBox(height: 20),
      Text('No class assigned to you yet',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
              color: Colors.grey.shade500)),
      const SizedBox(height: 6),
      Text('Ask the coordinator to assign your class and section',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
    ]),
  );

  Widget _emptyState() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        width: 88, height: 88,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.group_add_outlined, size: 44, color: Colors.grey.shade400),
      ),
      const SizedBox(height: 20),
      Text('No students in $_className',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
              color: Colors.grey.shade500)),
      const SizedBox(height: 6),
      Text('Add students via Student List first',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Attendance Hero Card (wave header)
// ─────────────────────────────────────────────────────────────────────────────

class _AttendanceHeroCard extends StatelessWidget {
  final String className, dateLabel;
  final int    total, present, leave, absent;

  const _AttendanceHeroCard({
    required this.className,
    required this.dateLabel,
    required this.total,
    required this.present,
    required this.leave,
    required this.absent,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : present / total * 100;
    return ClipPath(
      clipper: _WaveClipper(),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.primaryDark, Color(0xFF880E4F)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 56),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Label row
            Text(
              '${className.toUpperCase()}  ·  TODAY  ·  $dateLabel',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 10),
            // Big percentage
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${pct.round()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                    height: 1.0,
                  ),
                ),
                const SizedBox(width: 8),
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Present',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Glassmorphism stats row
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                _HeroStat('$total',   'Total'),
                Container(width: 1, height: 28, color: Colors.white24),
                _HeroStat('$present', 'Present'),
                Container(width: 1, height: 28, color: Colors.white24),
                _HeroStat('$leave',   'Leave'),
                Container(width: 1, height: 28, color: Colors.white24),
                _HeroStat('$absent',  'Absent'),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String value, label;
  const _HeroStat(this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(children: [
        Text(value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            )),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            )),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Wave clipper (shared shape for hero cards)
// ─────────────────────────────────────────────────────────────────────────────

class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 30);
    path.quadraticBezierTo(
        size.width * 0.25, size.height,
        size.width * 0.5,  size.height - 20);
    path.quadraticBezierTo(
        size.width * 0.75, size.height - 40,
        size.width,        size.height - 20);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_WaveClipper _) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Mark All row — small secondary action above the student list
// ─────────────────────────────────────────────────────────────────────────────

class _MarkAllRow extends StatelessWidget {
  final void Function(String) onMarkAll;
  const _MarkAllRow({required this.onMarkAll});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            'Quick mark:',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
          const Spacer(),
          _SmallMarkChip(
            label: 'All Present',
            color: const Color(0xFF2E7D32),
            onTap: () => onMarkAll('Present'),
          ),
        ],
      ),
    );
  }
}

class _SmallMarkChip extends StatelessWidget {
  final String label;
  final Color  color;
  final VoidCallback onTap;
  const _SmallMarkChip(
      {required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Student row
// ─────────────────────────────────────────────────────────────────────────────

class _StudentRow extends StatelessWidget {
  final Student  student;
  final String   status;
  final Color    accentColor, rowBg;
  final ValueChanged<String> onChanged;
  final Future<void> Function() onRemove;
  final bool isLast;

  const _StudentRow({
    required this.student,
    required this.status,
    required this.accentColor,
    required this.rowBg,
    required this.onChanged,
    required this.onRemove,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        color: rowBg,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 4,
                    color: accentColor,
                  ),
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: _Avatar(student: student, ringColor: accentColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            student.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.1,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            [
                              'Roll ${student.roll}',
                              if (student.fatherName.isNotEmpty) student.fatherName,
                            ].join('  ·  '),
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.grey.shade500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 2),
                    child: _StatusToggle(value: status, onChanged: onChanged),
                  ),
                  const SizedBox(width: 10),
                ],
              ),
            ),
            if (!isLast)
              Divider(height: 1, indent: 68, color: Colors.grey.shade200),
          ],
        ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Avatar with status ring
// ─────────────────────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final Student student;
  final Color   ringColor;
  const _Avatar({required this.student, required this.ringColor});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ringColor, width: 2.5),
      ),
      child: CircleAvatar(
        radius: 22,
        backgroundColor: Colors.grey.shade100,
        backgroundImage: student.photoPath != null
            ? FileImage(File(student.photoPath!))
            : null,
        child: student.photoPath == null
            ? Text(
                student.name.isNotEmpty ? student.name[0].toUpperCase() : '?',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.grey.shade600,
                ),
              )
            : null,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Status toggle  A | L | P
// ─────────────────────────────────────────────────────────────────────────────

class _StatusToggle extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _StatusToggle({required this.value, required this.onChanged});

  static const _opts = [
    _Opt('A', 'Absent',  Color(0xFFC62828)),
    _Opt('L', 'Leave',   Color(0xFFF57F17)),
    _Opt('P', 'Present', Color(0xFF2E7D32)),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primary.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _opts.length; i++) ...[
            if (i > 0)
              Container(width: 1, height: 24, color: AppTheme.primary.withOpacity(0.15)),
            _Pill(
              opt:     _opts[i],
              selected: value == _opts[i].state,
              isFirst:  i == 0,
              isLast:   i == _opts.length - 1,
              onTap:    () => onChanged(_opts[i].state),
            ),
          ],
        ],
      ),
    );
  }
}

class _Opt {
  final String label, state;
  final Color  color;
  const _Opt(this.label, this.state, this.color);
}

class _Pill extends StatelessWidget {
  final _Opt opt;
  final bool selected, isFirst, isLast;
  final VoidCallback onTap;

  const _Pill({
    required this.opt,
    required this.selected,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.horizontal(
      left:  isFirst ? const Radius.circular(9) : Radius.zero,
      right: isLast  ? const Radius.circular(9) : Radius.zero,
    );
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 40, height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? opt.color : Colors.transparent,
          borderRadius: r,
        ),
        child: Text(
          opt.label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.bold,
            color: selected ? Colors.white : opt.color.withOpacity(0.7),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Floating Save button
// ─────────────────────────────────────────────────────────────────────────────

class _SaveButton extends StatelessWidget {
  final bool dirty;
  final bool isOnline;
  final VoidCallback onTap;
  const _SaveButton(
      {required this.dirty, required this.isOnline, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = isOnline ? AppTheme.primary : Colors.orange.shade700;
    final label = isOnline ? 'Save Attendance' : 'Save Offline';
    final icon  = isOnline
        ? Icons.save_alt_rounded
        : Icons.cloud_off_outlined;

    return Material(
      elevation: 6,
      shadowColor: color.withOpacity(0.4),
      borderRadius: BorderRadius.circular(14),
      color: color,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 52,
          alignment: Alignment.center,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
            if (dirty) ...[
              const SizedBox(width: 8),
              Container(
                width: 7, height: 7,
                decoration: const BoxDecoration(
                  color: Colors.amberAccent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Stat bubble
// ─────────────────────────────────────────────────────────────────────────────

class _StatBubble extends StatelessWidget {
  final int    count;
  final String label;
  final Color  color;
  const _StatBubble(this.count, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(children: [
        Text(
          '$count',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade500,
            letterSpacing: 0.2,
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Summary row used in the post-save dialog
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  final String label, value;
  final Color  color;
  const _SummaryRow(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(child: Text(label,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700))),
        Text(value,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  WhatsApp Guardian Notification Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _WhatsAppNotifySheet extends StatelessWidget {
  final List<Student>    students;
  final Map<int, String> attendance;
  final String           className;

  const _WhatsAppNotifySheet({
    required this.students,
    required this.attendance,
    required this.className,
  });

  String _message(Student s) {
    final status = attendance[s.roll] ?? '';
    final statusWord = status == 'Leave' ? 'on leave' : 'absent';
    final d = DateTime.now();
    const mo = ['Jan','Feb','Mar','Apr','May','Jun',
                 'Jul','Aug','Sep','Oct','Nov','Dec'];
    final dateStr = '${d.day} ${mo[d.month - 1]} ${d.year}';

    return 'Dear Parent/Guardian,\n\n'
        'This is to inform you that your child *${s.name}* '
        '(Roll No. ${s.roll}) of *$className* is *$statusWord* '
        'in school today ($dateStr).\n\n'
        'Regular school attendance is essential for your child\'s academic '
        'growth and bright future. We kindly request you to ensure that your '
        'child attends school consistently.\n\n'
        'Thank you for your cooperation.\n'
        '— School Management';
  }

  Future<void> _openWhatsApp(String phone, String message) async {
    // Clean phone: keep digits only
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final url = Uri.parse(
        'https://wa.me/$digits?text=${Uri.encodeComponent(message)}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final absent  = students.where((s) => attendance[s.roll] == 'Absent').toList();
    final onLeave = students.where((s) => attendance[s.roll] == 'Leave').toList();
    final withPhone   = students.where((s) => s.phone.isNotEmpty).length;
    final withoutPhone= students.where((s) => s.phone.isEmpty).length;

    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          width: 36, height: 4,
          decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2)),
        ),

        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF25D366).withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.message,
                  color: Color(0xFF25D366), size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Notify Guardians via WhatsApp',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                Text(
                  '$withPhone with phone  ·  $withoutPhone without phone',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            )),
          ]),
        ),
        const Divider(height: 20),

        // Student list
        Flexible(
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, 0, 16, bottom + 20),
            shrinkWrap: true,
            children: [
              if (absent.isNotEmpty) ...[
                _label('Absent', const Color(0xFFC62828)),
                ...absent.map((s) => _NotifyRow(
                      student: s, message: _message(s),
                      onSend: () => _openWhatsApp(s.phone, _message(s)),
                    )),
              ],
              if (onLeave.isNotEmpty) ...[
                _label('On Leave', const Color(0xFFF57F17)),
                ...onLeave.map((s) => _NotifyRow(
                      student: s, message: _message(s),
                      onSend: () => _openWhatsApp(s.phone, _message(s)),
                    )),
              ],
            ],
          ),
        ),

        // Close button
        Container(
          padding: EdgeInsets.fromLTRB(20, 8, 20, bottom + 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
          ),
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Done',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }

  Widget _label(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
      child: Row(children: [
        Container(width: 8, height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: color, letterSpacing: 0.5)),
      ]),
    );
  }
}

class _NotifyRow extends StatelessWidget {
  final Student  student;
  final String   message;
  final VoidCallback onSend;

  const _NotifyRow({
    required this.student,
    required this.message,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhone = student.phone.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: hasPhone ? Colors.green.shade50 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: hasPhone ? Colors.green.shade200 : Colors.grey.shade200),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 18,
          backgroundColor:
              hasPhone ? Colors.green.shade100 : Colors.grey.shade200,
          child: Text(student.name[0].toUpperCase(),
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: hasPhone
                      ? Colors.green.shade800
                      : Colors.grey.shade500)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(student.name,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(hasPhone ? student.phone : 'No phone number',
                style: TextStyle(
                    fontSize: 11,
                    color: hasPhone
                        ? Colors.grey.shade600
                        : Colors.grey.shade400)),
          ],
        )),
        if (hasPhone)
          GestureDetector(
            onTap: onSend,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF25D366),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.message, color: Colors.white, size: 14),
                SizedBox(width: 4),
                Text('WhatsApp',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
              ]),
            ),
          )
        else
          Icon(Icons.phone_disabled_outlined,
              color: Colors.grey.shade400, size: 18),
      ]),
    );
  }
}

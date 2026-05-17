import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../theme.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/student.dart';
import '../services/auth_service.dart';
import '../services/student_service.dart';
import '../services/timetable_service.dart';
import '../services/notification_service.dart';
import '../services/offline_queue_service.dart';
import '../services/base_firestore_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/student_remark.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  AttendanceScreen
// ─────────────────────────────────────────────────────────────────────────────

class AttendanceScreen extends StatefulWidget {
  final String? schoolId;
  final String className;
  final String section;
  final DateTime? date;
  const AttendanceScreen({
    super.key,
    this.schoolId,
    required this.className,
    this.section = '',
    this.date,
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

  late final String _schoolId;
  List<Student>    _students   = [];
  Map<int, String> _attendance = {}; // roll → 'Present' | 'Leave' | 'Absent'
  bool   _loading        = true;
  bool   _dirty          = false;
  bool   _isOnline       = true;   // current connectivity status
  int    _pendingCount   = 0;      // items waiting to sync
  bool   _alreadySaved   = false; // today's attendance doc exists
  bool   _isMarking      = false; // user is actively marking attendance
  bool   _noAssignment   = false; // teacher has no assigned class/section

  // Feedback settings
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;

  // Pager & Stats
  final PageController _pageController = PageController();
  int _currentIndex = 0;
  Map<int, List<StudentRemark>> _remarks = {};
  Map<int, String> _lastWeekStats = {};
  Map<int, String> _lastMonthStats = {};

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

  // ── Lifecycle ───────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _schoolId  = widget.schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    _className = widget.className;
    _section   = widget.section;
    _loadSettings();
    _checkConnectivity();
    _connectSub = _connectivity.onConnectivityChanged.listen(_onConnectivityChanged);
    _load();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _soundEnabled = prefs.getBool('att_sound_enabled') ?? true;
        _vibrationEnabled = prefs.getBool('att_vibration_enabled') ?? true;
      });
    }
  }

  Future<void> _toggleSound() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _soundEnabled = !_soundEnabled);
    await prefs.setBool('att_sound_enabled', _soundEnabled);
  }

  Future<void> _toggleVibration() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _vibrationEnabled = !_vibrationEnabled);
    await prefs.setBool('att_vibration_enabled', _vibrationEnabled);
  }

  void _triggerFeedback() {
    if (_vibrationEnabled) {
      HapticFeedback.vibrate();
    }
    if (_soundEnabled) {
      SystemSound.play(SystemSoundType.click);
    }
  }

  @override
  void dispose() {
    _connectSub?.cancel();
    _studentSub?.cancel();
    _pageController.dispose();
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
    });
    return synced;
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    // Fetch teacher's assigned class AND section from Firestore teachers collection.
    final session   = await AuthService().getSession();
    final teacherId = session?['teacherId'] as String?;
    if (teacherId != null) {
      final teacher         = await TimetableService().getTeacherById(id: teacherId);
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

    if (_section.trim().isEmpty) {
      if (!mounted) return;
      setState(() { _noAssignment = true; _loading = false; });
      return;
    }

    List<Student> students = [];
    Map<int, String> saved = {};

    if (_isOnline) {
      try {
        students = await _service.getStudentsByClass(
            className: _className, section: _section, teacherId: _teacherId);
      } catch (_) {
        // Composite index may not exist yet — retry without teacherId filter.
        students = await _service.getStudentsByClass(className: _className, section: _section);
      }
      if (widget.date == null) {
        saved = await _service.loadTodayAttendance(className: _attendanceKey);
        if (saved.isEmpty) {
          final cached = await _offlineQueue.getCachedAttendance(_attendanceKey);
          if (cached != null) saved = cached;
        }
      } else {
        final raw = await _service.loadAttendanceForDate(className: _attendanceKey, date: widget.date!);
        if (raw != null) {
          final rolls = Map<String, dynamic>.from((raw['rolls'] as Map?) ?? {});
          rolls.forEach((k, v) {
            if (v is bool) saved[int.parse(k)] = v ? 'Present' : 'Absent';
            else saved[int.parse(k)] = v as String;
          });
        }
      }
    } else {
      try {
        students = await _service.getStudentsByClass(className: _className,
                section: _section, teacherId: _teacherId)
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        students = [];
      }
      if (widget.date == null) {
        final cached = await _offlineQueue.getCachedAttendance(_attendanceKey);
        if (cached != null) saved = cached;
      }
    }

    final pending = await _offlineQueue.pendingCount();

    // Debug: verify section correctness before committing to state
    debugPrint('Teacher: (id=$_teacherId)');
    debugPrint('Class: $_className');
    debugPrint('Section: $_section');
    debugPrint('Students loaded: ${students.length}');
    if (students.isNotEmpty) {
      debugPrint('First student section: ${students.first.section}');
    }
    assert(
      students.every((s) => s.section == _section),
      'SECTION MISMATCH: Wrong students loaded for section "$_section"! '
      'Mismatched: ${students.where((s) => s.section != _section).map((s) => '${s.name}(${s.section})').join(', ')}',
    );

    if (!mounted) return;
    setState(() {
      _students     = students;
      _pendingCount = pending;
      _alreadySaved = saved.isNotEmpty;
      for (final s in students) {
        // Initial state is unmarked ('') so counter starts at 0
        _attendance[s.roll] = saved[s.roll] ?? '';
      }
      _loading = false;
      _dirty   = saved.isEmpty && students.isNotEmpty;
    });
    _subscribeStudents();
    _loadExtraData();
  }

  Future<void> _loadExtraData() async {
    try {
      final now = DateTime.now();
      final monthData = await _service.loadMonthAttendance(className: _attendanceKey, year: now.year, month: now.month);
      
      final Map<int, String> lw = {};
      final Map<int, String> lm = {};

      for (final s in _students) {
        // Last week (last 7 recorded days)
        int totalW = 0, presentW = 0;
        final days = monthData.keys.toList()..sort((a,b) => b.compareTo(a));
        int count = 0;
        for (final d in days) {
          if (count >= 7) break;
          final st = monthData[d]?[s.roll];
          if (st != null) {
            totalW++;
            if (st == 'Present') presentW++;
            count++;
          }
        }
        lw[s.roll] = totalW == 0 ? 'N/A' : '${(presentW/totalW*100).round()}%';
        
        // Month avg
        int totalM = 0, presentM = 0;
        monthData.forEach((_, rolls) {
          final st = rolls[s.roll];
          if (st != null) {
            totalM++;
            if (st == 'Present') presentM++;
          }
        });
        lm[s.roll] = totalM == 0 ? 'N/A' : '${(presentM/totalM*100).round()}%';
      }

      // Remarks - fetch in parallel
      final remarksResults = await Future.wait<List<StudentRemark>>(
        _students.map((s) => _service.getStudentRemarks(_className, s.roll, section: _section))
      );
      final Map<int, List<StudentRemark>> rm = {};
      for (int i=0; i<_students.length; i++) {
        rm[_students[i].roll] = remarksResults[i];
      }

      if (mounted) {
        setState(() {
          _lastWeekStats = lw;
          _lastMonthStats = lm;
          _remarks = rm;
        });
      }
    } catch (e) {
      debugPrint('Error loading extra data: $e');
    }
  }

  void _subscribeStudents() {
    _studentSub?.cancel();
    bool isFirst = true;
    _studentSub = _service
        .watchStudentsByClass(className: _className, section: _section, teacherId: _teacherId)
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

  Future<void> _refresh() async {
    final connectivity = await _connectivity.checkConnectivity();
    final online = connectivity.any((r) => r != ConnectivityResult.none);
    setState(() => _isOnline = online);

    List<Student>    students = _students;
    Map<int, String> saved    = {};

    if (online) {
      students = await _service.getStudentsByClass(className: _className,
          section: _section, teacherId: _teacherId);
      if (widget.date == null) {
        saved = await _service.loadTodayAttendance(className: _attendanceKey);
      } else {
        final raw = await _service.loadAttendanceForDate(className: _attendanceKey, date: widget.date!);
        if (raw != null) {
          final rolls = Map<String, dynamic>.from((raw['rolls'] as Map?) ?? {});
          rolls.forEach((k, v) {
            if (v is bool) saved[int.parse(k)] = v ? 'Present' : 'Absent';
            else saved[int.parse(k)] = v as String;
          });
        }
      }
    } else {
      if (widget.date == null) {
        final cached = await _offlineQueue.getCachedAttendance(_attendanceKey);
        if (cached != null) saved = cached;
      }
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
    _loadExtraData();
  }

  // ── Actions ─────────────────────────────────────────────────────────────────
  void _setStatus(int roll, String status) =>
      setState(() { _attendance[roll] = status; _dirty = true; });

  void _markAll(String status) =>
      setState(() {
        for (final s in _students) _attendance[s.roll] = status;
        _dirty = true;
      });

  Future<void> _saveQuietly() async {
    if (!_dirty) return;
    final results = await _connectivity.checkConnectivity();
    final online  = results.any((r) => r != ConnectivityResult.none);
    
    final toSave = Map<int, String>.fromEntries(
        _attendance.entries.where((e) => e.value.isNotEmpty));

    if (!online) {
      await _offlineQueue.enqueue(className: _attendanceKey, attendance: toSave);
      final pending = await _offlineQueue.pendingCount();
      if (mounted) setState(() { _pendingCount = pending; _dirty = false; });
      return;
    }

    if (widget.date == null) {
      await _service.saveAttendance(className: _attendanceKey, attendance: toSave);
    } else {
      await _service.saveAttendanceForDate(className: _attendanceKey, attendance: toSave, date: widget.date!);
    }
    if (mounted) setState(() { _dirty = false; });
  }

  Future<void> _save() async {
    // Re-check connectivity
    final results = await _connectivity.checkConnectivity();
    final online  = results.any((r) => r != ConnectivityResult.none);
    setState(() => _isOnline = online);

    if (!online) {
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
        _pendingCount = pending;
        _alreadySaved = true;
        _isMarking    = false;
      });
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
            'No internet connection. Attendance has been saved locally.',
            style: TextStyle(fontSize: 13),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final toSave = Map<int, String>.fromEntries(
        _attendance.entries.where((e) => e.value.isNotEmpty));
    
    if (widget.date == null) {
      await _service.saveAttendance(className: _attendanceKey, attendance: toSave);
    } else {
      await _service.saveAttendanceForDate(className: _attendanceKey, attendance: toSave, date: widget.date!);
    }

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

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
        ]),
        actions: [
          if (_absent + _leave > 0)
            TextButton.icon(
              onPressed: () { Navigator.pop(ctx); _showWhatsAppSheet(); },
              icon: const Icon(FontAwesomeIcons.whatsapp, size: 16, color: Colors.green),
              label: const Text('Notify via WhatsApp', style: TextStyle(color: Colors.green)),
            ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
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
    final d = widget.date ?? DateTime.now();
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
    final title = _section.isNotEmpty ? '$_className - $_section' : _className;
    return AppBar(
      leading: (_isMarking && _alreadySaved)
          ? IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => setState(() => _isMarking = false),
            )
          : null,
      title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      actions: [
        if (_students.isNotEmpty && _currentIndex < _students.length)
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: _showSearchRollDialog,
            tooltip: 'Search by Roll No.',
          ),
      ],
    );
  }

  void _showSearchRollDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Go to Roll Number'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'Enter Roll Number'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final roll = int.tryParse(controller.text);
              if (roll != null) {
                final idx = _students.indexWhere((s) => s.roll == roll);
                if (idx != -1) {
                  Navigator.pop(ctx);
                  _pageController.animateToPage(
                    idx,
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeInOut,
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Roll number not found')),
                  );
                }
              }
            },
            child: const Text('Go'),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_students.isEmpty) return _emptyState();

    return Container(
      color: Colors.white, // Screen background is white
      child: Column(
        children: [
          // ── Top Bar: Hero Card (Fixed & Shifted Up) ──────────────────────
          _AttendanceHeroCard(
            className: _className,
            total: _total,
            present: _present,
            leave: _leave,
            absent: _absent,
            dateLabel: _dateLabel(),
          ),

          // ── Connectivity / Sync Banners ───────────────────────────────────
          if (!_isOnline)
            _banner(Colors.orange.shade700, Icons.cloud_off_outlined, 'Offline — saving locally')
          else if (_pendingCount > 0)
            GestureDetector(
              onTap: _syncOfflineQueue,
              child: _banner(AppTheme.primaryMid, Icons.sync_outlined, '$_pendingCount offline records — Tap to sync'),
            ),

          // ── Main Student Section: Vertical Swipe Card System ──────────────
          Expanded(
            child: PageView.builder(
              scrollDirection: Axis.vertical,
              controller: _pageController,
              physics: _currentIndex == _students.length 
                  ? const NeverScrollableScrollPhysics() 
                  : const BouncingScrollPhysics(),
              itemCount: _students.length + 1, // +1 for the Summary Screen
              onPageChanged: (i) {
                // If moving forward, mark the student we just FINISHED as Present (if unmarked)
                if (i > _currentIndex && _currentIndex < _students.length) {
                  final prevStudent = _students[_currentIndex];
                  if (_attendance[prevStudent.roll] == '') {
                    _setStatus(prevStudent.roll, 'Present');
                  }
                }
                setState(() => _currentIndex = i);
                if (i < _students.length) _saveQuietly();
              },
              itemBuilder: (context, index) {
                // Final Summary Screen
                if (index == _students.length) {
                  return _AttendanceSummaryCard(
                    total: _total,
                    present: _present,
                    absent: _absent,
                    leave: _leave,
                    onSave: _save,
                    onNotify: _showWhatsAppSheet,
                  );
                }

                final s = _students[index];
                // Use AnimatedBuilder to achieve 3D swipe effect
                return AnimatedBuilder(
                  animation: _pageController,
                  builder: (context, child) {
                    double value = 1.0;
                    if (_pageController.position.haveDimensions) {
                      value = _pageController.page! - index;
                      value = (1 - (value.abs() * 0.3)).clamp(0.0, 1.0);
                    } else {
                      if (_currentIndex == index) value = 1.0;
                      else value = 0.7;
                    }

                    return Center(
                      child: Transform(
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.001)
                          ..scale(value),
                        alignment: Alignment.center,
                        child: Opacity(
                          opacity: value.clamp(0.5, 1.0),
                          child: _VerticalStudentCard(
                            student: s,
                            status:  _attendance[s.roll] ?? '',
                            remarks: _remarks[s.roll] ?? [],
                            lastWeek: _lastWeekStats[s.roll],
                            lastMonth: _lastMonthStats[s.roll],
                            onStatusChanged: (status) {
                              _setStatus(s.roll, status);
                              _saveQuietly();
                              _triggerFeedback();
                              // Auto-swipe to next card after a very small delay
                              Future.delayed(const Duration(milliseconds: 150), () {
                                if (_pageController.hasClients) {
                                  _pageController.nextPage(
                                    duration: const Duration(milliseconds: 350),
                                    curve: Curves.easeOutCubic,
                                  );
                                }
                              });
                            },
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _banner(Color color, IconData icon, String text) => Container(
    width: double.infinity, color: color,
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
    child: Row(children: [
      Icon(icon, color: Colors.white, size: 16),
      const SizedBox(width: 8),
      Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _buildStatsCard() {
    return const SizedBox.shrink();
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
              label: Text(widget.date == null 
                  ? 'Take Attendance for Today'
                  : 'Update Attendance for ${_formatDate(widget.date!)}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
                  widget.date == null ? 'Attendance saved for today' : 'Attendance updated for ${_formatDate(widget.date!)}',
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
                icon: const Icon(FontAwesomeIcons.whatsapp,
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

  String _formatDate(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';

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
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primaryDark, AppTheme.primaryMid],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Only show Day and Date
            Text(
              dateLabel.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 12),
            // Glassmorphism stats row - Moved Up and Compact
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(children: [
                _HeroStat('$total',   'Total'),
                Container(width: 1, height: 24, color: Colors.white24),
                _HeroStat('$present', 'Present'),
                Container(width: 1, height: 24, color: Colors.white24),
                _HeroStat('$leave',   'Leave'),
                Container(width: 1, height: 24, color: Colors.white24),
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

// Unused widgets removed for clarity.


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

class _VerticalStudentCard extends StatelessWidget {
  final Student student;
  final String status;
  final List<StudentRemark> remarks;
  final String? lastWeek;
  final String? lastMonth;
  final ValueChanged<String> onStatusChanged;

  const _VerticalStudentCard({
    required this.student,
    required this.status,
    required this.remarks,
    this.lastWeek,
    this.lastMonth,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(
        color: AppTheme.primary, // Violet card background
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(0.35),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // Student photo taking upper half with faded end
            Positioned(
              top: 0, left: 0, right: 0,
              height: 300, // Roughly upper half
              child: Stack(
                children: [
                  Positioned.fill(
                    child: student.photoUrl != null
                        ? CachedNetworkImage(
                            imageUrl: student.photoUrl!,
                            fit: BoxFit.cover,
                            alignment: const Alignment(0, -0.5), // Heuristic: center face higher
                            placeholder: (context, url) => Container(color: Colors.white10),
                            errorWidget: (context, url, error) => const Icon(Icons.person, size: 150, color: Colors.white24),
                          )
                        : student.photoPath != null
                            ? Image.file(
                                File(student.photoPath!),
                                fit: BoxFit.cover,
                                alignment: const Alignment(0, -0.5),
                              )
                            : Container(
                                color: Colors.white10,
                                child: const Icon(Icons.person, size: 150, color: Colors.white24),
                              ),
                  ),
                  // Fade effect at bottom of photo
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            AppTheme.primary.withOpacity(0.5),
                            AppTheme.primary,
                          ],
                          stops: const [0.6, 0.9, 1.0],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Main Content shifted below photo
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 310, 88, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name
                  Text(student.name, 
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
                  const SizedBox(height: 12),

                  // Highlighted Roll
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'ROLL NO. ${student.roll}', 
                      style: const TextStyle(
                        fontSize: 18, 
                        color: Colors.white, 
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                  
                  // Complaints / Remarks
                  const Text('REMARKS / COMPLAINTS', 
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white70, letterSpacing: 1.5)),
                  const SizedBox(height: 10),
                  if (remarks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('No active remarks.', 
                          style: TextStyle(color: Colors.white38, fontStyle: FontStyle.italic, fontSize: 13.5)),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: remarks.length,
                        itemBuilder: (ctx, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(margin: const EdgeInsets.only(top: 8), width: 6, height: 6, 
                                  decoration: const BoxDecoration(color: Colors.white54, shape: BoxShape.circle)),
                              const SizedBox(width: 12),
                              Expanded(child: Text(remarks[i].remark, style: const TextStyle(fontSize: 15, color: Colors.white, height: 1.3))),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Stats
                  const Divider(height: 32, color: Colors.white24),
                  Row(
                    children: [
                      _StatItem('LAST WEEK', lastWeek ?? '...', isDark: false),
                      const SizedBox(width: 40),
                      _StatItem('LAST MONTH', lastMonth ?? '...', isDark: false),
                    ],
                  ),
                ],
              ),
            ),

            // Action Buttons attached to the card
            Positioned(
              right: 16,
              top: 0, bottom: 0,
              child: Center(
                child: _VerticalActionButtons(
                  status: status,
                  onChanged: onStatusChanged,
                  isDark: false,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    if (status == 'Present') return const Color(0xFF2E7D32);
    if (status == 'Leave')   return const Color(0xFFF57F17);
    if (status == 'Absent')  return const Color(0xFFC62828);
    return Colors.grey.shade200;
  }
}

class _AttendanceSummaryCard extends StatelessWidget {
  final int total, present, absent, leave;
  final VoidCallback onSave, onNotify;

  const _AttendanceSummaryCard({
    required this.total,
    required this.present,
    required this.absent,
    required this.leave,
    required this.onSave,
    required this.onNotify,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: AppTheme.primary.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline, size: 80, color: Colors.white),
            const SizedBox(height: 24),
            const Text('ATTENDANCE DONE', 
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1.0)),
            const SizedBox(height: 40),
            _SummaryItem('Total Students', '$total'),
            const Divider(color: Colors.white24, height: 24),
            _SummaryItem('Present', '$present'),
            const Divider(color: Colors.white24, height: 24),
            _SummaryItem('Absent', '$absent'),
            const Divider(color: Colors.white24, height: 24),
            _SummaryItem('On Leave', '$leave'),
            const SizedBox(height: 48),
            
            ElevatedButton(
              onPressed: onSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.primary,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: const Text('SAVE ATTENDANCE', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.0)),
            ),
            if (absent > 0 || leave > 0) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onNotify,
                icon: const Icon(FontAwesomeIcons.whatsapp, size: 18),
                label: const Text('WHATSAPP ABSENCE NOTICE'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white, width: 2),
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label, value;
  const _SummaryItem(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 16, color: Colors.white70, fontWeight: FontWeight.w600)),
        Text(value, style: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.w900)),
      ],
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label, value;
  final bool isDark;
  const _StatItem(this.label, this.value, {this.isDark = true});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isDark ? Colors.grey.shade500 : Colors.white60, letterSpacing: 0.5)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? AppTheme.primaryDark : Colors.white)),
      ],
    );
  }
}

class _VerticalActionButtons extends StatelessWidget {
  final String status;
  final ValueChanged<String> onChanged;
  final bool isDark;

  const _VerticalActionButtons({required this.status, required this.onChanged, this.isDark = true});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CircleAction('P', 'Present', const Color(0xFF2E7D32), status == 'Present', () => onChanged('Present'), isDark: isDark),
        const SizedBox(height: 24),
        _CircleAction('L', 'Leave', const Color(0xFFF57F17), status == 'Leave', () => onChanged('Leave'), isDark: isDark),
        const SizedBox(height: 24),
        _CircleAction('A', 'Absent', const Color(0xFFC62828), status == 'Absent', () => onChanged('Absent'), isDark: isDark),
      ],
    );
  }
}

class _CircleAction extends StatelessWidget {
  final String label, full;
  final Color color;
  final bool selected, isDark;
  final VoidCallback onTap;

  const _CircleAction(this.label, this.full, this.color, this.selected, this.onTap, {this.isDark = true});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        width: 62, height: 62,
        decoration: BoxDecoration(
          color: selected ? (isDark ? color : Colors.white) : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? (isDark ? color : Colors.white) : (isDark ? color.withOpacity(0.35) : Colors.white38), 
            width: selected ? 3.0 : 2.0
          ),
          boxShadow: [
            if (selected) 
              BoxShadow(
                color: (isDark ? color : Colors.white).withOpacity(0.4), 
                blurRadius: 12, 
                offset: const Offset(0, 5)
              ),
          ],
        ),
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              color: selected ? (isDark ? Colors.white : AppTheme.primary) : (isDark ? color : Colors.white70),
              fontSize: 24, 
              fontWeight: FontWeight.w900
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

class _VerticalProgressBar extends StatelessWidget {
  final int total, current;
  const _VerticalProgressBar({required this.total, required this.current});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        const h = 220.0;
        return Container(
          width: 5, height: h,
          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(3)),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                top: 0, left: 0, right: 0,
                height: h * (current / total),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.primary, AppTheme.primaryDark],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ),
        );
      }
    );
  }
}

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
              child: const Icon(FontAwesomeIcons.whatsapp,
                  color: Color(0xFF25D366), size: 22),
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
                Icon(FontAwesomeIcons.whatsapp, color: Colors.white, size: 14),
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

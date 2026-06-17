import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../shared/providers/school_settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../theme.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/student.dart';
import '../../models/teacher.dart';
import 'package:school_app/services/auth_service.dart';
import 'package:school_app/services/student_service.dart';
import 'package:school_app/services/timetable_service.dart';
import 'package:school_app/services/notification_service.dart';
import 'package:school_app/services/offline_queue_service.dart';
import 'package:school_app/services/sms_gateway_simulator.dart';
import 'package:school_app/services/base_firestore_service.dart';
import '../../shared/utils/phone_utils.dart';
import '../../l10n/app_strings.dart';
import 'package:school_app/services/consent_service.dart';
import '../../shared/utils/consent_gate.dart';
import '../../shared/widgets/consent_pending_banner.dart';
import '../../shared/utils/school_clock.dart';
import '../../shared/utils/app_logger.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/student_remark.dart';
import '../../shared/widgets/refreshable_data.dart';
import '../../main.dart';

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

class _AttendanceScreenState extends State<AttendanceScreen> with RouteAware {
  final _service      = StudentService.instance;
  final _offlineQueue = OfflineQueueService();
  final _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectSub;
  StreamSubscription<List<Student>>? _studentSub;

  List<Student>    _students   = [];
  final Map<int, String> _attendance = {}; // roll → 'Present' | 'Leave' | 'Absent'
  // Last persisted statuses, used to send guardian absence notices ONLY for
  // students whose status newly changed to Absent/Leave — so re-saving a day
  // (e.g. after a correction) doesn't re-alert every absent student (#74).
  final Map<int, String> _savedStatuses = {};
  bool   _loading        = true;
  bool   _dirty          = false;
  bool   _isOnline       = true;   // current connectivity status
  int    _pendingCount   = 0;      // items waiting to sync
  int    _classPendingCount = 0;
  bool   _alreadySaved   = false; // today's attendance doc exists
  bool   _isMarking      = false; // user is actively marking attendance
  bool   _noAssignment   = false; // teacher has no assigned class/section
  bool   _saving         = false; // a _save() is in flight (guards double-tap)
  bool   _loadingPrevious = false;
  Set<String> _consentedIds = {};
  bool _consentLoaded = false;

  // Attendance edit-lock (#34): non-management staff may not edit attendance
  // for a date older than this many days, so historical records can't be
  // silently rewritten. Management (coordinator/principal/admin/owner) is
  // exempt. Today's attendance (widget.date == null) is never locked.
  bool _isManagement = false;
  static const int _attendanceEditWindowDays = 7;

  bool get _isLocked {
    if (widget.date == null || _isManagement) return false;
    final d = widget.date!;
    final days = SchoolClock.today()
        .difference(DateTime(d.year, d.month, d.day))
        .inDays;
    return days > _attendanceEditWindowDays;
  }

  // Feedback settings
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  bool _autoMarkPresent = false;
  bool _isListView = true; // Default to exceptions-only list view

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
    _className = widget.className;
    _section   = widget.section;
    if (_section.trim().isEmpty && _className.isNotEmpty) {
      _section = Teacher.extractSection(_className);
    }
    _loadSettings();
    _loadRole();
    _checkConnectivity();
    _connectSub = _connectivity.onConnectivityChanged.listen(_onConnectivityChanged);
    _load();
  }
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute<dynamic>);
  }

  @override
  void didPopNext() {
    // Refresh when returning from a pushed route (e.g., AddStudentScreen)
    _load();
  }
  /// Determines whether the viewer is management (exempt from the edit lock, #34).
  Future<void> _loadRole() async {
    final session = await AuthService().getSession();
    final role = session?['role'] as String?;
    const mgmt = ['coordinator', 'principal', 'admin', 'owner', 'ownerPrincipal'];
    if (mounted) setState(() => _isManagement = mgmt.contains(role));
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _soundEnabled = prefs.getBool('att_sound_enabled') ?? true;
        _vibrationEnabled = prefs.getBool('att_vibration_enabled') ?? true;
        _autoMarkPresent = prefs.getBool('attendance_auto_mark_present') ?? false;
      });
    }
  }

  void _triggerFeedback() {
    if (_vibrationEnabled) {
      HapticFeedback.vibrate();
    }
    if (_soundEnabled) {
      SystemSound.play(SystemSoundType.click);
    }
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(context.tr('attendanceSettings'), style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: Text(context.tr('autoMarkPresent')),
                subtitle: Text(context.tr('autoMarkPresentDesc')),
                value: _autoMarkPresent,
                activeColor: AppTheme.primary,
                onChanged: (val) async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('attendance_auto_mark_present', val);
                  setS(() => _autoMarkPresent = val);
                  setState(() => _autoMarkPresent = val);
                },
              ),
              SwitchListTile(
                title: Text(context.tr('soundFeedback')),
                value: _soundEnabled,
                activeColor: AppTheme.primary,
                onChanged: (val) async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('att_sound_enabled', val);
                  setS(() => _soundEnabled = val);
                  setState(() => _soundEnabled = val);
                },
              ),
              SwitchListTile(
                title: Text(context.tr('vibrationFeedback')),
                value: _vibrationEnabled,
                activeColor: AppTheme.primary,
                onChanged: (val) async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('att_vibration_enabled', val);
                  setS(() => _vibrationEnabled = val);
                  setState(() => _vibrationEnabled = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.tr('close')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Unsubscribe from route observer
    routeObserver.unsubscribe(this);
    _connectSub?.cancel();
    _studentSub?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _updatePendingCounts() async {
    final pending = await _offlineQueue.pendingCount();
    final counts = await _offlineQueue.pendingCountsByClass();
    final classPending = counts[_attendanceKey] ?? 0;
    if (mounted) {
      setState(() {
        _pendingCount = pending;
        _classPendingCount = classPending;
      });
    }
  }

  Future<void> _checkConnectivity() async {
    final results = await _connectivity.checkConnectivity();
    final online  = results.any((r) => r != ConnectivityResult.none);
    await _updatePendingCounts();
    if (!mounted) return;
    setState(() {
      _isOnline     = online;
    });
    // Auto-sync if we just came online
    if (online) {
      if (_pendingCount > 0) _syncOfflineQueue();
      _retryFailedNotifications();
    }
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) async {
    final online = results.any((r) => r != ConnectivityResult.none);
    if (!mounted) return;
    final wasOffline = !_isOnline;
    setState(() => _isOnline = online);
    // Coming back online → auto-sync
    if (online && wasOffline) {
      _retryFailedNotifications();
      final synced = await _syncOfflineQueue();
      if (synced > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('syncedOfflineRecordsSuccess').replaceAll('{count}', synced.toString())),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<int> _syncOfflineQueue() async {
    final synced = await _offlineQueue.syncAll();
    await _updatePendingCounts();
    return synced;
  }

  Future<void> _queueFailedNotification({
    required String className,
    required int roll,
    required String studentName,
    required String status,
    required String? admissionId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('failed_notifications') ?? [];
      final item = {
        'className': className,
        'roll': roll,
        'studentName': studentName,
        'status': status,
        'admissionId': admissionId,
      };
      list.add(jsonEncode(item));
      await prefs.setStringList('failed_notifications', list);
    } catch (e, st) {
      AppLogger.e('AttendanceScreen', 'Failed to queue notification', e, st);
    }
  }

  Future<void> _retryFailedNotifications() async {
    try {
      final results = await _connectivity.checkConnectivity();
      final online  = results.any((r) => r != ConnectivityResult.none);
      if (!online) return;

      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('failed_notifications') ?? [];
      if (list.isEmpty) return;

      final remaining = <String>[];
      for (final itemStr in list) {
        try {
          final item = jsonDecode(itemStr) as Map<String, dynamic>;
          await NotificationService().addAbsenceNotice(
            className:   item['className'] as String,
            roll:        item['roll'] as int,
            studentName: item['studentName'] as String,
            status:      item['status'] as String,
            admissionId: item['admissionId'] as String?,
          );
        } catch (_) {
          remaining.add(itemStr);
        }
      }
      await prefs.setStringList('failed_notifications', remaining);
    } catch (e, st) {
      AppLogger.e('AttendanceScreen', 'Failed retrying notifications', e, st);
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    // Fetch teacher's assigned class AND section from Firestore teachers collection.
    final session   = await AuthService().getSession();
    final teacherId = session?['teacherId'] as String?;
    if (teacherId != null) {
      final teacher         = await TimetableService.instance.getTeacherById(id: teacherId);
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
            className: _className, section: _section);
      } catch (e) {
        AppLogger.e('Attendance', 'Error loading students online: $e', e);
        students = [];
      }
      if (widget.date == null) {
        saved = await _service.loadTodayAttendance(className: _attendanceKey);
        if (saved.isEmpty) {
          final cached = await _offlineQueue.getCachedAttendance(_attendanceKey, date: widget.date);
          if (cached != null) saved = cached;
        }
      } else {
        final raw = await _service.loadAttendanceForDate(className: _attendanceKey, date: widget.date!);
        if (raw != null) {
          final rolls = Map<String, dynamic>.from((raw['rolls'] as Map?) ?? {});
          rolls.forEach((k, v) {
            final roll = int.tryParse(k);
            if (roll != null) {
              if (v is bool) {
                saved[roll] = v ? 'Present' : 'Absent';
              } else {
                saved[roll] = v as String;
              }
            }
          });
        }
      }
    } else {
      try {
        students = await _service.getStudentsByClass(className: _className, section: _section)
            .timeout(const Duration(seconds: 3));
      } catch (e) {
        AppLogger.e('Attendance', 'Error loading students offline: $e', e);
        students = [];
      }
      if (widget.date == null) {
        final cached = await _offlineQueue.getCachedAttendance(_attendanceKey, date: widget.date);
        if (cached != null) saved = cached;
      }
    }

    await _updatePendingCounts();

    // Debug: verify section correctness before committing to state
    AppLogger.d('Attendance', 'Teacher: (id=$_teacherId)');
    AppLogger.d('Attendance', 'Class: $_className');
    AppLogger.d('Attendance', 'Section: $_section');
    AppLogger.d('Attendance', 'Students loaded: ${students.length}');
    if (students.isNotEmpty) {
      AppLogger.d('Attendance', 'First student section: ${students.first.section}');
    }
    assert(
      students.every((s) => s.section == _section),
      'SECTION MISMATCH: Wrong students loaded for section "$_section"! '
      'Mismatched: ${students.where((s) => s.section != _section).map((s) => '${s.name}(${s.section})').join(', ')}',
    );

    if (!mounted) return;
    setState(() {
      _students     = students;
      _alreadySaved = saved.isNotEmpty;
      for (final s in students) {
        // Initial state is unmarked ('') so counter starts at 0
        _attendance[s.roll] = saved[s.roll] ?? '';
      }
      // Seed the last-persisted snapshot so the first save only notifies
      // genuinely new absences (#74).
      _savedStatuses
        ..clear()
        ..addAll(saved);
      _loading = false;
      _dirty   = saved.isEmpty && students.isNotEmpty;
    });
    _loadConsent(students);
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
      AppLogger.e('Attendance', 'Error loading extra data: $e', e);
    }
  }

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

  void _subscribeStudents() {
    _studentSub?.cancel();
    bool isFirst = true;
    _studentSub = _service
        .watchStudentsByClass(className: _className, section: _section)
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
      _loadConsent(list);
    });
  }

  // ── Actions ─────────────────────────────────────────────────────────────────
  void _setStatus(int roll, String status) =>
      setState(() { _attendance[roll] = status; _dirty = true; });

  void _markAllPresent() {
    setState(() {
      for (final s in _students) {
        _attendance[s.roll] = 'Present';
      }
      _dirty = true;
      _isMarking = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.tr('allMarkedPresent')),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<Map<int, String>?> _loadPreviousAttendance() async {
    final baseDate = widget.date ?? SchoolClock.today();
    final futures = List.generate(7, (index) {
      final targetDate = baseDate.subtract(Duration(days: index + 1));
      return _service.loadAttendanceForDate(
        className: _attendanceKey,
        date: targetDate,
      ).then((raw) => (date: targetDate, data: raw));
    });

    final results = await Future.wait(futures);
    results.sort((a, b) => b.date.compareTo(a.date));

    for (final result in results) {
      if (result.data != null) {
        final rolls = Map<String, dynamic>.from((result.data!['rolls'] as Map?) ?? {});
        if (rolls.isNotEmpty) {
          final Map<int, String> copied = {};
          rolls.forEach((k, v) {
            final roll = int.tryParse(k);
            if (roll != null) {
              if (v is bool) {
                copied[roll] = v ? 'Present' : 'Absent';
              } else {
                copied[roll] = v as String;
              }
            }
          });
          return copied;
        }
      }
    }
    return null;
  }

  Future<void> _copyPreviousAttendance() async {
    setState(() {
      _loadingPrevious = true;
    });
    try {
      final prev = await _loadPreviousAttendance();
      if (prev == null || prev.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No previous attendance records found in the last 7 days'),
              backgroundColor: AppTheme.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      setState(() {
        prev.forEach((roll, status) {
          _attendance[roll] = status;
        });
        _dirty = true;
        _isMarking = true;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Copied attendance from previous day'),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      AppLogger.e('Attendance', 'Error copying previous attendance: $e', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to copy previous attendance: $e'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      setState(() {
        _loadingPrevious = false;
      });
    }
  }

  Future<void> _saveQuietly() async {
    if (_isLocked) return; // edit lock (#34)
    if (!_dirty) return;
    final results = await _connectivity.checkConnectivity();
    final online  = results.any((r) => r != ConnectivityResult.none);
    
    final toSave = Map<int, String>.fromEntries(
        _attendance.entries.where((e) => e.value.isNotEmpty));

    if (!online) {
      await _offlineQueue.enqueue(className: _attendanceKey, attendance: toSave, date: widget.date);
      await _updatePendingCounts();
      if (mounted) setState(() { _dirty = false; });
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
    // Edit lock (#34): non-management can't persist edits to an old date.
    if (_isLocked) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'This attendance date is locked. Ask a coordinator or principal to make changes.'),
          backgroundColor: Colors.orange,
        ));
      }
      return;
    }

    final unmarkedCount = _students.where((s) => _attendance[s.roll] == '').length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(context.tr('confirmAttendanceSave'), style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('verifyAttendanceSummaryBeforeSave')),
            const SizedBox(height: 16),
            _SummaryRow('Total Students', '$_total', Colors.grey),
            _SummaryRow('Present', '$_present', AppTheme.success),
            _SummaryRow('On Leave', '$_leave', AppTheme.warning),
            _SummaryRow('Absent', '$_absent', AppTheme.danger),
            if (unmarkedCount > 0) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Warning: $unmarkedCount student(s) remain unmarked.',
                        style: TextStyle(color: Colors.amber.shade900, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Guard against double-taps / re-entry while a save is already running.
    if (_saving) return;
    setState(() => _saving = true);
    try {
      // Re-check connectivity
      final results = await _connectivity.checkConnectivity();
      final online  = results.any((r) => r != ConnectivityResult.none);
      if (mounted) setState(() => _isOnline = online);

      final toSave = Map<int, String>.fromEntries(
          _attendance.entries.where((e) => e.value.isNotEmpty));

      if (online) {
        try {
          if (widget.date == null) {
            await _service.saveAttendance(className: _attendanceKey, attendance: toSave);
          } else {
            await _service.saveAttendanceForDate(className: _attendanceKey, attendance: toSave, date: widget.date!);
          }

          // Absence notices are secondary — a failure here must NEVER block the
          // save confirmation, so each is awaited inside its own guard. Notify
          // ONLY students whose status actually changed to Absent/Leave since
          // the last save, so re-saving doesn't duplicate alerts (#74).
          // Issue 19: also guard on consent — absence notifications must NOT be
          // sent for students whose guardian has not given data-processing consent.
          for (final s in _students) {
            final status = _attendance[s.roll];
            final wasStatus = _savedStatuses[s.roll];
            if ((status == 'Absent' || status == 'Leave') && status != wasStatus) {
              // Skip if consent has been loaded but this student is not in
              // the consented set.  Use buildDocId (not s.admissionId) to match
              // the key format used by _loadConsent / ConsentService.
              if (_consentLoaded && !_consentedIds.contains(
                  Student.buildDocId(s.roll, s.className, s.section))) continue;
              
              // Trigger simulated SMS alert in Firestore
              final phoneNum = s.parentPhone != null && s.parentPhone!.isNotEmpty ? s.parentPhone! : s.phone;
              SmsGatewaySimulator().sendAbsenceAlert(
                schoolId: BaseFirestoreService.currentSchoolId ?? 'school_1',
                studentName: s.name,
                roll: s.roll,
                parentPhone: phoneNum,
                status: status!,
              ).catchError((e) {
                AppLogger.e('Attendance', 'Simulated SMS dispatch error: $e');
                return false;
              });

              try {
                await NotificationService().addAbsenceNotice(
                  className:   _className,
                  roll:        s.roll,
                  studentName: s.name,
                  status:      status,
                  admissionId: s.admissionId,
                );
              } catch (_) {
                await _queueFailedNotification(
                  className:   _className,
                  roll:        s.roll,
                  studentName: s.name,
                  status:      status,
                  admissionId: s.admissionId,
                );
              }
            }
          }
          // Update the persisted snapshot to what we just saved.
          _savedStatuses
            ..clear()
            ..addAll(toSave);

          if (!mounted) return;
          setState(() {
            _dirty        = false;
            _alreadySaved = true;
            _isMarking    = false;
          });
          await _showSavedDialog();
          return;
        } on AttendanceLockedException catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(e.message),
              backgroundColor: Colors.orange,
            ));
          }
          return;
        } catch (e) {
          // The online write failed (e.g. permission-denied or a network/DNS
          // drop). Previously this threw out of _save with no feedback AND
          // without persisting anything, so the button looked dead and the
          // marks were lost. Fall back to the offline queue so the marks are
          // preserved and will sync later, and tell the teacher what happened.
          await _offlineQueue.enqueue(className: _attendanceKey, attendance: toSave, date: widget.date);
          await _updatePendingCounts();
          if (!mounted) return;
          setState(() {
            _dirty        = false;
            _alreadySaved = true;
            _isMarking    = false;
          });
          await _showSaveFallbackDialog(e);
          return;
        }
      }

      // Offline from the start — queue locally.
      await _offlineQueue.enqueue(className: _attendanceKey, attendance: toSave, date: widget.date);
      await _updatePendingCounts();
      if (!mounted) return;
      setState(() {
        _dirty        = false;
        _alreadySaved = true;
        _isMarking    = false;
      });
      await _showOfflineDialog();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showSavedDialog() => showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 24),
            const SizedBox(width: 10),
            Text(context.tr('attendanceSaved'), style: const TextStyle(fontSize: 16)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            _SummaryRow('Total Students', '$_total', Colors.grey),
            _SummaryRow('Present', '$_present', AppTheme.success),
            _SummaryRow('On Leave', '$_leave', AppTheme.warning),
            _SummaryRow('Absent', '$_absent', AppTheme.danger),
          ]),
          actions: [
            if (_absent + _leave > 0 && Provider.of<SchoolSettingsProvider>(context, listen: false).whatsappEnabled)
              TextButton.icon(
                onPressed: () { Navigator.pop(ctx); _showWhatsAppSheet(); },
                icon: const Icon(FontAwesomeIcons.whatsapp, size: 16, color: Colors.green),
                label: Text(context.tr('notifyViaWhatsapp'), style: const TextStyle(color: Colors.green)),
              ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              child: Text(context.tr('done')),
            ),
          ],
        ),
      );

  Future<void> _showOfflineDialog() => showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(children: [
            const Icon(Icons.cloud_off_outlined, color: Colors.orange, size: 24),
            const SizedBox(width: 10),
            Text(context.tr('savedOffline'), style: const TextStyle(fontSize: 16)),
          ]),
          content: const Text(
            'No internet connection. Attendance has been saved locally and '
            'will sync automatically when you are back online.',
            style: TextStyle(fontSize: 13),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
              child: Text(context.tr('ok')),
            ),
          ],
        ),
      );

  Future<void> _showSaveFallbackDialog(Object error) => showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(children: [
            const Icon(Icons.cloud_sync_outlined, color: Colors.orange, size: 24),
            const SizedBox(width: 10),
            Expanded(child: Text(context.tr('savedLocally'), style: const TextStyle(fontSize: 16))),
          ]),
          content: Text(
            'Attendance is saved on this device and will sync when the server '
            'is reachable.\n\nThe live save did not go through:\n$error',
            style: const TextStyle(fontSize: 12),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
              child: Text(context.tr('ok')),
            ),
          ],
        ),
      );

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

  // ── Helpers ─────────────────────────────────────────────────────────────────
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
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) setState(() => _isMarking = false);
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: _buildAppBar(),
        body: _loading
            ? const LoadingState(message: 'Loading students…')
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
    final title = (_section.isNotEmpty &&
            !_className.endsWith('-$_section') &&
            !_className.endsWith(' $_section'))
        ? '$_className - $_section'
        : _className;
    return AppBar(
      leading: (_isMarking && _alreadySaved)
          ? IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: context.tr('close') ?? 'Close',
              onPressed: () => setState(() => _isMarking = false),
            )
          : null,
      title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      actions: [
        if (_isMarking && _students.isNotEmpty && !_isLocked)
          IconButton(
            icon: const Icon(Icons.done_all, color: Colors.white),
            onPressed: _markAllPresent,
            tooltip: context.tr('markAllPresent'),
          ),
        if (!_isListView && _students.isNotEmpty && _currentIndex < _students.length)
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: _showSearchRollDialog,
            tooltip: context.tr('searchByRoll'),
          ),
        IconButton(
          icon: Icon(_isListView ? Icons.style : Icons.list, color: Colors.white),
          onPressed: () => setState(() => _isListView = !_isListView),
          tooltip: _isListView ? 'Switch to Swipe View' : 'Switch to List View',
        ),
        IconButton(
          icon: const Icon(Icons.settings, color: Colors.white),
          onPressed: _showSettingsDialog,
          tooltip: 'Attendance Settings',
        ),
      ],
    );
  }

  void _showSearchRollDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('goToRollNumber')),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: context.tr('enterRollNumberHint')),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('cancel'))),
          ElevatedButton(
            onPressed: () {
              final roll = int.tryParse(controller.text);
              if (roll != null) {
                final idx = _students.indexWhere((s) => s.roll == roll);
                if (idx != -1) {
                  FocusScope.of(context).unfocus();
                  Navigator.pop(ctx);
                  _pageController.animateToPage(
                    idx,
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeInOut,
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.tr('rollNotFound'))),
                  );
                }
              }
            },
            child: Text(context.tr('go')),
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
          else if (_classPendingCount > 0)
            GestureDetector(
              onTap: _syncOfflineQueue,
              child: _banner(AppTheme.primaryMid, Icons.sync_outlined, '$_classPendingCount offline record${_classPendingCount > 1 ? "s" : ""} for this class — Tap to sync'),
            ),

          if (_isListView)
            _buildListView()
          else
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
                  if (_autoMarkPresent && i > _currentIndex && _currentIndex < _students.length) {
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
                      saving: _saving,
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
                        if (_currentIndex == index) {
                          value = 1.0;
                        } else {
                          value = 0.7;
                        }
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
                              hasConsent: !_consentLoaded ||
                                  _consentedIds.contains(Student.buildDocId(
                                      s.roll, s.className, s.section)),
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

  Widget _buildListView() {
    return Expanded(
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _students.length,
              itemBuilder: (context, index) {
                final s = _students[index];
                final status = _attendance[s.roll] ?? '';
                
                Color rowBgColor = Colors.white;
                if (status == 'Present') rowBgColor = Colors.green.shade50.withValues(alpha: 0.1);
                if (status == 'Absent') rowBgColor = Colors.red.shade50.withValues(alpha: 0.1);
                if (status == 'Leave') rowBgColor = Colors.amber.shade50.withValues(alpha: 0.1);

                return Container(
                  color: rowBgColor,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: CircleAvatar(
                      backgroundColor: _getStatusColor(status).withValues(alpha: 0.1),
                      foregroundColor: _getStatusColor(status),
                      child: Text(
                        '${s.roll}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(
                      s.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    subtitle: Text(
                      'Father: ${s.fatherName}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _listViewStatusButton(s.roll, 'Present', 'P', Colors.green),
                        const SizedBox(width: 8),
                        _listViewStatusButton(s.roll, 'Leave', 'L', Colors.amber),
                        const SizedBox(width: 8),
                        _listViewStatusButton(s.roll, 'Absent', 'A', Colors.red),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          // Bottom save action bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
              border: const Border(top: BorderSide(color: AppTheme.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        for (final s in _students) {
                          if (_attendance[s.roll] == '') {
                            _attendance[s.roll] = 'Present';
                          }
                        }
                        _dirty = true;
                      });
                      _triggerFeedback();
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: AppTheme.primary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Mark Rest Present'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('Save Attendance', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    if (status == 'Present') return Colors.green;
    if (status == 'Absent') return Colors.red;
    if (status == 'Leave') return Colors.amber;
    return Colors.grey;
  }

  Widget _listViewStatusButton(int roll, String status, String label, Color color) {
    final active = _attendance[roll] == status;
    return InkWell(
      onTap: () {
        _setStatus(roll, status);
        _triggerFeedback();
        _saveQuietly();
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: active ? color : color.withValues(alpha: 0.05),
          border: Border.all(color: color, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : color,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
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
                color: AppTheme.primary.withValues(alpha: 0.1),
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
                color: AppTheme.primary.withValues(alpha: 0.08),
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
              onPressed: _isLocked ? null : () => setState(() => _isMarking = true),
              icon: Icon(_isLocked ? Icons.lock_outline : Icons.how_to_reg_outlined,
                  size: 22),
              label: Text(
                  _isLocked
                      ? 'Attendance locked for ${_formatDate(widget.date!)}'
                      : widget.date == null
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
            if (!_isLocked) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _markAllPresent,
                icon: const Icon(Icons.done_all, size: 20),
                label: Text(
                  context.tr('markAllPresent'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.success,
                  minimumSize: const Size(double.infinity, 50),
                  side: const BorderSide(color: AppTheme.success, width: 1.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _loadingPrevious ? null : _copyPreviousAttendance,
                icon: _loadingPrevious
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.primaryMid,
                        ),
                      )
                    : const Icon(Icons.copy_outlined, size: 20),
                label: const Text(
                  'Copy Previous Day\'s Attendance',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryMid,
                  minimumSize: const Size(double.infinity, 50),
                  side: const BorderSide(color: AppTheme.primaryMid, width: 1.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ],
            if (!_isOnline) ...[
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.cloud_off_outlined,
                    size: 14, color: Colors.orange.shade600),
                const SizedBox(width: 6),
                Text(context.tr('offlineAttendanceMsg'),
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
              child: const Row(children: [
                Icon(Icons.cloud_off_outlined,
                    color: Colors.white, size: 16),
                SizedBox(width: 8),
                Expanded(
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
          else if (_classPendingCount > 0)
            GestureDetector(
              onTap: () async {
                final synced = await _syncOfflineQueue();
                if (mounted && synced > 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.tr('syncedRecordsSuccess').replaceAll('{count}', synced.toString())),
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
                      '$_classPendingCount offline record${_classPendingCount > 1 ? "s" : ""} for this class waiting — Tap to sync',
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
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2)),
              ],
            ),
            child: Column(children: [
              Row(children: [
                _StatBubble(_total,   'Total',   AppTheme.textSecondary),
                _StatBubble(_present, 'Present', AppTheme.success),
                _StatBubble(_leave,   'Leave',   AppTheme.warning),
                _StatBubble(_absent,  'Absent',  AppTheme.danger),
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
              label: Text(context.tr('editAttendance'),
                  style: const TextStyle(
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

          if (_absent + _leave > 0 && Provider.of<SchoolSettingsProvider>(context, listen: false).whatsappEnabled) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton.icon(
                onPressed: _showWhatsAppSheet,
                icon: const Icon(FontAwesomeIcons.whatsapp,
                    size: 20, color: AppTheme.whatsapp),
                label: Text(context.tr('notifyGuardiansWhatsapp'),
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.whatsapp)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.whatsapp,
                  minimumSize: const Size(double.infinity, 48),
                  side: const BorderSide(
                      color: AppTheme.whatsapp, width: 1.5),
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
      Text(context.tr('noClassAssigned'),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
              color: Colors.grey.shade500)),
      const SizedBox(height: 6),
      Text(context.tr('askCoordinatorAssign'),
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
      Text(context.tr('noStudentsInClassName').replaceAll('{class}', _className),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
              color: Colors.grey.shade500)),
      const SizedBox(height: 6),
      Text(context.tr('addStudentsFirst'),
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
        color: AppTheme.primaryDark,
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
                color: Colors.white.withValues(alpha: 0.15),
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
  final bool hasConsent;

  const _VerticalStudentCard({
    required this.student,
    required this.status,
    required this.remarks,
    this.lastWeek,
    this.lastMonth,
    required this.onStatusChanged,
    required this.hasConsent,
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
            color: AppTheme.primary.withValues(alpha: 0.35),
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
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(Icons.person, size: 150, color: Colors.white24),
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
                            AppTheme.primary.withValues(alpha: 0.5),
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
                  // Name + Consent badge
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(student.name, 
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
                      ConsentMissingBadge(hasConsent: hasConsent),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Highlighted Roll
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
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
                  Text(context.tr('secRemarksComplaints'), 
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white70, letterSpacing: 1.5)),
                  const SizedBox(height: 10),
                  if (remarks.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(context.tr('noActiveRemarks'), 
                          style: const TextStyle(color: Colors.white38, fontStyle: FontStyle.italic, fontSize: 13.5)),
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

}

class _AttendanceSummaryCard extends StatelessWidget {
  final int total, present, absent, leave;
  final VoidCallback onSave, onNotify;
  final bool saving;

  const _AttendanceSummaryCard({
    required this.total,
    required this.present,
    required this.absent,
    required this.leave,
    required this.onSave,
    required this.onNotify,
    this.saving = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: AppTheme.primary.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline, size: 80, color: Colors.white),
            const SizedBox(height: 24),
            Text(context.tr('attendanceDone'), 
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1.0)),
            const SizedBox(height: 40),
            _SummaryItem(context.tr('totalStudents'), '$total'),
            const Divider(color: Colors.white24, height: 24),
            _SummaryItem(context.tr('presentLabel'), '$present'),
            const Divider(color: Colors.white24, height: 24),
            _SummaryItem(context.tr('absentLabel'), '$absent'),
            const Divider(color: Colors.white24, height: 24),
            _SummaryItem(context.tr('leaveLabel'), '$leave'),
            const SizedBox(height: 48),
            
            ElevatedButton(
              onPressed: saving ? null : onSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.primary,
                disabledBackgroundColor: Colors.white70,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: saving
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.primary))
                  : Text(context.tr('saveAttendance'),
                      style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.0)),
            ),
            if ((absent > 0 || leave > 0) && Provider.of<SchoolSettingsProvider>(context, listen: false).whatsappEnabled) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onNotify,
                icon: const Icon(FontAwesomeIcons.whatsapp, size: 18),
                label: Text(context.tr('whatsappAbsenceNotice')),
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
        _CircleAction('P', 'Present', AppTheme.success, status == 'Present', () => onChanged('Present'), isDark: isDark),
        const SizedBox(height: 24),
        _CircleAction('L', 'Leave', AppTheme.warning, status == 'Leave', () => onChanged('Leave'), isDark: isDark),
        const SizedBox(height: 24),
        _CircleAction('A', 'Absent', AppTheme.danger, status == 'Absent', () => onChanged('Absent'), isDark: isDark),
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
            color: selected ? (isDark ? color : Colors.white) : (isDark ? color.withValues(alpha: 0.35) : Colors.white38), 
            width: selected ? 3.0 : 2.0
          ),
          boxShadow: [
            if (selected) 
              BoxShadow(
                color: (isDark ? color : Colors.white).withValues(alpha: 0.4), 
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

  Future<void> _openWhatsApp(
      BuildContext context, Student s, String message) async {
    // Consent gate (#108): WhatsApp sends the child's data to a third party.
    if (!await ConsentGate.allowsThirdPartyShare(context,
        roll: s.roll, className: s.className, section: s.section)) {
      return;
    }
    // Normalise to a wa.me-ready number (digits + country code, #62).
    final digits = PhoneUtils.whatsAppNumber(s.phone);
    if (digits.isEmpty) return;
    final url = PhoneUtils.whatsAppUri(s.phone, text: message);
    try {
      final launched = await canLaunchUrl(url) &&
          await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr('whatsappNotAvailable')),
          backgroundColor: Colors.orange,
        ));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr('whatsappNotAvailable')),
          backgroundColor: Colors.orange,
        ));
      }
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
                color: AppTheme.whatsapp.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(FontAwesomeIcons.whatsapp,
                  color: AppTheme.whatsapp, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('notifyGuardiansWhatsapp'),
                    style: const TextStyle(
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
                _label('Absent', AppTheme.danger),
                ...absent.map((s) => _NotifyRow(
                      student: s, message: _message(s),
                      onSend: () => _openWhatsApp(context, s, _message(s)),
                    )),
              ],
              if (onLeave.isNotEmpty) ...[
                _label('On Leave', AppTheme.warning),
                ...onLeave.map((s) => _NotifyRow(
                      student: s, message: _message(s),
                      onSend: () => _openWhatsApp(context, s, _message(s)),
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
              backgroundColor: AppTheme.whatsapp,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(context.tr('done'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
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
                color: AppTheme.whatsapp,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(FontAwesomeIcons.whatsapp, color: Colors.white, size: 14),
                SizedBox(width: 4),
                Text(context.tr('whatsApp'),
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

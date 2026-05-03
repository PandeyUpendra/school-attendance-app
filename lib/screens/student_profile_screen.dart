import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/attendance_status.dart';
import '../models/student.dart';
import '../models/student_profile_data.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';

class StudentProfileScreen extends StatefulWidget {
  final Student student;
  final String className;
  final String schoolId;

  const StudentProfileScreen({
    super.key,
    required this.student,
    required this.className,
    required this.schoolId,
  });

  @override
  State<StudentProfileScreen> createState() => _StudentProfileScreenState();
}

class _StudentProfileScreenState extends State<StudentProfileScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool _loading = true;

  // Profile data
  FeesStatus _feesStatus = FeesStatus.pending;
  List<TestResult> _tests = [];
  List<BehaviorNote> _behaviorNotes = [];
  List<Complaint> _complaints = [];

  // Attendance
  Map<String, AttendanceStatus?> _last7Days = {};
  Map<DateTime, AttendanceStatus> _allAttendance = {};
  double _attendancePercent = 0;
  int _presentCount = 0;
  int _totalDays = 0;
  DateTime _focusedDay = DateTime.now();

  String? _teacherName;
  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging) {
          setState(() => _currentTab = _tabController.index);
        }
      });
    _teacherName = context.read<AuthProvider>().user?.name;
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String get _initials {
    final parts = widget.student.name.trim().split(' ');
    if (parts.length >= 2 &&
        parts[0].isNotEmpty &&
        parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0][0].toUpperCase();
    }
    return '?';
  }

  String _fmtDate(DateTime dt) {
    const m = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${m[dt.month]} ${dt.year}';
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 30) return _fmtDate(dt);
    if (diff.inDays >= 1) return '${diff.inDays}d ago';
    if (diff.inHours >= 1) return '${diff.inHours}h ago';
    return 'Just now';
  }

  Color _feesColor(FeesStatus fs) {
    switch (fs) {
      case FeesStatus.paid:    return Colors.green.shade600;
      case FeesStatus.pending: return Colors.amber.shade700;
      case FeesStatus.overdue: return Colors.red.shade600;
    }
  }

  IconData _feesIcon(FeesStatus fs) {
    switch (fs) {
      case FeesStatus.paid:    return Icons.check_circle_outline;
      case FeesStatus.pending: return Icons.hourglass_empty_rounded;
      case FeesStatus.overdue: return Icons.error_outline;
    }
  }

  Color _tagColor(BehaviorTag tag) {
    switch (tag) {
      case BehaviorTag.positive: return Colors.green.shade600;
      case BehaviorTag.neutral:  return Colors.grey.shade600;
      case BehaviorTag.concern:  return Colors.red.shade600;
    }
  }

  IconData _tagIcon(BehaviorTag tag) {
    switch (tag) {
      case BehaviorTag.positive: return Icons.thumb_up_outlined;
      case BehaviorTag.neutral:  return Icons.remove_circle_outline;
      case BehaviorTag.concern:  return Icons.warning_amber_rounded;
    }
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    if (widget.schoolId.isEmpty) {
      setState(() => _loading = false);
      return;
    }

    final profileFuture = FirestoreService.loadStudentProfile(
        schoolId: widget.schoolId,
        classId: widget.className,
        roll: widget.student.roll);

    final last7Future = FirestoreService.getLastNDaysAttendance(
        schoolId: widget.schoolId,
        classId: widget.className,
        studentRoll: widget.student.roll);

    final historyFuture = FirestoreService.getStudentAttendanceHistory(
        schoolId: widget.schoolId,
        classId: widget.className,
        studentRoll: widget.student.roll);

    final results = await Future.wait([profileFuture, last7Future, historyFuture]);

    final profile = results[0] as Map<String, dynamic>?;
    final last7 = results[1] as Map<String, AttendanceStatus?>;
    final history = results[2] as List<Map<String, dynamic>>;

    // Build calendar map
    final allAtt = <DateTime, AttendanceStatus>{};
    int pCount = 0;
    for (final h in history) {
      final parts = (h['date'] as String).split('-');
      if (parts.length == 3) {
        final dt = DateTime(
            int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
        final status = h['status'] as AttendanceStatus;
        allAtt[dt] = status;
        if (status.isPresent) pCount++;
      }
    }

    setState(() {
      if (profile != null) {
        _feesStatus =
            FeesStatus.fromString(profile['feesStatus'] as String?);
        _tests = (profile['tests'] as List<dynamic>? ?? [])
            .map((e) => TestResult.fromMap(e as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
        _behaviorNotes =
            (profile['behaviorNotes'] as List<dynamic>? ?? [])
                .map((e) =>
                    BehaviorNote.fromMap(e as Map<String, dynamic>))
                .toList()
              ..sort((a, b) => b.date.compareTo(a.date));
        _complaints = (profile['complaints'] as List<dynamic>? ?? [])
            .map((e) => Complaint.fromMap(e as Map<String, dynamic>))
            .toList();
      }
      _last7Days = last7;
      _allAttendance = allAtt;
      _presentCount = pCount;
      _totalDays = history.length;
      _attendancePercent =
          history.isEmpty ? 0 : pCount / history.length;
      _loading = false;
    });
  }

  // ── Profile actions ───────────────────────────────────────────────────────

  Future<void> _updateFees(FeesStatus status) async {
    setState(() => _feesStatus = status);
    if (widget.schoolId.isNotEmpty) {
      await FirestoreService.updateStudentProfile(
          schoolId: widget.schoolId,
          classId: widget.className,
          roll: widget.student.roll,
          data: {'feesStatus': status.name});
    }
  }

  void _showAddNoteSheet() {
    final ctrl = TextEditingController();
    BehaviorTag selectedTag = BehaviorTag.neutral;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Add Behavior Note',
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                maxLines: 3,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Write a note about this student…',
                ),
              ),
              const SizedBox(height: 16),
              const Text('Tag',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                children: BehaviorTag.values.map((tag) {
                  final sel = selectedTag == tag;
                  final color = _tagColor(tag);
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: () => setSheet(() => selectedTag = tag),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding:
                              const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: sel
                                ? color.withOpacity(0.12)
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color:
                                    sel ? color : Colors.transparent,
                                width: 1.5),
                          ),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              Icon(_tagIcon(tag),
                                  size: 14,
                                  color: sel
                                      ? color
                                      : Colors.grey.shade400),
                              const SizedBox(width: 4),
                              Text(tag.label,
                                  style: TextStyle(
                                      color:
                                          sel ? color : Colors.grey,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final text = ctrl.text.trim();
                    if (text.isEmpty) return;
                    final note = BehaviorNote(
                      text: text,
                      tag: selectedTag,
                      date: DateTime.now(),
                      addedBy: _teacherName ?? 'Teacher',
                    );
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    setState(() => _behaviorNotes.insert(0, note));
                    if (widget.schoolId.isNotEmpty) {
                      await FirestoreService.appendToStudentProfile(
                          schoolId: widget.schoolId,
                          classId: widget.className,
                          roll: widget.student.roll,
                          arrayField: 'behaviorNotes',
                          item: note.toMap());
                    }
                  },
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Save Note'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddTestSheet() {
    final nameCtrl = TextEditingController();
    final obtainedCtrl = TextEditingController();
    final totalCtrl = TextEditingController(text: '100');
    String selSubject = 'Math';
    DateTime selDate = DateTime.now();

    const subjects = [
      'Math', 'English', 'Science', 'Hindi',
      'Social Studies', 'Computer', 'Other',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Add Test Result',
                    style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                      labelText: 'Test Name',
                      hintText: 'e.g. Unit Test 1, Midterm…'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selSubject,
                  decoration:
                      const InputDecoration(labelText: 'Subject'),
                  items: subjects
                      .map((s) =>
                          DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) =>
                      setSheet(() => selSubject = v ?? selSubject),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: obtainedCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Marks Obtained'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: totalCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Total Marks'),
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today_outlined,
                      color: Color(0xFF1565C0), size: 20),
                  title: Text(_fmtDate(selDate),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600)),
                  subtitle: const Text('Test Date'),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: selDate,
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setSheet(() => selDate = picked);
                    }
                  },
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final name = nameCtrl.text.trim();
                      final obtained =
                          int.tryParse(obtainedCtrl.text.trim()) ?? 0;
                      final total =
                          int.tryParse(totalCtrl.text.trim()) ?? 100;
                      if (name.isEmpty) return;
                      final test = TestResult(
                        name: name,
                        subject: selSubject,
                        marksObtained: obtained,
                        totalMarks: total,
                        date: selDate,
                      );
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      setState(() => _tests.insert(0, test));
                      if (widget.schoolId.isNotEmpty) {
                        await FirestoreService.appendToStudentProfile(
                            schoolId: widget.schoolId,
                            classId: widget.className,
                            roll: widget.student.roll,
                            arrayField: 'tests',
                            item: test.toMap());
                      }
                    },
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('Save Result'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Avatar ────────────────────────────────────────────────────────────────

  Widget _buildAvatar(double radius) {
    final s = widget.student;
    final hasLocal =
        s.photoPath != null && File(s.photoPath!).existsSync();
    final hasCloud =
        s.photoUrl != null && s.photoUrl!.isNotEmpty;

    ImageProvider? img;
    if (hasLocal) img = FileImage(File(s.photoPath!));
    else if (hasCloud) img = NetworkImage(s.photoUrl!);

    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.white.withOpacity(0.25),
      backgroundImage: img,
      child: img == null
          ? Text(_initials,
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: radius * 0.55))
          : null,
    );
  }

  // ── Fees chip (shown in header) ───────────────────────────────────────────

  Widget _feesChip() {
    final color = _feesColor(_feesStatus);
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.5)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(_feesIcon(_feesStatus), color: Colors.white, size: 13),
        const SizedBox(width: 5),
        Text('Fees: ${_feesStatus.label}',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }

  // ── Overview tab ──────────────────────────────────────────────────────────

  Widget _overviewTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      children: [
        // Parent information
        _SectionCard(
          title: 'Parent Information',
          icon: Icons.family_restroom_outlined,
          child: (widget.student.parentPhone != null &&
                  widget.student.parentPhone!.isNotEmpty)
              ? ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                        color: const Color(0xFF1565C0).withOpacity(0.1),
                        shape: BoxShape.circle),
                    child: const Icon(Icons.phone_outlined,
                        color: Color(0xFF1565C0), size: 20),
                  ),
                  title: Text(widget.student.parentPhone!,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                  subtitle: const Text('Parent Phone'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _IconBtn(
                        icon: Icons.call_rounded,
                        color: Colors.green.shade600,
                        tooltip: 'Call',
                        onTap: () => launchUrl(Uri.parse(
                            'tel:${widget.student.parentPhone}')),
                      ),
                      _IconBtn(
                        icon: Icons.chat_rounded,
                        color: const Color(0xFF25D366),
                        tooltip: 'WhatsApp',
                        onTap: () {
                          final num = widget.student.parentPhone!
                              .replaceAll(RegExp(r'\D'), '');
                          launchUrl(Uri.parse('https://wa.me/$num'),
                              mode: LaunchMode.externalApplication);
                        },
                      ),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('No parent contact saved.',
                      style: TextStyle(color: Colors.grey.shade500)),
                ),
        ),

        const SizedBox(height: 16),

        // Fees status selector
        _SectionCard(
          title: 'Fees Status',
          icon: Icons.payments_outlined,
          child: Row(
            children: FeesStatus.values.map((fs) {
              final isSel = _feesStatus == fs;
              final color = _feesColor(fs);
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => _updateFees(fs),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding:
                          const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: isSel
                            ? color.withOpacity(0.10)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: isSel ? color : Colors.transparent,
                            width: 1.8),
                      ),
                      child: Column(children: [
                        Icon(_feesIcon(fs),
                            size: 20,
                            color: isSel
                                ? color
                                : Colors.grey.shade400),
                        const SizedBox(height: 4),
                        Text(fs.label,
                            style: TextStyle(
                                color:
                                    isSel ? color : Colors.grey,
                                fontWeight: FontWeight.w600,
                                fontSize: 12)),
                      ]),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 16),

        // Last 7 days strip
        _SectionCard(
          title: 'Last 7 Days',
          icon: Icons.date_range_outlined,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: _last7Days.entries.map((e) {
              final date = DateTime.parse(e.key);
              final status = e.value;
              const dayNames = [
                'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
              ];
              Color dotColor;
              IconData? dotIcon;
              if (status == null) {
                dotColor = Colors.grey.shade300;
              } else if (status.isPresent) {
                dotColor = Colors.green.shade500;
                dotIcon = Icons.check;
              } else if (status.isLeave) {
                dotColor = Colors.blue.shade400;
                dotIcon = Icons.event_busy;
              } else {
                dotColor = Colors.red.shade400;
                dotIcon = Icons.close;
              }
              return Column(children: [
                Text(dayNames[date.weekday - 1],
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 5),
                Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                      color: dotColor, shape: BoxShape.circle),
                  child: dotIcon != null
                      ? Icon(dotIcon,
                          color: Colors.white, size: 14)
                      : null,
                ),
                const SizedBox(height: 4),
                Text('${date.day}',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade400)),
              ]);
            }).toList(),
          ),
        ),

        const SizedBox(height: 16),

        // Complaints
        _SectionCard(
          title: 'Complaints (${_complaints.length})',
          icon: Icons.report_problem_outlined,
          child: _complaints.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Icon(Icons.check_circle_outline,
                        size: 16, color: Colors.green.shade400),
                    const SizedBox(width: 8),
                    Text('No open complaints.',
                        style: TextStyle(
                            color: Colors.grey.shade500)),
                  ]),
                )
              : Column(
                  children: _complaints.map((c) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: Colors.orange.shade100),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.text,
                              style: const TextStyle(fontSize: 13)),
                          const SizedBox(height: 4),
                          Row(children: [
                            Icon(Icons.menu_book_outlined,
                                size: 12,
                                color: Colors.orange.shade700),
                            const SizedBox(width: 4),
                            Text(
                              '${c.subject} · ${c.addedBy} · ${_timeAgo(c.date)}',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.orange.shade700),
                            ),
                          ]),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  // ── Attendance tab ────────────────────────────────────────────────────────

  Widget _attendanceTab() {
    final pctStr =
        '${(_attendancePercent * 100).toStringAsFixed(1)}%';
    final pctColor = _attendancePercent >= 0.75
        ? Colors.green.shade600
        : _attendancePercent >= 0.50
            ? Colors.orange.shade700
            : Colors.red.shade600;

    return SingleChildScrollView(
      child: Column(
        children: [
          // Overall badge
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1565C0), Color(0xFF1E88E5)],
              ),
            ),
            child: Column(children: [
              Text(pctStr,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.bold)),
              const Text('Overall Attendance',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('$_presentCount present',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12)),
                const Text('  ·  ',
                    style: TextStyle(color: Colors.white38)),
                Text(
                    '${_totalDays - _presentCount} absent/leave',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12)),
                const Text('  ·  ',
                    style: TextStyle(color: Colors.white38)),
                Text('$_totalDays days tracked',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12)),
              ]),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _attendancePercent,
                  minHeight: 8,
                  backgroundColor: Colors.white24,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(pctColor),
                ),
              ),
              const SizedBox(height: 12),
              // Legend
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _Dot(color: Colors.green.shade400, label: 'Present'),
                const SizedBox(width: 16),
                _Dot(color: Colors.red.shade400, label: 'Absent'),
                const SizedBox(width: 16),
                _Dot(color: Colors.blue.shade400, label: 'Leave'),
              ]),
            ]),
          ),

          // Calendar
          TableCalendar(
            firstDay: DateTime(2024, 1, 1),
            lastDay: DateTime.now().add(const Duration(days: 1)),
            focusedDay: _focusedDay,
            onPageChanged: (f) => setState(() => _focusedDay = f),
            headerStyle: const HeaderStyle(
                formatButtonVisible: false, titleCentered: true),
            calendarStyle: CalendarStyle(
              todayDecoration: BoxDecoration(
                color: const Color(0xFF1565C0).withOpacity(0.25),
                shape: BoxShape.circle,
              ),
            ),
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (ctx, day, _) {
                final key =
                    DateTime(day.year, day.month, day.day);
                final status = _allAttendance[key];
                if (status == null) return null;
                Color bg;
                Color fg;
                if (status.isPresent) {
                  bg = Colors.green.shade100;
                  fg = Colors.green.shade700;
                } else if (status.isLeave) {
                  bg = Colors.blue.shade100;
                  fg = Colors.blue.shade700;
                } else {
                  bg = Colors.red.shade100;
                  fg = Colors.red.shade700;
                }
                return Container(
                  margin: const EdgeInsets.all(4),
                  decoration:
                      BoxDecoration(color: bg, shape: BoxShape.circle),
                  child: Center(
                    child: Text('${day.day}',
                        style: TextStyle(
                            color: fg,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Performance tab ───────────────────────────────────────────────────────

  Widget _performanceTab() {
    if (_tests.isEmpty) {
      return _EmptyState(
        icon: Icons.school_outlined,
        title: 'No test results yet',
        subtitle: 'Tap + to add a test result',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      itemCount: _tests.length,
      itemBuilder: (context, i) {
        final t = _tests[i];
        final pct =
            t.totalMarks > 0 ? t.marksObtained / t.totalMarks : 0.0;
        final color = pct >= 0.75
            ? Colors.green.shade600
            : pct >= 0.50
                ? Colors.orange.shade700
                : Colors.red.shade600;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color:
                Theme.of(context).cardTheme.color ?? Colors.white,
            borderRadius: BorderRadius.circular(14),
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
              Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
                      const SizedBox(height: 4),
                      Row(children: [
                        _SubjectChip(t.subject),
                        const SizedBox(width: 8),
                        Text(_fmtDate(t.date),
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500)),
                      ]),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${t.marksObtained}/${t.totalMarks}',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: color)),
                    Text('${(pct * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                            fontSize: 12, color: color)),
                  ],
                ),
              ]),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct,
                  backgroundColor: color.withOpacity(0.12),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: 6,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Behavior tab ──────────────────────────────────────────────────────────

  Widget _behaviorTab() {
    if (_behaviorNotes.isEmpty) {
      return _EmptyState(
        icon: Icons.notes_outlined,
        title: 'No behavior notes yet',
        subtitle: 'Tap + to add a note',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      itemCount: _behaviorNotes.length,
      itemBuilder: (context, i) {
        final note = _behaviorNotes[i];
        final color = _tagColor(note.tag);
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color:
                Theme.of(context).cardTheme.color ?? Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.3)),
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
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_tagIcon(note.tag),
                            color: color, size: 13),
                        const SizedBox(width: 4),
                        Text(note.tag.label,
                            style: TextStyle(
                                color: color,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ]),
                ),
                const Spacer(),
                Text(_timeAgo(note.date),
                    style: TextStyle(
                        color: Colors.grey.shade400, fontSize: 11)),
              ]),
              const SizedBox(height: 8),
              Text(note.text,
                  style: const TextStyle(fontSize: 13, height: 1.4)),
              const SizedBox(height: 6),
              Text('— ${note.addedBy}',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade400,
                      fontStyle: FontStyle.italic)),
            ],
          ),
        );
      },
    );
  }

  // ── FAB (context-sensitive) ───────────────────────────────────────────────

  Widget? _buildFab() {
    if (_currentTab == 2) {
      return FloatingActionButton(
        heroTag: 'add_test',
        onPressed: _showAddTestSheet,
        tooltip: 'Add test result',
        child: const Icon(Icons.add),
      );
    }
    if (_currentTab == 3) {
      return FloatingActionButton(
        heroTag: 'add_note',
        onPressed: _showAddNoteSheet,
        tooltip: 'Add behavior note',
        child: const Icon(Icons.add),
      );
    }
    return null;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (ctx, innerScrolled) => [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            forceElevated: innerScrolled,
            backgroundColor: const Color(0xFF1565C0),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1565C0), Color(0xFF1E88E5)],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 8),
                      _buildAvatar(38),
                      const SizedBox(height: 10),
                      Text(
                        widget.student.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Roll ${widget.student.roll}  ·  ${widget.className}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 10),
                      if (!_loading) _feesChip(),
                    ],
                  ),
                ),
              ),
            ),
            bottom: TabBar(
              controller: _tabController,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              labelStyle: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: 'Overview'),
                Tab(text: 'Attendance'),
                Tab(text: 'Performance'),
                Tab(text: 'Behavior'),
              ],
            ),
          ),
        ],
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: [
                  _overviewTab(),
                  _attendanceTab(),
                  _performanceTab(),
                  _behaviorTab(),
                ],
              ),
      ),
      floatingActionButton: _loading ? null : _buildFab(),
    );
  }
}

// ── Reusable small widgets ────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color ?? Colors.white,
        borderRadius: BorderRadius.circular(14),
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
          Row(children: [
            Icon(icon, size: 16, color: const Color(0xFF1565C0)),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF1565C0))),
          ]),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1),
          ),
          child,
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _IconBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: color, size: 22),
      tooltip: tooltip,
      onPressed: onTap,
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  final String label;

  const _Dot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 8, height: 8,
          decoration:
              BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label,
          style: const TextStyle(color: Colors.white70, fontSize: 12)),
    ]);
  }
}

class _SubjectChip extends StatelessWidget {
  final String subject;
  const _SubjectChip(this.subject);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF1565C0).withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(subject,
          style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF1565C0),
              fontWeight: FontWeight.w500)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(title,
              style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 16,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Text(subtitle,
              style: TextStyle(
                  color: Colors.grey.shade400, fontSize: 13)),
        ],
      ),
    );
  }
}

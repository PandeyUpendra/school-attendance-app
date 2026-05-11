import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/attendance_status.dart';
import '../models/student.dart';
import '../models/student_profile_data.dart';
import '../providers/auth_provider.dart';
import '../services/attendance_service.dart';
import '../services/firestore_service.dart';
import 'attendance_screen.dart';
import 'student_profile_screen.dart';
import 'test_creation_screen.dart';

class ClassManagementScreen extends StatefulWidget {
  final String className;
  final String schoolId;

  const ClassManagementScreen({
    super.key,
    required this.className,
    required this.schoolId,
  });

  @override
  State<ClassManagementScreen> createState() =>
      _ClassManagementScreenState();
}

class _ClassManagementScreenState extends State<ClassManagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  // Students
  List<Student> _students = [];
  bool _studentsLoaded = false;

  // Tests
  List<Map<String, dynamic>> _tests = [];
  bool _testsLoaded = false;

  // Syllabus
  List<Map<String, dynamic>> _chapters = [];
  bool _syllabusLoaded = false;

  // Complaints
  List<Map<String, dynamic>> _complaints = [];
  bool _complaintsLoaded = false;

  // PTM
  List<Map<String, dynamic>> _ptmList = [];
  bool _ptmLoaded = false;

  // Attendance summary
  Map<int, AttendanceStatus> _todayAtt = {};
  bool _attLoaded = false;

  String? _teacherName;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 6, vsync: this)
      ..addListener(() {
        if (!_tabs.indexIsChanging) _loadTabData(_tabs.index);
      });
    _teacherName = context.read<AuthProvider>().user?.name;
    _loadTabData(0); // load attendance tab first
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadTabData(int index) async {
    switch (index) {
      case 0: // Attendance
        if (_attLoaded) return;
        final today = DateTime.now();
        final dateKey =
            '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
        Map<int, AttendanceStatus>? att;
        if (widget.schoolId.isNotEmpty) {
          att = await FirestoreService.loadAttendance(
              schoolId: widget.schoolId,
              classId: widget.className,
              date: dateKey);
        }
        att ??= await AttendanceService.loadAttendance(
            className: widget.className, date: today);
        if (mounted) {
          setState(() {
            _todayAtt = att ?? {};
            _attLoaded = true;
          });
        }
        _ensureStudentsLoaded();

      case 1: // Students
        _ensureStudentsLoaded();

      case 2: // Tests
        if (_testsLoaded) return;
        _ensureStudentsLoaded();
        final tests = await FirestoreService.getTests(
            schoolId: widget.schoolId, classId: widget.className);
        if (mounted) setState(() { _tests = tests; _testsLoaded = true; });

      case 3: // Syllabus
        if (_syllabusLoaded) return;
        final chapters = await FirestoreService.loadSyllabus(
            schoolId: widget.schoolId, classId: widget.className);
        if (mounted) setState(() {
          _chapters = chapters ?? [];
          _syllabusLoaded = true;
        });

      case 4: // Complaints
        if (_complaintsLoaded) return;
        final comp = await FirestoreService.loadClassComplaints(
            schoolId: widget.schoolId, classId: widget.className);
        if (mounted) setState(() {
          _complaints = comp ?? [];
          _complaintsLoaded = true;
        });

      case 5: // PTM
        if (_ptmLoaded) return;
        final ptm = await FirestoreService.getPtmList(
            schoolId: widget.schoolId, classId: widget.className);
        if (mounted) setState(() { _ptmList = ptm; _ptmLoaded = true; });
    }
  }

  Future<void> _ensureStudentsLoaded() async {
    if (_studentsLoaded) return;
    List<Student>? students;
    if (widget.schoolId.isNotEmpty) {
      final cloud = await FirestoreService.loadStudents(
          schoolId: widget.schoolId, classId: widget.className);
      if (cloud != null) {
        students = cloud
            .map((e) => Student.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    }
    students ??= await AttendanceService.loadStudents(widget.className);
    if (mounted && students != null) {
      setState(() { _students = students!; _studentsLoaded = true; });
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _fmtDate(dynamic raw) {
    DateTime? dt;
    if (raw is Timestamp) dt = raw.toDate();
    if (dt == null) return '—';
    const m = ['', 'Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${dt.day} ${m[dt.month]} ${dt.year}';
  }

  String _fmtDateTime(dynamic raw) {
    DateTime? dt;
    if (raw is Timestamp) dt = raw.toDate();
    if (dt == null) return '—';
    const m = ['', 'Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${dt.day} ${m[dt.month]} ${dt.year}';
  }

  // ── Tab 0: Attendance ─────────────────────────────────────────────────────

  Widget _attendanceTab() {
    final present = _todayAtt.values.where((v) => v.isPresent).length;
    final absent = _todayAtt.values.where((v) => v.isAbsent).length;
    final leave = _todayAtt.values.where((v) => v.isLeave).length;
    final total = _todayAtt.length;
    final pct = total > 0 ? present / total : 0.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Today header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1565C0), Color(0xFF1E88E5)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(children: [
            const Text("Today's Attendance",
                style: TextStyle(
                    color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 8),
            _attLoaded && total > 0
                ? Column(children: [
                    Text(
                      '${(pct * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 42,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _AttBadge(present, 'Present',
                            Colors.greenAccent.shade400),
                        const SizedBox(width: 12),
                        _AttBadge(absent, 'Absent',
                            Colors.redAccent.shade200),
                        const SizedBox(width: 12),
                        _AttBadge(leave, 'Leave',
                            Colors.lightBlueAccent),
                      ],
                    ),
                  ])
                : _attLoaded
                    ? const Text('No attendance taken yet today.',
                        style: TextStyle(
                            color: Colors.white70, fontSize: 13))
                    : const SizedBox(
                        width: 24, height: 24,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2)),
          ]),
        ),

        const SizedBox(height: 20),

        // Take attendance button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    AttendanceScreen(className: widget.className),
              ),
            ).then((_) {
              setState(() => _attLoaded = false);
              _loadTabData(0);
            }),
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Take / Update Attendance'),
          ),
        ),
      ],
    );
  }

  // ── Tab 1: Students ───────────────────────────────────────────────────────

  Widget _studentsTab() {
    if (!_studentsLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_students.isEmpty) {
      return _Empty(Icons.people_outline, 'No students yet',
          'Add students from the attendance screen');
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
      itemCount: _students.length,
      itemBuilder: (ctx, i) {
        final s = _students[i];
        return _StudentTile(
          student: s,
          onLongPress: () => _showStudentMenu(s),
        );
      },
    );
  }

  void _showStudentMenu(Student student) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 36, height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFF1565C0).withOpacity(0.1),
                  child: Text('${student.roll}',
                      style: const TextStyle(
                          color: Color(0xFF1565C0),
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(student.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  Text('Roll ${student.roll}',
                      style: TextStyle(
                          color: Colors.grey.shade500, fontSize: 12)),
                ]),
              ]),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.person_outlined,
                  color: Color(0xFF1565C0)),
              title: const Text('View Profile'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StudentProfileScreen(
                      student: student,
                      className: widget.className,
                      schoolId: widget.schoolId,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.notes_outlined,
                  color: Color(0xFF6A1B9A)),
              title: const Text('Add Behavior Note'),
              onTap: () {
                Navigator.pop(context);
                _addBehaviorNoteFor(student);
              },
            ),
            ListTile(
              leading: const Icon(Icons.report_problem_outlined,
                  color: Colors.orange),
              title: const Text('View Complaints'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StudentProfileScreen(
                      student: student,
                      className: widget.className,
                      schoolId: widget.schoolId,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _addBehaviorNoteFor(Student student) {
    final ctrl = TextEditingController();
    BehaviorTag tag = BehaviorTag.neutral;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 12),
              Text('Note for ${student.name}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLines: 3,
                autofocus: true,
                decoration: const InputDecoration(
                    hintText: 'Write a behavior note…'),
              ),
              const SizedBox(height: 12),
              Row(
                children: BehaviorTag.values.map((t) {
                  final sel = tag == t;
                  final Color c;
                  switch (t) {
                    case BehaviorTag.positive:
                      c = Colors.green.shade600;
                    case BehaviorTag.concern:
                      c = Colors.red.shade600;
                    case BehaviorTag.neutral:
                      c = Colors.grey.shade600;
                  }
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: () => ss(() => tag = t),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: sel
                                ? c.withOpacity(0.12)
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: sel ? c : Colors.transparent,
                                width: 1.5),
                          ),
                          child: Text(t.label,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: sel ? c : Colors.grey,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12)),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final text = ctrl.text.trim();
                    if (text.isEmpty) return;
                    final note = BehaviorNote(
                      text: text,
                      tag: tag,
                      date: DateTime.now(),
                      addedBy: _teacherName ?? 'Teacher',
                    );
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    if (widget.schoolId.isNotEmpty) {
                      await FirestoreService.appendToStudentProfile(
                          schoolId: widget.schoolId,
                          classId: widget.className,
                          roll: student.roll,
                          arrayField: 'behaviorNotes',
                          item: note.toMap());
                    }
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Note saved!'),
                          behavior: SnackBarBehavior.floating),
                    );
                  },
                  child: const Text('Save Note'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Tab 2: Tests ──────────────────────────────────────────────────────────

  Widget _testsTab() {
    if (!_testsLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    return Stack(
      children: [
        _tests.isEmpty
            ? _Empty(Icons.quiz_outlined, 'No tests yet',
                'Tap + to create a new test')
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
                itemCount: _tests.length,
                itemBuilder: (ctx, i) {
                  final t = _tests[i];
                  final marks =
                      (t['marks'] as Map<String, dynamic>?) ?? {};
                  double avg = 0;
                  if (marks.isNotEmpty) {
                    avg = marks.values
                            .map((v) => (v as num).toDouble())
                            .reduce((a, b) => a + b) /
                        marks.length;
                  }
                  final total =
                      (t['totalMarks'] as num?)?.toInt() ?? 100;
                  final pct = total > 0 ? avg / total : 0.0;
                  final color = pct >= 0.75
                      ? Colors.green.shade600
                      : pct >= 0.5
                          ? Colors.orange.shade700
                          : Colors.red.shade600;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardTheme.color ??
                          Colors.white,
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
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(t['name'] as String? ?? '—',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15)),
                                const SizedBox(height: 4),
                                Row(children: [
                                  _Tag(t['subject'] as String? ?? ''),
                                  const SizedBox(width: 8),
                                  Text(_fmtDate(t['date']),
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade500)),
                                ]),
                              ],
                            ),
                          ),
                          if (marks.isNotEmpty)
                            Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.end,
                              children: [
                                Text(
                                    '${avg.toStringAsFixed(1)}/$total',
                                    style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: color)),
                                Text('Class avg',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey.shade500)),
                              ],
                            )
                          else
                            Text('No marks',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade400)),
                        ]),
                        if (marks.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: pct,
                              backgroundColor:
                                  color.withOpacity(0.12),
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(color),
                              minHeight: 5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                              '${marks.length} students marked · ${(pct * 100).toStringAsFixed(1)}% avg',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500)),
                        ],
                      ],
                    ),
                  );
                },
              ),

        // FAB
        Positioned(
          bottom: 20,
          right: 16,
          child: FloatingActionButton.extended(
            heroTag: 'test_fab',
            onPressed: () async {
              if (!_studentsLoaded) await _ensureStudentsLoaded();
              if (!mounted) return;
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TestCreationScreen(
                    className: widget.className,
                    schoolId: widget.schoolId,
                    students: _students,
                  ),
                ),
              );
              setState(() => _testsLoaded = false);
              _loadTabData(2);
            },
            icon: const Icon(Icons.add),
            label: const Text('New Test'),
          ),
        ),
      ],
    );
  }

  // ── Tab 3: Syllabus ───────────────────────────────────────────────────────

  Widget _syllabusTab() {
    if (!_syllabusLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    return Stack(
      children: [
        _chapters.isEmpty
            ? _Empty(Icons.menu_book_outlined, 'No chapters yet',
                'Tap + to add a chapter')
            : ListView.builder(
                padding:
                    const EdgeInsets.fromLTRB(14, 14, 14, 90),
                itemCount: _chapters.length,
                itemBuilder: (ctx, i) {
                  final c = _chapters[i];
                  final done = c['completed'] as bool? ?? false;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardTheme.color ??
                          Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                            color: Colors.black12,
                            blurRadius: 3,
                            offset: Offset(0, 1))
                      ],
                    ),
                    child: ListTile(
                      leading: Checkbox(
                        value: done,
                        activeColor: const Color(0xFF1565C0),
                        onChanged: (_) => _toggleChapter(i),
                      ),
                      title: Text(c['name'] as String? ?? '—',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              decoration: done
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: done
                                  ? Colors.grey.shade400
                                  : null)),
                      subtitle: Text(c['subject'] as String? ?? '—',
                          style: const TextStyle(fontSize: 12)),
                      trailing: done
                          ? Icon(Icons.check_circle,
                              color: Colors.green.shade400, size: 18)
                          : Icon(Icons.radio_button_unchecked,
                              color: Colors.grey.shade300, size: 18),
                    ),
                  );
                },
              ),
        Positioned(
          bottom: 20,
          right: 16,
          child: FloatingActionButton(
            heroTag: 'syllabus_fab',
            onPressed: _addChapter,
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  void _toggleChapter(int index) async {
    setState(() {
      _chapters[index] = {
        ..._chapters[index],
        'completed': !(_chapters[index]['completed'] as bool? ?? false),
      };
    });
    if (widget.schoolId.isNotEmpty) {
      await FirestoreService.saveSyllabus(
          schoolId: widget.schoolId,
          classId: widget.className,
          chapters: _chapters);
    }
  }

  void _addChapter() {
    final nameCtrl = TextEditingController();
    String subject = 'Math';
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
        builder: (ctx, ss) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 14),
              const Text('Add Chapter',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    hintText: 'e.g. Chapter 3: Quadratic Equations'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: subject,
                decoration:
                    const InputDecoration(labelText: 'Subject'),
                items: subjects
                    .map((s) =>
                        DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => ss(() => subject = v ?? subject),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    final chapter = {
                      'name': name,
                      'subject': subject,
                      'completed': false,
                      'addedAt':
                          Timestamp.fromDate(DateTime.now()),
                    };
                    setState(() => _chapters.add(chapter));
                    if (widget.schoolId.isNotEmpty) {
                      await FirestoreService.saveSyllabus(
                          schoolId: widget.schoolId,
                          classId: widget.className,
                          chapters: _chapters);
                    }
                  },
                  child: const Text('Add Chapter'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Tab 4: Complaints ─────────────────────────────────────────────────────

  Widget _complaintsTab() {
    if (!_complaintsLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_complaints.isEmpty) {
      return _Empty(Icons.report_problem_outlined, 'No complaints',
          'No subject teacher has filed a complaint');
    }
    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: _complaints.length,
      itemBuilder: (ctx, i) {
        final c = _complaints[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.shade100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c['text'] as String? ?? '—',
                  style: const TextStyle(fontSize: 13, height: 1.4)),
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.menu_book_outlined,
                    size: 12, color: Colors.orange.shade700),
                const SizedBox(width: 4),
                Text(
                  '${c['subject'] ?? '—'}  ·  ${c['addedBy'] ?? '—'}  ·  ${_fmtDateTime(c['date'])}',
                  style: TextStyle(
                      fontSize: 11, color: Colors.orange.shade700),
                ),
              ]),
            ],
          ),
        );
      },
    );
  }

  // ── Tab 5: PTM ────────────────────────────────────────────────────────────

  Widget _ptmTab() {
    if (!_ptmLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    return Stack(
      children: [
        _ptmList.isEmpty
            ? _Empty(Icons.event_outlined, 'No PTM scheduled',
                'Tap + to schedule a parent-teacher meeting')
            : ListView.builder(
                padding:
                    const EdgeInsets.fromLTRB(14, 14, 14, 90),
                itemCount: _ptmList.length,
                itemBuilder: (ctx, i) {
                  final p = _ptmList[i];
                  final status = p['status'] as String? ?? 'scheduled';
                  Color statusColor;
                  switch (status) {
                    case 'completed':
                      statusColor = Colors.green.shade600;
                    case 'cancelled':
                      statusColor = Colors.red.shade600;
                    default:
                      statusColor = const Color(0xFF1565C0);
                  }
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).cardTheme.color ??
                              Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: const [
                        BoxShadow(
                            color: Colors.black12,
                            blurRadius: 4,
                            offset: Offset(0, 2))
                      ],
                    ),
                    child: Row(children: [
                      Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1565C0).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.event_outlined,
                            color: Color(0xFF1565C0), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p['topic'] as String? ?? '—',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14)),
                            const SizedBox(height: 3),
                            Text(
                              '${_fmtDate(p['date'])}  ·  ${p['time'] ?? ''}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () =>
                            _changePtmStatus(p['id'] as String, i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: statusColor.withOpacity(0.3)),
                          ),
                          child: Text(
                            _capFirst(status),
                            style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 12),
                          ),
                        ),
                      ),
                    ]),
                  );
                },
              ),
        Positioned(
          bottom: 20,
          right: 16,
          child: FloatingActionButton(
            heroTag: 'ptm_fab',
            onPressed: _schedulePtm,
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  String _capFirst(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  void _changePtmStatus(String ptmId, int index) {
    const statuses = ['scheduled', 'completed', 'cancelled'];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const Text('Update Status',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15)),
            const Divider(),
            ...statuses.map((s) {
              Color c;
              switch (s) {
                case 'completed':  c = Colors.green.shade600;
                case 'cancelled':  c = Colors.red.shade600;
                default:           c = const Color(0xFF1565C0);
              }
              return ListTile(
                leading: CircleAvatar(
                    backgroundColor: c.withOpacity(0.12),
                    child: Icon(
                      s == 'completed'
                          ? Icons.check_circle_outline
                          : s == 'cancelled'
                              ? Icons.cancel_outlined
                              : Icons.schedule,
                      color: c, size: 18,
                    )),
                title: Text(_capFirst(s)),
                onTap: () async {
                  Navigator.pop(context);
                  setState(() {
                    _ptmList[index] = {..._ptmList[index], 'status': s};
                  });
                  if (widget.schoolId.isNotEmpty) {
                    await FirestoreService.updatePtmStatus(
                        schoolId: widget.schoolId,
                        classId: widget.className,
                        ptmId: ptmId,
                        status: s);
                  }
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _schedulePtm() {
    final topicCtrl = TextEditingController();
    DateTime date = DateTime.now().add(const Duration(days: 7));
    TimeOfDay time = const TimeOfDay(hour: 14, minute: 0);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 14),
              const Text('Schedule PTM',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              TextField(
                controller: topicCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    hintText: 'Meeting topic / agenda',
                    prefixIcon: Icon(Icons.topic_outlined)),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: _PickerButton(
                    icon: Icons.calendar_today_outlined,
                    label: _fmtDate2(date),
                    onTap: () async {
                      final p = await showDatePicker(
                          context: ctx,
                          initialDate: date,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now()
                              .add(const Duration(days: 365)));
                      if (p != null) ss(() => date = p);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PickerButton(
                    icon: Icons.access_time_rounded,
                    label: _fmtTime2(time),
                    onTap: () async {
                      final p = await showTimePicker(
                          context: ctx, initialTime: time);
                      if (p != null) ss(() => time = p);
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final topic = topicCtrl.text.trim();
                    if (topic.isEmpty) return;
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    final h = time.hourOfPeriod == 0
                        ? 12
                        : time.hourOfPeriod;
                    final min =
                        time.minute.toString().padLeft(2, '0');
                    final period = time.period == DayPeriod.am
                        ? 'AM'
                        : 'PM';
                    final data = {
                      'topic': topic,
                      'date': Timestamp.fromDate(date),
                      'time': '$h:$min $period',
                      'status': 'scheduled',
                    };
                    if (widget.schoolId.isNotEmpty) {
                      final id = await FirestoreService.addPtm(
                          schoolId: widget.schoolId,
                          classId: widget.className,
                          data: data);
                      if (mounted) {
                        setState(() =>
                            _ptmList.insert(0, {'id': id, ...data}));
                      }
                    }
                  },
                  child: const Text('Schedule Meeting'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtDate2(DateTime d) {
    const m = ['','Jan','Feb','Mar','Apr','May','Jun',
                   'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${m[d.month]}';
  }

  String _fmtTime2(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final min = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$min $period';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.className),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          tabAlignment: TabAlignment.start,
          labelStyle: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: 'Attendance'),
            Tab(text: 'Students'),
            Tab(text: 'Tests'),
            Tab(text: 'Syllabus'),
            Tab(text: 'Complaints'),
            Tab(text: 'PTM'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _attendanceTab(),
          _studentsTab(),
          _testsTab(),
          _syllabusTab(),
          _complaintsTab(),
          _ptmTab(),
        ],
      ),
    );
  }
}

// ── Small reusable widgets ────────────────────────────────────────────────────

class _AttBadge extends StatelessWidget {
  final int count;
  final String label;
  final Color color;
  const _AttBadge(this.count, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 7, height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text('$count $label',
            style: const TextStyle(
                color: Colors.white, fontSize: 12,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _StudentTile extends StatelessWidget {
  final Student student;
  final VoidCallback onLongPress;
  const _StudentTile({required this.student, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final hasLocal = student.photoPath != null &&
        File(student.photoPath!).existsSync();
    final hasCloud =
        student.photoUrl != null && student.photoUrl!.isNotEmpty;
    ImageProvider? img;
    if (hasLocal) img = FileImage(File(student.photoPath!));
    else if (hasCloud) img = NetworkImage(student.photoUrl!);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color ?? Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))
        ],
      ),
      child: ListTile(
        onLongPress: onLongPress,
        leading: CircleAvatar(
          radius: 22,
          backgroundColor:
              const Color(0xFF1565C0).withOpacity(0.1),
          backgroundImage: img,
          child: img == null
              ? Text('${student.roll}',
                  style: const TextStyle(
                      color: Color(0xFF1565C0),
                      fontWeight: FontWeight.bold))
              : null,
        ),
        title: Text(student.name,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text('Roll ${student.roll}',
            style: const TextStyle(fontSize: 12)),
        trailing: Icon(Icons.adaptive.more,
            color: Colors.grey.shade400, size: 20),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  const _Tag(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF1565C0).withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF1565C0),
              fontWeight: FontWeight.w500)),
    );
  }
}

class _PickerButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _PickerButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Icon(icon, size: 16, color: Colors.grey.shade500),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
      ),
    );
  }
}

Widget _Empty(IconData icon, String title, String subtitle) {
  return Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, size: 72, color: Colors.grey.shade300),
      const SizedBox(height: 16),
      Text(title,
          style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 16,
              fontWeight: FontWeight.w500)),
      const SizedBox(height: 6),
      Text(subtitle,
          style:
              TextStyle(color: Colors.grey.shade400, fontSize: 13)),
    ]),
  );
}

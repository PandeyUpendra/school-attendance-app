import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/student_data.dart';
import '../models/student.dart';
import '../providers/auth_provider.dart';
import '../services/attendance_service.dart';
import '../services/firestore_service.dart';

class CoordinatorHome extends StatefulWidget {
  const CoordinatorHome({super.key});

  @override
  State<CoordinatorHome> createState() => _CoordinatorHomeState();
}

class _CoordinatorHomeState extends State<CoordinatorHome>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // User info
  String _schoolId = '';
  String _coordinatorName = '';
  List<String> _assignedClasses = [];

  // ── Tab 1: Timetable ──
  String? _ttClass;
  bool _ttLoading = true;
  bool _ttSaving = false;
  Map<String, List<Map<String, dynamic>>> _richTimetable = {};
  List<Map<String, dynamic>> _allTeachers = [];

  // ── Tab 2: Teachers ──
  bool _teachersLoading = false;
  bool _teachersLoaded = false;

  // ── Tab 3: Complaints ──
  bool _complaintsLoading = false;
  bool _complaintsLoaded = false;
  List<Map<String, dynamic>> _complaints = [];

  // ── Tab 4: Students ──
  bool _studentsLoading = false;
  bool _studentsLoaded = false;
  String? _studentsClass;
  List<Student> _students = [];
  final Set<int> _expandedRolls = {};
  String _studentSearch = '';

  // ── Period / day constants ──
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  static const _subjects = [
    'Math', 'English', 'Science', 'Hindi', 'Social Studies',
    'Computer', 'Art', 'PE', 'Music', 'Free Period',
  ];
  static const _periods = 8;
  static const _dutyTypes = [
    'Gate Duty', 'Exam Duty', 'Event Duty', 'Other'
  ];

  static const Color _accent = Color(0xFF6A1B9A);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _loadTabData(_tabController.index);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _initUser());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> _initUser() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    _schoolId = user.schoolId;
    _coordinatorName = user.name;

    // Coordinator sees all classes if classIds is empty, otherwise their list
    final allClasses = classStudents.keys.toList();
    _assignedClasses =
        user.classIds.isEmpty ? allClasses : user.classIds;

    if (_assignedClasses.isNotEmpty) {
      _ttClass = _assignedClasses.first;
      _studentsClass = _assignedClasses.first;
    }

    // Load teachers for timetable assignment
    final teachers = await FirestoreService.getUsersBySchool(_schoolId);
    _allTeachers = teachers
        .where((t) =>
            t['role'] == 'teacher' || t['role'] == 'subjectTeacher')
        .toList();

    await _loadRichTimetable();
  }

  void _loadTabData(int tab) {
    switch (tab) {
      case 0:
        if (_ttLoading) _loadRichTimetable();
      case 1:
        if (!_teachersLoaded) _loadTeachers();
      case 2:
        if (!_complaintsLoaded) _loadComplaints();
      case 3:
        if (!_studentsLoaded) _loadStudents();
    }
  }

  // ── Tab 1: Timetable ──────────────────────────────────────────────────────

  Future<void> _loadRichTimetable() async {
    if (_ttClass == null) {
      setState(() => _ttLoading = false);
      return;
    }
    setState(() => _ttLoading = true);

    Map<String, List<Map<String, dynamic>>>? loaded;
    if (_schoolId.isNotEmpty) {
      loaded = await FirestoreService.loadRichTimetable(
          schoolId: _schoolId, classId: _ttClass!);
    }

    setState(() {
      _richTimetable = loaded ??
          {
            for (final day in _days)
              day: List.generate(
                _periods,
                (_) => {'subject': 'Free Period', 'teacher': '', 'room': ''},
              ),
          };
      _ttLoading = false;
    });
  }

  Future<void> _saveTimetable() async {
    if (_ttClass == null || _schoolId.isEmpty) return;
    setState(() => _ttSaving = true);
    await FirestoreService.saveRichTimetable(
        schoolId: _schoolId,
        classId: _ttClass!,
        timetable: _richTimetable);
    setState(() => _ttSaving = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Timetable saved'),
      backgroundColor: _accent,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _editPeriodCell(String day, int periodIndex) {
    final cell = Map<String, dynamic>.from(
        _richTimetable[day]?[periodIndex] ??
            {'subject': 'Free Period', 'teacher': '', 'room': ''});

    String subject = cell['subject'] as String? ?? 'Free Period';
    String teacherUid = cell['teacher'] as String? ?? '';
    String room = cell['room'] as String? ?? '';
    final roomCtrl = TextEditingController(text: room);

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
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: _accent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text('$day · Period ${periodIndex + 1}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _accent,
                              fontSize: 13)),
                    ),
                    const Spacer(),
                    IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const SizedBox(height: 16),
                // Subject
                const Text('Subject',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _subjects.contains(subject) ? subject : 'Free Period',
                  decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.book_outlined)),
                  items: _subjects
                      .map((s) =>
                          DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setInner(() => subject = v);
                  },
                ),
                const SizedBox(height: 12),
                // Teacher
                const Text('Assign Teacher',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _allTeachers.any((t) => t['uid'] == teacherUid)
                      ? teacherUid
                      : null,
                  decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.person_outline),
                      hintText: 'None'),
                  items: [
                    const DropdownMenuItem(
                        value: '', child: Text('— None —')),
                    ..._allTeachers.map((t) => DropdownMenuItem(
                        value: t['uid'] as String,
                        child: Text(t['name'] as String? ?? '')))
                  ],
                  onChanged: (v) =>
                      setInner(() => teacherUid = v ?? ''),
                ),
                const SizedBox(height: 12),
                // Room
                const Text('Room No.',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextField(
                  controller: roomCtrl,
                  decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.meeting_room_outlined),
                      hintText: 'e.g. 203, Lab-1, Hall'),
                  onChanged: (v) => room = v,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Apply'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      setState(() {
                        _richTimetable[day]![periodIndex] = {
                          'subject': subject,
                          'teacher': teacherUid,
                          'room': roomCtrl.text.trim(),
                        };
                      });
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

  Color _subjectColor(String subject) {
    const colors = {
      'Math': Color(0xFF1565C0),
      'English': Color(0xFF00897B),
      'Science': Color(0xFF6A1B9A),
      'Hindi': Color(0xFFE65100),
      'Social Studies': Color(0xFF283593),
      'Computer': Color(0xFF00838F),
      'Art': Color(0xFFAD1457),
      'PE': Color(0xFF2E7D32),
      'Music': Color(0xFF6D4C41),
      'Free Period': Color(0xFF9E9E9E),
    };
    return colors[subject] ?? _accent;
  }

  // ── Tab 2: Teachers ───────────────────────────────────────────────────────

  Future<void> _loadTeachers() async {
    setState(() => _teachersLoading = true);
    final all = await FirestoreService.getUsersBySchool(_schoolId);
    setState(() {
      _allTeachers = all
          .where((t) =>
              t['role'] == 'teacher' || t['role'] == 'subjectTeacher')
          .toList();
      _teachersLoading = false;
      _teachersLoaded = true;
    });
  }

  void _showTeacherTimetable(Map<String, dynamic> teacher) {
    final uid = teacher['uid'] as String? ?? '';
    final name = teacher['name'] as String? ?? '';
    final classIds =
        List<String>.from(teacher['classIds'] as List? ?? []);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (ctx, scroll) => Column(
          children: [
            const SizedBox(height: 8),
            Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2))),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  CircleAvatar(
                      backgroundColor: _accent.withOpacity(0.12),
                      child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : 'T',
                          style: const TextStyle(
                              color: _accent,
                              fontWeight: FontWeight.bold))),
                  const SizedBox(width: 12),
                  Text(name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  const Spacer(),
                  IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx)),
                ],
              ),
            ),
            const Divider(height: 1),
            if (classIds.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text('No classes assigned',
                    style: TextStyle(color: Colors.grey)),
              )
            else
              Expanded(
                child: _TeacherTimetableView(
                  schoolId: _schoolId,
                  classIds: classIds,
                  teacherUid: uid,
                  scroll: scroll,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showAssignDuty(Map<String, dynamic> teacher) {
    final uid = teacher['uid'] as String? ?? '';
    final name = teacher['name'] as String? ?? '';
    DateTime selectedDate = DateTime.now();
    String dutyType = _dutyTypes.first;
    TimeOfDay startTime = const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay endTime = const TimeOfDay(hour: 10, minute: 0);
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
                    const Icon(Icons.assignment_ind_outlined,
                        color: _accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Assign Duty — $name',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                    ),
                    IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const SizedBox(height: 16),
                // Date
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today_outlined,
                      color: _accent),
                  title: const Text('Date',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: selectedDate,
                      firstDate: DateTime.now()
                          .subtract(const Duration(days: 30)),
                      lastDate: DateTime.now()
                          .add(const Duration(days: 180)),
                    );
                    if (picked != null)
                      setInner(() => selectedDate = picked);
                  },
                ),
                const Divider(height: 1),
                const SizedBox(height: 12),
                // Duty type
                DropdownButtonFormField<String>(
                  value: dutyType,
                  decoration: const InputDecoration(
                    labelText: 'Duty Type',
                    prefixIcon: Icon(Icons.work_outline),
                    isDense: true,
                  ),
                  items: _dutyTypes
                      .map((d) =>
                          DropdownMenuItem(value: d, child: Text(d)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setInner(() => dutyType = v);
                  },
                ),
                const SizedBox(height: 12),
                // Time slots
                Row(
                  children: [
                    Expanded(
                      child: _TimePickerTile(
                        label: 'Start Time',
                        time: startTime,
                        onChanged: (t) =>
                            setInner(() => startTime = t),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TimePickerTile(
                        label: 'End Time',
                        time: endTime,
                        onChanged: (t) =>
                            setInner(() => endTime = t),
                      ),
                    ),
                  ],
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
                    label: const Text('Save Duty'),
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
                            await FirestoreService.addTeacherDuty(
                              teacherUid: uid,
                              duty: {
                                'date':
                                    '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
                                'type': dutyType,
                                'startTime':
                                    '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}',
                                'endTime':
                                    '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}',
                                'assignedBy': _coordinatorName,
                              },
                            );
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(ctx)
                                .showSnackBar(SnackBar(
                              content: Text(
                                  'Duty assigned to $name'),
                              backgroundColor: _accent,
                              behavior: SnackBarBehavior.floating,
                            ));
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

  // ── Tab 3: Complaints ─────────────────────────────────────────────────────

  Future<void> _loadComplaints() async {
    setState(() => _complaintsLoading = true);
    final all = await FirestoreService.getComplaintsForClasses(
        schoolId: _schoolId, classIds: _assignedClasses);
    if (mounted) {
      setState(() {
        _complaints = all;
        _complaintsLoading = false;
        _complaintsLoaded = true;
      });
    }
  }

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
                _detailRow('Student',
                    complaint['studentName'] as String? ?? '—'),
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
                  child: Text(
                      complaint['complaintText'] as String? ?? '',
                      style: const TextStyle(
                          fontSize: 14, height: 1.5)),
                ),
                const SizedBox(height: 16),
                // Status dropdown
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
                                  'resolutionNote':
                                      noteCtrl.text.trim(),
                              },
                            );
                            // Update local state
                            final idx = _complaints
                                .indexWhere((c) => c['id'] == id);
                            if (idx != -1) {
                              setState(() {
                                _complaints[idx]['status'] = status;
                                if (noteCtrl.text.trim().isNotEmpty)
                                  _complaints[idx]['resolutionNote'] =
                                      noteCtrl.text.trim();
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

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text('$label:',
                style: const TextStyle(
                    color: Colors.grey, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  // ── Tab 4: Students ───────────────────────────────────────────────────────

  Future<void> _loadStudents() async {
    if (_studentsClass == null) {
      setState(() => _studentsLoaded = true);
      return;
    }
    setState(() => _studentsLoading = true);

    List<Student> loaded = [];
    if (_schoolId.isNotEmpty) {
      final cloud = await FirestoreService.loadStudents(
          schoolId: _schoolId, classId: _studentsClass!);
      if (cloud != null) {
        loaded = cloud
            .map((e) => Student(
                  roll: (e['roll'] as num).toInt(),
                  name: e['name'] as String,
                  parentPhone: e['parentPhone'] as String?,
                  photoUrl: e['photoUrl'] as String?,
                ))
            .toList();
      }
    }
    if (loaded.isEmpty) {
      loaded = await AttendanceService.loadStudents(_studentsClass!) ??
          List.from(classStudents[_studentsClass] ?? []);
    }

    if (mounted) {
      setState(() {
        _students = loaded;
        _studentsLoading = false;
        _studentsLoaded = true;
        _expandedRolls.clear();
      });
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Coordinator',
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold)),
            Text(_coordinatorName,
                style: const TextStyle(
                    fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          if (_tabController.index == 0 && !_ttLoading)
            _ttSaving
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2)))
                : IconButton(
                    icon: const Icon(Icons.save_rounded),
                    tooltip: 'Save timetable',
                    onPressed: _saveTimetable,
                  ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: _confirmSignOut,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelStyle: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600),
          onTap: (_) => setState(() {}), // refresh save button
          tabs: const [
            Tab(icon: Icon(Icons.table_chart_outlined, size: 17),
                text: 'Timetable'),
            Tab(icon: Icon(Icons.people_outline, size: 17),
                text: 'Teachers'),
            Tab(icon: Icon(Icons.report_outlined, size: 17),
                text: 'Complaints'),
            Tab(icon: Icon(Icons.school_outlined, size: 17),
                text: 'Students'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTimetableTab(),
          _buildTeachersTab(),
          _buildComplaintsTab(),
          _buildStudentsTab(),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 1 — TIMETABLE EDITOR
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildTimetableTab() {
    return Column(
      children: [
        // Class selector header
        Container(
          color: _accent.withOpacity(0.06),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.class_outlined, size: 18, color: _accent),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _ttClass,
                    isDense: true,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87),
                    items: _assignedClasses
                        .map((c) =>
                            DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null && v != _ttClass) {
                        setState(() => _ttClass = v);
                        _loadRichTimetable();
                      }
                    },
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('6 days × 8 periods',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.green,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        // Grid
        if (_ttLoading)
          const Expanded(
              child: Center(child: CircularProgressIndicator()))
        else
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(10),
              child: Column(
                children: [
                  // Header row
                  Row(
                    children: [
                      const SizedBox(width: 38),
                      ...List.generate(_periods, (i) => Expanded(
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: _accent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          margin:
                              const EdgeInsets.symmetric(horizontal: 2),
                          child: Center(
                            child: Text('P${i + 1}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                      )),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Day rows
                  ..._days.map((day) {
                    final periods = _richTimetable[day] ??
                        List.generate(
                          _periods,
                          (_) => <String, dynamic>{
                            'subject': 'Free Period',
                            'teacher': '',
                            'room': ''
                          },
                        );
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Day label
                          Container(
                            width: 38,
                            height: 52,
                            decoration: BoxDecoration(
                              color: _accent.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(day,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                      color: _accent)),
                            ),
                          ),
                          // Periods
                          ...List.generate(
                              periods.length.clamp(0, _periods), (i) {
                            final cell = periods[i];
                            final subject =
                                cell['subject'] as String? ??
                                    'Free Period';
                            final room =
                                cell['room'] as String? ?? '';
                            final color = _subjectColor(subject);
                            return Expanded(
                              child: GestureDetector(
                                onTap: () =>
                                    _editPeriodCell(day, i),
                                child: Container(
                                  height: 52,
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 2),
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.1),
                                    border: Border.all(
                                        color: color.withOpacity(0.3)),
                                    borderRadius:
                                        BorderRadius.circular(6),
                                  ),
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        subject.length > 6
                                            ? '${subject.substring(0, 5)}.'
                                            : subject,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontSize: 8,
                                            fontWeight: FontWeight.bold,
                                            color: color),
                                      ),
                                      if (room.isNotEmpty)
                                        Text(room,
                                            style: TextStyle(
                                                fontSize: 7,
                                                color: color
                                                    .withOpacity(0.7))),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.touch_app_outlined,
                          size: 13, color: Colors.grey.shade400),
                      const SizedBox(width: 4),
                      Text('Tap any cell to edit · press Save to persist',
                          style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 2 — TEACHERS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildTeachersTab() {
    if (_teachersLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: () async {
        _teachersLoaded = false;
        await _loadTeachers();
      },
      child: _allTeachers.isEmpty
          ? const Center(
              child: Text('No teachers found',
                  style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
              itemCount: _allTeachers.length,
              itemBuilder: (context, i) {
                final t = _allTeachers[i];
                final name = t['name'] as String? ?? '';
                final email = t['email'] as String? ?? '';
                final role = t['role'] as String? ?? 'teacher';
                final classIds = List<String>.from(
                    t['classIds'] as List? ?? []);
                final duties =
                    List.from(t['duties'] as List? ?? []);

                return _coordCard(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor:
                                _accent.withOpacity(0.12),
                            child: Text(
                              name.isNotEmpty
                                  ? name[0].toUpperCase()
                                  : 'T',
                              style: const TextStyle(
                                  color: _accent,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15)),
                                Text(email,
                                    style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 12)),
                              ],
                            ),
                          ),
                          _roleBadge(role),
                        ],
                      ),
                      if (classIds.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          children: classIds
                              .map((c) => Chip(
                                    label: Text(c,
                                        style: const TextStyle(
                                            fontSize: 11)),
                                    padding: EdgeInsets.zero,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize
                                            .shrinkWrap,
                                    backgroundColor: _accent
                                        .withOpacity(0.08),
                                  ))
                              .toList(),
                        ),
                      ],
                      if (duties.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text('${duties.length} duties assigned',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.amber.shade700)),
                      ],
                      const Divider(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(
                                  Icons.table_chart_outlined,
                                  size: 15),
                              label: const Text('View Timetable',
                                  style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _accent,
                                side: BorderSide(
                                    color: _accent.withOpacity(0.4)),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 8),
                              ),
                              onPressed: () =>
                                  _showTeacherTimetable(t),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(
                                  Icons.assignment_ind_outlined,
                                  size: 15),
                              label: const Text('Assign Duty',
                                  style: TextStyle(fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _accent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 8),
                              ),
                              onPressed: () => _showAssignDuty(t),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 3 — COMPLAINTS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildComplaintsTab() {
    if (_complaintsLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: () async {
        _complaintsLoaded = false;
        await _loadComplaints();
      },
      child: _complaints.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox_outlined,
                      size: 56, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('No complaints for your classes',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
              itemCount: _complaints.length,
              itemBuilder: (context, i) {
                final c = _complaints[i];
                final status = c['status'] as String? ?? 'Open';
                final text = c['complaintText'] as String? ?? '';
                final studentName =
                    c['studentName'] as String? ?? '';
                final className = c['className'] as String? ?? '';
                final recipient =
                    c['recipientRole'] as String? ?? '';
                final createdAt = c['createdAt'];
                String dateStr = '';
                if (createdAt != null) {
                  try {
                    final dt =
                        (createdAt as dynamic).toDate() as DateTime;
                    dateStr =
                        '${dt.day}/${dt.month}/${dt.year}';
                  } catch (_) {}
                }

                final statusInfo = _statusInfo(status);

                return GestureDetector(
                  onTap: () => _showComplaintDetail(c),
                  child: _coordCard(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(studentName,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14)),
                                  Text('$className · To: $recipient',
                                      style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 12)),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: statusInfo.color
                                    .withOpacity(0.1),
                                borderRadius:
                                    BorderRadius.circular(8),
                                border: Border.all(
                                    color: statusInfo.color
                                        .withOpacity(0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(statusInfo.icon,
                                      size: 11,
                                      color: statusInfo.color),
                                  const SizedBox(width: 3),
                                  Text(status,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: statusInfo.color,
                                          fontWeight:
                                              FontWeight.w600)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          text.length > 90
                              ? '${text.substring(0, 90)}…'
                              : text,
                          style: const TextStyle(
                              fontSize: 13, color: Colors.black87),
                        ),
                        if (dateStr.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(dateStr,
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey)),
                        ],
                        const SizedBox(height: 4),
                        Text('Tap to view & update →',
                            style: TextStyle(
                                fontSize: 11,
                                color: _accent.withOpacity(0.7))),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 4 — STUDENTS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildStudentsTab() {
    final filtered = _students.where((s) {
      if (_studentSearch.isEmpty) return true;
      return s.name.toLowerCase().contains(_studentSearch) ||
          s.roll.toString().contains(_studentSearch);
    }).toList();

    return Column(
      children: [
        // Class selector
        Container(
          color: _accent.withOpacity(0.06),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.class_outlined, size: 18, color: _accent),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _studentsClass,
                    isDense: true,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87),
                    items: _assignedClasses
                        .map((c) =>
                            DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null && v != _studentsClass) {
                        setState(() {
                          _studentsClass = v;
                          _studentsLoaded = false;
                        });
                        _loadStudents();
                      }
                    },
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${_students.length} students',
                    style: const TextStyle(
                        fontSize: 11,
                        color: _accent,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        // Search
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search by name or roll…',
              prefixIcon: Icon(Icons.search, color: Colors.grey),
              isDense: true,
            ),
            onChanged: (v) => setState(() {
              _studentSearch = v.toLowerCase();
              _expandedRolls.clear();
            }),
          ),
        ),
        // List
        Expanded(
          child: _studentsLoading
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? Center(
                      child: Text(
                        _studentSearch.isEmpty
                            ? 'No students found'
                            : 'No results for "$_studentSearch"',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      padding:
                          const EdgeInsets.fromLTRB(14, 6, 14, 24),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final student = filtered[i];
                        final expanded =
                            _expandedRolls.contains(student.roll);
                        return _CoordStudentCard(
                          student: student,
                          expanded: expanded,
                          accentColor: _accent,
                          onTap: () => setState(() {
                            if (expanded) {
                              _expandedRolls.remove(student.roll);
                            } else {
                              _expandedRolls.add(student.roll);
                            }
                          }),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

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

  Widget _roleBadge(String role) {
    final color = role == 'subjectTeacher'
        ? Colors.teal
        : Colors.blue;
    final label =
        role == 'subjectTeacher' ? 'Subject' : 'Class Teacher';
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w600)),
    );
  }

  Widget _coordCard(
      {required Widget child, EdgeInsets? margin, Color? color}) {
    return Container(
      margin: margin ?? EdgeInsets.zero,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color ?? (Theme.of(context).cardTheme.color ?? Colors.white),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
              color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
        ],
      ),
      child: child,
    );
  }

  void _confirmSignOut() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out?'),
        content: const Text('You will be returned to the login screen.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<AuthProvider>().signOut();
            },
            child: const Text('Sign Out',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// Teacher timetable view (embedded in bottom sheet)
// ══════════════════════════════════════════════════════════════════════════

class _TeacherTimetableView extends StatefulWidget {
  final String schoolId;
  final List<String> classIds;
  final String teacherUid;
  final ScrollController scroll;

  const _TeacherTimetableView({
    required this.schoolId,
    required this.classIds,
    required this.teacherUid,
    required this.scroll,
  });

  @override
  State<_TeacherTimetableView> createState() =>
      _TeacherTimetableViewState();
}

class _TeacherTimetableViewState extends State<_TeacherTimetableView> {
  static const _days = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'
  ];

  // classId → { day → [ cells ] }
  Map<String, Map<String, List<Map<String, dynamic>>>> _data = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result =
        <String, Map<String, List<Map<String, dynamic>>>>{};
    for (final cls in widget.classIds) {
      final tt = await FirestoreService.loadRichTimetable(
          schoolId: widget.schoolId, classId: cls);
      if (tt != null) result[cls] = tt;
    }
    if (mounted) setState(() {
      _data = result;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      children: widget.classIds.map((cls) {
        final tt = _data[cls];
        if (tt == null) return const SizedBox.shrink();

        // Collect only periods where this teacher is assigned
        final rows = <Widget>[];
        for (final day in _days) {
          final periods = tt[day] ?? [];
          for (int i = 0; i < periods.length; i++) {
            if (periods[i]['teacher'] == widget.teacherUid) {
              rows.add(ListTile(
                dense: true,
                leading: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6A1B9A).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('$day P${i + 1}',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF6A1B9A))),
                ),
                title: Text(
                    periods[i]['subject'] as String? ?? '',
                    style: const TextStyle(fontSize: 13)),
                subtitle: (periods[i]['room'] as String?)
                            ?.isNotEmpty ==
                        true
                    ? Text('Room ${periods[i]['room']}',
                        style: const TextStyle(fontSize: 11))
                    : null,
              ));
            }
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
              child: Text(cls,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Color(0xFF6A1B9A))),
            ),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('No assigned periods in $cls',
                    style: const TextStyle(
                        color: Colors.grey, fontSize: 12)),
              )
            else
              ...rows,
            const Divider(),
          ],
        );
      }).toList(),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// Expandable student card (read-only)
// ══════════════════════════════════════════════════════════════════════════

class _CoordStudentCard extends StatelessWidget {
  final Student student;
  final bool expanded;
  final Color accentColor;
  final VoidCallback onTap;

  const _CoordStudentCard({
    required this.student,
    required this.expanded,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color ?? Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: expanded
              ? accentColor.withOpacity(0.4)
              : Colors.grey.withOpacity(0.15),
          width: expanded ? 1.5 : 1,
        ),
        boxShadow: const [
          BoxShadow(
              color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
              child: Row(
                children: [
                  _avatar(accentColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(student.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15)),
                        Text('Roll ${student.roll}',
                            style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 12)),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.expand_more,
                        color: expanded
                            ? accentColor
                            : Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  if (student.parentPhone != null &&
                      student.parentPhone!.isNotEmpty)
                    Row(
                      children: [
                        Icon(Icons.phone_outlined,
                            size: 14, color: accentColor),
                        const SizedBox(width: 6),
                        Text(student.parentPhone!,
                            style: const TextStyle(fontSize: 13)),
                        const Spacer(),
                        _iconBtn(
                            icon: Icons.call,
                            color: Colors.green.shade600,
                            onTap: () => launchUrl(Uri.parse(
                                'tel:${student.parentPhone}'))),
                        _iconBtn(
                            icon: Icons.chat_bubble_outline,
                            color: const Color(0xFF25D366),
                            onTap: () {
                              final n = student.parentPhone!
                                  .replaceAll(RegExp(r'\D'), '');
                              launchUrl(
                                  Uri.parse('https://wa.me/$n'),
                                  mode:
                                      LaunchMode.externalApplication);
                            }),
                      ],
                    )
                  else
                    Text('No parent contact',
                        style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar(Color color) {
    final hasCloud =
        student.photoUrl != null && student.photoUrl!.isNotEmpty;
    final hasLocal = student.photoPath != null &&
        File(student.photoPath!).existsSync();

    ImageProvider? img;
    if (hasLocal) img = FileImage(File(student.photoPath!));
    else if (hasCloud) img = NetworkImage(student.photoUrl!);

    return CircleAvatar(
      radius: 22,
      backgroundColor: color.withOpacity(0.12),
      backgroundImage: img,
      child: img == null
          ? Text(student.roll.toString(),
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 13))
          : null,
    );
  }

  Widget _iconBtn(
      {required IconData icon,
      required Color color,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }
}

// ── Time picker tile ──────────────────────────────────────────────────────────

class _TimePickerTile extends StatelessWidget {
  final String label;
  final TimeOfDay time;
  final ValueChanged<TimeOfDay> onChanged;

  const _TimePickerTile({
    required this.label,
    required this.time,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final picked = await showTimePicker(
            context: context, initialTime: time);
        if (picked != null) onChanged(picked);
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: Colors.grey, fontSize: 11)),
            const SizedBox(height: 2),
            Row(
              children: [
                const Icon(Icons.access_time_outlined,
                    size: 16, color: Color(0xFF6A1B9A)),
                const SizedBox(width: 4),
                Text(time.format(context),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

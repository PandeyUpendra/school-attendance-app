import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/student_data.dart';
import '../models/student.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import 'timetable_screen.dart';

class SubjectTeacherHome extends StatefulWidget {
  const SubjectTeacherHome({super.key});

  @override
  State<SubjectTeacherHome> createState() => _SubjectTeacherHomeState();
}

class _SubjectTeacherHomeState extends State<SubjectTeacherHome> {
  int _selectedTab = 0;

  // Shared user data
  String _schoolId = '';
  String _teacherName = '';
  List<String> _assignedClasses = [];

  // Students tab
  String? _selectedClass;
  List<Student> _students = [];
  bool _loadingStudents = true;
  final Set<int> _expandedRolls = {};
  String _searchQuery = '';

  // Timetable tab
  String? _timetableClass;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<AuthProvider>().user;
      _schoolId = user?.schoolId ?? '';
      _teacherName = user?.name ?? 'Subject Teacher';
      _assignedClasses = user?.classIds ?? [];
      if (_assignedClasses.isNotEmpty) {
        _selectedClass = _assignedClasses.first;
        _timetableClass = _assignedClasses.first;
      }
      _loadStudents();
    });
  }

  Future<void> _loadStudents() async {
    if (_selectedClass == null) {
      setState(() => _loadingStudents = false);
      return;
    }
    setState(() {
      _loadingStudents = true;
      _expandedRolls.clear();
    });

    if (_schoolId.isNotEmpty) {
      final cloud = await FirestoreService.loadStudents(
          schoolId: _schoolId, classId: _selectedClass!);
      if (cloud != null && mounted) {
        setState(() {
          _students = cloud
              .map((e) => Student(
                    roll: (e['roll'] as num).toInt(),
                    name: e['name'] as String,
                    parentPhone: e['parentPhone'] as String?,
                    photoUrl: e['photoUrl'] as String?,
                  ))
              .toList();
          _loadingStudents = false;
        });
        return;
      }
    }

    // Fallback to local data
    if (mounted) {
      setState(() {
        _students = List.from(classStudents[_selectedClass] ?? []);
        _loadingStudents = false;
      });
    }
  }

  void _showComplaintSheet({String? preClass, Student? preStudent}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ComplaintSheet(
        schoolId: _schoolId,
        teacherName: _teacherName,
        assignedClasses: _assignedClasses,
        preClass: preClass,
        preStudent: preStudent,
      ),
    );
  }

  void _confirmSignOut() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedTab == 0 ? 'Students' : 'Timetable'),
        backgroundColor: const Color(0xFF6A1B9A),
        foregroundColor: Colors.white,
        actions: [
          if (_selectedTab == 0)
            IconButton(
              icon: const Icon(Icons.report_gmailerrorred_outlined),
              tooltip: 'Raise Complaint',
              onPressed: () => _showComplaintSheet(),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: _confirmSignOut,
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedTab,
        children: [
          _buildStudentsTab(),
          _buildTimetableTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        indicatorColor: const Color(0xFF6A1B9A).withOpacity(0.15),
        onDestinationSelected: (i) => setState(() => _selectedTab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people, color: Color(0xFF6A1B9A)),
            label: 'Students',
          ),
          NavigationDestination(
            icon: Icon(Icons.table_chart_outlined),
            selectedIcon: Icon(Icons.table_chart, color: Color(0xFF6A1B9A)),
            label: 'Timetable',
          ),
        ],
      ),
    );
  }

  // ── Students Tab ───────────────────────────────────────────────────────────

  Widget _buildStudentsTab() {
    if (_assignedClasses.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.class_outlined, size: 72, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No classes assigned.\nContact your school admin.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
      );
    }

    final filtered = _students.where((s) {
      if (_searchQuery.isEmpty) return true;
      return s.name.toLowerCase().contains(_searchQuery) ||
          s.roll.toString().contains(_searchQuery);
    }).toList();

    return Column(
      children: [
        // Header: class selector + count
        Container(
          color: const Color(0xFF6A1B9A).withOpacity(0.06),
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: Row(
            children: [
              const Icon(Icons.class_outlined,
                  size: 18, color: Color(0xFF6A1B9A)),
              const SizedBox(width: 8),
              if (_assignedClasses.length == 1)
                Text(
                  _assignedClasses.first,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                )
              else
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedClass,
                      isDense: true,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: Colors.black87),
                      items: _assignedClasses
                          .map((c) =>
                              DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null && v != _selectedClass) {
                          setState(() => _selectedClass = v);
                          _loadStudents();
                        }
                      },
                    ),
                  ),
                ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF6A1B9A).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_students.length} students',
                  style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6A1B9A),
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),

        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search by name or roll number…',
              prefixIcon: Icon(Icons.search, color: Colors.grey),
              isDense: true,
            ),
            onChanged: (v) => setState(() {
              _searchQuery = v.toLowerCase();
              _expandedRolls.clear();
            }),
          ),
        ),

        // List
        Expanded(
          child: _loadingStudents
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? Center(
                      child: Text(
                        _searchQuery.isEmpty
                            ? 'No students in this class'
                            : 'No results for "$_searchQuery"',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final student = filtered[i];
                        final expanded =
                            _expandedRolls.contains(student.roll);
                        return _StudentDetailCard(
                          student: student,
                          expanded: expanded,
                          onTap: () => setState(() {
                            if (expanded) {
                              _expandedRolls.remove(student.roll);
                            } else {
                              _expandedRolls.add(student.roll);
                            }
                          }),
                          onComplaint: () => _showComplaintSheet(
                            preClass: _selectedClass,
                            preStudent: student,
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  // ── Timetable Tab ──────────────────────────────────────────────────────────

  Widget _buildTimetableTab() {
    if (_assignedClasses.isEmpty) {
      return const Center(
        child: Text('No classes assigned.',
            style: TextStyle(color: Colors.grey)),
      );
    }

    final activeClass = _timetableClass ?? _assignedClasses.first;

    return Column(
      children: [
        // Class selector (only if multiple)
        if (_assignedClasses.length > 1)
          Container(
            color: const Color(0xFF6A1B9A).withOpacity(0.06),
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Row(
              children: [
                const Icon(Icons.class_outlined,
                    size: 18, color: Color(0xFF6A1B9A)),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: activeClass,
                      isDense: true,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: Colors.black87),
                      items: _assignedClasses
                          .map((c) =>
                              DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null)
                          setState(() => _timetableClass = v);
                      },
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.visibility_outlined,
                          size: 13, color: Colors.orange),
                      SizedBox(width: 4),
                      Text('Read-only',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.orange,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            color: const Color(0xFF6A1B9A).withOpacity(0.06),
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Row(
              children: [
                const Icon(Icons.class_outlined,
                    size: 18, color: Color(0xFF6A1B9A)),
                const SizedBox(width: 8),
                Text(activeClass,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.visibility_outlined,
                          size: 13, color: Colors.orange),
                      SizedBox(width: 4),
                      Text('Read-only',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.orange,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ),

        Expanded(
          child: TimetableScreen(
            key: ValueKey(activeClass),
            className: activeClass,
            schoolId: _schoolId,
            readOnly: true,
          ),
        ),
      ],
    );
  }
}

// ── Student detail card ────────────────────────────────────────────────────────

class _StudentDetailCard extends StatelessWidget {
  final Student student;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback onComplaint;

  const _StudentDetailCard({
    required this.student,
    required this.expanded,
    required this.onTap,
    required this.onComplaint,
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
              ? const Color(0xFF6A1B9A).withOpacity(0.4)
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
          // ── Header row (always visible) ──
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
              child: Row(
                children: [
                  _avatar(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(student.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 15)),
                        Text('Roll ${student.roll}',
                            style: TextStyle(
                                color: Colors.grey.shade500, fontSize: 12)),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.expand_more,
                        color: expanded
                            ? const Color(0xFF6A1B9A)
                            : Colors.grey),
                  ),
                ],
              ),
            ),
          ),

          // ── Expanded detail ──
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
                  const SizedBox(height: 10),

                  // Parent phone row
                  if (student.parentPhone != null &&
                      student.parentPhone!.isNotEmpty) ...[
                    Row(
                      children: [
                        const Icon(Icons.phone_outlined,
                            size: 16, color: Color(0xFF6A1B9A)),
                        const SizedBox(width: 8),
                        Text(student.parentPhone!,
                            style: const TextStyle(fontSize: 13)),
                        const Spacer(),
                        _ActionIconBtn(
                          icon: Icons.call,
                          color: const Color(0xFF2E7D32),
                          tooltip: 'Call parent',
                          onTap: () => launchUrl(
                              Uri.parse('tel:${student.parentPhone}')),
                        ),
                        _ActionIconBtn(
                          icon: Icons.chat_bubble_outline,
                          color: const Color(0xFF25D366),
                          tooltip: 'WhatsApp parent',
                          onTap: () {
                            final num = student.parentPhone!
                                .replaceAll(RegExp(r'\D'), '');
                            launchUrl(Uri.parse('https://wa.me/$num'),
                                mode: LaunchMode.externalApplication);
                          },
                        ),
                      ],
                    ),
                  ] else
                    Row(
                      children: [
                        Icon(Icons.phone_disabled_outlined,
                            size: 14, color: Colors.grey.shade400),
                        const SizedBox(width: 6),
                        Text('No parent contact on file',
                            style: TextStyle(
                                color: Colors.grey.shade500, fontSize: 12)),
                      ],
                    ),

                  const SizedBox(height: 10),

                  // Raise complaint button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.report_outlined, size: 16),
                      label: const Text('Raise Complaint',
                          style: TextStyle(fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.deepOrange.shade700,
                        side:
                            BorderSide(color: Colors.deepOrange.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: onComplaint,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar() {
    final hasCloud =
        student.photoUrl != null && student.photoUrl!.isNotEmpty;
    final hasLocal = student.photoPath != null &&
        File(student.photoPath!).existsSync();

    ImageProvider? img;
    if (hasLocal) img = FileImage(File(student.photoPath!));
    else if (hasCloud) img = NetworkImage(student.photoUrl!);

    return CircleAvatar(
      radius: 22,
      backgroundColor: const Color(0xFF6A1B9A).withOpacity(0.12),
      backgroundImage: img,
      child: img == null
          ? Text(
              student.roll.toString(),
              style: const TextStyle(
                  color: Color(0xFF6A1B9A),
                  fontWeight: FontWeight.bold,
                  fontSize: 13),
            )
          : null,
    );
  }
}

class _ActionIconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _ActionIconBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}

// ── Complaint Bottom Sheet ─────────────────────────────────────────────────────

class _ComplaintSheet extends StatefulWidget {
  final String schoolId;
  final String teacherName;
  final List<String> assignedClasses;
  final String? preClass;
  final Student? preStudent;

  const _ComplaintSheet({
    required this.schoolId,
    required this.teacherName,
    required this.assignedClasses,
    this.preClass,
    this.preStudent,
  });

  @override
  State<_ComplaintSheet> createState() => _ComplaintSheetState();
}

class _ComplaintSheetState extends State<_ComplaintSheet> {
  late String? _selectedClass;
  int? _selectedRoll;
  List<Student> _classStudents = [];
  final _textCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController();
  bool _loading = false;
  bool _loadingStudents = false;

  @override
  void initState() {
    super.initState();
    _selectedClass = widget.preClass ??
        (widget.assignedClasses.isNotEmpty
            ? widget.assignedClasses.first
            : null);
    _selectedRoll = widget.preStudent?.roll;
    if (_selectedClass != null) _loadClassStudents(_selectedClass!);
  }

  Future<void> _loadClassStudents(String className) async {
    setState(() {
      _loadingStudents = true;
      _classStudents = [];
    });

    List<Student> loaded = [];

    if (widget.schoolId.isNotEmpty) {
      final cloud = await FirestoreService.loadStudents(
          schoolId: widget.schoolId, classId: className);
      if (cloud != null) {
        loaded = cloud
            .map((e) => Student(
                  roll: (e['roll'] as num).toInt(),
                  name: e['name'] as String,
                ))
            .toList();
      }
    }

    if (loaded.isEmpty) {
      loaded = List.from(classStudents[className] ?? []);
    }

    if (mounted) {
      setState(() {
        _classStudents = loaded;
        _loadingStudents = false;
        // Keep preStudent selection only if it exists in the loaded class
        if (_selectedRoll != null &&
            !loaded.any((s) => s.roll == _selectedRoll)) {
          _selectedRoll = null;
        }
      });
    }
  }

  Future<void> _submit() async {
    final student =
        _classStudents.where((s) => s.roll == _selectedRoll).firstOrNull;
    if (_selectedClass == null ||
        student == null ||
        _textCtrl.text.trim().isEmpty) return;

    setState(() => _loading = true);

    await FirestoreService.addSchoolComplaint(
      schoolId: widget.schoolId,
      complaint: {
        'className': _selectedClass,
        'studentName': student.name,
        'studentRoll': student.roll,
        'subject': _subjectCtrl.text.trim().isEmpty
            ? 'General'
            : _subjectCtrl.text.trim(),
        'text': _textCtrl.text.trim(),
        'raisedBy': widget.teacherName,
        'date': DateTime.now().toIso8601String(),
      },
    );

    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Complaint raised successfully'),
        backgroundColor: Color(0xFF6A1B9A),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _subjectCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final canSubmit = _selectedClass != null &&
        _selectedRoll != null &&
        _textCtrl.text.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.deepOrange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.report_outlined,
                      color: Colors.deepOrange, size: 20),
                ),
                const SizedBox(width: 10),
                const Text('Raise Complaint',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Class selector
            DropdownButtonFormField<String>(
              value: _selectedClass,
              decoration: const InputDecoration(
                labelText: 'Class',
                prefixIcon: Icon(Icons.class_outlined),
              ),
              items: widget.assignedClasses
                  .map((c) =>
                      DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) {
                if (v != null && v != _selectedClass) {
                  setState(() {
                    _selectedClass = v;
                    _selectedRoll = null;
                  });
                  _loadClassStudents(v);
                }
              },
            ),
            const SizedBox(height: 12),

            // Student selector
            if (_loadingStudents)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              DropdownButtonFormField<int>(
                value: _selectedRoll,
                decoration: const InputDecoration(
                  labelText: 'Student',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                items: _classStudents
                    .map((s) => DropdownMenuItem(
                        value: s.roll,
                        child: Text('${s.roll}. ${s.name}')))
                    .toList(),
                onChanged: (v) => setState(() => _selectedRoll = v),
              ),
            const SizedBox(height: 12),

            // Subject / Category (optional)
            TextField(
              controller: _subjectCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Subject / Category (optional)',
                prefixIcon: Icon(Icons.topic_outlined),
                hintText: 'e.g. Behaviour, Homework, Discipline…',
              ),
            ),
            const SizedBox(height: 12),

            // Complaint text
            TextField(
              controller: _textCtrl,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Complaint Details',
                prefixIcon: Icon(Icons.edit_note_outlined),
                alignLabelWithHint: true,
                hintText: 'Describe the issue clearly…',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 20),

            // Submit button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.send_rounded),
                label: const Text('Submit Complaint'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6A1B9A),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: (canSubmit && !_loading) ? _submit : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

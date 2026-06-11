import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/teacher.dart';
import '../../services/student_service.dart';
import '../../services/timetable_service.dart';
import '../../services/auth_service.dart';
import '../../theme.dart';
import '../../l10n/app_strings.dart';
import './student_list_screen.dart';
import '../../shared/widgets/refreshable_data.dart';

// ── Level 1 — class picker ─────────────────────────────────────────────────────

class ClassSectionItem {
  final String className;
  final String section;
  final Teacher? classTeacher;
  final int studentCount;

  ClassSectionItem({
    required this.className,
    required this.section,
    this.classTeacher,
    required this.studentCount,
  });
}

class StudentDetailsScreen extends StatefulWidget {
  const StudentDetailsScreen({super.key});

  @override
  State<StudentDetailsScreen> createState() => _StudentDetailsScreenState();
}

class _StudentDetailsScreenState extends State<StudentDetailsScreen> {
  /// Sorted list of unique class names.
  List<String> _classes = [];
  /// classTeacherOf → list of teachers for that class (one per section).
  Map<String, List<Teacher>> _teachersByClass = {};
  /// teacherId → student count.
  Map<String, int> _studentCounts = {};
  
  bool _isPrincipal = false;
  List<ClassSectionItem> _principalItems = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await _reload();
  }

  Future<void> _reload() async {
    final session = await AuthService().getSession();
    final isPrincipal = session?['role'] == 'principal';

    if (isPrincipal) {
      final settings = await TimetableService.instance.getSettings();
      final classesInSchool = List<String>.from(settings['classes'] ?? [])..sort();

      final academicDoc = await FirebaseFirestore.instance
          .collection('schools')
          .doc(AuthService.currentSchoolId)
          .collection('settings')
          .doc('academic')
          .get();
      final sectionsInSchool = List<String>.from(academicDoc.data()?['sections'] as List? ?? ['A'])..sort();

      final teachers = await TimetableService.instance.getTeachers();
      final classTeachers = teachers
          .where((t) => t.isClassTeacher && t.classTeacherOf != null)
          .toList();

      final items = <ClassSectionItem>[];

      // Fetch student counts and map class teachers for all combinations
      await Future.wait(classesInSchool.expand((cls) => sectionsInSchool.map((sec) async {
        Teacher? classTeacher;
        for (final t in classTeachers) {
          if (t.classTeacherOf == cls && t.section == sec) {
            classTeacher = t;
            break;
          }
        }

        final students = await StudentService.instance.getStudentsByClass(
          className: cls,
          section:   sec,
        );

        items.add(ClassSectionItem(
          className: cls,
          section: sec,
          classTeacher: classTeacher,
          studentCount: students.length,
        ));
      })));

      // Sort items: class name first, then section name
      items.sort((a, b) {
        final cmpClass = a.className.compareTo(b.className);
        if (cmpClass != 0) return cmpClass;
        return a.section.compareTo(b.section);
      });

      if (!mounted) return;
      setState(() {
        _isPrincipal = true;
        _principalItems = items;
        _loading = false;
      });
      return;
    }

    final teachers = await TimetableService.instance.getTeachers();
    final classTeachers = teachers
        .where((t) => t.isClassTeacher && t.classTeacherOf != null)
        .toList();

    // Group by class name
    final grouped = <String, List<Teacher>>{};
    for (final t in classTeachers) {
      grouped.putIfAbsent(t.classTeacherOf!, () => []).add(t);
    }
    // Sort sections within each class
    for (final list in grouped.values) {
      list.sort((a, b) => a.section.compareTo(b.section));
    }
    final sortedClasses = grouped.keys.toList()..sort();

    // Fetch student counts for every class teacher in parallel
    final counts = <String, int>{};
    await Future.wait(classTeachers.map((t) async {
      final students = await StudentService.instance.getStudentsByClass(
        className: t.classTeacherOf!,
        section:   t.section,
        teacherId: t.id,
      );
      counts[t.id] = students.length;
    }));

    if (!mounted) return;
    setState(() {
      _isPrincipal = false;
      _classes        = sortedClasses;
      _teachersByClass = grouped;
      _studentCounts  = counts;
      _loading        = false;
    });
  }

  int _totalForClass(String cls) {
    return (_teachersByClass[cls] ?? [])
        .fold(0, (acc, t) => acc + (_studentCounts[t.id] ?? 0));
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = _isPrincipal ? _principalItems.isEmpty : _classes.isEmpty;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(context.tr('studentDetails'))),
      body: _loading
          ? const LoadingState()
          : isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.class_outlined,
                          size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text(context.tr('noClassTeachersAssigned'),
                          style: TextStyle(
                              fontSize: 16, color: Colors.grey.shade400)),
                      const SizedBox(height: 6),
                      Text(context.tr('assignClassTeachersHint'),
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade400)),
                    ],
                  ),
                )
              : Column(children: [
                  Container(
                    color: AppTheme.primary,
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: Text(
                      _isPrincipal
                          ? 'Select a class section to view its students'
                          : 'Select a class to view its sections',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _reload,
                      color: AppTheme.primary,
                      child: _isPrincipal
                          ? ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: _principalItems.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1, indent: 70),
                              itemBuilder: (_, i) {
                                final item = _principalItems[i];
                                final teacherName = item.classTeacher?.name ?? 'No class teacher assigned';
                                final count = item.studentCount;
                                final label = '${item.className} — Section ${item.section}';
                                return InkWell(
                                  onTap: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => StudentListScreen(
                                          className:      item.className,
                                          section:        item.section,
                                          teacherId:      item.classTeacher?.id,
                                          isClassTeacher: false,
                                        ),
                                      ),
                                    );
                                    _load();
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 14),
                                    child: Row(children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: AppTheme.primaryLight
                                              .withValues(alpha: 0.25),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: const Icon(Icons.school_outlined,
                                            color: AppTheme.primary, size: 22),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(label,
                                                style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600)),
                                            const SizedBox(height: 2),
                                            Text(
                                              teacherName,
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade500),
                                            ),
                                            Text(
                                              count == 0
                                                  ? 'No students yet'
                                                  : '$count student${count == 1 ? '' : 's'}',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey.shade400),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(Icons.chevron_right,
                                          color: Colors.grey.shade400),
                                    ]),
                                  ),
                                );
                              },
                            )
                          : ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: _classes.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1, indent: 70),
                              itemBuilder: (_, i) {
                                final cls   = _classes[i];
                                final total = _totalForClass(cls);
                                final sections =
                                    (_teachersByClass[cls] ?? []).length;
                                return InkWell(
                                  onTap: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => _SectionPickerScreen(
                                          className:     cls,
                                          teachers:      _teachersByClass[cls]!,
                                          studentCounts: _studentCounts,
                                        ),
                                      ),
                                    );
                                    _load();
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 14),
                                    child: Row(children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: AppTheme.primaryLight
                                              .withValues(alpha: 0.25),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: const Icon(Icons.school_outlined,
                                            color: AppTheme.primary, size: 22),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(cls,
                                                style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600)),
                                            const SizedBox(height: 2),
                                            Text(
                                              '$sections section${sections == 1 ? '' : 's'}  ·  '
                                              '$total student${total == 1 ? '' : 's'}',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade500),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(Icons.chevron_right,
                                          color: Colors.grey.shade400),
                                    ]),
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                ]),
    );
  }
}

// ── Level 2 — section picker ───────────────────────────────────────────────────

class _SectionPickerScreen extends StatelessWidget {
  final String          className;
  final List<Teacher>   teachers;       // teachers for this class, sorted by section
  final Map<String, int> studentCounts; // teacherId → count

  const _SectionPickerScreen({
    required this.className,
    required this.teachers,
    required this.studentCounts,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.tr('selectSection'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          Text(className,
              style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ]),
      ),
      body: Column(children: [
        Container(
          color: AppTheme.primary,
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: const Text(
            'Select a section to view its students',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: teachers.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, indent: 70),
            itemBuilder: (_, i) {
              final t     = teachers[i];
              final count = studentCounts[t.id] ?? 0;
              final label = t.section.trim().isEmpty
                  ? 'No Section'
                  : 'Section ${t.section}';
              return InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StudentListScreen(
                      className:      t.classTeacherOf!,
                      section:        t.section,
                      teacherId:      t.id,
                      isClassTeacher: false,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  child: Row(children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryLight.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.group_outlined,
                          color: AppTheme.primary, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label,
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(t.name,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500)),
                          Text(
                            count == 0
                                ? 'No students yet'
                                : '$count student${count == 1 ? '' : 's'}',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade400),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right,
                        color: Colors.grey.shade400),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

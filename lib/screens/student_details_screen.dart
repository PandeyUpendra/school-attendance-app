import 'package:flutter/material.dart';
import '../models/teacher.dart';
import '../services/student_service.dart';
import '../services/timetable_service.dart';
import '../theme.dart';
import 'student_list_screen.dart';

// ── Level 1 — class picker ─────────────────────────────────────────────────────

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
    final teachers = await TimetableService().getTeachers();
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
      final students = await StudentService().getStudentsByClass(
        t.classTeacherOf!,
        section:   t.section,
        teacherId: t.id,
      );
      counts[t.id] = students.length;
    }));

    if (!mounted) return;
    setState(() {
      _classes        = sortedClasses;
      _teachersByClass = grouped;
      _studentCounts  = counts;
      _loading        = false;
    });
  }

  int _totalForClass(String cls) {
    return (_teachersByClass[cls] ?? [])
        .fold(0, (sum, t) => sum + (_studentCounts[t.id] ?? 0));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Student Details')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _classes.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.class_outlined,
                          size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('No class teachers assigned',
                          style: TextStyle(
                              fontSize: 16, color: Colors.grey.shade400)),
                      const SizedBox(height: 6),
                      Text('Assign class teachers in Teacher Management',
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
                    child: const Text(
                      'Select a class to view its sections',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _reload,
                      color: AppTheme.primary,
                      child: ListView.separated(
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
                                        .withOpacity(0.25),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(Icons.school_outlined,
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
          const Text('Select Section',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
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
                        color: AppTheme.primaryLight.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.group_outlined,
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

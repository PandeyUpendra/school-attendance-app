import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../models/teacher.dart';
import '../services/timetable_service.dart';
import '../theme.dart';

enum ClassPickerMode { attendance, studentList, reports }

/// Returned by [ClassPickerScreen] — always includes the class name and,
/// when the class has sections, the chosen section.
class ClassSectionPick {
  final String className;
  final String section;
  const ClassSectionPick(this.className, {this.section = ''});
}

class ClassPickerScreen extends StatefulWidget {
  final ClassPickerMode mode;
  /// When non-empty, only these classes are shown. Empty means show all.
  final List<String> allowedClasses;
  const ClassPickerScreen({
    super.key,
    required this.mode,
    this.allowedClasses = const [],
  });

  @override
  State<ClassPickerScreen> createState() => _ClassPickerScreenState();
}

class _ClassPickerScreenState extends State<ClassPickerScreen> {
  List<String> _classes = [];
  Map<String, List<String>> _sectionsByClass = {}; // className → sorted sections
  bool _loading = true;
  bool _noneAssigned = false; // allowedClasses was set but nothing matched

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settingsFuture = TimetableService.instance.getSettings();
    final teachersFuture = TimetableService.instance.getTeachers();
    final settings = await settingsFuture;
    final teachers = await teachersFuture;

    // Build className → sorted sections from class teachers with a section assigned.
    final sections = <String, List<String>>{};
    for (final Teacher t in teachers) {
      if (t.isClassTeacher &&
          t.classTeacherOf != null &&
          t.section.trim().isNotEmpty) {
        sections
            .putIfAbsent(t.classTeacherOf!, () => [])
            .add(t.section.trim());
      }
    }
    for (final list in sections.values) {
      list.sort();
    }

    final allClasses = List<String>.from(settings['classes'] as List);
    final filtered = widget.allowedClasses.isEmpty
        ? allClasses
        : allClasses.where((c) => widget.allowedClasses.contains(c)).toList();

    setState(() {
      _classes = filtered;
      _sectionsByClass = sections;
      _noneAssigned =
          widget.allowedClasses.isNotEmpty && filtered.isEmpty;
      _loading = false;
    });

    // Auto-navigate when exactly one class is allowed — no need to show the picker.
    if (filtered.length == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onClassTap(filtered.first);
      });
    }
  }

  void _onClassTap(String cls) {
    final sections = _sectionsByClass[cls] ?? [];
    if (sections.isNotEmpty) {
      // Push a section picker; when it pops with a pick, relay it to the caller.
      Navigator.push<ClassSectionPick>(
        context,
        MaterialPageRoute(
          builder: (_) => _SectionPickerStep(
            className: cls,
            sections: sections,
            color: _color,
            icon: _icon,
          ),
        ),
      ).then((pick) {
        if (pick != null && mounted) Navigator.pop(context, pick);
      });
    } else {
      Navigator.pop(context, ClassSectionPick(cls));
    }
  }

  String get _title => context.tr('selectClass');

  String get _subtitle {
    switch (widget.mode) {
      case ClassPickerMode.attendance:
        return context.tr('chooseClassAttendance');
      case ClassPickerMode.reports:
        return context.tr('chooseClassHistory');
      default:
        return context.tr('chooseClassStudents');
    }
  }

  Color get _color => AppTheme.primary;

  IconData get _icon {
    switch (widget.mode) {
      case ClassPickerMode.attendance:
        return Icons.fact_check_outlined;
      case ClassPickerMode.reports:
        return Icons.bar_chart_outlined;
      default:
        return Icons.people_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(_title),
      ),
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
                      Text(
                        _noneAssigned
                            ? context.tr('noClassesAssignedToYou')
                            : context.tr('noClassesConfiguredPlain'),
                        style: TextStyle(
                            fontSize: 16, color: Colors.grey.shade400),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _noneAssigned
                            ? context.tr('contactCoordinatorAssign')
                            : context.tr('askCoordinatorAddClasses'),
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade400),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Container(
                      color: _color,
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: Text(_subtitle,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13)),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _classes.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 70),
                        itemBuilder: (_, i) {
                          final cls = _classes[i];
                          final sections = _sectionsByClass[cls] ?? [];
                          return InkWell(
                            onTap: () => _onClassTap(cls),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                              child: Row(children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: _color.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(_icon, color: _color, size: 22),
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
                                      if (sections.isNotEmpty)
                                        Text(
                                          '${sections.length} ${sections.length == 1 ? context.tr('sectionSingular') : context.tr('sectionPlural')}  ·  ${sections.map((s) => '${context.tr('secPrefix')} $s').join(', ')}',
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
                  ],
                ),
    );
  }
}

// ── Section picker — pushed when a multi-section class is tapped ──────────────

class _SectionPickerStep extends StatelessWidget {
  final String       className;
  final List<String> sections;
  final Color        color;
  final IconData     icon;

  const _SectionPickerStep({
    required this.className,
    required this.sections,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('selectSection'),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text(className,
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
      ),
      body: Column(children: [
        Container(
          color: color,
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Text(
            context.tr('chooseSectionReport'),
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: sections.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, indent: 70),
            itemBuilder: (_, i) {
              final section = sections[i];
              return InkWell(
                onTap: () => Navigator.pop(
                  context,
                  ClassSectionPick(className, section: section),
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
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: color, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        '${context.tr('sectionWord')} $section',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Colors.grey.shade400),
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

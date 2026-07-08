import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../l10n/app_strings.dart';
import '../../models/deleted_student.dart';
import '../../services/student_service.dart';
import '../../theme.dart';
import '../../shared/widgets/refreshable_data.dart';

import '../../services/auth_service.dart';

/// Read-only history of students that have been permanently removed.
///
/// • Class teacher — pass [classNameFilter] (and optionally [sectionFilter]) to
///   scope the list to their own class.
/// • Coordinator / Principal — omit the filters to see every deleted student
///   across the school, grouped class-wise.
class DeletedStudentsScreen extends StatefulWidget {
  /// When set, only deleted students of this class are shown (class-teacher
  /// view). Null shows the whole school, grouped by class.
  final String? classNameFilter;

  /// Optional section filter, applied alongside [classNameFilter].
  final String? sectionFilter;

  const DeletedStudentsScreen({
    super.key,
    this.classNameFilter,
    this.sectionFilter,
  });

  @override
  State<DeletedStudentsScreen> createState() => _DeletedStudentsScreenState();
}

class _DeletedStudentsScreenState extends State<DeletedStudentsScreen> {
  bool _isPrincipal = false;

  bool get _scoped => widget.classNameFilter != null && widget.classNameFilter!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    final session = await AuthService().getSession();
    if (session != null && mounted) {
      setState(() {
        _isPrincipal = session['role'] == 'principal';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(context.tr('deletedStudents')),
      ),
      body: StreamBuilder<List<DeletedStudent>>(
        stream: StudentService.instance.watchDeletedAndPendingStudents(
          className: widget.classNameFilter,
          section: widget.sectionFilter,
        ),
        builder: (context, snap) {
          final waiting = snap.connectionState == ConnectionState.waiting;
          final all = snap.data ?? const <DeletedStudent>[];

          // Apply the class-teacher scope client-side so no composite index is
          // needed and legacy records (null teacherId) are still matched.
          final items = _scoped
              ? all
                  .where((s) =>
                      s.className == widget.classNameFilter &&
                      (widget.sectionFilter == null ||
                          widget.sectionFilter!.isEmpty ||
                          s.section == widget.sectionFilter))
                  .toList()
              : all;

          return RefreshableData(
            loading: waiting,
            isEmpty: items.isEmpty,
            hasError: snap.hasError,
            // Stream is live; pull just gives tactile feedback.
            onRefresh: () async =>
                Future<void>.delayed(const Duration(milliseconds: 400)),
            loadingMessage: context.tr('loadingDeletedStudents'),
            emptyMessage: _scoped
                ? context.tr('noDeletedStudentsInClass')
                : context.tr('noDeletedStudentsYet'),
            errorMessage: context.tr('couldNotLoadDeletedStudents'),
            builder: (context) => _scoped
                ? _buildFlat(items)
                : _buildGroupedByClass(context, items),
          );
        },
      ),
    );
  }

  /// Class-teacher view: a simple flat list.
  Widget _buildFlat(List<DeletedStudent> items) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (_, i) => _DeletedStudentCard(
        student: items[i],
        isPrincipal: _isPrincipal,
      ),
    );
  }

  /// Coordinator / principal view: grouped under per-class section headers.
  Widget _buildGroupedByClass(BuildContext context, List<DeletedStudent> items) {
    final groups = <String, List<DeletedStudent>>{};
    for (final s in items) {
      final cls =
          s.className.trim().isEmpty ? context.tr('unknownClass') : s.className;
      groups.putIfAbsent(cls, () => []).add(s);
    }
    final classKeys = groups.keys.toList()..sort(_compareClasses);

    final children = <Widget>[];
    for (final cls in classKeys) {
      final group = groups[cls]!;
      children.add(_ClassHeader(className: cls, count: group.length));
      for (final s in group) {
        children.add(_DeletedStudentCard(
          student: s,
          isPrincipal: _isPrincipal,
        ));
      }
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: children,
    );
  }

  /// Natural compare so "Class 2" sorts before "Class 10".
  static int _compareClasses(String a, String b) {
    int? numIn(String s) {
      final m = RegExp(r'\d+').firstMatch(s);
      return m == null ? null : int.tryParse(m.group(0)!);
    }

    final na = numIn(a), nb = numIn(b);
    if (na != null && nb != null && na != nb) return na.compareTo(nb);
    return a.toLowerCase().compareTo(b.toLowerCase());
  }
}

// ── Per-class section header ─────────────────────────────────────────────────

class _ClassHeader extends StatelessWidget {
  final String className;
  final int count;

  const _ClassHeader({required this.className, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8, left: 2, right: 2),
      child: Row(
        children: [
          const Icon(Icons.class_outlined, size: 18, color: AppTheme.primary),
          const SizedBox(width: 8),
          Text(
            className,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppTheme.primary),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count ${count == 1 ? context.tr('studentWord') : context.tr('studentsWord')}',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Individual deleted-student card ──────────────────────────────────────────

class _DeletedStudentCard extends StatelessWidget {
  final DeletedStudent student;
  final bool isPrincipal;

  const _DeletedStudentCard({
    required this.student,
    this.isPrincipal = false,
  });

  String _fmtDate(BuildContext context, Timestamp? ts) {
    if (ts == null) return context.tr('dateUnknown');
    final d = ts.toDate();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}, '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final sectionBit = student.section.trim().isEmpty
        ? ''
        : ' · ${context.tr('secPrefix')} ${student.section}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: student.deletedAt == null
                    ? AppTheme.warning.withValues(alpha: 0.08)
                    : AppTheme.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                student.deletedAt == null
                    ? Icons.hourglass_top_outlined
                    : Icons.person_off_outlined,
                size: 20,
                color: student.deletedAt == null
                    ? AppTheme.warning
                    : AppTheme.danger,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    student.name,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${context.tr('roll')} ${student.roll} · ${student.className}$sectionBit',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        student.deletedAt == null
                            ? Icons.hourglass_top_outlined
                            : Icons.event_busy_outlined,
                        size: 12,
                        color: student.deletedAt == null
                            ? AppTheme.warning
                            : Colors.grey.shade500,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        student.deletedAt == null
                            ? (isPrincipal
                                ? context.tr('awaitingYourApproval')
                                : context.tr('awaitingPrincipalApproval'))
                            : '${context.tr('deletedPrefix')} ${_fmtDate(context, student.deletedAt)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: student.deletedAt == null
                              ? AppTheme.warning
                              : Colors.grey.shade500,
                          fontWeight: student.deletedAt == null
                              ? FontWeight.bold
                              : null,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

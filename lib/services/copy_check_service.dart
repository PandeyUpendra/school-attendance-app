import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/copy_check.dart';
import 'timetable_service.dart';

/// Manages copy-checking sessions.
///
/// Schema:
///   copy_checks/{checkId}             → CopyCheck doc
///   copy_checks/{checkId}/statuses/{roll} → CopyStatus doc
class CopyCheckService {
  static final _db    = FirebaseFirestore.instance;
  static final _coll  = _db.collection('copy_checks');

  static final CopyCheckService _instance = CopyCheckService._();
  CopyCheckService._();
  factory CopyCheckService() => _instance;

  CollectionReference _statuses(String checkId) =>
      _coll.doc(checkId).collection('statuses');

  // ── Teacher's classes from timetable ──────────────────────────────────────

  /// Returns a list of all unique (className, section, subject) assignments for the teacher.
  Future<List<TeacherAssignment>> getTeacherAssignments(String teacherId) async {
    final tt = await TimetableService().getTimetable();
    final assignments = <TeacherAssignment>{};

    for (final clsEntry in tt.entries) {
      String className = clsEntry.key;
      String section   = '';

      // Heuristic split "Class 6 A" -> "Class 6", "A"
      if (className.contains(' ')) {
        final parts = className.split(' ');
        final last  = parts.last;
        if (last.length <= 5) {
          section   = last;
          className = parts.sublist(0, parts.length - 1).join(' ');
        }
      }

      for (final dayEntry in clsEntry.value.entries) {
        for (final bellEntry in dayEntry.value.entries) {
          final entry = bellEntry.value;
          if (entry.teacherId == teacherId) {
            assignments.add(TeacherAssignment(
              className: className,
              section:   section,
              subject:   entry.subject ?? '',
            ));
          }
        }
      }
    }
    return assignments.toList();
  }

  // ── Coordinator Overview ──────────────────────────────────────────────────

  /// For each unique (class + section + subject) combo, finds the LATEST
  /// checking session and returns its summary.
  Future<List<CopyCheckSummary>> getLatestSummaries() async {
    // 1. Get all checks
    final allChecks = await getAllChecks();
    
    // 2. Group by class+section+subject and find newest in each group
    final newestMap = <String, CopyCheck>{};
    for (final c in allChecks) {
      final key = '${c.className}|${c.section}|${c.subject}';
      if (!newestMap.containsKey(key)) {
        newestMap[key] = c;
      } else {
        if (c.checkDate.isAfter(newestMap[key]!.checkDate)) {
          newestMap[key] = c;
        }
      }
    }

    // 3. For each newest check, fetch its statuses and build a summary
    final summaries = <CopyCheckSummary>[];
    for (final check in newestMap.values) {
      final statuses = await getStatuses(check.id);
      final checked    = statuses.where((s) => s.status == 'checked').length;
      final uncheckedNames = statuses
          .where((s) => s.status != 'checked')
          .map((s) => s.studentName)
          .toList();

      summaries.add(CopyCheckSummary(
        check:          check,
        checkedCount:   checked,
        totalCount:     statuses.length,
        uncheckedNames: uncheckedNames,
      ));
    }

    // Sort by class then section
    summaries.sort((a, b) {
      int res = a.check.className.compareTo(b.check.className);
      if (res != 0) return res;
      return a.check.section.compareTo(b.check.section);
    });

    return summaries;
  }

  Future<List<CopyCheckGroup>> getStructuredSummaries() async {
    final summaries = await getLatestSummaries();

    // Group by className
    final classMap = <String, Map<String, List<CopyCheckSummary>>>{};
    for (final s in summaries) {
      classMap.putIfAbsent(s.check.className, () => {});
      classMap[s.check.className]!.putIfAbsent(s.check.section, () => []);
      classMap[s.check.className]![s.check.section]!.add(s);
    }

    final result = <CopyCheckGroup>[];
    classMap.forEach((className, sectionsMap) {
      final sections = <CopyCheckSectionGroup>[];
      sectionsMap.forEach((section, summaries) {
        sections.add(CopyCheckSectionGroup(section: section, summaries: summaries));
      });
      // Sort sections
      sections.sort((a, b) => a.section.compareTo(b.section));
      result.add(CopyCheckGroup(className: className, sections: sections));
    });

    // Sort classes
    result.sort((a, b) => a.className.compareTo(b.className));

    return result;
  }

  // ── Copy checks ────────────────────────────────────────────────────────────

  /// Get all checking sessions for a teacher in a class.
  Future<List<CopyCheck>> getChecks({
    required String teacherId,
    String? className,
  }) async {
    Query q = _coll.where('teacherId', isEqualTo: teacherId);
    if (className != null) {
      q = q.where('className', isEqualTo: className);
    }
    final snap = await q.get();
    final list = snap.docs
        .map((d) =>
            CopyCheck.fromDoc(d.id, Map<String, dynamic>.from(d.data() as Map)))
        .toList()
      ..sort((a, b) => b.checkDate.compareTo(a.checkDate));
    return list;
  }

  /// Get ALL checking sessions — for coordinator overview.
  Future<List<CopyCheck>> getAllChecks({String? className}) async {
    Query q = _coll;
    if (className != null) {
      q = q.where('className', isEqualTo: className);
    }
    final snap = await q.get();
    return snap.docs
        .map((d) =>
            CopyCheck.fromDoc(d.id, Map<String, dynamic>.from(d.data() as Map)))
        .toList()
      ..sort((a, b) => b.checkDate.compareTo(a.checkDate));
  }

  Future<String> createCheck(CopyCheck check) async {
    final ref = await _coll.add(check.toJson());
    return ref.id;
  }

  Future<void> deleteCheck(String checkId) async {
    await _coll.doc(checkId).delete();
  }

  // ── Student statuses ───────────────────────────────────────────────────────

  Future<List<CopyStatus>> getStatuses(String checkId) async {
    final snap = await _statuses(checkId).get();
    return snap.docs
        .map((d) => CopyStatus.fromDoc(Map<String, dynamic>.from(d.data() as Map)))
        .toList()
      ..sort((a, b) => a.roll.compareTo(b.roll));
  }

  Future<void> saveStatuses(
      String checkId, List<CopyStatus> statuses) async {
    final batch = _db.batch();
    for (final s in statuses) {
      batch.set(_statuses(checkId).doc('${s.roll}'), s.toJson());
    }
    await batch.commit();
  }

  /// Returns students whose status is 'incomplete' or 'not_done'.
  Future<List<CopyStatus>> getPendingStatuses(String checkId) async {
    final all = await getStatuses(checkId);
    return all
        .where((s) => s.status == 'incomplete' || s.status == 'not_done')
        .toList();
  }
}

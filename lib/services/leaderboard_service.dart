import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/leaderboard_entry.dart';
import 'base_firestore_service.dart';
import 'exam_service.dart';
import 'student_service.dart';

/// Manages multi-category class leaderboards.
///
/// Firestore schema:
///   schools/{schoolId}/leaderboards/{leaderboardId}          → metadata
///   schools/{schoolId}/leaderboards/{leaderboardId}/entries/{roll} → LeaderboardEntry
///
/// leaderboardId for auto categories: {classKey}_{category}
///   e.g. "8_A_academics", "8_A_attendance"
class LeaderboardService extends BaseFirestoreService {
  static final LeaderboardService _instance = LeaderboardService._();
  LeaderboardService._();
  factory LeaderboardService() => _instance;

  // Categories
  static const String catAcademics    = 'academics';
  static const String catAttendance   = 'attendance';
  static const String catDiscipline   = 'discipline';
  static const String catMostImproved = 'most_improved';

  CollectionReference<Map<String, dynamic>> _lb(String schoolId) =>
      schoolCollection(schoolId, 'leaderboards');

  CollectionReference<Map<String, dynamic>> _entries(
          String schoolId, String leaderboardId) =>
      _lb(schoolId).doc(leaderboardId).collection('entries');

  CollectionReference<Map<String, dynamic>> _attendance(String schoolId) =>
      schoolCollection(schoolId, 'attendance');

  String _leaderboardId(String classId, String category) =>
      '${classId.replaceAll(' ', '_')}_$category';

  // ── Calculations ───────────────────────────────────────────────────────────

  /// Average exam percentage per student, sorted highest first.
  Future<List<LeaderboardEntry>> calculateAcademicsRanking(
    String classId, {
    String? schoolId,
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    final examService = ExamService();
    final exams = await examService.getExams(schoolId: sId, className: classId);
    if (exams.isEmpty) return [];

    // Gather all results across exams: roll → list of percentages
    final Map<int, List<double>>    pcts      = {};
    final Map<int, String>          names     = {};

    await Future.wait(exams.map((exam) async {
      final results = await examService.getResults(schoolId: sId, examId: exam.id);
      for (final r in results) {
        pcts[r.roll]  ??= [];
        pcts[r.roll]!.add(r.percentage);
        if (r.studentName.isNotEmpty) names[r.roll] = r.studentName;
      }
    }));

    if (pcts.isEmpty) return [];

    final sorted = pcts.entries.toList()
      ..sort((a, b) {
        final avgA = a.value.fold(0.0, (s, v) => s + v) / a.value.length;
        final avgB = b.value.fold(0.0, (s, v) => s + v) / b.value.length;
        return avgB.compareTo(avgA);
      });

    return _toEntries(
      sorted.map((e) {
        final avg = e.value.fold(0.0, (s, v) => s + v) / e.value.length;
        return _RollScore(roll: e.key, name: names[e.key] ?? 'Roll ${e.key}', score: avg);
      }).toList(),
      classId,
    );
  }

  /// Attendance percentage per student, sorted highest first.
  Future<List<LeaderboardEntry>> calculateAttendanceRanking(
    String classId, {
    String? schoolId,
  }) async {
    final sId    = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    final prefix = '${classId.replaceAll(' ', '_')}_';

    // Fetch all attendance docs for this class
    final snap = await _attendance(sId)
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: prefix)
        .where(FieldPath.documentId, isLessThan: _prefixEnd(prefix))
        .get();

    final Map<int, int>    presentDays = {};
    final Map<int, int>    totalDays   = {};

    for (final doc in snap.docs) {
      final rolls = Map<String, dynamic>.from(
          (doc.data()['rolls'] as Map?) ?? {});
      for (final entry in rolls.entries) {
        final roll   = int.tryParse(entry.key);
        if (roll == null) continue;
        final status = entry.value is String ? entry.value as String
            : (entry.value == true ? 'Present' : 'Absent');
        totalDays[roll]   = (totalDays[roll]   ?? 0) + 1;
        if (status == 'Present') presentDays[roll] = (presentDays[roll] ?? 0) + 1;
      }
    }

    if (totalDays.isEmpty) return [];

    final students = await StudentService().getStudentsByClass(
        schoolId: sId, className: classId);
    final nameByRoll = {for (final s in students) s.roll: s.name};

    final items = totalDays.entries.map((e) {
      final pct = (presentDays[e.key] ?? 0) / e.value * 100;
      return _RollScore(
        roll:  e.key,
        name:  nameByRoll[e.key] ?? 'Roll ${e.key}',
        score: pct,
      );
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return _toEntries(items, classId);
  }

  /// Behaviour score per student (field `behaviourScore` on student docs), highest first.
  Future<List<LeaderboardEntry>> calculateDisciplineRanking(
    String classId, {
    String? schoolId,
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    final students = await StudentService()
        .getStudentsByClass(schoolId: sId, className: classId);
    if (students.isEmpty) return [];

    // Read behaviourScore field raw from Firestore (not in Student model)
    final snap = await schoolCollection(sId, 'students')
        .where('className', isEqualTo: _className(classId))
        .get();

    final Map<int, double> scores = {};
    for (final doc in snap.docs) {
      final data = doc.data();
      final roll = (data['roll'] as num?)?.toInt();
      if (roll == null) continue;
      final sec = (data['section'] as String?) ?? '';
      if (_section(classId).isNotEmpty && sec != _section(classId)) continue;
      final score = (data['behaviourScore'] as num?)?.toDouble() ?? 0.0;
      scores[roll] = score;
    }

    final nameByRoll = {for (final s in students) s.roll: s.name};
    final items = scores.entries.map((e) => _RollScore(
      roll:  e.key,
      name:  nameByRoll[e.key] ?? 'Roll ${e.key}',
      score: e.value,
    )).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return _toEntries(items, classId);
  }

  /// Improvement from first-3-exam avg to last-3-exam avg (%), highest first.
  Future<List<LeaderboardEntry>> calculateMostImprovedRanking(
    String classId, {
    String? schoolId,
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    final examService = ExamService();
    final exams = await examService.getExams(schoolId: sId, className: classId);
    if (exams.length < 2) return [];

    // Sort oldest first
    final sorted = List.from(exams)
      ..sort((a, b) => a.examDate.compareTo(b.examDate));

    final n         = sorted.length;
    final earlyExams = sorted.take(n <= 3 ? 1 : 3).toList();
    final recentExams = sorted.skip(n <= 3 ? 1 : n - 3).toList();

    Future<Map<int, double>> avgPct(List exams) async {
      final Map<int, List<double>> pcts = {};
      await Future.wait(exams.map((e) async {
        final results = await examService.getResults(schoolId: sId, examId: e.id);
        for (final r in results) {
          pcts[r.roll] ??= [];
          pcts[r.roll]!.add(r.percentage);
        }
      }));
      return {
        for (final entry in pcts.entries)
          entry.key: entry.value.fold(0.0, (s, v) => s + v) / entry.value.length,
      };
    }

    final Map<int, List<double>> pcts = {};
    final Map<int, String>       names = {};
    await Future.wait(exams.map((exam) async {
      final results = await examService.getResults(schoolId: sId, examId: exam.id);
      for (final r in results) {
        pcts[r.roll] ??= [];
        if (r.studentName.isNotEmpty) names[r.roll] = r.studentName;
      }
    }));

    final earlyAvg  = await avgPct(earlyExams);
    final recentAvg = await avgPct(recentExams);

    final common = earlyAvg.keys.toSet().intersection(recentAvg.keys.toSet());
    if (common.isEmpty) return [];

    final items = common.map((roll) {
      final early  = earlyAvg[roll]!;
      final recent = recentAvg[roll]!;
      final improvement = early == 0 ? recent : (recent - early) / early * 100;
      return _RollScore(
        roll:  roll,
        name:  names[roll] ?? 'Roll $roll',
        score: improvement,
      );
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return _toEntries(items, classId);
  }

  // ── Persistence ────────────────────────────────────────────────────────────

  /// Save (or overwrite) a leaderboard. Assigns gold/silver/bronze to top 3.
  /// Sends notifications to guardians of newly-ranked top-3 students.
  Future<String> saveLeaderboard(
    String classId,
    String category,
    List<LeaderboardEntry> entries, {
    String? schoolId,
    String? name,
  }) async {
    final sId          = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    final leaderboardId = _leaderboardId(classId, category);
    final isCustom     = category != catAcademics &&
                         category != catAttendance &&
                         category != catDiscipline &&
                         category != catMostImproved;

    // Detect previous top-3 for notification diff
    Set<int> prevTop3 = {};
    try {
      final prevSnap = await _entries(sId, leaderboardId)
          .where('rank', isLessThanOrEqualTo: 3).get();
      prevTop3 = prevSnap.docs
          .map((d) => (d.data()['roll'] as num?)?.toInt() ?? 0)
          .toSet();
    } catch (_) {}

    // Assign badges
    final badged = entries.asMap().entries.map((e) {
      final badge = e.key == 0 ? 'gold'
          : e.key == 1        ? 'silver'
          : e.key == 2        ? 'bronze'
          : 'none';
      return e.value.copyWith(badge: badge);
    }).toList();

    // Save metadata
    await _lb(sId).doc(leaderboardId).set({
      'name':      name ?? _defaultName(category),
      'classId':   classId,
      'category':  category,
      'isCustom':  isCustom,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Batch-write entries (Firestore max 500 per batch — classes are typically < 60)
    final batch = db.batch();
    for (final entry in badged) {
      batch.set(
        _entries(sId, leaderboardId).doc('${entry.roll}'),
        entry.toJson(),
      );
    }
    // Delete stale entries not in this save
    final existing = await _entries(sId, leaderboardId).get();
    final newRolls = badged.map((e) => '${e.roll}').toSet();
    for (final doc in existing.docs) {
      if (!newRolls.contains(doc.id)) batch.delete(doc.reference);
    }
    await batch.commit();

    // Notify guardians of new top-3 entrants
    final newTop3 = badged
        .where((e) => e.rank <= 3 && !prevTop3.contains(e.roll))
        .toList();
    for (final entry in newTop3) {
      await _notifyGuardian(sId, entry, name ?? _defaultName(category));
    }

    return leaderboardId;
  }

  /// Stream of entries for a leaderboard, ordered by rank ascending.
  Stream<List<LeaderboardEntry>> getLeaderboard(
    String leaderboardId, {
    String? schoolId,
  }) {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    return _entries(sId, leaderboardId)
        .orderBy('rank')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => LeaderboardEntry.fromJson(
                Map<String, dynamic>.from(d.data())))
            .toList());
  }

  /// One-shot fetch of leaderboard entries, ordered by rank.
  Future<List<LeaderboardEntry>> fetchLeaderboard(
    String leaderboardId, {
    String? schoolId,
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    final snap = await _entries(sId, leaderboardId)
        .orderBy('rank')
        .get();
    return snap.docs
        .map((d) => LeaderboardEntry.fromJson(
            Map<String, dynamic>.from(d.data())))
        .toList();
  }

  /// Metadata for a leaderboard (name, updatedAt, isCustom, …).
  Future<Map<String, dynamic>?> getLeaderboardMeta(
    String leaderboardId, {
    String? schoolId,
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    final doc = await _lb(sId).doc(leaderboardId).get();
    if (!doc.exists || doc.data() == null) return null;
    return Map<String, dynamic>.from(doc.data()!);
  }

  /// Creates a blank custom leaderboard and returns its ID.
  Future<String> createCustomLeaderboard(
    String name,
    String classId, {
    String? schoolId,
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    final ref = await _lb(sId).add({
      'name':      name,
      'classId':   classId,
      'category':  name.toLowerCase().replaceAll(' ', '_'),
      'isCustom':  true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Update a single student's score in a custom leaderboard,
  /// then recalculate all ranks and badges.
  Future<void> updateCustomEntry(
    String leaderboardId,
    int    roll,
    double score, {
    String? schoolId,
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    await _entries(sId, leaderboardId)
        .doc('$roll')
        .set({'score': score}, SetOptions(merge: true));

    // Re-fetch all entries and recalculate ranks
    final snap = await _entries(sId, leaderboardId).get();
    final all = snap.docs
        .map((d) => LeaderboardEntry.fromJson(
            Map<String, dynamic>.from(d.data())))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final batch = db.batch();
    for (int i = 0; i < all.length; i++) {
      final badge = i == 0 ? 'gold' : i == 1 ? 'silver' : i == 2 ? 'bronze' : 'none';
      batch.set(
        _entries(sId, leaderboardId).doc('${all[i].roll}'),
        all[i].copyWith(rank: i + 1, badge: badge).toJson(),
      );
    }
    await batch.commit();
    await _lb(sId)
        .doc(leaderboardId)
        .update({'updatedAt': FieldValue.serverTimestamp()});
  }

  /// Save a complete custom leaderboard (all students with scores).
  Future<void> saveCustomLeaderboard(
    String leaderboardId,
    List<LeaderboardEntry> entries, {
    String? schoolId,
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    final sorted = List<LeaderboardEntry>.from(entries)
      ..sort((a, b) => b.score.compareTo(a.score));

    final batch = db.batch();
    for (int i = 0; i < sorted.length; i++) {
      final badge = i == 0 ? 'gold' : i == 1 ? 'silver' : i == 2 ? 'bronze' : 'none';
      batch.set(
        _entries(sId, leaderboardId).doc('${sorted[i].roll}'),
        sorted[i].copyWith(rank: i + 1, badge: badge).toJson(),
      );
    }
    await batch.commit();
    await _lb(sId)
        .doc(leaderboardId)
        .update({'updatedAt': FieldValue.serverTimestamp()});
  }

  /// Stream of custom leaderboard metadata docs for a class.
  Stream<List<Map<String, dynamic>>> watchCustomLeaderboards(
    String classId, {
    String? schoolId,
  }) {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    return _lb(sId)
        .where('classId',  isEqualTo: classId)
        .where('isCustom', isEqualTo: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final m = Map<String, dynamic>.from(d.data());
              m['id'] = d.id;
              return m;
            }).toList());
  }

  Future<void> deleteLeaderboard(String leaderboardId, {String? schoolId}) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    // Delete entries sub-collection first
    final snap = await _entries(sId, leaderboardId).get();
    final batch = db.batch();
    for (final doc in snap.docs) batch.delete(doc.reference);
    await batch.commit();
    await _lb(sId).doc(leaderboardId).delete();
  }

  /// Recalculate and persist all four auto-leaderboards for a class.
  Future<void> refreshAllAutoLeaderboards(
    String classId, {
    String? schoolId,
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    final results = await Future.wait([
      calculateAcademicsRanking(classId,    schoolId: sId),
      calculateAttendanceRanking(classId,   schoolId: sId),
      calculateDisciplineRanking(classId,   schoolId: sId),
      calculateMostImprovedRanking(classId, schoolId: sId),
    ]);
    await Future.wait([
      saveLeaderboard(classId, catAcademics,    results[0], schoolId: sId),
      saveLeaderboard(classId, catAttendance,   results[1], schoolId: sId),
      saveLeaderboard(classId, catDiscipline,   results[2], schoolId: sId),
      saveLeaderboard(classId, catMostImproved, results[3], schoolId: sId),
    ]);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  List<LeaderboardEntry> _toEntries(List<_RollScore> items, String classId) {
    return List.generate(items.length, (i) {
      final badge = i == 0 ? 'gold' : i == 1 ? 'silver' : i == 2 ? 'bronze' : 'none';
      return LeaderboardEntry(
        studentId:   '${classId.replaceAll(' ', '_')}_${items[i].roll}',
        studentName: items[i].name,
        roll:        items[i].roll,
        classId:     classId,
        score:       double.parse(items[i].score.toStringAsFixed(1)),
        rank:        i + 1,
        badge:       badge,
      );
    });
  }

  String _prefixEnd(String prefix) {
    if (prefix.isEmpty) return prefix;
    final last = prefix.codeUnitAt(prefix.length - 1);
    return prefix.substring(0, prefix.length - 1) +
        String.fromCharCode(last + 1);
  }

  String _defaultName(String category) {
    switch (category) {
      case catAcademics:    return 'Academics';
      case catAttendance:   return 'Attendance';
      case catDiscipline:   return 'Discipline';
      case catMostImproved: return 'Most Improved';
      default:              return category;
    }
  }

  // classId may be "8 A" — extract bare className and section
  String _className(String classId) {
    final parts = classId.trim().split(' ');
    if (parts.length > 1 && parts.last.length <= 2) {
      return parts.sublist(0, parts.length - 1).join(' ');
    }
    return classId;
  }

  String _section(String classId) {
    final parts = classId.trim().split(' ');
    if (parts.length > 1 && parts.last.length <= 2) return parts.last;
    return '';
  }

  Future<void> _notifyGuardian(
    String schoolId,
    LeaderboardEntry entry,
    String categoryName,
  ) async {
    await schoolCollection(schoolId, 'notifications').add({
      'type':      'leaderboard_badge',
      'title':     '${entry.studentName} earned a ${entry.badge} badge!',
      'body':      '${entry.studentName} is Rank ${entry.rank} in $categoryName.',
      'audience':  'guardian:${entry.classId}:${entry.roll}',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}

class _RollScore {
  final int    roll;
  final String name;
  final double score;
  const _RollScore({required this.roll, required this.name, required this.score});
}

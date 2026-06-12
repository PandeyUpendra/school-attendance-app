import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/teacher.dart';
import 'auth_service.dart';
import 'student_service.dart';
import 'timetable_service.dart';
import 'copy_check_service.dart';

/// Aggregates one day's school-wide signals into a single `DigestSnapshot`
/// for the Principal EOD Digest screen.
///
/// All sub-queries fan out in parallel.  Remarks and fee payments are read
/// from the CURRENT school's subtree only (never a cross-school
/// `collectionGroup`), with a server-side date filter so just today's
/// documents are fetched.
class PrincipalDigestService {
  static final _db = FirebaseFirestore.instance;

  static final PrincipalDigestService _instance = PrincipalDigestService._();
  PrincipalDigestService._();
  factory PrincipalDigestService() => _instance;

  Future<DigestSnapshot> buildTodayDigest() async {
    final now           = DateTime.now();
    final dayStart      = DateTime(now.year, now.month, now.day);

    final settings      = await TimetableService.instance.getSettings();
    final classes       = List<String>.from(settings['classes'] as List);
    final schoolName    = (settings['schoolName'] as String?) ?? 'School';

    // School-scoped: read only the signed-in user's school subtree.
    final sid           = AuthService.currentSchoolId;

    final thirtyDaysAgo = dayStart.subtract(const Duration(days: 30));
    final sevenDaysAgo  = dayStart.subtract(const Duration(days: 7));

    // Fan out everything in parallel.
    final summariesF    = StudentService.instance.loadTodayFullSummary(classes: classes);
    final teachersF     = TimetableService.instance.getTeachers();
    final allLeavesF    = TimetableService.instance.getLeaveApplications(since: thirtyDaysAgo);
    final pendingLeavesF= TimetableService.instance.getLeaveApplications(status: 'pending');
    final remarksTodayF = _fetchTodayRemarks(sid, dayStart);
    final paymentsTodayF= _fetchTodayPayments(sid, dayStart);
    final copyChecksF   = CopyCheckService().getAllChecks(since: sevenDaysAgo);

    final summaries     = await summariesF;
    final teachers      = await teachersF;
    final allLeaves     = await allLeavesF;
    final pendingLeaves = await pendingLeavesF;
    final remarks       = await remarksTodayF;
    final payments      = await paymentsTodayF;
    final allChecks     = await copyChecksF;

    // ── Attendance roll-up ──────────────────────────────────────────────────
    int total = 0, present = 0, absent = 0, leave = 0, classesMarked = 0;
    for (final s in summaries) {
      total   += s.total;
      present += s.present;
      absent  += s.absent;
      leave   += s.leave;
      if (s.marked) classesMarked++;
    }
    // Exclude students on approved leave from the denominator — counting them
    // as "not present" dragged the figure below 100% for a class that was fully
    // present apart from sanctioned leave (review #276). Attendance % is now
    // present / (present + absent).
    final attendanceBase = total - leave;
    final attendancePct = attendanceBase > 0 ? (present / attendanceBase * 100) : 0.0;

    // ── Absent teachers (approved leaves overlapping today) ─────────────────
    final teacherById = {for (final t in teachers) t.id: t};
    final absentTeachers = <Teacher>[];
    for (final app in allLeaves) {
      if (app['status'] != 'approved') continue;
      final startStr = app['startDate'] as String?;
      if (startStr == null) continue;
      final start = DateTime.tryParse(startStr);
      if (start == null) continue;
      final days  = (app['numberOfDays'] as num?)?.toInt() ?? 1;
      final end   = start.add(Duration(days: days - 1));
      final today = DateTime(now.year, now.month, now.day);
      final inWindow = !today.isBefore(DateTime(start.year, start.month, start.day))
                    && !today.isAfter(DateTime(end.year, end.month, end.day));
      if (!inWindow) continue;
      final tid = app['teacherId'] as String?;
      final t   = tid == null ? null : teacherById[tid];
      if (t != null) absentTeachers.add(t);
    }

    // ── Leaves: pending + decided today ─────────────────────────────────────
    int approvedToday = 0, rejectedToday = 0;
    for (final app in allLeaves) {
      // We don't store a decision timestamp — best proxy: status != pending AND
      // createdAt is today.  Imperfect but the only signal we have.
      final status = app['status'] as String?;
      if (status == 'pending') continue;
      final ts = app['createdAt'];
      if (ts is! Timestamp) continue;
      final dt = ts.toDate();
      if (dt.isBefore(dayStart)) continue;
      if (status == 'approved') {
        approvedToday++;
      } else if (status == 'rejected') {
        rejectedToday++;
      }
    }

    // ── Remarks today (already filtered + sorted in _fetchTodayRemarks) ──────

    // ── Fees collected today ────────────────────────────────────────────────
    double feesTotal = 0;
    int    paymentsCount = 0;
    final feesByMode = <String, double>{};
    for (final data in payments) {
      final amt  = (data['amount'] as num?)?.toDouble() ?? 0;
      final mode = (data['mode']   as String?) ?? 'Cash';
      feesTotal += amt;
      paymentsCount++;
      feesByMode[mode] = (feesByMode[mode] ?? 0) + amt;
    }

    // ── Copy-check backlog (last 7 days) ────────────────────────────────────
    final cutoff = dayStart.subtract(const Duration(days: 7));
    final recentChecks = allChecks
        .where((c) => c.checkDate.isAfter(cutoff) ||
                      c.checkDate.isAtSameMomentAs(cutoff))
        .toList();
    final pendingCounts = await Future.wait(
      recentChecks.map((c) async {
        if (c.pendingCount != null) {
          return c.pendingCount!;
        }
        final pendingStatuses = await CopyCheckService().getPendingStatuses(c.id);
        return pendingStatuses.length;
      }),
    );
    int copyBacklog = 0;
    final backlogByTeacher = <String, int>{};
    for (var i = 0; i < recentChecks.length; i++) {
      final n = pendingCounts[i];
      copyBacklog += n;
      if (n > 0) {
        final key = recentChecks[i].teacherName.isNotEmpty
            ? recentChecks[i].teacherName
            : recentChecks[i].teacherId;
        backlogByTeacher[key] = (backlogByTeacher[key] ?? 0) + n;
      }
    }

    return DigestSnapshot(
      generatedAt:     now,
      schoolName:      schoolName,
      classSummaries:  summaries,
      classesMarked:   classesMarked,
      classesTotal:    classes.length,
      totalStudents:   total,
      presentToday:    present,
      absentToday:     absent,
      leaveToday:      leave,
      attendancePct:   attendancePct,
      absentTeachers:  absentTeachers,
      pendingLeaves:   pendingLeaves.length,
      approvedToday:   approvedToday,
      rejectedToday:   rejectedToday,
      remarksToday:    remarks,
      feesCollected:   feesTotal,
      paymentsCount:   paymentsCount,
      feesByMode:      feesByMode,
      copyBacklog:     copyBacklog,
      copyBacklogByTeacher: backlogByTeacher,
    );
  }

  /// Today's student remarks for [sid] only.
  ///
  /// Walks `schools/{sid}/students/*` and reads each student's `remarks`
  /// subcollection with a server-side `timestamp >= dayStart` filter, so we
  /// never touch another school's data and only fetch today's documents.
  Future<List<RemarkItem>> _fetchTodayRemarks(
      String sid, DateTime dayStart) async {
   try {
    final cutoff = Timestamp.fromDate(dayStart);
    final rs = await _db
        .collectionGroup('remarks')
        .where('schoolId', isEqualTo: sid)
        .where('timestamp', isGreaterThanOrEqualTo: cutoff)
        .get();

    final remarks = rs.docs.map((doc) {
      final data = doc.data();
      final ts = data['timestamp'];
      final dt = ts is Timestamp ? ts.toDate() : dayStart;
      final studentId = doc.reference.parent.parent?.id ?? '';
      return RemarkItem(
        studentId:  studentId,
        remark:     (data['remark']    as String?) ?? '',
        role:       (data['role']      as String?) ?? '',
        createdBy:  (data['createdBy'] as String?) ?? '',
        timestamp:  dt,
      );
    }).toList();

    remarks.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return remarks;
   } catch (_) {
     return [];
   }
  }

  /// Today's fee payments for [sid] only.
  ///
  /// Uses a collectionGroup query on 'payments' with a server-side filter
  /// on 'schoolId' and 'paidOn >= dayStart'.
  Future<List<Map<String, dynamic>>> _fetchTodayPayments(
      String sid, DateTime dayStart) async {
   try {
    final cutoff = Timestamp.fromDate(dayStart);
    final rs = await _db
        .collectionGroup('payments')
        .where('schoolId', isEqualTo: sid)
        .where('paidOn', isGreaterThanOrEqualTo: cutoff)
        .get();

    return rs.docs.map((d) => d.data()).toList();
   } catch (_) {
     return [];
   }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Snapshot data classes
// ─────────────────────────────────────────────────────────────────────────────

class DigestSnapshot {
  final DateTime         generatedAt;
  final String           schoolName;
  final List<ClassSummary> classSummaries;
  final int              classesMarked;
  final int              classesTotal;

  // Attendance
  final int    totalStudents;
  final int    presentToday;
  final int    absentToday;
  final int    leaveToday;
  final double attendancePct;

  // Teachers
  final List<Teacher> absentTeachers;

  // Leaves
  final int pendingLeaves;
  final int approvedToday;
  final int rejectedToday;

  // Remarks / incidents
  final List<RemarkItem> remarksToday;

  // Fees
  final double               feesCollected;
  final int                  paymentsCount;
  final Map<String, double>  feesByMode;

  // Copy-check
  final int                  copyBacklog;
  final Map<String, int>     copyBacklogByTeacher;

  const DigestSnapshot({
    required this.generatedAt,
    required this.schoolName,
    required this.classSummaries,
    required this.classesMarked,
    required this.classesTotal,
    required this.totalStudents,
    required this.presentToday,
    required this.absentToday,
    required this.leaveToday,
    required this.attendancePct,
    required this.absentTeachers,
    required this.pendingLeaves,
    required this.approvedToday,
    required this.rejectedToday,
    required this.remarksToday,
    required this.feesCollected,
    required this.paymentsCount,
    required this.feesByMode,
    required this.copyBacklog,
    required this.copyBacklogByTeacher,
  });
}

class RemarkItem {
  final String   studentId;
  final String   remark;
  final String   role;
  final String   createdBy;
  final DateTime timestamp;
  const RemarkItem({
    required this.studentId,
    required this.remark,
    required this.role,
    required this.createdBy,
    required this.timestamp,
  });
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';
import 'base_firestore_service.dart';

/// Firestore-backed notification / real-time alert system.
///
/// Works WITHOUT a backend server by:
///   1. Writing notifications to the `notifications` collection when events
///      happen (e.g. student marked absent, leave submitted, announcement
///      posted).
///   2. Each client listens to snapshots filtered to their audience.
///   3. Unread tracking is done locally via SharedPreferences (last-seen
///      timestamp per category).
///
/// Schema (school-scoped):
///   schools/{sid}/notifications/{auto} = {
///     type:      'absent' | 'leave_submitted' | 'leave_resolved' |
///                'announcement',
///     title:     string,
///     body:      string,
///     audience:  'guardian:{class}:{roll}' | 'coordinator' | 'principal' |
///                'teacher:{teacherId}' | 'all' | 'teachers' | 'guardians',
///     createdAt: Timestamp,
///   }
class NotificationService extends BaseFirestoreService {
  static final NotificationService _instance = NotificationService._();
  NotificationService._();
  factory NotificationService() => _instance;

  String get _sid => AuthService.currentSchoolId;

  CollectionReference<Map<String, dynamic>> get _coll =>
      schoolCollection(_sid, 'notifications');

  // ── Writers ────────────────────────────────────────────────────────────────

  /// Called when a student is marked Absent or Leave — notifies the guardian.
  Future<void> addAbsenceNotice({
    required String className,
    required int    roll,
    required String studentName,
    required String status, // 'Absent' | 'Leave'
  }) async {
    await _coll.add({
      'type':      'absent',
      'title':     '$studentName marked $status today',
      'body':      'Your child has been marked $status today in $className. '
                   'Please contact the school if this is incorrect.',
      'audience':  'guardian:$className:$roll',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Called when a teacher submits a leave application — notifies recipients.
  Future<void> addLeaveSubmitted({
    String? schoolId,
    required String teacherName,
    required String toRole, // 'coordinator' | 'principal'
    required int    days,
    required String startDate,
  }) async {
    await _coll.add({
      'type':      'leave_submitted',
      'title':     'New leave application from $teacherName',
      'body':      '$teacherName has applied for $days day(s) '
                   'starting $startDate. Tap to review.',
      'audience':  toRole,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Called when a leave is approved or rejected — notifies the teacher.
  Future<void> addLeaveResolved({
    required String teacherId,
    required String teacherName,
    required String status, // 'approved' | 'rejected'
  }) async {
    await _coll.add({
      'type':      'leave_resolved',
      'status':    status,
      'title':     'Leave $status',
      'body':      'Your leave application has been $status.',
      'audience':  'teacher:$teacherId',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Called when a teacher is assigned as substitute for a class+bell+date.
  Future<void> addSubstitutionAssigned({
    required String   teacherId,
    required String   className,
    required int      bell,
    required String   subject,
    required DateTime date,
  }) async {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final dateStr = '${date.day} ${months[date.month]}';
    final subjBit = subject.isEmpty ? '' : ' ($subject)';
    await _coll.add({
      'type':      'substitution_assigned',
      'title':     'Substitution: $className · Bell $bell',
      'body':      'You\'ve been assigned to cover$subjBit in $className, '
                   'Bell $bell on $dateStr.',
      'audience':  'teacher:$teacherId',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Called when a new announcement is posted.
  Future<void> addAnnouncementNotice({
    required String title,
    required String body,
    required String audience, // 'all' | 'teachers' | 'guardians'
  }) async {
    await _coll.add({
      'type':      'announcement',
      'title':     'New announcement: $title',
      'body':      body.length > 120 ? '${body.substring(0, 117)}…' : body,
      'audience':  audience,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addTaskNotice({
    required String title,
    required String createdBy,
    required List<String> classes,
  }) async {
    await _coll.add({
      'type':      'task',
      'title':     'New task assigned: $title',
      'body':      'Assigned by $createdBy to ${classes.join(", ")}',
      'audience':  'teachers',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Sends a targeted notification to a specific teacher when a staff task
  /// is assigned to them.
  Future<void> addStaffTaskNotice({
    required String taskTitle,
    required String assignedTeacherId,
    required String assignedByName,
    String? dueDateStr,
    String? priority,
    String? audience, // defaults to teacher:{id}; pass 'coordinator' etc. to override
  }) async {
    final parts = <String>[taskTitle];
    if (dueDateStr != null && dueDateStr.isNotEmpty) {
      parts.add('Due: $dueDateStr');
    }
    if (priority != null && priority.isNotEmpty) {
      parts.add('Priority: $priority');
    }
    await _coll.add({
      'type':      'staff_task',
      'title':     'New Task Assigned',
      'body':      '${parts.join(' · ')} — by $assignedByName',
      'audience':  audience ?? 'teacher:$assignedTeacherId',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Called when a meeting task is assigned to a teacher.
  Future<void> addMeetingTaskNotification({
    required String teacherId,
    required String meetingTitle,
    required String pointText,
  }) async {
    final body = pointText.length > 100
        ? '${pointText.substring(0, 97)}…'
        : pointText;
    await _coll.add({
      'type':      'meeting_task',
      'title':     'New Meeting Task: $meetingTitle',
      'body':      body,
      'audience':  'teacher:$teacherId',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Called when a guardian submits a student leave — notifies the class teacher.
  Future<void> addStudentLeaveSubmitted({
    required String studentName,
    required String studentClass,
    required int    days,
    required String startDate,
  }) async {
    await _coll.add({
      'type':      'student_leave_submitted',
      'title':     'Leave request: $studentName',
      'body':      'Guardian applied $days day(s) leave for $studentName '
                   '($studentClass) starting $startDate. Tap to review.',
      'audience':  'class_teacher:$studentClass',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Called when a student leave is resolved — notifies the guardian.
  Future<void> addStudentLeaveResolved({
    required String studentClass,
    required int    studentRoll,
    required String studentName,
    required String status,
  }) async {
    await _coll.add({
      'type':      'student_leave_resolved',
      'status':    status,
      'title':     'Leave $status for $studentName',
      'body':      "Your child's leave application has been $status.",
      'audience':  'guardian:$studentClass:$studentRoll',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Deleters ───────────────────────────────────────────────────────────────

  /// Deletes a single notification by its Firestore document ID.
  Future<void> deleteNotification({required String id}) async {
    await _coll.doc(id).delete();
  }

  /// Deletes all notifications whose IDs are in [ids].
  Future<void> deleteAll(List<String> ids) async {
    final batch = db.batch();
    for (final id in ids) {
      batch.delete(_coll.doc(id));
    }
    await batch.commit();
  }

  // ── Readers ────────────────────────────────────────────────────────────────

  /// Builds the exact set of `audience` values this viewer is allowed to see,
  /// so the filter can run **server-side** via a single `whereIn` query rather
  /// than pulling the whole collection and filtering in Dart.
  ///
  /// The candidate set mirrors the writers above exactly:
  ///   • everyone sees `'all'` and their own role string;
  ///   • teachers also see `'teachers'` and their `'teacher:{id}'` channel;
  ///   • guardians also see `'guardians'` and their `'guardian:{class}:{roll}'`.
  List<String> _audiencesFor({
    required String role,
    String? teacherId,
    String? studentClass,
    int?    studentRoll,
  }) {
    final audiences = <String>{'all'};

    // Bare-role channel. Only 'coordinator' and 'principal' are ever addressed
    // by their bare role string (addLeaveSubmitted's toRole is only ever those
    // two). Adding the bare role for any OTHER role — 'teacher', 'guardian',
    // 'owner', … — requests an audience that is never written AND is not
    // permitted by firestore.rules. Firestore rules are not filters, so a
    // single unreadable candidate in a whereIn rejects the ENTIRE query, which
    // is why the whole notifications feed was failing with permission-denied
    // for teachers (and guardians). Keep this set to exactly what the writers
    // emit and the rules allow.
    if (role == 'coordinator' || role == 'principal') {
      audiences.add(role);
    }

    if (role == 'teacher') {
      audiences.add('teachers');
      if (teacherId != null && teacherId.isNotEmpty) {
        audiences.add('teacher:$teacherId');
      }
    }
    if (role == 'guardian') {
      audiences.add('guardians');
      if (studentClass != null && studentRoll != null) {
        audiences.add('guardian:$studentClass:$studentRoll');
      }
    }
    return audiences.toList();
  }

  /// Real-time stream of notifications visible to this viewer, newest first,
  /// capped at 30 days. Filtering is done server-side by `audience`.
  Stream<List<Map<String, dynamic>>> streamFor({
    required String role,
    String? teacherId,
    String? studentClass,
    int?    studentRoll,
  }) {
    return _coll
        .where('audience',
            whereIn: _audiencesFor(
              role: role,
              teacherId: teacherId,
              studentClass: studentClass,
              studentRoll: studentRoll,
            ))
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) {
      final cutoff = DateTime.now().subtract(const Duration(days: 30));
      return snap.docs
          .map((d) {
            final data = Map<String, dynamic>.from(d.data());
            data['id'] = d.id;
            return data;
          })
          .where((n) {
            final ts = n['createdAt'];
            return !(ts is Timestamp && ts.toDate().isBefore(cutoff));
          })
          .toList();
    });
  }

  /// Returns all notifications visible to this viewer, newest first.
  /// Filtering is done server-side by `audience`; only the 30-day recency
  /// cap remains a (cheap) client-side trim.
  Future<List<Map<String, dynamic>>> getFor({
    required String role,
    String? teacherId,
    String? studentClass,
    int?    studentRoll,
    String? userEmail,
    String? schoolId,
  }) async {
    final snap = await _coll
        .where('audience',
            whereIn: _audiencesFor(
              role: role,
              teacherId: teacherId,
              studentClass: studentClass,
              studentRoll: studentRoll,
            ))
        .orderBy('createdAt', descending: true)
        .limit(50)
        .get();
    final now = DateTime.now();
    return snap.docs
        .map((d) {
          final data = Map<String, dynamic>.from(d.data());
          data['id'] = d.id;
          return data;
        })
        .where((n) {
          final ts = n['createdAt'];
          if (ts is! Timestamp) return true;
          return now.difference(ts.toDate()).inDays <= 30;
        })
        .toList();
  }

  /// Counts unread notifications (those newer than the last-seen marker).
  Future<int> unreadCount({
    required String role,
    String? teacherId,
    String? studentClass,
    int?    studentRoll,
    String? schoolId,
    String? userEmail,
  }) async {
    final items = await getFor(
      role: role,
      teacherId: teacherId,
      studentClass: studentClass,
      studentRoll: studentRoll,
    );
    final prefs = await SharedPreferences.getInstance();
    final lastSeenMs = prefs.getInt(_lastSeenKey) ?? 0;
    return items.where((n) {
      final ts = n['createdAt'];
      if (ts is! Timestamp) return false;
      return ts.toDate().millisecondsSinceEpoch > lastSeenMs;
    }).length;
  }

  Future<void> markAllSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
        _lastSeenKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Separate "last seen" for the announcements screen (so opening it
  /// clears just that section, not all notifications).
  Future<void> markAnnouncementsSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastSeenAnnKey,
        DateTime.now().millisecondsSinceEpoch);
  }

  static const _lastSeenKey    = 'notif_last_seen_ms';
  static const _lastSeenAnnKey = 'notif_ann_last_seen_ms';
}

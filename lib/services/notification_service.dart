import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
/// Schema:
///   notifications/{auto} = {
///     type:      'absent' | 'leave_submitted' | 'leave_resolved' |
///                'announcement',
///     title:     string,
///     body:      string,
///     audience:  'guardian:{class}:{roll}' | 'coordinator' | 'principal' |
///                'teacher:{teacherId}' | 'all' | 'teachers' | 'guardians',
///     createdAt: Timestamp,
///   }
class NotificationService {
  static final _db   = FirebaseFirestore.instance;
  static final _coll = _db.collection('notifications');

  static final NotificationService _instance = NotificationService._();
  NotificationService._();
  factory NotificationService() => _instance;

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
      'title':     'Leave $status',
      'body':      'Your leave application has been $status.',
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

  // ── Readers ────────────────────────────────────────────────────────────────

  /// Returns all notifications visible to this viewer, newest first.
  /// The audience filter logic matches the writers above.
  Future<List<Map<String, dynamic>>> getFor({
    required String role,
    String? teacherId,
    String? studentClass,
    int?    studentRoll,
  }) async {
    final snap = await _coll.get();
    final now  = DateTime.now();
    final list = snap.docs.map((d) {
      final data = Map<String, dynamic>.from(d.data());
      data['id'] = d.id;
      return data;
    }).where((n) {
      final aud = (n['audience'] as String?) ?? '';
      if (aud == 'all') return true;
      // Role-matched
      if (aud == role)                                             return true;
      if (aud == 'teachers'  && role == 'teacher')                 return true;
      if (aud == 'guardians' && role == 'guardian')                return true;
      if (aud.startsWith('teacher:')  && role == 'teacher'  &&
          teacherId != null && aud == 'teacher:$teacherId')         return true;
      if (aud.startsWith('guardian:') && role == 'guardian' &&
          studentClass != null && studentRoll != null &&
          aud == 'guardian:$studentClass:$studentRoll')             return true;
      return false;
    }).toList();

    // Sort newest first. Keep recent notifications (last 30 days max) to
    // avoid pulling a giant history.
    list.sort((a, b) {
      final ta = a['createdAt'];
      final tb = b['createdAt'];
      if (ta is! Timestamp && tb is! Timestamp) return 0;
      if (ta is! Timestamp) return 1;
      if (tb is! Timestamp) return -1;
      return (tb).compareTo(ta);
    });
    return list.where((n) {
      final ts = n['createdAt'];
      if (ts is! Timestamp) return true;
      return now.difference(ts.toDate()).inDays <= 30;
    }).toList();
  }

  /// Counts unread notifications (those newer than the last-seen marker).
  Future<int> unreadCount({
    required String role,
    String? teacherId,
    String? studentClass,
    int?    studentRoll,
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

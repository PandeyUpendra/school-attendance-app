import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/staff_task.dart';
import 'base_firestore_service.dart';

class NotificationService extends BaseFirestoreService {
  static final NotificationService _instance = NotificationService._();
  NotificationService._();
  factory NotificationService() => _instance;

  CollectionReference<Map<String, dynamic>> _coll(String schoolId) =>
      schoolCollection(schoolId, 'notifications');

  // ── Writers ────────────────────────────────────────────────────────────────

  Future<void> addAbsenceNotice({
    String? schoolId,
    required String className,
    required int    roll,
    required String studentName,
    required String status,
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    await _coll(sId).add({
      'type':      'absent',
      'title':     '$studentName marked $status today',
      'body':      'Your child has been marked $status today in $className. Please contact the school if this is incorrect.',
      'audience':  'guardian:$className:$roll',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addLeaveSubmitted({
    String? schoolId,
    required String teacherName,
    required String toRole,
    required int    days,
    required String startDate,
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    await _coll(sId).add({
      'type':      'leave_submitted',
      'title':     'New leave application from $teacherName',
      'body':      '$teacherName has applied for $days day(s) starting $startDate. Tap to review.',
      'audience':  toRole,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addLeaveResolved({
    String? schoolId,
    required String teacherId,
    required String teacherName,
    required String status,
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    await _coll(sId).add({
      'type':      'leave_resolved',
      'title':     'Leave $status',
      'body':      'Your leave application has been $status.',
      'audience':  'teacher:$teacherId',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addAnnouncementNotice({
    String? schoolId,
    required String title,
    required String body,
    required String audience,
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    await _coll(sId).add({
      'type':      'announcement',
      'title':     'New announcement: $title',
      'body':      body.length > 120 ? '${body.substring(0, 117)}…' : body,
      'audience':  audience,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addTaskNotice({
    String? schoolId,
    required String title,
    required String createdBy,
    required List<String> classes,
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    await _coll(sId).add({
      'type':      'task',
      'title':     'New Task: $title',
      'body':      'A new task has been assigned by $createdBy to classes: ${classes.join(", ")}.',
      'audience':  'teachers',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addStaffTaskNotice({
    String? schoolId,
    required StaffTask task,
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    for (var userId in task.assignedToIds) {
      await _coll(sId).add({
        'type':      'staff_task',
        'title':     'New Task: ${task.title}',
        'body':      'Priority: ${task.priority.name.toUpperCase()}. Due: ${task.dueDate.day}/${task.dueDate.month}.',
        'audience':  'user:$userId',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // ── Deleters ───────────────────────────────────────────────────────────────

  Future<void> deleteNotification({String? schoolId, required String id}) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    await _coll(sId).doc(id).delete();
  }

  // ── Readers ────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getFor({
    String? schoolId,
    required String role,
    String? teacherId,
    String? studentClass,
    int?    studentRoll,
    String? userEmail,
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    final snap = await _coll(sId).get();
    final now  = DateTime.now();
    final list = snap.docs.map((d) {
      final data = Map<String, dynamic>.from(d.data());
      data['id'] = d.id;
      return data;
    }).where((n) {
      final aud = (n['audience'] as String?) ?? '';
      if (aud == 'all') return true;
      if (aud == role)                                             return true;
      if (aud == 'teachers'  && role == 'teacher')                 return true;
      if (aud == 'guardians' && role == 'guardian')                return true;
      if (userEmail != null && aud == 'user:$userEmail')           return true;
      if (aud.startsWith('teacher:')  && role == 'teacher'  &&
          teacherId != null && aud == 'teacher:$teacherId')         return true;
      if (aud.startsWith('guardian:') && role == 'guardian' &&
          studentClass != null && studentRoll != null &&
          aud == 'guardian:$studentClass:$studentRoll')             return true;
      return false;
    }).toList();

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

  Future<int> unreadCount({
    String? schoolId,
    required String role,
    String? teacherId,
    String? studentClass,
    int?    studentRoll,
    String? userEmail,
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    final items = await getFor(
      schoolId: sId,
      role: role,
      teacherId: teacherId,
      studentClass: studentClass,
      studentRoll: studentRoll,
      userEmail: userEmail,
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
    await prefs.setInt(_lastSeenKey, DateTime.now().millisecondsSinceEpoch);
  }

  static const _lastSeenKey = 'notif_last_seen_ms';
}

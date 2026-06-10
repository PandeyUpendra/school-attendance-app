import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/meeting.dart';
import '../models/staff_task.dart';
import 'auth_service.dart';

class MeetingService {
  static final MeetingService _instance = MeetingService._();
  factory MeetingService() => _instance;
  MeetingService._();

  static final _db = FirebaseFirestore.instance;

  /// Active school, resolved from the signed-in session.
  String get _schoolId => AuthService.currentSchoolId;

  CollectionReference<Map<String, dynamic>> get _meetings =>
      _db.collection('schools').doc(_schoolId).collection('meetings');

  CollectionReference<Map<String, dynamic>> get _meetingTasks =>
      _db.collection('schools').doc(_schoolId).collection('meetingTasks');

  // Mirrors StaffTaskService's school-scoped staff_tasks collection so meeting-
  // derived tasks appear in the regular staff task lists.
  CollectionReference<Map<String, dynamic>> get _staffTasks =>
      _db.collection('schools').doc(_schoolId).collection('staff_tasks');

  // ── Create ────────────────────────────────────────────────────────────────

  Future<String> createMeeting(Meeting meeting) async {
    final ref  = _meetings.doc();
    await ref.set(meeting.toCreateJson());
    return ref.id;
  }

  /// Converts a meeting point to both a MeetingTask and a StaffTask.
  /// Updates the meeting's points list and assignedTeacher arrays.
  Future<String> convertPointToTask({
    required Meeting      meeting,
    required MeetingPoint point,
    required String       teacherId,
    required String       teacherName,
    required String       assignedBy,
    String                assignedByRole = 'coordinator',
  }) async {
    // 1. Create StaffTask in staff_tasks collection.
    final staffRef = _staffTasks.doc();
    final staffTask = StaffTask(
      id:             staffRef.id,
      title:          '[Meeting] ${meeting.title}',
      description:    point.text,
      assignedTo:     teacherId,
      assignedToName: teacherName,
      assignedBy:     assignedBy,
      // Use the actual converter's role — a principal converting a point was
      // previously mislabeled as coordinator-assigned (review #283).
      assignedByRole: assignedByRole,
      status:         TaskStatus.pending,
      priority:       TaskPriority.medium,
      createdAt:      DateTime.now(),
    );
    await staffRef.set(staffTask.toJson());

    // 2. Create MeetingTask.
    final mtRef = _meetingTasks.doc();
    final mtData = MeetingTask(
      id:            mtRef.id,
      meetingId:     meeting.id,
      meetingTitle:  meeting.title,
      meetingDate:   meeting.date,
      pointText:     point.text,
      assignedTo:    teacherId,
      assignedToName: teacherName,
      assignedBy:    assignedBy,
      staffTaskId:   staffRef.id,
      status:        'Pending',
      createdAt:     DateTime.now(),
    );
    await mtRef.set(mtData.toJson());

    // 3. Update meeting doc: mark point converted, update assigned teachers.
    final updatedPoints = meeting.points.map((p) {
      if (p.id == point.id) {
        return p.copyWith(convertedToTask: true, taskId: mtRef.id);
      }
      return p;
    }).toList();

    final ids   = List<String>.from(meeting.assignedTeacherIds);
    final names = List<String>.from(meeting.assignedTeacherNames);
    if (!ids.contains(teacherId)) {
      ids.add(teacherId);
      names.add(teacherName);
    }

    await _meetings.doc(meeting.id).update({
      'points':               updatedPoints.map((p) => p.toJson()).toList(),
      'assignedTeacherIds':   ids,
      'assignedTeacherNames': names,
      'updatedAt':            FieldValue.serverTimestamp(),
    });

    return mtRef.id;
  }

  // ── Update ────────────────────────────────────────────────────────────────

  Future<void> updatePoints(String meetingId, List<MeetingPoint> points) =>
      _meetings.doc(meetingId).update({
        'points':    points.map((p) => p.toJson()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> markCompleted(String meetingId) =>
      _meetings.doc(meetingId).update({
        'status':      'Completed',
        'completedAt': FieldValue.serverTimestamp(),
        'updatedAt':   FieldValue.serverTimestamp(),
      });

  Future<void> markActive(String meetingId) =>
      _meetings.doc(meetingId).update({
        'status':    'Active',
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> updatePdfUrl(String meetingId, String url) =>
      _meetings.doc(meetingId).update({
        'pdfUrl':    url,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> deleteMeeting(String meetingId) =>
      _meetings.doc(meetingId).delete();

  /// Teacher marks a meeting task done — updates meetingTask, staffTask, and
  /// the meeting point's isChecked flag.
  Future<void> completeMeetingTask({
    required String meetingTaskId,
    required String staffTaskId,
    required String meetingId,
    required String pointTaskId, // the meetingTask ID stored on the point
  }) async {
    await _db.runTransaction((transaction) async {
      final meetingRef = _meetings.doc(meetingId);
      final meetingSnap = await transaction.get(meetingRef);
      if (!meetingSnap.exists) return;

      // Update meeting task status.
      transaction.update(_meetingTasks.doc(meetingTaskId), {'status': 'Completed'});

      // Update staff task status.
      if (staffTaskId.isNotEmpty) {
        transaction.update(_staffTasks.doc(staffTaskId), {'status': 'completed'});
      }

      // Update the meeting point isChecked.
      final data = meetingSnap.data()!;
      final rawPoints = data['points'] as List? ?? [];
      final points = rawPoints
          .map((e) => MeetingPoint.fromJson(e as Map<String, dynamic>))
          .toList();
      final updated = points.map((p) {
        if (p.taskId == pointTaskId) return p.copyWith(isChecked: true);
        return p;
      }).toList();

      transaction.update(meetingRef, {
        'points':    updated.map((p) => p.toJson()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  // ── Streams ───────────────────────────────────────────────────────────────

  Stream<List<Meeting>> streamAllMeetings() =>
      _meetings
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((s) => s.docs.map((d) => Meeting.fromJson(d.data(), d.id)).toList());

  Stream<List<Meeting>> streamMeetingsByCreator(String createdBy) =>
      _meetings
          .where('createdBy', isEqualTo: createdBy)
          .snapshots()
          .map((s) {
            final list = s.docs.map((d) => Meeting.fromJson(d.data(), d.id)).toList();
            list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
            return list;
          });

  Stream<Meeting?> streamMeeting(String meetingId) =>
      _meetings.doc(meetingId).snapshots().map((s) {
        if (!s.exists) return null;
        return Meeting.fromJson(s.data()!, s.id);
      });

  Stream<List<MeetingTask>> streamTasksForTeacher(String teacherId) =>
      _meetingTasks
          .where('assignedTo', isEqualTo: teacherId)
          .snapshots()
          .map((s) {
            final list = s.docs.map((d) => MeetingTask.fromJson(d.data(), d.id)).toList();
            list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
            return list;
          });

  Stream<int> streamPendingTaskCountForTeacher(String teacherId) =>
      streamTasksForTeacher(teacherId)
          .map((tasks) => tasks.where((t) => !t.isCompleted).length);

  Stream<List<MeetingTask>> streamTasksForMeeting(String meetingId) =>
      _meetingTasks
          .where('meetingId', isEqualTo: meetingId)
          .snapshots()
          .map((s) => s.docs.map((d) => MeetingTask.fromJson(d.data(), d.id)).toList());

  Future<List<MeetingTask>> getTasksForMeeting(String meetingId) async {
    final s = await _meetingTasks.where('meetingId', isEqualTo: meetingId).get();
    return s.docs.map((d) => MeetingTask.fromJson(d.data(), d.id)).toList();
  }

  // ── One-off reads ─────────────────────────────────────────────────────────

  Future<Meeting?> getMeeting(String meetingId) async {
    final s = await _meetings.doc(meetingId).get();
    if (!s.exists) return null;
    return Meeting.fromJson(s.data()!, s.id);
  }

  Future<int> countMeetingsThisMonth() async {
    final start = DateTime(DateTime.now().year, DateTime.now().month, 1);
    final s = await _meetings
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .get();
    return s.size;
  }

  Future<int> countMyMeetingsThisMonth(String createdBy) async {
    final start = DateTime(DateTime.now().year, DateTime.now().month, 1);
    final s = await _meetings
        .where('createdBy', isEqualTo: createdBy)
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .get();
    return s.size;
  }

  Future<Map<String, int>> countMeetingTasksThisMonth() async {
    final start = DateTime(DateTime.now().year, DateTime.now().month, 1);
    final s = await _meetingTasks
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .get();
    final docs = s.docs.map((d) => d.data()).toList();
    return {
      'total':   docs.length,
      'pending': docs.where((d) => (d['status'] as String? ?? '') != 'Completed').length,
      'done':    docs.where((d) => (d['status'] as String? ?? '') == 'Completed').length,
    };
  }

}

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/staff_task.dart';

class StaffTaskService {
  static final StaffTaskService _instance = StaffTaskService._();
  factory StaffTaskService() => _instance;
  StaffTaskService._();

  static final _db    = FirebaseFirestore.instance;
  static final _tasks = _db.collection('staff_tasks');

  // ── School-scoped collection helper ───────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _col(String schoolId) =>
      _db.collection('schools').doc(schoolId).collection('staff_tasks');

  // ── Writers ───────────────────────────────────────────────────────────────

  Future<void> createTask(StaffTask task) async {
    final ref = _tasks.doc();
    await ref.set(task.toJson());
  }

  Future<void> createTaskWithAutoId(StaffTask task) async {
    final ref = _col(task.schoolId).doc();
    await ref.set({...task.toJson(), 'id': ref.id});
  }

  /// Update a full task object (replaces the Firestore doc).
  /// Extra params (userEmail, userName, userRole) are accepted but ignored —
  /// kept for call-site compatibility with the detail screen.
  Future<void> updateTask(
    StaffTask task, [
    String? userEmail,
    String? userName,
    String? userRole,
  ]) {
    final schoolId = task.schoolId;
    if (schoolId.isNotEmpty) {
      return _col(schoolId).doc(task.id).update(task.toJson());
    }
    return _tasks.doc(task.id).update(task.toJson());
  }

  /// Partial update via map.
  Future<void> updateTaskFields(
      String schoolId, String taskId, Map<String, dynamic> data) =>
      _col(schoolId).doc(taskId).update(data);

  Future<void> updateTaskStatus(String taskId, TaskStatus status) =>
      _tasks.doc(taskId).update({'status': status.name});

  /// Delete a task. Extra params accepted for call-site compat.
  Future<void> deleteTask(
    StaffTask task, [
    String? userEmail,
    String? userName,
    String? userRole,
  ]) {
    final schoolId = task.schoolId;
    if (schoolId.isNotEmpty) {
      return _col(schoolId).doc(task.id).delete();
    }
    return _tasks.doc(task.id).delete();
  }

  Future<void> deleteTaskById(String taskId) => _tasks.doc(taskId).delete();

  // ── School-scoped streams ─────────────────────────────────────────────────

  Stream<List<StaffTask>> getTasksCreatedBy(String schoolId, String email) =>
      _col(schoolId)
          .where('createdBy', isEqualTo: email)
          .snapshots()
          .map(_mapSnap);

  Stream<List<StaffTask>> getTasksAssignedTo(
      String schoolId, String email, String role) =>
      _col(schoolId).snapshots().map((snap) {
        final tasks = _mapSnap(snap);
        return tasks
            .where((t) =>
                t.assignedToIds.contains(email) ||
                t.targetRoles.contains(role))
            .toList();
      });

  Stream<List<StaffTask>> getPersonalTasks(String schoolId, String email) =>
      _col(schoolId)
          .where('createdBy', isEqualTo: email)
          .snapshots()
          .map((snap) {
        return _mapSnap(snap)
            .where((t) =>
                t.assignedToIds.length == 1 &&
                t.assignedToIds.first == email &&
                t.targetRoles.isEmpty)
            .toList();
      });

  Stream<List<StaffTask>> getAllStaffTasks(String schoolId) =>
      _col(schoolId).snapshots().map(_mapSnap);

  Future<void> updateTask2(
          String schoolId, String taskId, Map<String, dynamic> data) =>
      _col(schoolId).doc(taskId).update(data);

  // ── Teacher streams ────────────────────────────────────────────────────────

  /// Real-time stream of tasks assigned to one teacher, sorted urgent-first.
  Stream<List<StaffTask>> getTasksForTeacherStream(String teacherId) =>
      _tasks
          .where('assignedTo', isEqualTo: teacherId)
          .snapshots()
          .map(_sortByDueDate);

  /// Alias for teacher tasks screen compatibility.
  Stream<List<StaffTask>> getTasksForTeacher({required String className}) =>
      _tasks
          .where('classId', isEqualTo: className)
          .snapshots()
          .map(_sortByDueDate);

  /// Pending (non-completed) count for home-screen badge.
  Future<int> getPendingCountForTeacher(String teacherId) async {
    final snap =
        await _tasks.where('assignedTo', isEqualTo: teacherId).get();
    return snap.docs
        .where((d) => (d.data()['status'] as String? ?? '') != 'completed')
        .length;
  }

  // ── Coordinator streams ────────────────────────────────────────────────────

  /// Real-time stream of tasks created BY a specific coordinator/principal.
  Stream<List<StaffTask>> getTasksByAssignerStream(String assignedBy) =>
      _tasks
          .where('assignedBy', isEqualTo: assignedBy)
          .snapshots()
          .map(_sortByCreatedAt);

  /// Incomplete task count for coordinator dashboard badge.
  Future<int> getIncompleteCountByAssigner(String assignedBy) async {
    final snap =
        await _tasks.where('assignedBy', isEqualTo: assignedBy).get();
    return snap.docs
        .where((d) => (d.data()['status'] as String? ?? '') != 'completed')
        .length;
  }

  /// School-wide incomplete task count for coordinator dashboard badge.
  Future<int> getAllIncompleteCount() async {
    final snap = await _tasks.get();
    return snap.docs
        .where((d) => (d.data()['status'] as String? ?? '') != 'completed')
        .length;
  }

  // ── Principal streams ──────────────────────────────────────────────────────

  /// Real-time stream of ALL tasks in the school.
  Stream<List<StaffTask>> getAllTasksStream() =>
      _tasks.snapshots().map(_sortByCreatedAt);

  /// Real-time incomplete (non-completed) count — for coordinator badge.
  Stream<int> streamAllIncompleteCount() =>
      getAllTasksStream().map(
        (tasks) => tasks.where((t) => t.status != TaskStatus.completed).length,
      );

  /// Real-time pending count for a single teacher — for teacher home badge.
  Stream<int> streamPendingCountForTeacher(String teacherId) =>
      getTasksForTeacherStream(teacherId).map(
        (tasks) => tasks.where((t) => t.status != TaskStatus.completed).length,
      );

  // ── Helpers ───────────────────────────────────────────────────────────────

  List<StaffTask> _mapSnap(QuerySnapshot<Map<String, dynamic>> snap) =>
      snap.docs.map((d) => StaffTask.fromJson(d.data(), d.id)).toList();

  List<StaffTask> _sortByDueDate(
      QuerySnapshot<Map<String, dynamic>> snap) {
    final tasks = _mapSnap(snap);
    tasks.sort((a, b) {
      // Overdue first, then by due date asc, null due-dates last.
      if (a.dueDate == null && b.dueDate == null) {
        return b.createdAt.compareTo(a.createdAt);
      }
      if (a.dueDate == null) return 1;
      if (b.dueDate == null) return -1;
      return a.dueDate!.compareTo(b.dueDate!);
    });
    return tasks;
  }

  List<StaffTask> _sortByCreatedAt(
      QuerySnapshot<Map<String, dynamic>> snap) {
    final tasks = _mapSnap(snap);
    tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return tasks;
  }
}

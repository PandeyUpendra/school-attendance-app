import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/staff_task.dart';

class StaffTaskService {
  static final StaffTaskService _instance = StaffTaskService._();
  factory StaffTaskService() => _instance;
  StaffTaskService._();

  static final _db    = FirebaseFirestore.instance;
  static final _tasks = _db.collection('staff_tasks');

  // ── Writers ───────────────────────────────────────────────────────────────

  Future<void> createTask(StaffTask task) async {
    final ref = _tasks.doc();
    await ref.set(task.toJson());
  }

  Future<void> updateTaskStatus(String taskId, TaskStatus status) =>
      _tasks.doc(taskId).update({'status': status.name});

  Future<void> deleteTask(String taskId) => _tasks.doc(taskId).delete();

  // ── Teacher streams ────────────────────────────────────────────────────────

  /// Real-time stream of tasks assigned to one teacher, sorted urgent-first.
  Stream<List<StaffTask>> getTasksForTeacherStream(String teacherId) =>
      _tasks
          .where('assignedTo', isEqualTo: teacherId)
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

  // ── Helpers ───────────────────────────────────────────────────────────────

  List<StaffTask> _sortByDueDate(
      QuerySnapshot<Map<String, dynamic>> snap) {
    final tasks = snap.docs
        .map((d) => StaffTask.fromJson(d.data(), d.id))
        .toList();
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
    final tasks = snap.docs
        .map((d) => StaffTask.fromJson(d.data(), d.id))
        .toList();
    tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return tasks;
  }
}

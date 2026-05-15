import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/task.dart';
import 'notification_service.dart';

class TaskService {
  static final _db = FirebaseFirestore.instance;
  static final _tasks = _db.collection('tasks');

  static final TaskService _instance = TaskService._();
  TaskService._();
  factory TaskService() => _instance;

  Future<void> createTask({
    required String title,
    required String description,
    required String createdBy,
    required String creatorRole,
    required List<String> assignedClasses,
    DateTime? dueDate,
  }) async {
    final docRef = _tasks.doc();
    final task = Task(
      id: docRef.id,
      title: title,
      description: description,
      createdBy: createdBy,
      creatorRole: creatorRole,
      assignedClasses: assignedClasses,
      createdAt: DateTime.now(),
      dueDate: dueDate,
      studentStatuses: {},
    );

    await docRef.set(task.toJson());

    await NotificationService().addTaskNotice(
      title: title,
      createdBy: createdBy,
      classes: assignedClasses,
    );
  }

  Stream<List<Task>> getTasksForTeacher({required String className}) {
    return _tasks
        .where('assignedClasses', arrayContains: className)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => Task.fromJson(doc.data(), doc.id))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }

  Stream<List<Task>> getTasksCreatedBy(String email) {
    return _tasks
        .where('createdBy', isEqualTo: email)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => Task.fromJson(doc.data(), doc.id))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }

  Stream<List<Task>> getAllTasks() {
    return _tasks
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => Task.fromJson(doc.data(), doc.id))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }

  Future<void> updateStudentStatus(
      String taskId, String className, int roll, bool isDone) async {
    final key = '${className}_$roll';
    await _tasks.doc(taskId).update({
      'studentStatuses.$key': isDone,
    });
  }

  Future<void> updateBulkStudentStatuses({
      required String taskId, required Map<String, bool> updates}) async {
    final batchUpdates = <String, dynamic>{};
    updates.forEach((key, value) {
      batchUpdates['studentStatuses.$key'] = value;
    });
    await _tasks.doc(taskId).update(batchUpdates);
  }
}

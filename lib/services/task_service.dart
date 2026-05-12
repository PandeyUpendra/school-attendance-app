import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/task.dart';
import 'notification_service.dart';
import 'base_firestore_service.dart';

class TaskService extends BaseFirestoreService {
  static final TaskService _instance = TaskService._();
  TaskService._();
  factory TaskService() => _instance;

  CollectionReference<Map<String, dynamic>> _tasks(String schoolId) =>
      schoolCollection(schoolId, 'tasks');

  Future<void> createTask({
    String? schoolId,
    required String title,
    required String description,
    required String createdBy,
    required String creatorRole,
    required List<String> assignedClasses,
    DateTime? dueDate,
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    final docRef = _tasks(sId).doc();
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

    // Notification service might also need schoolId, check it next
    await NotificationService().addTaskNotice(
      schoolId: sId,
      title: title,
      createdBy: createdBy,
      classes: assignedClasses,
    );
  }

  Stream<List<Task>> getTasksForTeacher({String? schoolId, required String className}) {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    return _tasks(sId)
        .where('assignedClasses', arrayContains: className)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => Task.fromJson(doc.data(), doc.id))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }

  Stream<List<Task>> getTasksCreatedBy({String? schoolId, required String email}) {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    return _tasks(sId)
        .where('createdBy', isEqualTo: email)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => Task.fromJson(doc.data(), doc.id))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }

  Stream<List<Task>> getAllTasks({String? schoolId}) {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    return _tasks(sId)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => Task.fromJson(doc.data(), doc.id))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }

  Future<void> updateStudentStatus({
    String? schoolId,
    required String taskId,
    required String className,
    required int roll,
    required bool isDone,
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    final key = '${className}_$roll';
    await _tasks(sId).doc(taskId).update({
      'studentStatuses.$key': isDone,
    });
  }

  Future<void> updateBulkStudentStatuses({
    String? schoolId,
    required String taskId,
    required Map<String, bool> updates,
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    final batchUpdates = <String, dynamic>{};
    updates.forEach((key, value) {
      batchUpdates['studentStatuses.$key'] = value;
    });
    await _tasks(sId).doc(taskId).update(batchUpdates);
  }
}

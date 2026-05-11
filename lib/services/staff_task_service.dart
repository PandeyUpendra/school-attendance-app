import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/staff_task.dart';

class StaffTaskService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  late final CollectionReference _tasks;

  static final StaffTaskService _instance = StaffTaskService._();
  StaffTaskService._() {
    _tasks = _db.collection('staff_tasks');
  }
  factory StaffTaskService() => _instance;

  Future<void> createTask(StaffTask task) async {
    final docRef = _tasks.doc();
    final newTask = task.copyWith(); // If we wanted to ensure ID is set, but we use the one passed or generated
    await _tasks.add(task.toFirestore());
  }

  Future<void> createTaskWithAutoId(StaffTask task) async {
    final docRef = _tasks.doc();
    final taskWithId = StaffTask(
      id: docRef.id,
      title: task.title,
      description: task.description,
      notes: task.notes,
      createdBy: task.createdBy,
      creatorRole: task.creatorRole,
      creatorName: task.creatorName,
      assignedToIds: task.assignedToIds,
      assignedToNames: task.assignedToNames,
      assignedToRoles: task.assignedToRoles,
      targetClasses: task.targetClasses,
      priority: task.priority,
      status: task.status,
      createdAt: task.createdAt,
      dueDate: task.dueDate,
      isRecurring: task.isRecurring,
      recurrencePattern: task.recurrencePattern,
      checkpoints: task.checkpoints,
      completionNotes: task.completionNotes,
      progressUpdates: task.progressUpdates,
    );
    await docRef.set(taskWithId.toFirestore());
  }

  Future<void> updateTask(StaffTask task) async {
    await _tasks.doc(task.id).update(task.toFirestore());
  }

  Future<void> deleteTask(String taskId) async {
    await _tasks.doc(taskId).delete();
  }

  Stream<List<StaffTask>> getTasksAssignedTo(String userId, String userRole) {
    return _tasks
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => StaffTask.fromFirestore(doc.data() as Map<String, dynamic>, doc.id))
            .where((task) => task.assignedToIds.contains(userId) || task.targetRoles.contains(userRole))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }

  Stream<List<StaffTask>> getTasksCreatedBy(String userId) {
    return _tasks
        .where('createdBy', isEqualTo: userId)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => StaffTask.fromFirestore(doc.data() as Map<String, dynamic>, doc.id))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }

  Stream<List<StaffTask>> getAllStaffTasks() {
    return _tasks
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => StaffTask.fromFirestore(doc.data() as Map<String, dynamic>, doc.id))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }

  // Personal tasks are those created by the user and assigned only to themselves (or no one else)
  // Or we can have a separate 'isPersonal' flag.
  // Given the requirement "Maintain personal self-created to-do lists",
  // I'll assume personal tasks have assignedToIds containing only the creatorId.
  Stream<List<StaffTask>> getPersonalTasks(String userId) {
    return _tasks
        .where('createdBy', isEqualTo: userId)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => StaffTask.fromFirestore(doc.data() as Map<String, dynamic>, doc.id))
            .where((task) => task.assignedToIds.length == 1 && task.assignedToIds.contains(userId))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }
}

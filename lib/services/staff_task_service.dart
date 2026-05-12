import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/staff_task.dart';
import 'audit_log_service.dart';
import 'base_firestore_service.dart';

class StaffTaskService extends BaseFirestoreService {
  static final StaffTaskService _instance = StaffTaskService._();
  StaffTaskService._();
  factory StaffTaskService() => _instance;

  CollectionReference _tasks(String schoolId) =>
      db.collection('schools').doc(schoolId).collection('staff_tasks');

  Future<void> createTaskWithAutoId(StaffTask task) async {
    final docRef = _tasks(task.schoolId).doc();
    final taskWithId = task.copyWith(
      schoolId: task.schoolId, // Ensure it's set
    );
    // Note: copyWith doesn't take id, so we'll just set it in toFirestore or here
    final data = taskWithId.toFirestore();
    data['id'] = docRef.id; // Ensure ID is in document too if needed

    await docRef.set(data);

    await AuditLogService().log(
      schoolId: task.schoolId,
      userId: task.createdBy,
      userName: task.creatorName,
      userRole: task.creatorRole,
      action: AuditAction.create,
      resourceType: 'staff_task',
      resourceId: docRef.id,
      description: 'Created task: ${task.title}',
    );
  }

  Future<void> updateTask(StaffTask task, String updaterId, String updaterName, String updaterRole) async {
    await _tasks(task.schoolId).doc(task.id).update(task.toFirestore());

    await AuditLogService().log(
      schoolId: task.schoolId,
      userId: updaterId,
      userName: updaterName,
      userRole: updaterRole,
      action: AuditAction.update,
      resourceType: 'staff_task',
      resourceId: task.id,
      description: 'Updated task: ${task.title}',
    );
  }

  /// Soft delete
  Future<void> deleteTask(StaffTask task, String updaterId, String updaterName, String updaterRole) async {
    await _tasks(task.schoolId).doc(task.id).update({
      'isDeleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
    });

    await AuditLogService().log(
      schoolId: task.schoolId,
      userId: updaterId,
      userName: updaterName,
      userRole: updaterRole,
      action: AuditAction.delete,
      resourceType: 'staff_task',
      resourceId: task.id,
      description: 'Soft-deleted task: ${task.title}',
    );
  }

  Future<void> restoreTask(StaffTask task, String updaterId, String updaterName, String updaterRole) async {
    await _tasks(task.schoolId).doc(task.id).update({
      'isDeleted': false,
      'deletedAt': null,
    });

    await AuditLogService().log(
      schoolId: task.schoolId,
      userId: updaterId,
      userName: updaterName,
      userRole: updaterRole,
      action: AuditAction.restore,
      resourceType: 'staff_task',
      resourceId: task.id,
      description: 'Restored task: ${task.title}',
    );
  }

  Stream<List<StaffTask>> getTasksAssignedTo(String schoolId, String userId, String userRole, {int limit = 20, DocumentSnapshot? startAfter}) {
    Query query = _tasks(schoolId)
        .where('isDeleted', isEqualTo: false)
        .where(Filter.or(
          Filter('assignedToIds', arrayContains: userId),
          Filter('targetRoles', arrayContains: userRole),
        ))
        .orderBy('createdAt', descending: true)
        .limit(limit);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    return query.snapshots().map((snap) => snap.docs
        .map((doc) => StaffTask.fromFirestore(doc.data() as Map<String, dynamic>, doc.id))
        .toList());
  }

  Stream<List<StaffTask>> getTasksCreatedBy(String schoolId, String userId, {int limit = 20, DocumentSnapshot? startAfter}) {
    Query query = _tasks(schoolId)
        .where('createdBy', isEqualTo: userId)
        .where('isDeleted', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .limit(limit);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    return query.snapshots().map((snap) => snap.docs
        .map((doc) => StaffTask.fromFirestore(doc.data() as Map<String, dynamic>, doc.id))
        .toList());
  }

  Stream<List<StaffTask>> getAllStaffTasks(String schoolId, {int limit = 20, DocumentSnapshot? startAfter}) {
    Query query = _tasks(schoolId)
        .where('isDeleted', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .limit(limit);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    return query.snapshots().map((snap) => snap.docs
        .map((doc) => StaffTask.fromFirestore(doc.data() as Map<String, dynamic>, doc.id))
        .toList());
  }

  Stream<List<StaffTask>> getPersonalTasks(String schoolId, String userId, {int limit = 20, DocumentSnapshot? startAfter}) {
    // A personal task is one created by the user where assignedToIds contains only them
    // and no target roles. We can simplify this query.
    Query query = _tasks(schoolId)
        .where('createdBy', isEqualTo: userId)
        .where('assignedToIds', isEqualTo: [userId])
        .where('isDeleted', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .limit(limit);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    return query.snapshots().map((snap) => snap.docs
        .map((doc) => StaffTask.fromFirestore(doc.data() as Map<String, dynamic>, doc.id))
        .toList());
  }
}


import 'package:cloud_firestore/cloud_firestore.dart';
import 'base_firestore_service.dart';

enum AuditAction { create, update, delete, restore, access }

class AuditLogService extends BaseFirestoreService {
  static final AuditLogService _instance = AuditLogService._();
  AuditLogService._();
  factory AuditLogService() => _instance;

  Future<void> log({
    String? schoolId,
    required String userId,
    required String userName,
    required String userRole,
    required AuditAction action,
    required String resourceType,
    required String resourceId,
    String? description,
    Map<String, dynamic>? metadata,
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    try {
      await db.collection('schools').doc(sId).collection('audit_logs').add({
        'userId': userId,
        'userName': userName,
        'userRole': userRole,
        'action': action.name,
        'resourceType': resourceType,
        'resourceId': resourceId,
        'description': description,
        'metadata': metadata,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Failed to log audit entry: $e');
    }
  }
}

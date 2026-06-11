import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/app_logger.dart';
import 'auth_service.dart';
import 'base_firestore_service.dart';

/// Service to log all individual notification and email communication events.
/// Writes to communication_logs/{schoolId}/logs collection.
class CommunicationLogService extends BaseFirestoreService {
  static final CommunicationLogService _instance = CommunicationLogService._();
  CommunicationLogService._();
  factory CommunicationLogService() => _instance;

  CollectionReference<Map<String, dynamic>> _col(String sid) =>
      db.collection('communication_logs').doc(sid).collection('logs');

  /// Logs a sent communication (notification or email).
  Future<void> logSend({
    required String targetUid,
    required String type,
    required Map<String, dynamic> payload,
    required bool success,
    String? schoolId,
  }) async {
    try {
      final sid = schoolId ?? AuthService.currentSchoolId;
      await _col(sid).add({
        'targetUid': targetUid,
        'type': type,
        'payload': payload,
        'success': success,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e, stack) {
      AppLogger.e('CommunicationLogService', 'Failed to log send: $e', e, stack);
    }
  }
}

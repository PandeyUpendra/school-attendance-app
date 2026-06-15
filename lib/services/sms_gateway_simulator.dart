import 'package:cloud_firestore/cloud_firestore.dart';
import '../shared/utils/app_logger.dart';

class SmsGatewaySimulator {
  static final SmsGatewaySimulator _instance = SmsGatewaySimulator._();
  SmsGatewaySimulator._();
  factory SmsGatewaySimulator() => _instance;

  /// Simulates sending an SMS absence alert.
  /// Delays for 500ms to simulate network latency, then writes an audit record
  /// in the school's sms_logs collection in Firestore.
  Future<bool> sendAbsenceAlert({
    required String schoolId,
    required String studentName,
    required int roll,
    required String parentPhone,
    required String status,
  }) async {
    if (parentPhone.trim().isEmpty) {
      AppLogger.w('SmsGatewaySimulator', 'Parent phone number is empty. Skipping SMS dispatch.');
      return false;
    }

    // Simulate API delay
    await Future.delayed(const Duration(milliseconds: 500));

    final String messageText = 'Dear Parent, your child $studentName (Roll No: $roll) has been marked $status today. '
        'If this is an error, please contact the class teacher immediately.';

    try {
      final db = FirebaseFirestore.instance;
      final docRef = db
          .collection('schools')
          .doc(schoolId)
          .collection('sms_logs')
          .doc();

      final logData = {
        'id': docRef.id,
        'studentName': studentName,
        'roll': roll,
        'parentPhone': parentPhone,
        'status': status,
        'message': messageText,
        'characterCount': messageText.length,
        'smsCost': 0.30, // ₹0.30 cost per SMS
        'providerStatus': 'Sent',
        'providerResponse': 'MOCK_GATEWAY_SUCCESS_200',
        'timestamp': FieldValue.serverTimestamp(),
      };

      await docRef.set(logData);
      AppLogger.d('SmsGatewaySimulator', 'Simulated SMS sent successfully to $parentPhone: "$messageText"');
      return true;
    } catch (e, st) {
      AppLogger.e('SmsGatewaySimulator', 'Failed to log simulated SMS', e, st);
      return false;
    }
  }

  /// Streams the last 50 SMS logs for a school (used to verify dispatches).
  Stream<QuerySnapshot<Map<String, dynamic>>> streamSmsLogs(String schoolId) {
    return FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('sms_logs')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots();
  }
}

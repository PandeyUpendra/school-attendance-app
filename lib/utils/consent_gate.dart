import 'package:flutter/material.dart';
import '../models/student.dart';
import '../services/consent_service.dart';

/// Parental-consent processing gate (#108).
///
/// Call before any action that sends a child's personal data to a THIRD PARTY
/// (e.g. a WhatsApp message). Returns true when active consent is on record;
/// otherwise shows a blocking message and returns false so the caller aborts.
/// Internal-only processing (saving a record in Firestore) does NOT need this.
abstract class ConsentGate {
  static Future<bool> allowsThirdPartyShare(
    BuildContext context, {
    required int roll,
    required String className,
    required String section,
  }) async {
    final ok = await ConsentService()
        .hasActiveConsent(Student.buildDocId(roll, className, section));
    if (ok) return true;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Not sent — parental consent to share this child's data is not on record.",
          ),
          backgroundColor: Colors.orange,
        ),
      );
    }
    return false;
  }
}

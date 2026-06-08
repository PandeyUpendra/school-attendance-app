import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../models/student.dart';
import '../services/consent_service.dart';

/// Parental-consent processing gate (#108 / #17).
///
/// Call before any action that sends a child's personal data to a THIRD PARTY —
/// a WhatsApp message OR a PDF share/export that leaves the device (report card,
/// attendance certificate). Returns true when active consent is on record;
/// otherwise shows a blocking message and returns false so the caller aborts.
/// Internal-only processing (saving a record, viewing on-screen) does NOT need
/// this.
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
        SnackBar(
          content: Text(context.tr('consentNotOnRecord')),
          backgroundColor: Colors.orange,
        ),
      );
    }
    return false;
  }

  /// Convenience overload that reads identifiers off a [Student].
  static Future<bool> allowsForStudent(BuildContext context, Student s) =>
      allowsThirdPartyShare(context,
          roll: s.roll, className: s.className, section: s.section);
}

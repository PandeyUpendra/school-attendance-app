import 'package:flutter_test/flutter_test.dart';
import 'package:school_app/services/notification_service.dart';

/// Unit tests for the stable guardian-audience logic (#39). Pure function — no
/// Firestore needed. The end-to-end delivery (login → subscribe → stream) is a
/// device-verified step; here we pin the identity-selection rule.
void main() {
  group('NotificationService.guardianAudience', () {
    test('prefers the stable admissionId channel when known', () {
      expect(
        NotificationService.guardianAudience('Class 9', 5, 'ADM-A'),
        'guardian_adm:ADM-A',
      );
    });

    test('falls back to the legacy roll channel when admissionId is null', () {
      expect(
        NotificationService.guardianAudience('Class 9', 5, null),
        'guardian:Class 9:5',
      );
    });

    test('falls back when admissionId is blank/whitespace', () {
      expect(
        NotificationService.guardianAudience('Class 9', 5, '   '),
        'guardian:Class 9:5',
      );
    });
  });
}

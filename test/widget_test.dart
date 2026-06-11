import 'package:flutter_test/flutter_test.dart';

/// App-level smoke tests require a fully initialized Firebase environment
/// (firebase_core, firebase_auth, firebase_messaging, firebase_crashlytics,
/// firebase_app_check). These should be run as integration tests against a
/// Firebase emulator or real project — not as `flutter test` unit tests.
///
/// See: integration_test/ for device-level test coverage.
void main() {
  test('placeholder — see integration_test/ for app smoke tests', () {
    // This test intentionally does nothing. The actual smoke test is an
    // integration test that requires a running Firebase environment.
    expect(true, isTrue);
  });
}

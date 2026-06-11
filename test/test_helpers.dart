import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sets up minimal Firebase platform channel stubs so that
/// transitive imports of Firebase services don't crash at class load time.
///
/// NOTE: This does NOT call Firebase.initializeApp(). With the lazy getter
/// on AuthService._auth, class loading no longer triggers FirebaseAuth.instance.
/// This helper is retained for any test that does need to pump a widget tree
/// that may hit Firebase channels during render.
void setupFirebaseMocks() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Stub the firebase_core method channel.
  const MethodChannel firebaseCoreChannel =
      MethodChannel('plugins.flutter.io/firebase_core');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(firebaseCoreChannel, (MethodCall call) async {
    return null;
  });

  // Stub firebase_auth channel so FirebaseAuth.instance doesn't crash
  // when the channel is accessed.
  const MethodChannel firebaseAuthChannel =
      MethodChannel('plugins.flutter.io/firebase_auth');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(firebaseAuthChannel, (MethodCall call) async {
    switch (call.method) {
      case 'Auth#registerIdTokenListener':
      case 'Auth#registerAuthStateListener':
        return {'handle': 0};
      default:
        return null;
    }
  });

  // Stub cloud_firestore channel.
  const MethodChannel firestoreChannel =
      MethodChannel('plugins.flutter.io/cloud_firestore');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(firestoreChannel, (MethodCall call) async {
    return null;
  });
}

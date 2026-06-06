import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../screens/login_screen.dart';

class RoleGuard {
  static Future<bool> verify(
      BuildContext context, List<String> allowedRoles) async {
    final session = await AuthService().getSession();
    final role    = session?['role'] as String? ?? '';

    final noSession  = session == null;
    final wrongRole  = !allowedRoles.contains(role);

    // Verify the Firebase Auth session is still active for ALL roles. Guardians
    // were previously exempt, so a guardian whose token was revoked kept access
    // (review #26). Phone-OTP guardians also have a Firebase Auth user, so this
    // check is valid for them too.
    final firebaseExpired = FirebaseAuth.instance.currentUser == null;

    if (noSession || wrongRole || firebaseExpired) {
      // Always clear the cached session when bouncing to login — previously a
      // wrong-role user was bounced but kept their stale prefs (review #27).
      await AuthService().clearSession();
      if (context.mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
      }
      return false;
    }
    return true;
  }
}

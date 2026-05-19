import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../screens/login_screen.dart';

class RoleGuard {
  static Future<bool> verify(
      BuildContext context, List<String> allowedRoles) async {
    final session = await AuthService().getSession();
    final role    = session?['role'] as String? ?? '';

    final isGuardian = role == 'guardian';
    final noSession  = session == null;
    final wrongRole  = !allowedRoles.contains(role);

    // For staff, also verify Firebase Auth session is still active.
    final firebaseExpired =
        !isGuardian && FirebaseAuth.instance.currentUser == null;

    if (noSession || wrongRole || firebaseExpired) {
      if (firebaseExpired || noSession) {
        await AuthService().clearSession();
      }
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

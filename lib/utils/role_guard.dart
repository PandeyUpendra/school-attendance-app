import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../screens/role_selection_screen.dart';

class RoleGuard {
  static Future<bool> verify(
      BuildContext context, List<String> allowedRoles) async {
    final session = await AuthService().getSession();
    if (session == null) {
      if (context.mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
          (_) => false,
        );
      }
      return false;
    }
    final role = session['role'] as String? ?? '';
    if (!allowedRoles.contains(role)) {
      if (context.mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
          (_) => false,
        );
      }
      return false;
    }
    return true;
  }
}

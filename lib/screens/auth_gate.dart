import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_user.dart';
import '../providers/auth_provider.dart';
import 'login_screen.dart';
import 'class_selection_screen.dart';
import 'guardian_home.dart';
import 'teacher_dashboard_screen.dart';
import 'subject_teacher_home.dart';
import 'coordinator_home.dart';
import 'principal_home.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (auth.isAuthenticated) {
      final user = auth.user;
      if (user?.role == UserRole.guardian) return const GuardianHome();
      if (user?.role == UserRole.teacher) return const TeacherDashboardScreen();
      if (user?.role == UserRole.subjectTeacher) return const SubjectTeacherHome();
      if (user?.role == UserRole.coordinator) return const CoordinatorHome();
      if (user?.role == UserRole.principal) return const PrincipalHome();
      return const ClassSelectionScreen();
    }

    return const LoginScreen();
  }
}

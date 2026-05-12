import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'firebase_options.dart';
import 'theme.dart';
import 'screens/role_selection_screen.dart';
import 'screens/coordinator_dashboard.dart';
import 'screens/home_screen.dart';
import 'screens/principal_dashboard.dart';
import 'screens/guardian_dashboard.dart';
import 'screens/student_selection_screen.dart';
import 'services/auth_service.dart';
import 'services/timetable_service.dart';
import 'services/base_firestore_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Status bar: solid deep-violet so it matches the hero gradient top edge
  // on every screen. AppBarTheme sets it precisely to AppTheme.primary on
  // screens that have an AppBar.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: AppTheme.primaryDark,        // #4A148C – gradient start
    statusBarIconBrightness: Brightness.light,   // white icons on dark bg
    statusBarBrightness: Brightness.dark,        // iOS: white icons
  ));
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Ensure we have a Firebase Auth session for Storage/Firestore rules
  try {
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
  } catch (e) {
    debugPrint('Firebase Anonymous Sign-in failed: $e');
    // We continue so the app doesn't crash, but some features may fail 
    // if Firebase rules require authentication.
  }
  runApp(const SchoolApp());
}

class SchoolApp extends StatelessWidget {
  const SchoolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'School App',
      theme: AppTheme.light,
      home: const _SplashGate(),
    );
  }
}

/// Checks for a saved session and redirects to the appropriate screen.
/// Shows a spinner while loading.
class _SplashGate extends StatefulWidget {
  const _SplashGate();

  @override
  State<_SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<_SplashGate> {
  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final session = await AuthService().getSession();
    if (session != null && session['schoolId'] != null) {
      BaseFirestoreService.currentSchoolId = session['schoolId'];
    }

    if (!mounted) return;

    if (session == null) {
      _go(const RoleSelectionScreen());
      return;
    }

    final role = session['role'] as String? ?? '';

    switch (role) {
      case 'coordinator':
        _go(const CoordinatorDashboard());
        return;

      case 'principal':
        _go(const PrincipalDashboard());
        return;

      case 'guardian':
        final links = session['studentLinks'] as List?;
        final schoolId = session['schoolId'] as String? ?? 'default_school';
        if (links != null && links.isNotEmpty) {
          if (links.length == 1) {
            final parts = (links.first as String).split('|');
            if (parts.length >= 2) {
              _go(GuardianDashboard(
                  schoolId: schoolId,
                  studentClass: parts[0], studentRoll: int.parse(parts[1])));
              return;
            }
          } else {
            // Multiple children: go to selection screen
            _go(StudentSelectionScreen(schoolId: schoolId, links: List<String>.from(links)));
            return;
          }
        }
        // Guardian session missing student link → re-login
        _go(const RoleSelectionScreen());
        return;

      case 'teacher':
        final teacherId = session['teacherId'] as String?;
        final schoolId = session['schoolId'] as String? ?? 'default_school';
        if (teacherId != null) {
          final teacher =
              await TimetableService().getTeacherById(schoolId: schoolId, id: teacherId);
          if (!mounted) return;
          if (teacher != null) {
            _go(HomeScreen(teacher: teacher.copyWith(schoolId: schoolId)));
            return;
          }
        }
        // Teacher session exists but no valid teacherId → re-login
        _go(const RoleSelectionScreen());
        return;

      default:
        _go(const RoleSelectionScreen());
    }
  }

  void _go(Widget screen) {
    if (!mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.school, size: 56, color: AppTheme.primary),
            SizedBox(height: 20),
            CircularProgressIndicator(color: AppTheme.primary),
          ],
        ),
      ),
    );
  }
}

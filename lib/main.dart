import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'firebase_options.dart';
import 'theme.dart';
import 'screens/role_selection_screen.dart';
import 'screens/coordinator_dashboard.dart';
import 'screens/home_screen.dart';
import 'screens/principal_dashboard.dart';
import 'screens/guardian_dashboard.dart';
import 'screens/owner/owner_home.dart';
import 'screens/owner/owner_principal_home.dart';
import 'services/auth_service.dart';
import 'services/timetable_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Status bar: solid deep-violet so it matches the hero gradient top edge
  // on every screen. AppBarTheme sets it precisely to AppTheme.primary on
  // screens that have an AppBar.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: AppTheme.primary,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: AppTheme.primary,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarDividerColor: AppTheme.primary,
  ));
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const SchoolApp());
}

class SchoolApp extends StatelessWidget {
  const SchoolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: AppTheme.primary,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppTheme.primary,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: AppTheme.primary,
      ),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'School App',
        theme: AppTheme.light,
        home: const _SplashGate(),
      ),
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

      case 'owner':
        _go(const OwnerHome());
        return;

      case 'ownerPrincipal':
        _go(const OwnerPrincipalHome());
        return;

      case 'guardian':
        final sClass   = session['studentClass']   as String?;
        final sRoll    = session['studentRoll']    as int?;
        final sSection = session['studentSection'] as String? ?? '';
        if (sClass != null && sRoll != null) {
          _go(GuardianDashboard(
              studentClass: sClass, studentRoll: sRoll, studentSection: sSection));
          return;
        }
        // Guardian session missing student link → re-login
        _go(const RoleSelectionScreen());
        return;

      case 'teacher':
        final teacherId = session['teacherId'] as String?;
        if (teacherId != null) {
          final teacher =
              await TimetableService().getTeacherById(id: teacherId);
          if (!mounted) return;
          if (teacher != null) {
            _go(HomeScreen(teacher: teacher));
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.primaryDark, AppTheme.primary, AppTheme.primaryMid],
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.school, size: 56, color: Colors.white),
              SizedBox(height: 20),
              CircularProgressIndicator(color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

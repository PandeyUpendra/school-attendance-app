import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'theme.dart';
import 'providers/school_settings_provider.dart';
import 'screens/login_screen.dart';
import 'screens/role_selection_screen.dart';
import 'screens/coordinator_dashboard.dart';
import 'screens/home_screen.dart';
import 'screens/principal_dashboard.dart';
import 'screens/guardian_dashboard.dart';
import 'screens/owner/owner_home.dart';
import 'screens/owner/owner_principal_home.dart';
import 'services/auth_service.dart';
import 'services/base_firestore_service.dart';
import 'services/timetable_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
  ));
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const SchoolApp());
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

class SchoolApp extends StatelessWidget {
  const SchoolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SchoolSettingsProvider()),
      ],
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarContrastEnforced: false,
        ),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'School App',
          theme: AppTheme.light,
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(
                  MediaQuery.of(context).textScaler.scale(1.0).clamp(0.8, 1.2),
                ),
              ),
              child: child!,
            );
          },
          home: const _SplashGate(),
        ),
      ),
    );
  }
}

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
      _go(const LoginScreen());
      return;
    }

    final role = session['role'] as String? ?? '';

    // All roles (including guardians) now use Firebase Auth — verify the
    // session is still valid before routing. Guardians may have signed in via
    // email+password or phone OTP; both produce a Firebase Auth user.
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      await AuthService().clearSession();
      if (!mounted) return;
      _go(const LoginScreen());
      return;
    }

    // Restore in-memory schoolId so services read from the correct school
    // on cold-start with a cached session. Without this, BaseFirestoreService
    // falls back to 'school_1' which may not match the user's allowed_users doc.
    final schoolId = session['schoolId'] as String?;
    if (schoolId != null && schoolId.isNotEmpty) {
      BaseFirestoreService.currentSchoolId = schoolId;
    }

    // IDENTITY GUARD — the cached session and the live Firebase Auth user must
    // be the SAME account. Firestore rules derive identity from the Auth token
    // email (`request.auth.token.email`), NOT from the cached session. If a
    // previous/different account is still the signed-in Firebase Auth user while
    // the session says "owner", the app routes to the owner dashboard but every
    // read/write is denied (the app thinks you're the owner; the server doesn't).
    // Force re-login on any mismatch so the two can't diverge. Phone-OTP
    // guardians have no token email, so they are exempt from this check.
    if (role != 'guardian') {
      final authEmail    = firebaseUser.email?.toLowerCase().trim();
      final sessionEmail = (session['email'] as String?)?.toLowerCase().trim();
      if (authEmail == null || authEmail.isEmpty ||
          sessionEmail == null || sessionEmail.isEmpty ||
          authEmail != sessionEmail) {
        await AuthService().clearSession();
        if (!mounted) return;
        _go(const LoginScreen());
        return;
      }
    }

    // Re-validate management sessions against the authoritative allowed_users
    // doc. SplashGate otherwise routes purely from the cached SharedPreferences
    // session — so a session whose role was since revoked or changed would
    // render a dashboard the Firestore rules no longer honour, and every write
    // (e.g. an owner creating a principal) then fails with permission-denied
    // while looking like a generic error. Reconcile against the live doc:
    //   • doc absent OR role changed  → clear the stale session, force re-login
    //   • read threw (offline/transient) → keep cached routing (don't lock out)
    //   • role matches                 → proceed
    const managementRoles = {'owner', 'ownerPrincipal', 'principal', 'coordinator'};
    final email = session['email'] as String?;
    if (managementRoles.contains(role) && email != null && email.isNotEmpty) {
      bool readFailed = false;
      Map<String, dynamic>? live;
      try {
        live = await TimetableService().getAllowedUserDoc(email);
      } catch (_) {
        readFailed = true; // network/transient — fall through to cached routing.
      }
      if (!mounted) return;
      if (!readFailed && (live == null || (live['role'] as String? ?? '') != role)) {
        await AuthService().clearSession();
        if (!mounted) return;
        _go(const LoginScreen());
        return;
      }
    }

    switch (role) {
      case 'admin':
        // Admin is a privileged, non-persistent role reached only via the
        // explicit "Admin Access" dialog on the login screen — never
        // auto-resume into the Admin panel on app launch. Show the login
        // screen instead so the app opens normally.
        _go(const LoginScreen());
        return;

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
        _go(const RoleSelectionScreen());
        return;

      case 'teacher':
      case 'subjectTeacher':
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
        _go(const LoginScreen());
        return;

      default:
        _go(const LoginScreen());
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
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppTheme.primaryDark, AppTheme.primaryMid],
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

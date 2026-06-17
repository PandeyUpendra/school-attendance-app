import 'dart:async';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'theme.dart';
import './shared/providers/locale_provider.dart';
import './shared/providers/school_settings_provider.dart';
import './features/auth/login_screen.dart';
import './features/auth/role_selection_screen.dart';
import './features/dashboards/coordinator_dashboard.dart';
import './features/dashboards/home_screen.dart';
import './features/dashboards/principal_dashboard.dart';
import './features/dashboards/guardian_dashboard.dart';
import './features/owner/owner_home.dart';
import './features/owner/owner_principal_home.dart';
import 'services/auth_service.dart';
import 'services/base_firestore_service.dart';
import 'services/birthday_service.dart';
import 'services/timetable_service.dart';
import './shared/utils/app_transitions.dart';
final RouteObserver<PageRoute<dynamic>> routeObserver = RouteObserver<PageRoute<dynamic>>();
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

  // Crash reporting (#71): route Flutter framework errors and uncaught async
  // errors to Crashlytics so production crashes are visible.
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  // App Check (#2): attest requests come from a genuine app build. Activation
  // is harmless until enforcement is turned on in the Firebase console — debug
  // builds use the debug provider (token printed to logcat for registration),
  // release uses Play Integrity / App Attest. Best-effort: never block startup.
  try {
    await FirebaseAppCheck.instance.activate(
      androidProvider:
          kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
      appleProvider: kDebugMode ? AppleProvider.debug : AppleProvider.appAttest,
    );
  } catch (_) {/* App Check unavailable — continue without it */}

  final messaging = FirebaseMessaging.instance;
  // Request permission asynchronously to avoid blocking startup (issue #1)
  unawaited(messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  ));
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  
  // Load cached root admin emails
  await AuthService().loadCachedAdminEmails();

  // Restore the saved app language before the first frame to avoid a flash.
  final languageCode = await LocaleProvider.savedCode();

  runApp(SchoolApp(languageCode: languageCode));
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Guard against [core/duplicate-app] if Firebase is already initialized
  // (Issue 17: background isolate may share the same Firebase instance).
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
}

/// Navigator key for the root MaterialApp — lets non-widget code (e.g. the
/// idle-lock below) navigate without a BuildContext.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}

class SchoolApp extends StatefulWidget {
  final String languageCode;
  const SchoolApp({super.key, this.languageCode = 'en'});

  @override
  State<SchoolApp> createState() => _SchoolAppState();
}

class _SchoolAppState extends State<SchoolApp> with WidgetsBindingObserver {
  /// Auto sign-out after this much time spent in the background, so a shared
  /// staff device left unattended doesn't stay authenticated (#22). The cold-
  /// start 7-day check in _SplashGate complements this for fully-closed apps.
  static const _idleLockThreshold = Duration(minutes: 15);
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _backgroundedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      _maybeLock();
    }
  }

  Future<void> _maybeLock() async {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (since == null) return;
    if (DateTime.now().difference(since) < _idleLockThreshold) return;
    // Only force a re-login when there is actually a session to protect.
    final session = await AuthService().getSession();
    if (session == null) return;
    await AuthService().clearSession();
    rootNavigatorKey.currentState?.pushAndRemoveUntil(
      AppPageRoute(child: const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SchoolSettingsProvider()),
        ChangeNotifierProvider(create: (_) => LocaleProvider(widget.languageCode)),
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
        child: Consumer<LocaleProvider>(
          builder: (context, localeProvider, _) {
            final settings = Provider.of<SchoolSettingsProvider>(context);
            return MaterialApp(
              scrollBehavior: const AppScrollBehavior(),
              navigatorKey: rootNavigatorKey,
              debugShowCheckedModeBanner: false,
              navigatorObservers: [routeObserver],
              title: settings.schoolName == 'My School' ? 'Klassivo' : settings.schoolName,
              theme: AppTheme.light,
              locale: localeProvider.locale,
              supportedLocales: LocaleProvider.supported.keys.map(Locale.new),
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              builder: (context, child) {
                return ConnectivityBannerWrapper(
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(
                        MediaQuery.of(context).textScaler.scale(1.0).clamp(0.8, 1.2),
                      ),
                    ),
                    child: child!,
                  ),
                );
              },
              home: const _SplashGate(),
            );
          },
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
    var session = await AuthService().getSession();

    if (!mounted) return;

    if (session == null) {
      _go(const LoginScreen());
      return;
    }

    // 7-day inactivity session timeout check
    final prefs = await SharedPreferences.getInstance();
    final lastActivity = prefs.getInt('last_activity_timestamp');
    final now = DateTime.now().millisecondsSinceEpoch;
    if (lastActivity != null) {
      final diff = now - lastActivity;
      const sevenDaysMs = 7 * 24 * 60 * 60 * 1000;
      if (diff > sevenDaysMs) {
        await AuthService().clearSession();
        if (!mounted) return;
        _go(const LoginScreen());
        return;
      }
    }
    await prefs.setInt('last_activity_timestamp', now);

    final role = session['role'] as String? ?? '';

    // All roles (including guardians) now use Firebase Auth — verify the
    // session is still valid before routing. Guardians may have signed in via
    // email+password or phone OTP; both produce a Firebase Auth user.
    final firebaseUser = await FirebaseAuth.instance.authStateChanges().first;
    if (firebaseUser == null) {
      await AuthService().clearSession();
      if (!mounted) return;
      _go(const LoginScreen());
      return;
    }

    // Restore in-memory schoolId so services read from the correct school
    // on cold-start with a cached session. Without this, AuthService.currentSchoolId
    // would throw a StateError on access.
    final schoolId = session['schoolId'] as String?;
    if (schoolId != null && schoolId.isNotEmpty) {
      BaseFirestoreService.currentSchoolId = schoolId;
      BirthdayService().migrateLegacyBirthdays();
    }

    // IDENTITY GUARD — the cached session and the live Firebase Auth user must
    // be the SAME account. Firestore rules derive identity from the Auth token
    // email (`request.auth.token.email`), NOT from the cached session. If a
    // previous/different account is still the signed-in Firebase Auth user while
    // the session says "owner", the app routes to the owner dashboard but every
    // read/write is denied (the app thinks you're the owner; the server doesn't).
    // Force re-login on any mismatch so the two can't diverge.
    //
    // Applies to EVERY role, guardians included: phone-OTP login was removed
    // (L1), so all sessions — guardian or staff — are email-keyed. (The old
    // guardian phone-number branch here was dead code that also FAILED OPEN on
    // any query error and ran an unscoped cross-tenant allowed_users query —
    // SCALE-11 audit.)
    {
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

    // Re-validate the session against the authoritative allowed_users doc on
    // EVERY resume, for EVERY role (previously only management). SplashGate
    // otherwise routes purely from the cached SharedPreferences session — so a
    // user who was since suspended, disabled, or had their role changed would
    // keep full access until they happened to log out or 7 days elapsed.
    // Suspending or firing a teacher mid-term now takes effect on next app open
    // (review #8, #9). Reconcile against the live doc:
    //   • doc absent OR role changed OR status suspended/disabled
    //                                  → clear the stale session, force re-login
    //   • read threw (offline/transient) → keep cached routing (don't lock out)
    //   • role matches & status active  → proceed
    final email = session['email'] as String?;
    if (email != null && email.isNotEmpty) {
      bool readFailed = false;
      Map<String, dynamic>? live;
      try {
        live = await TimetableService.instance.getAllowedUserDoc(email);
      } on FirebaseException catch (e) {
        // permission-denied means the server explicitly rejected this session
        // (e.g. user was suspended/deleted). Do NOT fall through — force re-login.
        // (Issue 6: previously ALL exceptions fell through to cached routing,
        // which kept suspended users active if they could trigger a rules error.)
        if (e.code == 'permission-denied') {
          await AuthService().clearSession();
          if (!mounted) return;
          _go(const LoginScreen());
          return;
        }
        // Other FirebaseExceptions (network, quota) = transient — keep cached routing.
        readFailed = true;
      } catch (_) {
        // Non-Firebase exceptions (SocketException, TimeoutException, etc.) are
        // network-class errors — keep cached routing for offline tolerance.
        readFailed = true;
      }
      if (!mounted) return;
      if (!readFailed && live != null) {
        final liveRole   = (live['role']   as String?) ?? '';
        final liveStatus = (live['status'] as String?) ?? '';
        final liveSchoolId = (live['schoolId'] as String?) ?? '';
        
        bool schoolSuspended = false;
        if (liveSchoolId.isNotEmpty && liveRole != 'admin') {
          try {
            final schoolDoc = await FirebaseFirestore.instance.collection('schools').doc(liveSchoolId).get();
            if (schoolDoc.exists && schoolDoc.data()?['isActive'] == false) {
              schoolSuspended = true;
            }
          } catch (_) {
            // Keep cached routing if Firestore check fails (offline tolerance)
          }
        }

        final revoked = liveRole != role
            || liveStatus == 'suspended'
            || liveStatus == 'disabled'
            || schoolSuspended;
        if (revoked) {
          await AuthService().clearSession();
          if (!mounted) return;
          _go(const LoginScreen());
          return;
        }

        // Auto-refresh the guardian session metadata on app launch so that
        // class promotions, section assignments, or teacher corrections apply immediately
        // without requiring a manual logout/login.
        if (role == 'guardian') {
          final links = await TimetableService.instance.getGuardianLinks(email);
          if (links != null && links.isNotEmpty) {
            final sessionLinks = links
                .map((l) =>
                    '${l['studentClass']}|${l['studentRoll']}|${l['studentName'] ?? ''}|${l['studentSection'] ?? ''}')
                .toList();
            final firstLink = links.first;
            final firstClass   = firstLink['studentClass'] as String?;
            final firstRoll    = (firstLink['studentRoll'] as num?)?.toInt();
            final firstSection = firstLink['studentSection'] as String? ?? '';

            await AuthService().saveSession(
              email:        email,
              role:         'guardian',
              name:         live['name'] as String? ?? email.split('@').first,
              schoolId:     live['schoolId'] as String? ?? '',
              studentClass:   firstClass,
              studentRoll:    firstRoll,
              studentSection: firstSection,
              studentLinks: sessionLinks,
              studentAdmissionId: live['studentAdmissionId'] as String?,
            );
            session = (await AuthService().getSession()) ?? session;
          }
        }
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
              await TimetableService.instance.getTeacherById(id: teacherId);
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
        context, AppPageRoute(child: screen));
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SchoolSettingsProvider>(context);
    final logo = settings.schoolLogo;
    final name = settings.schoolName == 'My School' ? 'Klassivo' : settings.schoolName;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          color: AppTheme.primaryDark,
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (logo.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(
                    logo,
                    height: 80,
                    width: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                      Image.asset(
                        'assets/images/logo_orange_white.png',
                        height: 72,
                        width: 72,
                        filterQuality: FilterQuality.high,
                      ),
                  ),
                )
              else
                Image.asset(
                  'assets/images/logo_orange_white.png',
                  height: 72,
                  width: 72,
                  filterQuality: FilterQuality.high,
                ),
              const SizedBox(height: 20),
              Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 24),
              const CircularProgressIndicator(color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class ConnectivityBannerWrapper extends StatefulWidget {
  final Widget child;
  const ConnectivityBannerWrapper({super.key, required this.child});

  @override
  State<ConnectivityBannerWrapper> createState() => _ConnectivityBannerWrapperState();
}

class _ConnectivityBannerWrapperState extends State<ConnectivityBannerWrapper> {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription? _subscription;
  bool _isOnline = true;
  bool _showOnlineIndicator = false;

  @override
  void initState() {
    super.initState();
    _checkInitialConnectivity();
    _subscription = _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
  }

  Future<void> _checkInitialConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _updateConnectionStatus(results);
    } catch (_) {}
  }

  void _updateConnectionStatus(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    if (online != _isOnline) {
      setState(() {
        _isOnline = online;
        if (online) {
          _showOnlineIndicator = true;
        } else {
          _showOnlineIndicator = false;
        }
      });
      if (online) {
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _showOnlineIndicator = false;
            });
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Column(
        children: [
          Expanded(child: widget.child),
          if (!_isOnline)
            Material(
              color: AppTheme.danger,
              child: SafeArea(
                top: false,
                bottom: true,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                  alignment: Alignment.center,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.wifi_off_outlined, color: Colors.white, size: 14),
                      SizedBox(width: 8),
                      Text(
                        'You are offline. Changes will sync when you reconnect.',
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_showOnlineIndicator)
            Material(
              color: AppTheme.success,
              child: SafeArea(
                top: false,
                bottom: true,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                  alignment: Alignment.center,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.wifi_outlined, color: Colors.white, size: 14),
                      SizedBox(width: 8),
                      Text(
                        'Back online!',
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

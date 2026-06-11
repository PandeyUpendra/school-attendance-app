import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../models/teacher.dart';
import '../services/auth_service.dart';
import '../services/timetable_service.dart';
import '../services/base_firestore_service.dart';
import '../utils/validators.dart';
import '../l10n/app_strings.dart';
import '../widgets/email_text_form_field.dart';
import 'coordinator_dashboard.dart';
import 'home_screen.dart';
import 'principal_dashboard.dart';
import 'guardian_login_screen.dart';
import 'admin_screen.dart';
import 'admin_login_screen.dart';
import 'forgot_password_screen.dart';
import 'role_selection_screen.dart';
import 'owner/owner_home.dart';
import 'owner/owner_principal_home.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool _loading    = false;
  bool _showPass   = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final email    = _emailCtrl.text.trim().toLowerCase();
    final password = _passCtrl.text;

    if (!Validators.isValidEmail(email)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = 'Enter your password.');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      // Firebase Auth sign-in.
      await AuthService().signInWithEmail(email, password);

      if (!mounted) return;

      // Fetch role + extra data from allowed_users.
      final userData = await TimetableService.instance.getAllowedUserDoc(email);
      if (!mounted) return;

      if (userData == null) {
        await AuthService().signOut();
        setState(() {
          _loading = false;
          _error = 'Your account is not registered in this school system. '
              'Contact your administrator.';
        });
        return;
      }

      final role      = userData['role']     as String? ?? '';
      final name      = userData['name']     as String? ?? '';
      final schoolId  = userData['schoolId'] as String? ?? '';
      final status    = userData['status']   as String? ?? 'active';
      final teacherId = userData['teacherId'] as String?;

      // Block both suspended AND disabled here. Previously only 'suspended' was
      // checked, so a 'disabled' account could still sign in fresh and was only
      // ejected on the next cold start by the splash gate — inconsistent.
      if (status == 'suspended' || status == 'disabled') {
        await AuthService().signOut();
        setState(() {
          _loading = false;
          _error = status == 'disabled'
              ? 'This account has been disabled. Contact your administrator.'
              : 'Your account has been suspended. Contact your administrator.';
        });
        return;
      }

      // Mark account active on first successful login.
      if (status == 'pending') {
        TimetableService.instance.markUserActive(email);
      }

      if (schoolId.isNotEmpty) {
        BaseFirestoreService.currentSchoolId = schoolId;
      }

      // Role-specific data.
      List<String>? assignedClasses;
      if (role == 'coordinator' || role == 'principal' || role == 'owner') {
        final loginData = await TimetableService.instance.getAssignedClasses(email);
        assignedClasses = loginData.assignedClasses;
      }

      await AuthService().saveSession(
        email:          email,
        role:           role,
        name:           name,
        schoolId:       schoolId,
        assignedClasses: assignedClasses,
        // Stamp teacherId from allowed_users now, so the teacher route doesn't
        // have to re-save the session (which dropped assignedClasses) — #149.
        teacherId:      teacherId,
      );

      if (!mounted) return;
      await _routeToDashboard(role, email, teacherId);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error   = AuthService.friendlyAuthError(e);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // Don't assume connectivity — this branch also catches config/
        // permission errors, where "check your internet" is misleading (#89).
        _error   = 'Login failed. Please try again. If this keeps happening, '
            'contact your administrator.';
      });
    }
  }

  Future<void> _routeToDashboard(String role, String email, [String? teacherId]) async {
    Widget destination;
    switch (role) {
      case 'admin':
        // Admin status is verified by fetching system/root_config from Firestore.
        // This read will fail with permission-denied for non-admins.
        try {
          final adminEmails = await AuthService().fetchAndCacheAdminEmails();
          if (!adminEmails.contains(email)) {
            throw Exception('User is not in the system root admins list.');
          }
        } catch (_) {
          await AuthService().signOut();
          setState(() {
            _loading = false;
            _error   = 'This account is not permitted admin access.';
          });
          return;
        }
        destination = const AdminScreen();
        break;
      case 'coordinator':
        destination = const CoordinatorDashboard();
        break;
      case 'principal':
        destination = const PrincipalDashboard();
        break;
      case 'owner':
        destination = const OwnerHome();
        break;
      case 'ownerPrincipal':
        destination = const OwnerPrincipalHome();
        break;
      case 'teacher':
      case 'subjectTeacher':
        // Teacher needs to load their full profile — use splash gate routing.
        _loadTeacherAndRoute(email, teacherId);
        return;
      default:
        setState(() {
          _loading = false;
          _error   = 'Unknown role "$role". Contact your administrator.';
        });
        return;
    }
    if (!mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => destination));
  }

  Future<void> _loadTeacherAndRoute(String email, [String? teacherId]) async {
    try {
      // Prefer a direct O(1) fetch by the teacherId stamped on allowed_users.
      // Fall back to an email scan only for legacy docs missing teacherId
      // (the old path always scanned every teacher — review #41). The session
      // was already saved with teacherId in _login(), so no re-save here (#149).
      Teacher? teacher;
      if (teacherId != null && teacherId.isNotEmpty) {
        teacher = await TimetableService.instance.getTeacherById(id: teacherId);
      }
      if (teacher == null) {
        final teachers = await TimetableService.instance.getTeachers();
        teacher = teachers.firstWhere(
          (t) => t.email.toLowerCase() == email,
          orElse: () => throw Exception('Teacher profile not found'),
        );
      }
      if (!mounted) return;
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => HomeScreen(teacher: teacher!)));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error   = 'Teacher profile not found. Ask your administrator to set up your profile.';
      });
    }
  }

  /// Admin access — opens the full-screen [AdminLoginScreen] (replaces the old
  /// in-line "Admin Access" dialog so the experience matches the other roles).
  void _openAdminLogin() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AdminLoginScreen()),
    );
  }

  // Hardware/gesture back from this root login screen returns to the role
  // selection hub instead of exiting the app.
  void _backToRoleSelection() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _backToRoleSelection();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppTheme.primaryDark,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: AppTheme.primaryDark,
        body: Container(
          decoration: const BoxDecoration(
            color: AppTheme.primaryDark,
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  // Header. Long-pressing the title opens admin login — the
                  // entry point is a hidden gesture rather than a visible link,
                  // so it isn't a discoverable attack surface (#93).
                  GestureDetector(
                    onLongPress: _openAdminLogin,
                    child: const Icon(Icons.school, size: 56, color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'School App',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.tr('signInSubtitle'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 15, color: Colors.white.withValues(alpha: 0.75)),
                  ),
                  const SizedBox(height: 40),

                  // Card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Email
                        EmailTextFormField(
                          controller: _emailCtrl,
                          // RFC 5321 caps an email address at 254 chars; 100
                          // silently truncated valid long addresses (#105)
                          // while still bounding length against absurd input (#147).
                          maxLength: 254,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: context.tr('emailAddress'),
                            prefixIcon: const Icon(Icons.email_outlined),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                            counterText: '',
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Password
                        TextField(
                          controller: _passCtrl,
                          obscureText: !_showPass,
                          maxLength: 100,
                          maxLengthEnforcement: MaxLengthEnforcement.enforced,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _loading ? null : _signIn(),
                          decoration: InputDecoration(
                            labelText: context.tr('password'),
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(
                                  _showPass
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  size: 18),
                              onPressed: () =>
                                  setState(() => _showPass = !_showPass),
                            ),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                            counterText: '',
                          ),
                        ),

                        // Forgot password
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const ForgotPasswordScreen()),
                            ),
                            child: Text(
                              context.tr('forgotPassword'),
                              style: const TextStyle(color: AppTheme.primary),
                            ),
                          ),
                        ),

                        // Error
                        if (_error != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border:
                                  Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline,
                                    color: Colors.red.shade600, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.red.shade700),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Sign In button
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _signIn,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                            child: _loading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white),
                                  )
                                : Text(
                                    context.tr('signIn'),
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Guardian login
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const GuardianLoginScreen()),
                    ),
                    icon: const Icon(Icons.family_restroom_outlined,
                        color: Colors.white70),
                    label: const Text(
                      'Guardian? Sign in here',
                      style: TextStyle(color: Colors.white70),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),

                  const SizedBox(height: 24),
                  // (Admin access moved to a long-press on the header icon — #93.)
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}

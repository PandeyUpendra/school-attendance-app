import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../services/auth_service.dart';
import '../services/timetable_service.dart';
import '../services/base_firestore_service.dart';
import '../utils/validators.dart';
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
      final userData = await TimetableService().getAllowedUserDoc(email);
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

      final role     = userData['role']     as String? ?? '';
      final name     = userData['name']     as String? ?? '';
      final schoolId = userData['schoolId'] as String? ?? '';
      final status   = userData['status']   as String? ?? 'active';

      if (status == 'suspended') {
        await AuthService().signOut();
        setState(() {
          _loading = false;
          _error = 'Your account has been suspended. Contact your administrator.';
        });
        return;
      }

      // Mark account active on first successful login.
      if (status == 'pending') {
        TimetableService().markUserActive(email);
      }

      if (schoolId.isNotEmpty) {
        BaseFirestoreService.currentSchoolId = schoolId;
      }

      // Role-specific data.
      List<String>? assignedClasses;
      if (role == 'coordinator' || role == 'principal' || role == 'owner') {
        final loginData = await TimetableService().getAssignedClasses(email);
        assignedClasses = loginData.assignedClasses;
      }

      await AuthService().saveSession(
        email:          email,
        role:           role,
        name:           name,
        schoolId:       schoolId,
        assignedClasses: assignedClasses,
      );

      if (!mounted) return;
      _routeToDashboard(role, email);
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
        _error   = 'Login failed. Check your internet connection and try again.';
      });
    }
  }

  void _routeToDashboard(String role, String email) {
    Widget destination;
    switch (role) {
      case 'admin':
        // Admin is hardcoded to a single email — no other account may ever
        // resolve to the admin panel, even if a stray allowed_users doc claims
        // the admin role. The admin signs in through the dedicated screen.
        if (!AuthService.isRootAdminEmail(email)) {
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
        _loadTeacherAndRoute(email);
        return;
      default:
        setState(() {
          _loading = false;
          _error   = 'Unknown role "$role". Contact your administrator.';
        });
        return;
    }
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => destination));
  }

  Future<void> _loadTeacherAndRoute(String email) async {
    try {
      final teachers = await TimetableService().getTeachers();
      final teacher = teachers.firstWhere(
        (t) => t.email.toLowerCase() == email,
        orElse: () => throw Exception('Teacher profile not found'),
      );
      if (!mounted) return;

      // Save teacherId to session for future restarts.
      final session = await AuthService().getSession();
      if (session != null) {
        await AuthService().saveSession(
          email:          session['email'] as String,
          role:           session['role']  as String,
          name:           session['name']  as String? ?? '',
          schoolId:       session['schoolId'] as String? ?? '',
          teacherId:      teacher.id,
        );
      }
      if (!mounted) return;
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => HomeScreen(teacher: teacher)));
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
                  // Header
                  const Icon(Icons.school, size: 56, color: Colors.white),
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
                    'Sign in to your account',
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
                        TextField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          // Email must not be auto-corrected/suggested: otherwise
                          // the IME holds the whole address as one composing
                          // region, showing it highlighted and making single
                          // characters impossible to edit/delete.
                          autocorrect: false,
                          enableSuggestions: false,
                          maxLength: 100,
                          maxLengthEnforcement: MaxLengthEnforcement.enforced,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: 'Email Address',
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
                            labelText: 'Password',
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
                            child: const Text(
                              'Forgot Password?',
                              style: TextStyle(color: AppTheme.primary),
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
                                : const Text(
                                    'Sign In',
                                    style: TextStyle(
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

                  // Admin access (small, unobtrusive)
                  Center(
                    child: TextButton(
                      onPressed: _openAdminLogin,
                      child: Text(
                        'Admin Access',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.45)),
                      ),
                    ),
                  ),
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

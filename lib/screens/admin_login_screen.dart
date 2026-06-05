import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../services/auth_service.dart';
import '../services/base_firestore_service.dart';
import '../utils/validators.dart';
import 'admin_screen.dart';

/// Full-screen admin login — replaces the old "Admin Access" dialog so the
/// experience matches the other roles (staff / guardian) instead of a
/// cramped, laggy `AlertDialog`.
///
/// Authenticates email + password via Firebase Auth, verifies the account
/// holds the `admin` role in `allowed_users`, persists a session so the
/// `RoleGuard` on [AdminScreen] passes, then opens the admin panel. An inline
/// "Forgot password?" link sends a Firebase reset email to the entered address.
class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool _loading  = false;
  bool _showPass = false;
  String? _error;
  String? _resetMsg;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    final pass  = _passCtrl.text;
    if (!Validators.isValidEmail(email)) {
      setState(() { _error = 'Enter a valid email address.'; _resetMsg = null; });
      return;
    }
    if (pass.isEmpty) {
      setState(() { _error = 'Enter your password.'; _resetMsg = null; });
      return;
    }

    // Admin identity is hardcoded to the single permanent system admin. Reject
    // every other address up-front — before even touching Firebase Auth — so no
    // other account can ever reach the admin panel.
    if (!AuthService.isRootAdminEmail(email)) {
      setState(() {
        _loading = false;
        _error = 'This is not the system admin account. Admin access is '
            'restricted to a single fixed email.';
        _resetMsg = null;
      });
      return;
    }

    setState(() { _loading = true; _error = null; _resetMsg = null; });
    try {
      // Firebase Auth sign-in. The hardcoded email above IS the authorization —
      // no allowed_users/role lookup is needed (and it would fail anyway when
      // the database is empty, which is exactly when the admin must bootstrap
      // the system). The security rules trust the same hardcoded email via
      // isRootAdmin(), so admin writes succeed without an identity document.
      await AuthService().signInWithEmail(email, pass);

      // Admin operates at the root level, not inside any one school.
      BaseFirestoreService.currentSchoolId = 'school_1';

      // Persist a session so RoleGuard on the admin screen passes, then open it.
      // (The splash gate deliberately does NOT auto-resume admin sessions, so
      // this never causes the app to launch straight into the admin panel.)
      await AuthService().saveSession(
        email:    email,
        role:     'admin',
        name:     'Admin',
        schoolId: '',
      );
      if (!mounted) return;
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const AdminScreen()));
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

  /// Sends a Firebase password-reset link to the entered admin email.
  /// For an alias like name+admin@gmail.com the email lands in the base
  /// name@gmail.com inbox.
  Future<void> _resetPassword() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    if (!Validators.isValidEmail(email)) {
      setState(() {
        _resetMsg = null;
        _error = 'Enter your admin email above first, then tap reset.';
      });
      return;
    }
    // Only the one fixed admin address may request an admin password reset.
    if (!AuthService.isRootAdminEmail(email)) {
      setState(() {
        _resetMsg = null;
        _error = 'Password reset is only available for the system admin account.';
      });
      return;
    }
    setState(() { _loading = true; _error = null; _resetMsg = null; });
    try {
      await AuthService().sendPasswordResetEmail(email);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _resetMsg = 'Reset link sent to $email. Check that inbox, set a '
            'new password, then sign in here.';
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = AuthService.friendlyAuthError(e); });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not send the reset email. Check your connection.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
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
                  // Back button
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: _loading ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      tooltip: 'Back',
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Header
                  const Icon(Icons.manage_accounts_outlined,
                      size: 56, color: Colors.white),
                  const SizedBox(height: 16),
                  const Text(
                    'Admin Access',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Manage registered users & login access',
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
                          enabled: !_loading,
                          keyboardType: TextInputType.emailAddress,
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
                          enabled: !_loading,
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
                            onPressed: _loading ? null : _resetPassword,
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
                              border: Border.all(color: Colors.red.shade200),
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

                        // Reset confirmation
                        if (_resetMsg != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.green.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.mark_email_read_outlined,
                                    color: Colors.green.shade600, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _resetMsg!,
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        color: Colors.green.shade700),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Login button
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
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text(
                                    'Login',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

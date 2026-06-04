import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/auth_service.dart';
import '../services/timetable_service.dart';
import '../services/base_firestore_service.dart';
import 'guardian_dashboard.dart';
import 'student_selection_screen.dart';
import 'forgot_password_screen.dart';
import 'login_screen.dart';

class GuardianLoginScreen extends StatefulWidget {
  const GuardianLoginScreen({super.key});

  @override
  State<GuardianLoginScreen> createState() => _GuardianLoginScreenState();
}

class _GuardianLoginScreenState extends State<GuardianLoginScreen> {
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

    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = 'Enter your password.');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      await AuthService().signInWithEmail(email, password);
      if (!mounted) return;

      final userData = await TimetableService().getAllowedUserDoc(email);
      if (!mounted) return;

      if (userData == null || userData['role'] != 'guardian') {
        await AuthService().signOut();
        setState(() {
          _loading = false;
          _error   = 'This email is not registered as a guardian account. '
              'Ask your child\'s teacher to add your email in student details.';
        });
        return;
      }

      final links = await TimetableService().getGuardianLinks(email);
      if (!mounted) return;

      if (links == null || links.isEmpty) {
        await AuthService().signOut();
        setState(() {
          _loading = false;
          _error   = 'No student is linked to this email. '
              'Ask your child\'s teacher to set up guardian access.';
        });
        return;
      }

      final name     = userData['name']     as String? ?? email.split('@').first;
      final schoolId = userData['schoolId'] as String? ?? '';
      if (schoolId.isNotEmpty) {
        BaseFirestoreService.currentSchoolId = schoolId;
      }

      final sessionLinks = links
          .map((l) =>
              '${l['studentClass']}|${l['studentRoll']}|${l['studentName'] ?? ''}')
          .toList();

      await AuthService().saveSession(
        email:        email,
        role:         'guardian',
        name:         name,
        schoolId:     schoolId,
        studentLinks: sessionLinks,
      );

      if (!mounted) return;

      if (sessionLinks.length == 1) {
        final parts = sessionLinks.first.split('|');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => GuardianDashboard(
              studentClass: parts[0],
              studentRoll:  int.parse(parts[1]),
            ),
          ),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                StudentSelectionScreen(schoolId: schoolId, links: sessionLinks),
          ),
        );
      }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primaryMid,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end:   Alignment.bottomCenter,
            colors: [AppTheme.primaryDark, AppTheme.primaryMid],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),

                // Header
                const Icon(Icons.family_restroom_outlined,
                    size: 56, color: Colors.white),
                const SizedBox(height: 16),
                const Text(
                  'Guardian Portal',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Sign in to view your child\'s progress',
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
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Email Address',
                          prefixIcon: const Icon(Icons.email_outlined),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Password
                      TextField(
                        controller: _passCtrl,
                        obscureText: !_showPass,
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
                        ),
                      ),

                      // Forgot password
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const ForgotPasswordScreen()),
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
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(children: [
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
                          ]),
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
                                      strokeWidth: 2, color: Colors.white),
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

                // Back to staff login
                OutlinedButton.icon(
                  onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  ),
                  icon: const Icon(Icons.work_outline, color: Colors.white70),
                  label: const Text(
                    'Staff? Sign in here',
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
                Center(
                  child: Text(
                    'Your email must be registered by your\nchild\'s teacher before you can sign in.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.45),
                        height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

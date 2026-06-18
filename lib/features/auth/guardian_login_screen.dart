import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme.dart';
import '../../l10n/app_strings.dart';
import '../../services/auth_service.dart';
import '../../services/timetable_service.dart';
import '../../services/base_firestore_service.dart';
import '../../shared/utils/validators.dart';
import '../../shared/widgets/email_text_form_field.dart';
import '../dashboards/guardian_dashboard.dart';
import './forgot_password_screen.dart';
import './role_selection_screen.dart';
import './login_screen.dart';
import './guardian_register_screen.dart';
import '../../shared/utils/app_transitions.dart';

class GuardianLoginScreen extends StatefulWidget {
  const GuardianLoginScreen({super.key});

  @override
  State<GuardianLoginScreen> createState() => _GuardianLoginScreenState();
}

class _GuardianLoginScreenState extends State<GuardianLoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _passFocusNode  = FocusNode();
  bool _loading    = false;
  bool _showPass   = false;
  String? _error;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _emailFocusNode.dispose();
    _passFocusNode.dispose();
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
      await AuthService().signInWithEmail(email, password);
      TextInput.finishAutofillContext();
      if (!mounted) return;

      final userData = await TimetableService.instance.getAllowedUserDoc(email);
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

      final links = await TimetableService.instance.getGuardianLinks(email);
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
              '${l['studentClass']}|${l['studentRoll']}|${l['studentName'] ?? ''}|${l['studentSection'] ?? ''}')
          .toList();

      // Extract first child's class/roll/section for session persistence so
      // auto-login (main.dart) can reconstruct the GuardianDashboard.
      final firstLink = links.first;
      final firstClass   = firstLink['studentClass'] as String?;
      final firstRoll    = (firstLink['studentRoll'] as num?)?.toInt();
      final firstSection = firstLink['studentSection'] as String? ?? '';

      await AuthService().saveSession(
        email:        email,
        role:         'guardian',
        name:         name,
        schoolId:     schoolId,
        studentClass:   firstClass,
        studentRoll:    firstRoll,
        studentSection: firstSection,
        studentLinks: sessionLinks,
        // Provisioned stable id (#39) for the safe guardian_adm subscription.
        studentAdmissionId: userData['studentAdmissionId'] as String?,
      );

      if (!mounted) return;

      final parts = sessionLinks.first.split('|');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => GuardianDashboard(
            studentClass: parts[0],
            studentRoll:  int.tryParse(parts[1]) ?? 0,
            studentSection: parts.length > 3 ? parts[3] : '',
          ),
        ),
      );
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
        // Don't assume connectivity — also catches config/permission errors (#89).
        _error   = 'Login failed. Please try again. If this keeps happening, '
            'contact your child\'s teacher.';
      });
    }
  }

  // Back from this root guardian-login screen returns to the role selection
  // hub instead of exiting the app.
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
      child: Scaffold(
      backgroundColor: AppTheme.primaryDark,
      body: Container(
        decoration: const BoxDecoration(
          color: AppTheme.primaryDark,
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 48, // Subtract padding top + bottom
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Spacer(flex: 3), // Push everything down on tall screens
                        
                        FadeInUp(
                          delay: Duration.zero,
                          child: Column(
                            children: [
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
                                context.tr('guardianSignInSubtitle'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 15, color: Colors.white.withValues(alpha: 0.75)),
                              ),
                            ],
                          ),
                        ),
                        
                        const Spacer(flex: 2), // Extra space between header and card

                        // Card
                        FadeInUp(
                          delay: const Duration(milliseconds: 150),
                          child: Container(
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
                            child: AutofillGroup(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Email
                                  EmailTextFormField(
                                    controller: _emailCtrl,
                                    focusNode: _emailFocusNode,
                                    nextFocusNode: _passFocusNode,
                                    textInputAction: TextInputAction.next,
                                    decoration: InputDecoration(
                                      labelText: context.tr('emailAddress'),
                                      prefixIcon: const Icon(Icons.email_outlined),
                                      border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                  const SizedBox(height: 16),

                                  // Password
                                  TextField(
                                    controller: _passCtrl,
                                    focusNode: _passFocusNode,
                                    obscureText: !_showPass,
                                    textInputAction: TextInputAction.done,
                                    onSubmitted: (_) => _loading ? null : _signIn(),
                                    autofillHints: const [AutofillHints.password],
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
                                    ),
                                  ),

                                  // Forgot password
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) => ForgotPasswordScreen(
                                                initialEmail: _emailCtrl.text.trim(),
                                            )),
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
                                  Row(
                                    children: [
                                      Expanded(
                                        child: SizedBox(
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
                                                : Text(
                                                    context.tr('signIn'),
                                                    style: const TextStyle(
                                                        fontSize: 16,
                                                        fontWeight: FontWeight.w600),
                                                  ),
                                          ),
                                        ),
                                      ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                        const SizedBox(height: 16),
                        Center(
                          child: TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const GuardianRegisterScreen()),
                              );
                            },
                            child: const Text(
                              'Have an Invite Code? Register here',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

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
                        
                        const Spacer(flex: 1), // Padding at bottom
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}
}

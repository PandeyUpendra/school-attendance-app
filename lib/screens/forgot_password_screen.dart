import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';
import '../services/auth_service.dart';
import '../utils/validators.dart';
import 'role_selection_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with WidgetsBindingObserver {
  final _emailCtrl = TextEditingController();
  bool   _loading     = false;
  bool   _sent        = false;
  bool   _gmailOpened = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When user returns from Gmail after opening it, go straight to sign-in.
    if (state == AppLifecycleState.resumed && _gmailOpened && mounted) {
      _gmailOpened = false;
      _goToSignIn();
    }
  }

  void _goToSignIn() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
      (_) => false,
    );
  }

  Future<void> _openGmail() async {
    // Try the Gmail app deep-link first; fall back to the web Gmail URL.
    final gmailApp = Uri.parse('googlegmail://');
    final gmailWeb = Uri.parse('https://mail.google.com/');

    setState(() => _gmailOpened = true);

    if (await canLaunchUrl(gmailApp)) {
      await launchUrl(gmailApp, mode: LaunchMode.externalApplication);
    } else {
      await launchUrl(gmailWeb, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _sendReset() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    if (!Validators.isValidEmail(email)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      final result = await AuthService().sendResetIfRegistered(email);
      if (!mounted) return;
      switch (result) {
        case ResetResult.notRegistered:
          setState(() {
            _loading = false;
            _error =
                'This email is not registered. Check the address, or contact '
                'your school administrator.';
          });
        case ResetResult.sent:
        case ResetResult.unknown:
          // unknown = reset function not deployed; a best-effort email was sent.
          setState(() { _loading = false; _sent = true; });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error   = 'Could not send reset email. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Reset Password'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),

              // Icon
              Container(
                alignment: Alignment.center,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_reset_outlined,
                      size: 36, color: AppTheme.primary),
                ),
              ),
              const SizedBox(height: 24),

              Text(
                _sent ? 'Check Your Email' : 'Forgot Your Password?',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryDark,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _sent
                    ? 'We\'ve sent a password reset link to your email. '
                        'Check your inbox (and spam folder).'
                    : 'Enter the email address registered with your school account '
                        'and we\'ll send you a secure link to reset your password.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.5),
              ),
              const SizedBox(height: 32),

              if (!_sent) ...[
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _loading ? null : _sendReset(),
                  decoration: InputDecoration(
                    labelText: 'Email Address',
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),

                if (_error != null)
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
                        child: Text(_error!,
                            style: TextStyle(
                                fontSize: 13, color: Colors.red.shade700)),
                      ),
                    ]),
                  ),

                const SizedBox(height: 20),

                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _sendReset,
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
                            'Send Reset Link',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
              ] else ...[
                // Success state
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Column(children: [
                    Icon(Icons.mark_email_read_outlined,
                        size: 40, color: Colors.green.shade600),
                    const SizedBox(height: 12),
                    Text(
                      'Reset link sent to\n${_emailCtrl.text.trim()}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 14,
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w600),
                    ),
                  ]),
                ),
                const SizedBox(height: 20),

                // Open Gmail button
                SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _openGmail,
                    icon: const Icon(Icons.mail_outline_rounded, size: 20),
                    label: const Text(
                      'Open Gmail',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEA4335), // Gmail red
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Done — go straight to sign-in
                SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    onPressed: _goToSignIn,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side: const BorderSide(color: AppTheme.primary),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      'I\'ve Reset My Password — Sign In',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                TextButton(
                  onPressed: () => setState(() {
                    _sent        = false;
                    _gmailOpened = false;
                    _error       = null;
                    _emailCtrl.clear();
                  }),
                  child: const Text('Try a different email'),
                ),
              ],

              const SizedBox(height: 24),
              Center(
                child: TextButton(
                  onPressed: _goToSignIn,
                  child: const Text('Back to Sign In',
                      style: TextStyle(color: AppTheme.primary)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

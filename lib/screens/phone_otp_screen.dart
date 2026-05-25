import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../services/auth_service.dart';
import '../services/timetable_service.dart';
import '../services/base_firestore_service.dart';
import 'guardian_dashboard.dart';
import 'student_selection_screen.dart';

/// Phone OTP login screen — used as an alternative sign-in method,
/// especially for guardians who may not remember their email password.
///
/// Flow:
///   1. User enters phone number (E.164 format, e.g. +919876543210)
///   2. Firebase Auth sends an SMS with a 6-digit OTP
///   3. User enters OTP → credential created → signInWithCredential
///   4. Profile looked up from [allowed_users] by phone number
///   5. Session saved → routed to the appropriate dashboard
class PhoneOtpScreen extends StatefulWidget {
  const PhoneOtpScreen({super.key});

  @override
  State<PhoneOtpScreen> createState() => _PhoneOtpScreenState();
}

class _PhoneOtpScreenState extends State<PhoneOtpScreen> {
  // ── Step control ───────────────────────────────────────────────────────────
  bool _inOtpStep = false;

  // ── Controllers ────────────────────────────────────────────────────────────
  final _phoneCtrl = TextEditingController();
  final _otpCtrl   = TextEditingController();

  // ── State ──────────────────────────────────────────────────────────────────
  bool    _loading        = false;
  String? _error;
  String? _verificationId;
  int?    _resendToken;
  int     _resendCountdown = 0;
  Timer?  _resendTimer;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Normalises the entered number to E.164 (+CC…).
  /// Assumes India (+91) if no country code is given.
  String _normalisePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.startsWith('+')) return digits;
    if (digits.startsWith('0')) return '+91${digits.substring(1)}';
    if (digits.length == 10) return '+91$digits';
    return '+$digits';
  }

  void _startResendCountdown() {
    _resendCountdown = 60;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _resendCountdown--;
        if (_resendCountdown <= 0) t.cancel();
      });
    });
  }

  // ── Step 1: send OTP ───────────────────────────────────────────────────────

  Future<void> _sendOtp({bool resend = false}) async {
    final phone = _normalisePhone(_phoneCtrl.text);
    if (phone.length < 10) {
      setState(() => _error = 'Enter a valid phone number.');
      return;
    }

    setState(() { _loading = true; _error = null; });

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phone,
      forceResendingToken: resend ? _resendToken : null,
      timeout: const Duration(seconds: 60),

      // Android auto-retrieval / instant verification
      verificationCompleted: (PhoneAuthCredential credential) async {
        await _verifyCredential(credential);
      },

      verificationFailed: (FirebaseAuthException e) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error   = _friendlyPhoneError(e);
        });
      },

      codeSent: (String verificationId, int? resendToken) {
        if (!mounted) return;
        _verificationId = verificationId;
        _resendToken    = resendToken;
        _startResendCountdown();
        setState(() {
          _loading   = false;
          _inOtpStep = true;
        });
      },

      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
    );
  }

  // ── Step 2: verify OTP ─────────────────────────────────────────────────────

  Future<void> _verifyOtp() async {
    final code = _otpCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    if (_verificationId == null) {
      setState(() => _error = 'Session expired. Please request a new code.');
      return;
    }

    final credential = PhoneAuthProvider.credential(
      verificationId: _verificationId!,
      smsCode: code,
    );
    await _verifyCredential(credential);
  }

  Future<void> _verifyCredential(PhoneAuthCredential credential) async {
    setState(() { _loading = true; _error = null; });

    try {
      final userCred = await FirebaseAuth.instance
          .signInWithCredential(credential);
      final user = userCred.user;
      if (user == null) throw Exception('Authentication failed.');

      if (!mounted) return;

      // Look up the allowed_users profile by phone number.
      final phone = user.phoneNumber ?? _normalisePhone(_phoneCtrl.text);
      final userData = await TimetableService().getGuardianByPhone(phone);

      if (!mounted) return;

      if (userData == null) {
        // Phone not registered — sign out and show error.
        await AuthService().signOut();
        setState(() {
          _loading = false;
          _error   = 'Your phone number is not registered in this school '
              'system. Please use email/password login, or ask the school '
              'to register your phone number.';
        });
        return;
      }

      final email    = userData['email']    as String? ?? '';
      final role     = userData['role']     as String? ?? 'guardian';
      final name     = userData['name']     as String? ?? email.split('@').first;
      final schoolId = userData['schoolId'] as String? ?? '';

      if (schoolId.isNotEmpty) {
        BaseFirestoreService.currentSchoolId = schoolId;
      }

      // Fetch student links.
      final links = await TimetableService().getGuardianLinks(email);
      if (!mounted) return;

      if (links == null || links.isEmpty) {
        await AuthService().signOut();
        setState(() {
          _loading = false;
          _error   = 'No student is linked to this account. '
              'Ask the school to set up guardian access.';
        });
        return;
      }

      final sessionLinks = links
          .map((l) =>
              '${l['studentClass']}|${l['studentRoll']}|${l['studentName'] ?? ''}')
          .toList();

      await AuthService().saveSession(
        email:        email,
        role:         role,
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
        _error   = _friendlyOtpError(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error   = 'Verification failed. Please try again.';
      });
    }
  }

  // ── Error helpers ──────────────────────────────────────────────────────────

  String _friendlyPhoneError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-phone-number':
        return 'Invalid phone number format. Include your country code (e.g. +91…).';
      case 'too-many-requests':
        return 'Too many requests. Please wait a moment and try again.';
      case 'network-request-failed':
        return 'No internet connection. Check your network.';
      default:
        return e.message ?? 'Could not send OTP. Please try again.';
    }
  }

  String _friendlyOtpError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-verification-code':
        return 'Incorrect code. Check the SMS and try again.';
      case 'session-expired':
        return 'Code expired. Tap "Resend" to get a new one.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait and try again.';
      default:
        return e.message ?? 'Verification failed. Please try again.';
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primaryMid,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Sign In with Phone'),
        leading: BackButton(
          onPressed: () {
            if (_inOtpStep) {
              setState(() {
                _inOtpStep = false;
                _otpCtrl.clear();
                _error = null;
              });
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
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
            child: _inOtpStep ? _buildOtpStep() : _buildPhoneStep(),
          ),
        ),
      ),
    );
  }

  // ── Phone step ─────────────────────────────────────────────────────────────
  Widget _buildPhoneStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        const Icon(Icons.phone_android_outlined, size: 56, color: Colors.white),
        const SizedBox(height: 16),
        const Text(
          'Phone Verification',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(
          'We\'ll send a one-time code to your number.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.7)),
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
                  offset: const Offset(0, 8)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                maxLength: 15,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                onSubmitted: (_) => _loading ? null : _sendOtp(),
                decoration: InputDecoration(
                  labelText: 'Phone Number',
                  hintText: '+91 98765 43210',
                  prefixIcon: const Icon(Icons.phone_outlined),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Include country code, e.g. +91 for India.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                _ErrorBox(_error!),
              ],

              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _sendOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Send OTP',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── OTP step ───────────────────────────────────────────────────────────────
  Widget _buildOtpStep() {
    final phone = _normalisePhone(_phoneCtrl.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        const Icon(Icons.sms_outlined, size: 56, color: Colors.white),
        const SizedBox(height: 16),
        const Text(
          'Enter OTP',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(
          'Code sent to $phone',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.7)),
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
                  offset: const Offset(0, 8)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _otpCtrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _loading ? null : _verifyOtp(),
                style: const TextStyle(
                    fontSize: 24,
                    letterSpacing: 8,
                    fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: '6-digit code',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  counterText: '',
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                _ErrorBox(_error!),
              ],

              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _verifyOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Verify',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),

              const SizedBox(height: 16),
              Center(
                child: _resendCountdown > 0
                    ? Text(
                        'Resend OTP in ${_resendCountdown}s',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade500),
                      )
                    : TextButton(
                        onPressed: () => _sendOtp(resend: true),
                        child: const Text('Resend OTP',
                            style: TextStyle(color: AppTheme.primary)),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(children: [
        Icon(Icons.error_outline, color: Colors.red.shade600, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message,
              style: TextStyle(fontSize: 13, color: Colors.red.shade700)),
        ),
      ]),
    );
  }
}

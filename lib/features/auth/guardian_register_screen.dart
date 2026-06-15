import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme.dart';
import '../../l10n/app_strings.dart';
import '../../services/auth_service.dart';
import '../../services/timetable_service.dart';
import '../../services/base_firestore_service.dart';
import '../../shared/utils/validators.dart';
import '../../shared/utils/app_functions.dart';
import '../../shared/widgets/email_text_form_field.dart';
import '../dashboards/guardian_dashboard.dart';
import '../../shared/utils/app_transitions.dart';

class GuardianRegisterScreen extends StatefulWidget {
  const GuardianRegisterScreen({super.key});

  @override
  State<GuardianRegisterScreen> createState() => _GuardianRegisterScreenState();
}

class _GuardianRegisterScreenState extends State<GuardianRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _inviteCtrl = TextEditingController();

  bool _loading = false;
  bool _showPass = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _inviteCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim().toLowerCase();
    final password = _passCtrl.text;
    final inviteCode = _inviteCtrl.text.trim().toUpperCase();

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 1. Call registration Cloud Function to register and link student
      final result = await appFunctions.httpsCallable('registerGuardianWithInviteCode').call(<String, dynamic>{
        'email': email,
        'password': password,
        'name': name,
        'inviteCode': inviteCode,
      });

      final schoolId = (result.data as Map)['schoolId'] as String;

      // 2. Perform local login since account was created on server
      await AuthService().signInWithEmail(email, password);

      // 3. Fetch linked students
      final links = await TimetableService.instance.getGuardianLinks(email);
      if (links == null || links.isEmpty) {
        throw Exception('Failed to link guardian account. Please contact the school.');
      }

      // 4. Save session and navigate
      BaseFirestoreService.currentSchoolId = schoolId;

      final sessionLinks = links
          .map((l) =>
              '${l['studentClass']}|${l['studentRoll']}|${l['studentName'] ?? ''}|${l['studentSection'] ?? ''}')
          .toList();

      final firstLink = links.first;
      final firstClass = firstLink['studentClass'] as String?;
      final firstRoll = (firstLink['studentRoll'] as num?)?.toInt();
      final firstSection = firstLink['studentSection'] as String? ?? '';

      await AuthService().saveSession(
        email: email,
        role: 'guardian',
        name: name,
        schoolId: schoolId,
        studentClass: firstClass,
        studentRoll: firstRoll,
        studentSection: firstSection,
        studentLinks: sessionLinks,
      );

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => GuardianDashboard(
            studentClass: firstClass ?? '',
            studentRoll: firstRoll ?? 0,
            studentSection: firstSection,
          ),
        ),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceAll('Exception: ', '').replaceAll('FirebaseException: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primaryDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title
                  const Icon(Icons.family_restroom, size: 54, color: Colors.white),
                  const SizedBox(height: 16),
                  const Text(
                    'Guardian Registration',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your child\'s invite code to register',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Card containing inputs
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 8,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_error != null) ...[
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.danger.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppTheme.danger.withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                _error!,
                                style: const TextStyle(color: AppTheme.danger, fontSize: 13),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Invite Code Input
                          TextFormField(
                            controller: _inviteCtrl,
                            textCapitalization: TextCapitalization.characters,
                            decoration: InputDecoration(
                              labelText: 'Parent Invite Code',
                              hintText: 'e.g. INV-A1B2C3',
                              prefixIcon: const Icon(Icons.vpn_key_outlined),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Please enter the invite code';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // Full Name
                          TextFormField(
                            controller: _nameCtrl,
                            keyboardType: TextInputType.name,
                            decoration: InputDecoration(
                              labelText: 'Your Full Name',
                              prefixIcon: const Icon(Icons.person_outline),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Please enter your name';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // Email
                          EmailTextFormField(
                            controller: _emailCtrl,
                            decoration: InputDecoration(
                              labelText: 'Email Address',
                              prefixIcon: const Icon(Icons.email_outlined),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Password
                          TextFormField(
                            controller: _passCtrl,
                            obscureText: !_showPass,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(_showPass ? Icons.visibility : Icons.visibility_off),
                                onPressed: () => setState(() => _showPass = !_showPass),
                              ),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            validator: (val) {
                              if (val == null || val.isEmpty) {
                                return 'Please enter password';
                              }
                              if (val.length < 6) {
                                return 'Password must be at least 6 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 24),

                          // Submit Button
                          SizedBox(
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _loading ? null : _register,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: _loading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Text(
                                      'Register & Link Child',
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                            ),
                          ),
                        ],
                      ),
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

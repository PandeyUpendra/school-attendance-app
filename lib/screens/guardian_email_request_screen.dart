import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../l10n/app_strings.dart';
import '../theme.dart';
import '../utils/validators.dart';
import '../services/auth_service.dart';
import '../models/student.dart';

class GuardianEmailRequestScreen extends StatefulWidget {
  final Student student;

  const GuardianEmailRequestScreen({super.key, required this.student});

  @override
  State<GuardianEmailRequestScreen> createState() => _GuardianEmailRequestScreenState();
}

class _GuardianEmailRequestScreenState extends State<GuardianEmailRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _newEmailCtrl = TextEditingController();
  final _confirmEmailCtrl = TextEditingController();
  final _remarksCtrl = TextEditingController();
  bool _submitting = false;

  late String _currentEmail;

  @override
  void initState() {
    super.initState();
    _currentEmail = FirebaseAuth.instance.currentUser?.email ?? widget.student.guardianEmail ?? '';
  }

  @override
  void dispose() {
    _newEmailCtrl.dispose();
    _confirmEmailCtrl.dispose();
    _remarksCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;

    final newEmail = _newEmailCtrl.text.trim().toLowerCase();
    if (newEmail == _currentEmail.toLowerCase()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('emailSameAsCurrent')),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    if (newEmail != _confirmEmailCtrl.text.trim().toLowerCase()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('emailsDoNotMatch')),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final schoolId = AuthService.currentSchoolId;
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('email_change_requests')
          .add({
        'studentId': widget.student.id,
        'studentName': widget.student.name,
        'studentRoll': widget.student.roll,
        'studentClass': widget.student.className,
        'studentSection': widget.student.section,
        'currentEmail': _currentEmail,
        'newEmail': newEmail,
        'remarks': _remarksCtrl.text.trim(),
        'status': 'pending',
        'requestedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('emailChangeRequestSubmitted')),
          backgroundColor: AppTheme.success,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Submission failed: $e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(context.tr('emailChangeRequest')),
        backgroundColor: AppTheme.primaryDark,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.info_outline, color: AppTheme.primary, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            context.tr('currentEmail'),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _currentEmail,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _newEmailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: context.tr('newEmail'),
                  prefixIcon: const Icon(Icons.email_outlined, color: AppTheme.primary),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return context.tr('validationRequired');
                  }
                  if (!Validators.isValidEmail(val.trim())) {
                    return context.tr('enterValidEmail');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmEmailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: context.tr('confirmNewEmail'),
                  prefixIcon: const Icon(Icons.mark_email_read_outlined, color: AppTheme.primary),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return context.tr('validationRequired');
                  }
                  if (!Validators.isValidEmail(val.trim())) {
                    return context.tr('enterValidEmail');
                  }
                  if (val.trim().toLowerCase() != _newEmailCtrl.text.trim().toLowerCase()) {
                    return context.tr('emailsDoNotMatch');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _remarksCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: '${context.tr('reasonChange')} (${context.tr('reasonOptional')})',
                  prefixIcon: const Icon(Icons.comment_outlined, color: AppTheme.primary),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: _submitting ? null : _submitRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Text(
                        context.tr('submitRequest'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

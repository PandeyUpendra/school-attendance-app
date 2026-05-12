import 'package:flutter/material.dart';
import '../models/school.dart';
import '../services/school_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import 'principal_dashboard.dart';

class SchoolRegistrationScreen extends StatefulWidget {
  const SchoolRegistrationScreen({super.key});

  @override
  State<SchoolRegistrationScreen> createState() => _SchoolRegistrationScreenState();
}

class _SchoolRegistrationScreenState extends State<SchoolRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();

  final _schoolNameCtrl = TextEditingController();
  final _schoolIdCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  final _adminNameCtrl = TextEditingController();
  final _adminEmailCtrl = TextEditingController();
  final _adminPasswordCtrl = TextEditingController();

  bool _loading = false;

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      final schoolId = _schoolIdCtrl.text.trim().toLowerCase().replaceAll(' ', '_');

      // Check if school exists
      final existing = await SchoolService().getSchool(schoolId);
      if (existing != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('School ID already taken. Please choose another.')),
          );
        }
        setState(() => _loading = false);
        return;
      }

      final school = School(
        id: schoolId,
        name: _schoolNameCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        contactNumber: _contactCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        createdAt: DateTime.now(),
      );

      // Register school and admin
      await SchoolService().registerSchool(
        school,
        _adminEmailCtrl.text.trim(),
        _adminPasswordCtrl.text.trim(),
        _adminNameCtrl.text.trim(),
      );

      // Login automatically
      await AuthService().login(_adminEmailCtrl.text.trim(), _adminPasswordCtrl.text.trim());
      await AuthService().saveSession(
        email: _adminEmailCtrl.text.trim(),
        role: 'principal',
        name: _adminNameCtrl.text.trim(),
        schoolId: schoolId,
      );

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const PrincipalDashboard()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Registration failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Register Your School'),
        backgroundColor: AppTheme.primary,
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('School Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _schoolNameCtrl,
                    decoration: const InputDecoration(labelText: 'School Name*', border: OutlineInputBorder()),
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _schoolIdCtrl,
                    decoration: const InputDecoration(
                      labelText: 'School ID (unique handle)*',
                      hintText: 'e.g. greenwood_high',
                      border: OutlineInputBorder()
                    ),
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _addressCtrl,
                    decoration: const InputDecoration(labelText: 'Address*', border: OutlineInputBorder()),
                    maxLines: 2,
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _contactCtrl,
                    decoration: const InputDecoration(labelText: 'Contact Number*', border: OutlineInputBorder()),
                    keyboardType: TextInputType.phone,
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _emailCtrl,
                    decoration: const InputDecoration(labelText: 'School Email*', border: OutlineInputBorder()),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),

                  const SizedBox(height: 32),
                  const Text('Admin Account', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _adminNameCtrl,
                    decoration: const InputDecoration(labelText: 'Admin Full Name*', border: OutlineInputBorder()),
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _adminEmailCtrl,
                    decoration: const InputDecoration(labelText: 'Admin Email (Username)*', border: OutlineInputBorder()),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _adminPasswordCtrl,
                    decoration: const InputDecoration(labelText: 'Admin Password*', border: OutlineInputBorder()),
                    obscureText: true,
                    validator: (v) => v!.length < 6 ? 'Min 6 characters' : null,
                  ),

                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _register,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('REGISTER & SETUP SCHOOL', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
    );
  }
}

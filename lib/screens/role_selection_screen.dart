import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';

import '../services/timetable_service.dart';
import '../services/auth_service.dart';
import '../services/base_firestore_service.dart';
import 'coordinator_dashboard.dart';
import 'teacher_profile_screen.dart';
import 'admin_screen.dart';
import 'principal_dashboard.dart';
import 'guardian_dashboard.dart';
import 'guardian_login_screen.dart';
import 'student_selection_screen.dart';
import 'school_registration_screen.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  // ── Email + Password login for Teacher / Coordinator / Principal / Guardian ─

  Future<void> _loginAsRole(
      BuildContext context, String role, Widget destination) async {
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    bool checking   = false;
    bool obscurePassword = true;
    bool cancelled  = false;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Icon(
              _roleIcon(role),
              color: _roleColor(role),
              size: 22,
            ),
            const SizedBox(width: 8),
            Text('Sign in as ${role[0].toUpperCase()}${role.substring(1)}',
                style: const TextStyle(fontSize: 15)),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter your registered credentials.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emailCtrl,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                maxLength: 100,
                decoration: InputDecoration(
                  labelText: 'Email Address',
                  prefixIcon: const Icon(Icons.email_outlined, size: 20),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordCtrl,
                obscureText: obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      size: 20,
                    ),
                    onPressed: () => setS(() => obscurePassword = !obscurePassword),
                  ),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                ),
                onSubmitted: (_) async {
                  if (checking) return;
                  setS(() => checking = true);
                  final allowed = await _validateAndLogin(
                      ctx, emailCtrl.text, passwordCtrl.text, role);
                  if (!ctx.mounted || cancelled) return;
                  if (allowed) Navigator.pop(ctx, true);
                  else setS(() => checking = false);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                cancelled = true;
                Navigator.pop(ctx, false);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: checking
                  ? null
                  : () async {
                      setS(() => checking = true);
                      final allowed = await _validateAndLogin(
                          ctx, emailCtrl.text, passwordCtrl.text, role);
                      if (!ctx.mounted || cancelled) return;
                      if (allowed) {
                        Navigator.pop(ctx, true);
                      } else {
                        setS(() => checking = false);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: _roleColor(role),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: checking
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Sign In'),
            ),
          ],
        ),
      ),
    );

    if (ok == true && context.mounted) {
      final email = emailCtrl.text.trim().toLowerCase();

      // Fetch user data from Firestore to get name and schoolId
      final userDoc = await FirebaseFirestore.instance.collection('allowed_users').doc(email).get();
      final userData = userDoc.data() ?? {};
      final name = userData['name'] as String? ?? email.split('@')[0];
      final schoolId = userData['schoolId'] as String? ?? 'default_school';
      BaseFirestoreService.currentSchoolId = schoolId;

      // Route based on role (existing logic)
      if (role == 'guardian') {
        final links = await TimetableService().getGuardianLinks(email);
        if (!context.mounted) return;
        if (links == null || links.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('No students linked to this account.'),
            backgroundColor: Colors.orange.shade700,
          ));
          return;
        }

        final sessionLinks = links.map((l) => '${l['studentClass']}|${l['studentRoll']}|${l['studentName'] ?? ''}').toList();
        await AuthService().saveSession(
          email: email,
          role: role,
          name: name,
          schoolId: schoolId,
          studentLinks: sessionLinks,
        );

        if (sessionLinks.length == 1) {
          final parts = sessionLinks.first.split('|');
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => GuardianDashboard(schoolId: schoolId, studentClass: parts[0], studentRoll: int.parse(parts[1]))));
        } else {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => StudentSelectionScreen(schoolId: schoolId, links: sessionLinks)));
        }
        return;
      }

      List<String>? assignedClasses;
      if (role == 'coordinator' || role == 'principal') {
        assignedClasses = await TimetableService().getAssignedClasses(email);
      }

      await AuthService().saveSession(
        email: email,
        role: role,
        name: name,
        schoolId: schoolId,
        assignedClasses: assignedClasses,
      );
      if (context.mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => destination));
      }
    }

  }

  Future<bool> _validateAndLogin(
      BuildContext context, String email, String password,
      String expectedRole) async {
    final trimmedEmail = email.trim().toLowerCase();
    if (trimmedEmail.isEmpty || !RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(trimmedEmail)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid email address')));
      return false;
    }
    if (password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter your password')));
      return false;
    }

    try {
      final role = await TimetableService().validateLogin(trimmedEmail, password);
      if (role == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Invalid email or password.'),
            backgroundColor: Colors.red.shade700,
          ));
        }
        return false;
      }
      if (role != expectedRole) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Access denied. This account is registered as ${role[0].toUpperCase()}${role.substring(1)}.'),
            backgroundColor: Colors.red.shade700,
          ));
        }
        return false;
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Login failed. Please try again.'),
          backgroundColor: Colors.red.shade700,
        ));
      }
      return false;
    }
  }


  Color _roleColor(String role) => AppTheme.primary;

  IconData _roleIcon(String role) {
    switch (role) {
      case 'coordinator': return Icons.admin_panel_settings_outlined;
      case 'principal':   return Icons.business_outlined;
      case 'guardian':    return Icons.family_restroom_outlined;
      default:            return Icons.person_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),
              const Icon(Icons.school, size: 48, color: AppTheme.primary),
              const SizedBox(height: 16),
              const Text('School App',
                  style: TextStyle(
                      fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('Who are you?',
                  style: TextStyle(
                      fontSize: 16, color: Colors.grey.shade500)),
              const SizedBox(height: 32),

              // ── Admin ─────────────────────────────────────────────────
              _RoleCard(
                icon: Icons.manage_accounts_outlined,
                title: 'Admin',
                subtitle: 'Manage registered users & login access',
                color: AppTheme.primary,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminScreen()),
                ),
              ),
              const SizedBox(height: 12),

              // ── Principal ─────────────────────────────────────────────
              _RoleCard(
                icon: Icons.business_outlined,
                title: 'Principal',
                subtitle: 'School overview, attendance & leave approvals',
                color: AppTheme.primary,
                onTap: () => _loginAsRole(
                    context, 'principal', const PrincipalDashboard()),
              ),
              const SizedBox(height: 12),

              // ── Coordinator ───────────────────────────────────────────
              _RoleCard(
                icon: Icons.admin_panel_settings_outlined,
                title: 'Coordinator',
                subtitle: 'Manage timetable, teachers, duties & students',
                color: AppTheme.primary,
                onTap: () => _loginAsRole(
                    context, 'coordinator', const CoordinatorDashboard()),
              ),
              const SizedBox(height: 12),

              // ── Teacher ───────────────────────────────────────────────
              _RoleCard(
                icon: Icons.person_outline,
                title: 'Teacher',
                subtitle: 'Take attendance, manage your students',
                color: AppTheme.primary,
                onTap: () => _loginAsRole(
                    context, 'teacher', const TeacherProfileScreen()),
              ),
              const SizedBox(height: 12),

              // ── Guardian ──────────────────────────────────────────────
              _RoleCard(
                icon: Icons.family_restroom_outlined,
                title: 'Guardian',
                subtitle: "Sign in with Google to view your child's progress",
                color: AppTheme.primary,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GuardianLoginScreen()),
                ),
              ),

              const SizedBox(height: 32),

              // ── SaaS Onboarding Link ──────────────────────────────────
              Center(
                child: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SchoolRegistrationScreen()),
                  ),
                  child: const Text('Not a member? Register your school here',
                      style: TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline)),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String   title;
  final String   subtitle;
  final Color    color;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: color)),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ),
          Icon(Icons.arrow_forward_ios,
              size: 14, color: color.withOpacity(0.4)),
        ]),
      ),
    );
  }
}

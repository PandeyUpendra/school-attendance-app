import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../services/timetable_service.dart';
import '../services/auth_service.dart';
import 'coordinator_dashboard.dart';
import 'teacher_profile_screen.dart';
import 'admin_screen.dart';
import 'principal_dashboard.dart';
import 'guardian_dashboard.dart';
import 'owner/owner_home.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  // ── Email + Password login for Teacher / Coordinator / Principal / Guardian ─

  Future<void> _loginAsRole(
      BuildContext context, String role, Widget destination) async {
    final emailCtrl = TextEditingController();
    final passCtrl  = TextEditingController();
    bool checking   = false;
    bool showPass   = false;

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
                'Enter your registered email and password.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                maxLength: 100,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                decoration: InputDecoration(
                  labelText: 'Email Address',
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: passCtrl,
                obscureText: !showPass,
                maxLength: 50,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(showPass
                        ? Icons.visibility_off
                        : Icons.visibility,
                        size: 18),
                    onPressed: () => setS(() => showPass = !showPass),
                  ),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  counterText: '',
                ),
                onSubmitted: (_) async {
                  if (checking) return;
                  setS(() => checking = true);
                  final allowed = await _validate(
                      ctx, emailCtrl.text, passCtrl.text, role);
                  if (!ctx.mounted) return;
                  if (allowed) Navigator.pop(ctx, true);
                  else setS(() => checking = false);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: checking
                  ? null
                  : () async {
                      setS(() => checking = true);
                      final allowed = await _validate(
                          ctx, emailCtrl.text, passCtrl.text, role);
                      if (!ctx.mounted) return;
                      if (allowed) {
                        Navigator.pop(ctx, true);
                      } else {
                        setS(() => checking = false);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: _roleColor(role),
                foregroundColor: Colors.white,
              ),
              child: checking
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Continue'),
            ),
          ],
        ),
      ),
    );

    if (ok == true && context.mounted) {
      final email = emailCtrl.text.trim().toLowerCase();

      try {
        // Guardian: fetch the linked student (class + roll) from Firestore,
        // store it in the session and route to a GuardianDashboard built for
        // that specific child. If not linked, the admin needs to set it.
        if (role == 'guardian') {
          final link = await TimetableService().getGuardianLink(email);
          if (!context.mounted) return;
          if (link == null) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text(
                  'Your guardian account is not linked to a student yet. '
                  'Please ask the admin to set your child class & roll.'),
              backgroundColor: Colors.orange.shade700,
              duration: const Duration(seconds: 4),
            ));
            return;
          }
          final sClass   = link['studentClass']   as String;
          final sRoll    = link['studentRoll']    as int;
          final sSection = link['studentSection'] as String? ?? '';
          await AuthService().saveSession(
            email: email,
            role: role,
            studentClass: sClass,
            studentRoll:  sRoll,
            studentSection: sSection,
          );
          if (!context.mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => GuardianDashboard(
                  studentClass: sClass, studentRoll: sRoll, studentSection: sSection),
            ),
          );
          return;
        }

        // Coordinator / Principal / Owner — fetch their assigned classes and schoolId.
        List<String>? assignedClasses;
        String?       schoolId;
        if (role == 'coordinator' || role == 'principal' || role == 'owner') {
          final loginData = await TimetableService().getAssignedClasses(email);
          assignedClasses = loginData.assignedClasses;
          schoolId        = loginData.schoolId;
        }

        // Teacher / Coordinator / Principal — save session and go to destination.
        await AuthService().saveSession(
          email: email,
          role:  role,
          assignedClasses: assignedClasses,
          schoolId: schoolId,
        );
        if (context.mounted) {
          Navigator.pushReplacement(
              context, MaterialPageRoute(builder: (_) => destination));
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text(
                'Login failed. Check your internet connection and try again.'),
            backgroundColor: Colors.red.shade700,
          ));
        }
      }
    }
  }

  Future<bool> _validate(
      BuildContext context, String email, String password,
      String expectedRole) async {
    final trimmed = email.trim().toLowerCase();
    if (trimmed.isEmpty ||
        !RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(trimmed)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid email address')));
      return false;
    }
    if (password.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter your password')));
      return false;
    }
    final String? role;
    try {
      role = await TimetableService().validateLogin(trimmed, password.trim());
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text(
              'Login failed. Check your internet connection and try again.'),
          backgroundColor: Colors.red.shade700,
        ));
      }
      return false;
    }
    if (role == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text(
              'Invalid email or password. Contact admin if not registered.'),
          backgroundColor: Colors.red.shade700,
        ));
      }
      return false;
    }
    if (role != expectedRole) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'This email is registered as ${role[0].toUpperCase()}${role.substring(1)}, not ${expectedRole[0].toUpperCase()}${expectedRole.substring(1)}.'),
          backgroundColor: Colors.orange.shade700,
        ));
      }
      return false;
    }
    return true;
  }

  Future<void> _openAdmin(BuildContext context) async {
    final pinCtrl = TextEditingController();
    bool obscure = true;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Admin Access'),
          content: TextField(
            controller: pinCtrl,
            obscureText: obscure,
            keyboardType: TextInputType.visiblePassword,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'PIN',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                    obscure ? Icons.visibility : Icons.visibility_off,
                    size: 18),
                onPressed: () => setS(() => obscure = !obscure),
              ),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              constraints: const BoxConstraints(minHeight: 56),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );

    if (!context.mounted) return;
    if (confirmed != true) return;

    if (pinCtrl.text == 'admin@1234') {
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => const AdminScreen()));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Incorrect PIN'),
          backgroundColor: Colors.red,
        ),
      );
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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppTheme.primaryDark, AppTheme.primary, AppTheme.primaryMid],
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 48),
                  const Icon(Icons.school, size: 48, color: Colors.white),
                  const SizedBox(height: 16),
                  const Text('School App',
                      style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const SizedBox(height: 6),
                  Text('Who are you?',
                      style: TextStyle(
                          fontSize: 16,
                          color: Colors.white.withOpacity(0.7))),
                  const SizedBox(height: 32),

                  // ── Admin ─────────────────────────────────────────────────
                  _RoleCard(
                    icon: Icons.manage_accounts_outlined,
                    title: 'Admin',
                    subtitle: 'Manage registered users & login access',
                    onTap: () => _openAdmin(context),
                  ),
                  const SizedBox(height: 12),

                  // ── Owner ─────────────────────────────────────────────────
                  _RoleCard(
                    icon: Icons.stars_outlined,
                    title: 'Owner',
                    subtitle: 'Manage principals and school hierarchy',
                    onTap: () => _loginAsRole(
                        context, 'owner', const OwnerHome()),
                  ),
                  const SizedBox(height: 12),

                  // ── Principal ─────────────────────────────────────────────
                  _RoleCard(
                    icon: Icons.business_outlined,
                    title: 'Principal',
                    subtitle: 'School overview, attendance & leave approvals',
                    onTap: () => _loginAsRole(
                        context, 'principal', const PrincipalDashboard()),
                  ),
                  const SizedBox(height: 12),

                  // ── Coordinator ───────────────────────────────────────────
                  _RoleCard(
                    icon: Icons.admin_panel_settings_outlined,
                    title: 'Coordinator',
                    subtitle: 'Manage timetable, teachers, duties & students',
                    onTap: () => _loginAsRole(
                        context, 'coordinator', const CoordinatorDashboard()),
                  ),
                  const SizedBox(height: 12),

                  // ── Teacher ───────────────────────────────────────────────
                  _RoleCard(
                    icon: Icons.person_outline,
                    title: 'Teacher',
                    subtitle: 'Take attendance, manage your students',
                    onTap: () => _loginAsRole(
                        context, 'teacher', const TeacherProfileScreen()),
                  ),
                  const SizedBox(height: 12),

                  // ── Guardian ──────────────────────────────────────────────
                  _RoleCard(
                    icon: Icons.family_restroom_outlined,
                    title: 'Guardian',
                    subtitle: "View your child's attendance & progress",
                    onTap: () => _loginAsRole(
                        context, 'guardian', const _PlaceholderDestination()),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Placeholder used when the real destination depends on data fetched
/// during login (e.g. Guardian → needs student class+roll from Firestore).
/// Never actually shown — _loginAsRole handles the guardian branch directly.
class _PlaceholderDestination extends StatelessWidget {
  const _PlaceholderDestination();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: SizedBox.shrink());
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String   title;
  final String   subtitle;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      splashColor: Colors.white24,
      highlightColor: Colors.white10,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.13),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.25)),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.7))),
              ],
            ),
          ),
          Icon(Icons.arrow_forward_ios,
              size: 14, color: Colors.white.withOpacity(0.5)),
        ]),
      ),
    );
  }
}

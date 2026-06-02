import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../services/auth_service.dart';
import '../services/timetable_service.dart';
import 'login_screen.dart';
import 'guardian_login_screen.dart';
import 'admin_screen.dart';

/// Role selection screen — now a lightweight hub that routes to:
/// • LoginScreen for all staff (owner, principal, coordinator, teacher)
/// • GuardianLoginScreen for guardians (Google Sign-In)
/// • AdminScreen via Firebase Auth (email + password, admin role) for admins
///
/// This screen is only shown when navigating back from the guardian flow,
/// or from legacy navigation references. New sessions always start at LoginScreen.
class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  /// Admin access via real Firebase Auth (replaces the old hardcoded PIN).
  /// Authenticates email + password, then verifies the account holds the
  /// `admin` role in allowed_users before opening [AdminScreen].
  Future<void> _openAdmin(BuildContext context) async {
    final emailCtrl = TextEditingController();
    final passCtrl  = TextEditingController();
    bool    obscure = true;
    bool    busy    = false;
    String? dlgError;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          Future<void> attempt() async {
            final email = emailCtrl.text.trim().toLowerCase();
            final pass  = passCtrl.text;
            if (email.isEmpty || !email.contains('@')) {
              setS(() => dlgError = 'Enter a valid email address.');
              return;
            }
            if (pass.isEmpty) {
              setS(() => dlgError = 'Enter your password.');
              return;
            }

            setS(() { busy = true; dlgError = null; });
            try {
              await AuthService().signInWithEmail(email, pass);
              final userData =
                  await TimetableService().getAllowedUserDoc(email);
              final role = userData?['role'] as String? ?? '';
              if (role != 'admin') {
                await AuthService().signOut();
                setS(() {
                  busy = false;
                  dlgError = 'Not an admin account.';
                });
                return;
              }
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (!context.mounted) return;
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AdminScreen()));
            } on FirebaseAuthException catch (e) {
              setS(() {
                busy = false;
                dlgError = AuthService.friendlyAuthError(e);
              });
            } catch (_) {
              setS(() {
                busy = false;
                dlgError =
                    'Login failed. Check your internet connection and try again.';
              });
            }
          }

          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Admin Access'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: emailCtrl,
                  enabled: !busy,
                  autofocus: true,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Email Address',
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passCtrl,
                  enabled: !busy,
                  obscureText: obscure,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => busy ? null : attempt(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                          obscure ? Icons.visibility : Icons.visibility_off,
                          size: 18),
                      onPressed: () => setS(() => obscure = !obscure),
                    ),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                if (dlgError != null) ...[
                  const SizedBox(height: 12),
                  Text(dlgError!,
                      style:
                          TextStyle(color: Colors.red.shade700, fontSize: 13)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: busy ? null : attempt,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                ),
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Login'),
              ),
            ],
          );
        },
      ),
    );

    emailCtrl.dispose();
    passCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppTheme.primaryMid,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: AppTheme.primaryMid,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppTheme.primaryDark, AppTheme.primaryMid],
            ),
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              24,
              MediaQuery.paddingOf(context).top + 48,
              24,
              MediaQuery.paddingOf(context).bottom + 32,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.school, size: 48, color: Colors.white),
                const SizedBox(height: 16),
                const Text('School App',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const SizedBox(height: 6),
                Text('Choose how to sign in',
                    style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withValues(alpha: 0.7))),
                const SizedBox(height: 32),

                // ── Staff (teacher / coordinator / principal / owner) ───────
                _RoleCard(
                  icon: Icons.badge_outlined,
                  title: 'Staff Login',
                  subtitle: 'Teacher, Coordinator, Principal, Owner',
                  onTap: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  ),
                ),
                const SizedBox(height: 12),

                // ── Guardian ──────────────────────────────────────────────
                _RoleCard(
                  icon: Icons.family_restroom_outlined,
                  title: 'Guardian',
                  subtitle: "View your child's attendance & progress",
                  onTap: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const GuardianLoginScreen()),
                  ),
                ),
                const SizedBox(height: 12),

                // ── Admin ─────────────────────────────────────────────────
                _RoleCard(
                  icon: Icons.manage_accounts_outlined,
                  title: 'Admin',
                  subtitle: 'Manage registered users & login access',
                  onTap: () => _openAdmin(context),
                ),

                const SizedBox(height: 32),
              ],
            ),
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
          color: Colors.white.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
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
                        color: Colors.white.withValues(alpha: 0.7))),
              ],
            ),
          ),
          Icon(Icons.arrow_forward_ios,
              size: 14, color: Colors.white.withValues(alpha: 0.5)),
        ]),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme.dart';
import '../../l10n/app_strings.dart';
import './login_screen.dart';
import './guardian_login_screen.dart';
import './admin_login_screen.dart';

/// Role selection screen — now a lightweight hub that routes to:
/// • LoginScreen for all staff (owner, principal, coordinator, teacher)
/// • GuardianLoginScreen for guardians (Google Sign-In)
/// • AdminLoginScreen via Firebase Auth (email + password, admin role)
///
/// This screen is only shown when navigating back from the guardian flow,
/// or from legacy navigation references. New sessions always start at LoginScreen.
class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  /// Admin access — opens the full-screen [AdminLoginScreen] (replaces the old
  /// in-line "Admin Access" dialog so the experience matches the other roles).
  void _openAdmin(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AdminLoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppTheme.primaryDark,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: AppTheme.primaryDark,
        body: Container(
          decoration: const BoxDecoration(
            color: AppTheme.primaryDark,
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
                Text(context.tr('schoolApp'),
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const SizedBox(height: 6),
                Text(context.tr('chooseHowToSignIn'),
                    style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withValues(alpha: 0.7))),
                const SizedBox(height: 32),

                // ── Staff (teacher / coordinator / principal / owner) ───────
                _RoleCard(
                  icon: Icons.badge_outlined,
                  title: context.tr('staffLogin'),
                  subtitle: context.tr('staffLoginSubtitle'),
                  onTap: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  ),
                ),
                const SizedBox(height: 12),

                // ── Guardian ──────────────────────────────────────────────
                _RoleCard(
                  icon: Icons.family_restroom_outlined,
                  title: context.tr('role_guardian'),
                  subtitle: context.tr('guardianSubtitle'),
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
                  title: context.tr('role_admin'),
                  subtitle: context.tr('adminSubtitle'),
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

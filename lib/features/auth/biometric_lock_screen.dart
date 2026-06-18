import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../../theme.dart';
import '../../l10n/app_strings.dart';
import '../../services/auth_service.dart';
import './role_selection_screen.dart';

class BiometricLockScreen extends StatefulWidget {
  final Widget? targetScreen;
  final bool isResume;

  static bool isVisible = false;

  const BiometricLockScreen({
    super.key,
    this.targetScreen,
    this.isResume = false,
  });

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen> with SingleTickerProviderStateMixin {
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _authenticating = false;
  String? _error;
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    BiometricLockScreen.isVisible = true;

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    // Auto-trigger biometric check after screen is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          _authenticate();
        }
      });
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    BiometricLockScreen.isVisible = false;
    super.dispose();
  }

  Future<void> _authenticate() async {
    if (_authenticating) return;
    setState(() {
      _authenticating = true;
      _error = null;
    });

    try {
      final didAuth = await _localAuth.authenticate(
        localizedReason: context.tr('biometricReason'),
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (!mounted) return;

      if (didAuth) {
        // Unlock successful!
        if (widget.isResume) {
          Navigator.of(context).pop();
        } else if (widget.targetScreen != null) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => widget.targetScreen!),
          );
        }
      } else {
        setState(() {
          _authenticating = false;
          _error = 'Authentication failed. Please try again.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _authenticating = false;
        _error = 'Error: $e';
      });
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(context.tr('logOut')),
        content: Text(context.tr('logoutConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              context.tr('logOut'),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (ok != true) return;
    await AuthService().clearSession();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppTheme.primaryDark,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              children: [
                const Spacer(flex: 2),
                
                // Pulsing Lock Icon & Logo
                Center(
                  child: Column(
                    children: [
                      Image.asset(
                        'assets/images/logo.png',
                        height: 80,
                        width: 80,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        context.tr('appLocked'),
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        key: const ValueKey('biometric-lock-subtitle'),
                        child: Text(
                          context.tr('tapToUnlock'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const Spacer(flex: 3),
                
                // Fingerprint Pulse / Action Button
                ScaleTransition(
                  scale: _scaleAnimation,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                    padding: const EdgeInsets.all(24),
                    child: IconButton(
                      iconSize: 64,
                      icon: const Icon(
                        Icons.fingerprint_outlined,
                        color: Colors.white,
                      ),
                      onPressed: _authenticate,
                    ),
                  ),
                ),
                
                if (_error != null) ...[
                  const SizedBox(height: 24),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                
                const Spacer(flex: 4),
                
                // Manual Unlock / Log Out Buttons
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton(
                      onPressed: _authenticate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppTheme.primaryDark,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        context.tr('verifyIdentity'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: _logout,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        context.tr('logOut'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
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
    );
  }
}

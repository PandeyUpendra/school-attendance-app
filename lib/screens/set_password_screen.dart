import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/auth_service.dart';

/// Allows a signed-in user to change their password.
/// Re-authenticates first so Firebase accepts the update even after a long session.
class SetPasswordScreen extends StatefulWidget {
  const SetPasswordScreen({super.key});

  @override
  State<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends State<SetPasswordScreen> {
  final _currentCtrl  = TextEditingController();
  final _newCtrl      = TextEditingController();
  final _confirmCtrl  = TextEditingController();

  bool _loadingReauth = false;
  bool _loadingUpdate = false;
  bool _reauthDone    = false;
  bool _done          = false;

  bool _showCurrent  = false;
  bool _showNew      = false;
  bool _showConfirm  = false;

  String? _reauthError;
  String? _updateError;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _reauth() async {
    final email    = AuthService().currentFirebaseUser?.email ?? '';
    final password = _currentCtrl.text;

    if (password.isEmpty) {
      setState(() => _reauthError = 'Enter your current password.');
      return;
    }
    setState(() { _loadingReauth = true; _reauthError = null; });

    try {
      await AuthService().reauthenticate(email, password);
      if (!mounted) return;
      setState(() { _loadingReauth = false; _reauthDone = true; });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingReauth = false;
        _reauthError   = AuthService.friendlyAuthError(e);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingReauth = false;
        _reauthError   = 'Verification failed. Check your connection.';
      });
    }
  }

  Future<void> _updatePassword() async {
    final newPass     = _newCtrl.text;
    final confirmPass = _confirmCtrl.text;

    if (newPass.length < 8) {
      setState(() => _updateError = 'Password must be at least 8 characters.');
      return;
    }
    if (newPass != confirmPass) {
      setState(() => _updateError = 'Passwords do not match.');
      return;
    }
    setState(() { _loadingUpdate = true; _updateError = null; });

    try {
      await AuthService().updatePassword(newPass);
      if (!mounted) return;
      setState(() { _loadingUpdate = false; _done = true; });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingUpdate = false;
        _updateError   = AuthService.friendlyAuthError(e);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingUpdate = false;
        _updateError   = 'Password update failed. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Change Password'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: _done ? _buildSuccess() : _buildForm(),
        ),
      ),
    );
  }

  Widget _buildSuccess() {
    return Column(
      children: [
        const SizedBox(height: 48),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Column(children: [
            Icon(Icons.check_circle_outline,
                size: 56, color: Colors.green.shade600),
            const SizedBox(height: 16),
            const Text(
              'Password Updated',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87),
            ),
            const SizedBox(height: 8),
            Text(
              'Your password has been changed successfully.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ]),
        ),
        const SizedBox(height: 28),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Done'),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),

        // Step 1 — verify identity
        _SectionCard(
          step: '1',
          title: 'Verify Your Identity',
          done: _reauthDone,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Enter your current password to confirm it\'s you.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _currentCtrl,
                obscureText: !_showCurrent,
                enabled: !_reauthDone,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) =>
                    _loadingReauth || _reauthDone ? null : _reauth(),
                decoration: InputDecoration(
                  labelText: 'Current Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                        _showCurrent
                            ? Icons.visibility_off
                            : Icons.visibility,
                        size: 18),
                    onPressed: () =>
                        setState(() => _showCurrent = !_showCurrent),
                  ),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              if (_reauthError != null) ...[
                const SizedBox(height: 10),
                _ErrorBanner(_reauthError!),
              ],
              if (!_reauthDone) ...[
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _loadingReauth ? null : _reauth,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  child: _loadingReauth
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Verify'),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Step 2 — set new password
        _SectionCard(
          step: '2',
          title: 'Set New Password',
          locked: !_reauthDone,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Choose a strong password with at least 8 characters.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _newCtrl,
                obscureText: !_showNew,
                enabled: _reauthDone,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'New Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                        _showNew ? Icons.visibility_off : Icons.visibility,
                        size: 18),
                    onPressed: () => setState(() => _showNew = !_showNew),
                  ),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmCtrl,
                obscureText: !_showConfirm,
                enabled: _reauthDone,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) =>
                    _loadingUpdate || !_reauthDone ? null : _updatePassword(),
                decoration: InputDecoration(
                  labelText: 'Confirm New Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                        _showConfirm
                            ? Icons.visibility_off
                            : Icons.visibility,
                        size: 18),
                    onPressed: () =>
                        setState(() => _showConfirm = !_showConfirm),
                  ),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              if (_updateError != null) ...[
                const SizedBox(height: 10),
                _ErrorBanner(_updateError!),
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed:
                    (_reauthDone && !_loadingUpdate) ? _updatePassword : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: _loadingUpdate
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Update Password'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String step;
  final String title;
  final Widget child;
  final bool done;
  final bool locked;

  const _SectionCard({
    required this.step,
    required this.title,
    required this.child,
    this.done   = false,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: done
              ? Colors.green.shade200
              : locked
                  ? Colors.grey.shade200
                  : AppTheme.primary.withOpacity(0.3),
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: done
                  ? Colors.green
                  : locked
                      ? Colors.grey.shade300
                      : AppTheme.primary,
              child: done
                  ? const Icon(Icons.check, color: Colors.white, size: 14)
                  : Text(step,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 10),
            Text(title,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: locked ? Colors.grey.shade400 : Colors.black87)),
          ]),
          const SizedBox(height: 16),
          Opacity(opacity: locked ? 0.4 : 1, child: child),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(children: [
        Icon(Icons.error_outline, color: Colors.red.shade600, size: 16),
        const SizedBox(width: 8),
        Expanded(
            child: Text(message,
                style:
                    TextStyle(fontSize: 12, color: Colors.red.shade700))),
      ]),
    );
  }
}

import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/auth_service.dart';
import '../services/timetable_service.dart';
import '../services/base_firestore_service.dart';
import 'guardian_dashboard.dart';
import 'student_selection_screen.dart';
import 'role_selection_screen.dart';

class GuardianLoginScreen extends StatefulWidget {
  const GuardianLoginScreen({super.key});

  @override
  State<GuardianLoginScreen> createState() => _GuardianLoginScreenState();
}

class _GuardianLoginScreenState extends State<GuardianLoginScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _signInWithGoogle() async {
    setState(() { _loading = true; _error = null; });

    try {
      final result = await AuthService().signInWithGoogle();
      if (result == null) {
        // User cancelled the sign-in
        setState(() => _loading = false);
        return;
      }

      final email = result['email'];
      if (email == null || email.isEmpty) {
        setState(() { _loading = false; _error = 'Could not retrieve your email from Google.'; });
        return;
      }

      final links = await TimetableService().getGuardianLinks(email);
      if (!mounted) return;

      if (links == null || links.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'Your Google account ($email) is not linked to any student.\n\n'
              'Ask your child\'s class teacher to set up guardian access.';
        });
        return;
      }

      final userData = await _fetchUserData(email);
      final name    = userData?['name'] as String? ?? email.split('@').first;
      final schoolId = userData?['schoolId'] as String? ?? 'default_school';
      BaseFirestoreService.currentSchoolId = schoolId;

      final sessionLinks = links
          .map((l) => '${l['studentClass']}|${l['studentRoll']}|${l['studentName'] ?? ''}')
          .toList();

      await AuthService().saveSession(
        email: email,
        role: 'guardian',
        name: name,
        schoolId: schoolId,
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
              studentRoll: int.parse(parts[1]),
            ),
          ),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => StudentSelectionScreen(schoolId: schoolId, links: sessionLinks),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Sign-in failed. Please try again.';
      });
    }
  }

  Future<Map<String, dynamic>?> _fetchUserData(String email) async {
    try {
      final doc = await TimetableService().getAllowedUserDoc(email);
      return doc;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Guardian Login'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // Icon + title
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.family_restroom_outlined,
                    size: 44, color: AppTheme.primary),
              ),
              const SizedBox(height: 24),
              const Text(
                'Guardian Portal',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryDark,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "Sign in with your Google account to view\nyour child's attendance & progress.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.5),
              ),

              const SizedBox(height: 40),

              // Google Sign-In button
              _loading
                  ? const CircularProgressIndicator(color: AppTheme.primary)
                  : _GoogleSignInButton(onPressed: _signInWithGoogle),

              // Error
              if (_error != null) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade600, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(fontSize: 13, color: Colors.red.shade700, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const Spacer(flex: 3),

              // Footer hint
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Text(
                  'Your email must be registered by your\nchild\'s teacher before you can sign in.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleSignInButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _GoogleSignInButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: BorderSide(color: Colors.grey.shade300, width: 1.5),
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 1,
          shadowColor: Colors.black12,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Google "G" logo rendered with coloured text
            const _GoogleLogo(),
            const SizedBox(width: 12),
            const Text(
              'Sign in with Google',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Approximates the Google "G" logo using four coloured quadrant arcs.
class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(painter: _GoogleGPainter()),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  static const _blue   = Color(0xFF4285F4);
  static const _red    = Color(0xFFEA4335);
  static const _yellow = Color(0xFFFBBC05);
  static const _green  = Color(0xFF34A853);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final r = s / 2;
    final center = Offset(r, r);
    final outerR = r;
    final innerR = r * 0.6;
    final arcRect = Rect.fromCircle(center: center, radius: (outerR + innerR) / 2);
    final strokeW = outerR - innerR;

    Paint arc(Color c) =>
        Paint()..color = c..style = PaintingStyle.stroke..strokeWidth = strokeW..strokeCap = StrokeCap.butt;

    // Angles in radians: 0 = 3 o'clock, going clockwise
    // Red: top-right → top (−45° to −135°, i.e. -π/4 to -3π/4)
    canvas.drawArc(arcRect, -2.356, 1.571, false, arc(_red));
    // Yellow: bottom-left (135° to 225°, i.e. 3π/4 to 5π/4)
    canvas.drawArc(arcRect, 2.356, 0.785, false, arc(_yellow));
    // Green: bottom-right (225° to 315°, i.e. 5π/4 to 7π/4) – actually 270→315
    canvas.drawArc(arcRect, 3.142, 0.785, false, arc(_green));
    // Blue: right side (−45° to 45°, top-right to bottom-right)
    canvas.drawArc(arcRect, -0.785, 1.571, false, arc(_blue));

    // White cutout for the horizontal bar of the G
    final whitePaint = Paint()..color = Colors.white;
    canvas.drawRect(
      Rect.fromLTWH(r, r - strokeW * 0.5, r + strokeW, strokeW),
      whitePaint,
    );
    // White inner circle to complete the donut
    canvas.drawCircle(center, innerR - 1, whitePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

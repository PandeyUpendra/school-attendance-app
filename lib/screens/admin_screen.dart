import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/timetable_service.dart';
import '../utils/app_logger.dart';
import '../utils/role_guard.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _service   = TimetableService();
  final _emailCtrl  = TextEditingController();

  // Admin can only create Owner accounts — the role is fixed (no picker).
  static const _role = 'owner';

  List<Map<String, dynamic>> _users = [];
  bool _loading  = true;
  bool _saving   = false;

  // Role → accent colour (all purple-family now, semantic distinction by shade/hue)
  static const _roleColors = {
    'teacher':     AppTheme.primary,
    'coordinator': AppTheme.primaryMid,
    'principal':   AppTheme.primaryDark,
    'guardian':    AppTheme.accent,
    'owner':       Color(0xFF37474F),
  };

  @override
  void initState() {
    super.initState();
    // Guard: only a signed-in Firebase user with the admin role may stay here.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      RoleGuard.verify(context, ['admin']);
    });
    _load();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  // ── Data ───────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // Admin sees only Owner accounts. Query owners directly with
      // where('role' == 'owner') — an unscoped allowed_users read is rejected
      // by the security rules (non-owner managers may only read docs in their
      // own school), whereas the owner-scoped query satisfies the owner rule.
      final owners = await _service.getAllowedOwners();
      if (!mounted) return;
      setState(() {
        _users   = owners;
        _loading = false;
      });
    } catch (e) {
      AppLogger.e('AdminScreen', '_load failed: $e', e);
      if (!mounted) return;
      setState(() {
        _users   = [];
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not load users: $e'),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 8),
      ));
    }
  }

  // ── Add ────────────────────────────────────────────────────────────────────

  Future<void> _add() async {
    final email = _emailCtrl.text.trim().toLowerCase();

    if (email.isEmpty ||
        !RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(email)) {
      _snack('Enter a valid email address');
      return;
    }
    if (_users.any((u) => u['email'] == email)) {
      _snack('Email already registered');
      return;
    }

    setState(() => _saving = true);
    try {
      // Each owner runs an independent school. Stamp a unique schoolId on the
      // account so two owners never share data — without this the account is
      // written with no schoolId and login falls back to the default
      // 'school_1', which is why every owner was seeing the same school.
      final schoolId =
          'school_${DateTime.now().millisecondsSinceEpoch}_${email.hashCode.abs()}';
      // No password needed — a secure temp is generated automatically and a
      // setup link is sent to the user's email via Firebase Auth.
      await _service.addAllowedUser(email, '', _role, schoolId: schoolId);
      _emailCtrl.clear();
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$email added as Owner — setup link sent'),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 3),
      ));
    } catch (e) {
      AppLogger.e('AdminScreen', '_add failed for $email: $e', e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not add $email: $e'),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 8),
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Remove ─────────────────────────────────────────────────────────────────

  Future<void> _remove(String email) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Access'),
        content: Text('Remove login access for $email?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _service.removeAllowedUser(email);
    _load();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _snack(String msg) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));

  Color _roleColor(String role) =>
      _roleColors[role] ?? Colors.grey;

  IconData _roleIcon(String role) {
    switch (role) {
      case 'coordinator': return Icons.admin_panel_settings_outlined;
      case 'principal':   return Icons.business_outlined;
      case 'guardian':    return Icons.family_restroom_outlined;
      case 'owner':       return Icons.stars_outlined;
      default:            return Icons.person_outline;
    }
  }

  BoxDecoration get _cardDecoration => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      );

  Widget _fieldLabel(String t) => Text(t,
      style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade500,
          letterSpacing: 0.6));

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          _AdminHero(onBack: () => Navigator.maybePop(context)),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              color: AppTheme.primary,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  _buildAddCard(),
                  const SizedBox(height: 16),
                  _buildInfoBanner(),
                  const SizedBox(height: 22),
                  Row(children: [
                    _fieldLabel('REGISTERED OWNERS'),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('${_users.length}',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary)),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  _buildUsersSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Add-account card ─────────────────────────────────────────────────────────

  Widget _buildAddCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(Icons.person_add_alt_1_outlined,
                  color: AppTheme.primary, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('Add Owner',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 18),

          // Role — fixed to Owner (admin creates owners only), shown read-only.
          _fieldLabel('ROLE'),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(children: [
              Icon(_roleIcon('owner'), color: _roleColor('owner'), size: 18),
              const SizedBox(width: 10),
              const Text('Owner',
                  style:
                      TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const Spacer(),
              Icon(Icons.lock_outline, size: 14, color: Colors.grey.shade400),
            ]),
          ),
          const SizedBox(height: 14),

          // Email
          _fieldLabel('EMAIL ADDRESS'),
          const SizedBox(height: 6),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              hintText: 'name@example.com',
              hintStyle: TextStyle(color: Colors.grey.shade400),
              prefixIcon: Icon(Icons.email_outlined,
                  color: Colors.grey.shade500, size: 20),
              filled: true,
              fillColor: AppTheme.background,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppTheme.primary, width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.lock_clock_outlined,
                size: 14, color: Colors.grey.shade400),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'A password-setup link is emailed automatically.',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
              ),
            ),
          ]),
          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _add,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: _saving
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(_saving ? 'Sending…' : 'Add & Send Invite',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Info banner ──────────────────────────────────────────────────────────────

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.30)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.info_outline, color: AppTheme.warning, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Admins create Owner accounts only. Each role then creates the '
            'roles below it in the hierarchy.',
            style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: Colors.brown.shade700),
          ),
        ),
      ]),
    );
  }

  // ── Users section ────────────────────────────────────────────────────────────

  Widget _buildUsersSection() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.only(top: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_users.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 44),
        alignment: Alignment.center,
        child: Column(children: [
          Icon(Icons.group_outlined, size: 54, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text('No owners registered yet',
              style: TextStyle(fontSize: 14.5, color: Colors.grey.shade400)),
          const SizedBox(height: 4),
          Text('Add an email above to send an invite',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
        ]),
      );
    }
    return Column(children: [for (final u in _users) _buildUserCard(u)]);
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final email    = user['email'] as String;
    final role     = user['role'] as String;
    final schoolId = (user['schoolId'] as String?) ?? '';
    final color    = _roleColor(role);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
      decoration: _cardDecoration,
      child: Row(children: [
        Container(
          width: 46, height: 46,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(_roleIcon(role), color: color, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(email,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Text(role[0].toUpperCase() + role.substring(1),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: color)),
              ),
              if (schoolId.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(children: [
                  Icon(Icons.school_outlined,
                      size: 12, color: Colors.grey.shade400),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(schoolId,
                        style: TextStyle(
                            fontSize: 10.5, color: Colors.grey.shade500),
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),
              ],
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline,
              color: AppTheme.danger, size: 20),
          onPressed: () => _remove(email),
          tooltip: 'Remove',
        ),
      ]),
    );
  }
}

// ── Wave hero header (matches the dashboard hero pattern) ──────────────────────

class _AdminHero extends StatelessWidget {
  final VoidCallback onBack;
  const _AdminHero({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: _AdminWaveClipper(),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.primaryDark, AppTheme.primaryMid],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 16, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: onBack,
                  ),
                  const Icon(Icons.shield_outlined,
                      color: Colors.white70, size: 14),
                  const SizedBox(width: 6),
                  const Text('ADMIN PANEL',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.1)),
                ]),
                const Padding(
                  padding: EdgeInsets.only(left: 14, top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Manage Access',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text('Create and manage owner login accounts',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 12.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 28);
    path.quadraticBezierTo(
        size.width * 0.25, size.height + 6, size.width * 0.5, size.height - 16);
    path.quadraticBezierTo(
        size.width * 0.75, size.height - 38, size.width, size.height - 16);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_AdminWaveClipper old) => false;
}

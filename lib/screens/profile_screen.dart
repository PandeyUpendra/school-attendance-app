import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../utils/app_logger.dart';
import '../providers/locale_provider.dart';
import '../services/auth_service.dart';
import '../services/timetable_service.dart';
import '../theme.dart';
import 'role_selection_screen.dart';

/// Profile screen available to every role. Shows the signed-in user's own
/// account details, read from the session and their `allowed_users` document.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _loading = true;

  String _name = '';
  String _email = '';
  String _role = '';
  String _phone = '';
  String _status = '';
  String _schoolName = '';
  List<String> _classes = [];
  List<String> _children = []; // guardian: "Name · Class · Roll N"

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
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final session = await AuthService().getSession();
      final email = (session?['email'] as String? ?? '').toLowerCase();
      _email = email;
      _role = session?['role'] as String? ?? '';
      _name = session?['name'] as String? ?? '';

      final svc = TimetableService();
      Map<String, dynamic>? doc;
      try {
        doc = await svc.getAllowedUserDoc(email);
      } catch (e, st) { AppLogger.e('ProfileScreen', 'Best-effort load failed', e, st); }

      if (doc != null) {
        _name = (doc['name'] as String?)?.trim().isNotEmpty == true
            ? doc['name'] as String
            : _name;
        _phone = doc['phone'] as String? ?? '';
        _status = doc['status'] as String? ?? '';

        // Teacher → classIds; coordinator/principal/owner → assignedClasses.
        final classIds = (doc['classIds'] as List?)?.whereType<String>().toList();
        final assigned =
            (doc['assignedClasses'] as List?)?.whereType<String>().toList();
        _classes = [...?classIds, ...?assigned];
        _classes = _classes.toSet().toList()..sort();
      }

      // Guardian children.
      if (_role == 'guardian') {
        try {
          final links = await svc.getGuardianLinks(email);
          _children = (links ?? []).map((l) {
            final name = (l['studentName'] as String? ?? '').trim();
            final cls = l['studentClass'] as String? ?? '';
            final roll = l['studentRoll'];
            final parts = <String>[
              if (name.isNotEmpty) name,
              if (cls.isNotEmpty) cls,
              if (roll != null) 'Roll $roll',
            ];
            return parts.join(' · ');
          }).where((s) => s.isNotEmpty).toList();
        } catch (e, st) { AppLogger.e('ProfileScreen', 'Best-effort load failed', e, st); }
      }

      // School name (best-effort).
      final sid = AuthService.currentSchoolId;
      try {
        final s = await FirebaseFirestore.instance
            .collection('schools').doc(sid)
            .collection('settings').doc('school').get();
        _schoolName = (s.data()?['name'] as String?)?.trim() ?? '';
      } catch (e, st) { AppLogger.e('ProfileScreen', 'Best-effort load failed', e, st); }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _name.trim().isNotEmpty ? _name.trim() : _email;
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    final roleLabel = context.trRole(_role);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(context.tr('myProfile'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // ── Header card ───────────────────────────────────────────
                Container(
                  width: double.infinity,
                  color: AppTheme.primaryDark,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  child: Column(children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: Colors.white,
                      child: Text(initial,
                          style: const TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryDark)),
                    ),
                    const SizedBox(height: 12),
                    Text(displayName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(roleLabel,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 12)),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),

                // ── Detail rows ───────────────────────────────────────────
                _section(context.tr('account')),
                _row(Icons.email_outlined, context.tr('email'), _email),
                if (_phone.isNotEmpty)
                  _row(Icons.phone_outlined, context.tr('phone'), _phone),
                if (_schoolName.isNotEmpty)
                  _row(Icons.school_outlined, context.tr('school'), _schoolName),
                if (_status.isNotEmpty)
                  _row(Icons.verified_user_outlined, context.tr('status'),
                      _statusLabel(context)),

                if (_classes.isNotEmpty) ...[
                  _section(context.tr('assignedClasses')),
                  _chips(_classes),
                ],

                if (_role == 'guardian' && _children.isNotEmpty) ...[
                  _section(context.tr('children')),
                  ..._children.map((c) =>
                      _row(Icons.child_care_outlined, '', c)),
                ],

                // ── Preferences: language ─────────────────────────────────
                _section(context.tr('preferences')),
                _languageRow(context),

                const SizedBox(height: 24),

                // ── Logout Button ─────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _logout,
                    icon: const Icon(Icons.logout),
                    label: Text(
                      context.tr('logOut'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
    );
  }

  String _statusLabel(BuildContext context) {
    switch (_status.toLowerCase()) {
      case 'active':  return context.tr('statusActive');
      case 'pending': return context.tr('statusPending');
      default:        return _status[0].toUpperCase() + _status.substring(1);
    }
  }

  /// Tappable row showing the current language; opens a picker.
  Widget _languageRow(BuildContext context) {
    final provider = context.watch<LocaleProvider>();
    final current = LocaleProvider.supported[provider.code] ?? 'English';
    return InkWell(
      onTap: () => _pickLanguage(context),
      child: Container(
        color: AppTheme.surface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          const Icon(Icons.language_outlined, size: 20, color: AppTheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.tr('language'),
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textSecondary)),
              Text(current,
                  style: const TextStyle(
                      fontSize: 15, color: AppTheme.textPrimary)),
            ]),
          ),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ]),
      ),
    );
  }

  Future<void> _pickLanguage(BuildContext context) async {
    final provider = context.read<LocaleProvider>();
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(context.tr('chooseLanguage'),
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          ...LocaleProvider.supported.entries.map((e) => RadioListTile<String>(
                value: e.key,
                groupValue: provider.code,
                activeColor: AppTheme.primary,
                title: Text(e.value),
                onChanged: (v) => Navigator.pop(ctx, v),
              )),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (picked != null) await provider.setLanguage(picked);
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Text(title,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey,
                letterSpacing: 0.8)),
      );

  Widget _row(IconData icon, String label, String value) => Container(
        color: AppTheme.surface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        margin: const EdgeInsets.only(bottom: 1),
        child: Row(children: [
          Icon(icon, size: 20, color: AppTheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (label.isNotEmpty)
                Text(label,
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textSecondary)),
              Text(value,
                  style: const TextStyle(
                      fontSize: 15, color: AppTheme.textPrimary)),
            ]),
          ),
        ]),
      );

  Widget _chips(List<String> items) => Container(
        color: AppTheme.surface,
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items
              .map((c) => Chip(
                    label: Text(c, style: const TextStyle(fontSize: 12)),
                    backgroundColor: AppTheme.primaryLight.withValues(alpha: 0.4),
                    side: BorderSide.none,
                  ))
              .toList(),
        ),
      );
}

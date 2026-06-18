import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/app_strings.dart';
import '../../theme.dart';
import '../../shared/widgets/email_text_form_field.dart';
import '../../services/auth_service.dart';
import '../../services/timetable_service.dart';
import '../../shared/utils/app_logger.dart';
import '../../shared/utils/role_guard.dart';
import '../auth/role_selection_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _service    = TimetableService.instance;
  final _schoolNameCtrl = TextEditingController();
  final _schoolAddressCtrl = TextEditingController();
  final _primaryOwnerEmailCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  static const _role = 'owner';

  List<Map<String, dynamic>> _users = [];
  Map<String, Map<String, dynamic>> _schoolsMap = {};
  bool _loading  = true;
  bool _saving   = false;
  String _searchQuery = '';
  String _filterStatus = 'all'; // 'all', 'active', 'suspended'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      RoleGuard.verify(context, ['admin']);
    });
    _load();
  }

  @override
  void dispose() {
    _schoolNameCtrl.dispose();
    _schoolAddressCtrl.dispose();
    _primaryOwnerEmailCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Data ───────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await _service.cleanOrphanedSchools();
      final owners = await _service.getAllowedOwners();
      
      final schoolsSnap = await FirebaseFirestore.instance.collection('schools').get();
      final Map<String, Map<String, dynamic>> schools = {};
      for (final doc in schoolsSnap.docs) {
        schools[doc.id] = doc.data();
      }

      if (!mounted) return;
      setState(() {
        _users   = owners;
        _schoolsMap = schools;
        _loading = false;
      });
    } catch (e) {
      AppLogger.e('AdminScreen', '_load failed: $e', e);
      if (!mounted) return;
      setState(() {
        _users   = [];
        _schoolsMap = {};
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${context.tr('couldNotLoadUsers')} $e'),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 8),
      ));
    }
  }

  // ── Filtered Schools ───────────────────────────────────────────────────────

  List<String> get _filteredSchools {
    final query = _searchQuery;
    
    return _schoolsMap.keys.where((schoolId) {
      final school = _schoolsMap[schoolId];
      final name = (school?['name'] as String? ?? '').toLowerCase();
      final brandName = (school?['brandName'] as String? ?? '').toLowerCase();
      
      final schoolOwners = _users
          .where((u) => u['schoolId'] == schoolId)
          .map((u) => (u['email'] as String).toLowerCase())
          .toList();
          
      final matchesSearch = schoolId.toLowerCase().contains(query) ||
          name.contains(query) ||
          brandName.contains(query) ||
          schoolOwners.any((email) => email.contains(query));
          
      if (!matchesSearch) return false;
      
      final isActive = school?['isActive'] as bool? ?? true;
      if (_filterStatus == 'active') {
        return isActive == true;
      } else if (_filterStatus == 'suspended') {
        return isActive == false;
      }
      
      return true;
    }).toList();
  }

  // ── Create School System ───────────────────────────────────────────────────

  Future<void> _createSchoolSystem() async {
    final name = _schoolNameCtrl.text.trim();
    final address = _schoolAddressCtrl.text.trim();
    final email = _primaryOwnerEmailCtrl.text.trim().toLowerCase();

    if (name.isEmpty) {
      _snack(context.tr('enterSchoolNameError'));
      return;
    }
    if (address.isEmpty) {
      _snack(context.tr('enterSchoolAddressError'));
      return;
    }
    if (email.isEmpty ||
        !RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(email)) {
      _snack(context.tr('enterValidEmailAddress'));
      return;
    }
    if (_users.any((u) => u['email'] == email)) {
      _snack(context.tr('emailAlreadyRegisteredOwner'));
      return;
    }

    final schoolExists = _schoolsMap.values.any((s) =>
        (s['name'] as String? ?? '').trim().toLowerCase() == name.toLowerCase() &&
        (s['address'] as String? ?? '').trim().toLowerCase() == address.toLowerCase() &&
        (s['email'] as String? ?? '').trim().toLowerCase() == email.toLowerCase());
    if (schoolExists) {
      _snack(context.tr('schoolSystemExistsError'));
      return;
    }

    setState(() => _saving = true);
    String? createdSchoolId;
    try {
      final schoolId =
          'school_${DateTime.now().millisecondsSinceEpoch}_${email.hashCode.abs()}';
      
      await FirebaseFirestore.instance.collection('schools').doc(schoolId).set({
        'name': name,
        'address': address,
        'contactNumber': '',
        'email': email,
        'logoUrl': '',
        'createdAt': FieldValue.serverTimestamp(),
        'subscriptionPlan': 'free',
        'isActive': true,
        'brandName': name,
      });
      createdSchoolId = schoolId;

      await _service.addAllowedUser(email, '', _role, schoolId: schoolId);

      _schoolNameCtrl.clear();
      _schoolAddressCtrl.clear();
      _primaryOwnerEmailCtrl.clear();

      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr('createdSchoolSystemSuccess').replaceAll('{email}', email)),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 3),
      ));
    } catch (e) {
      AppLogger.e('AdminScreen', '_createSchoolSystem failed: $e', e);
      if (createdSchoolId != null) {
        try {
          await FirebaseFirestore.instance.collection('schools').doc(createdSchoolId).delete();
        } catch (rollbackError) {
          AppLogger.e('AdminScreen', 'Rollback failed: $rollbackError', rollbackError);
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr('couldNotCreateSchoolSystem').replaceAll('{error}', e.toString())),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 8),
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Multi-Owner Management ─────────────────────────────────────────────────

  Future<void> _addOwnerToSchool(String schoolId) async {
    final emailCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(context.tr('addSchoolOwner')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('enterAdditionalOwnerEmail')),
            const SizedBox(height: 12),
            EmailTextFormField(
              controller: emailCtrl,
              decoration: InputDecoration(
                hintText: 'owner2@example.com',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
            child: Text(context.tr('addSchoolOwner')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;
    final email = emailCtrl.text.trim().toLowerCase();
    if (email.isEmpty || !RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(email)) {
      _snack(context.tr('enterValidEmailAddress'));
      return;
    }
    if (_users.any((u) => u['email'] == email)) {
      _snack(context.tr('emailAlreadyRegisteredOwner'));
      return;
    }

    setState(() => _loading = true);
    try {
      await _service.addAllowedUser(email, '', _role, schoolId: schoolId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr('addedOwnerSuccess').replaceAll('{email}', email)),
        backgroundColor: Colors.green.shade700,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr('failedToAddOwner').replaceAll('{error}', e.toString())),
        backgroundColor: Colors.red.shade700,
      ));
    }
    _load();
  }

  Future<void> _removeOwnerEmail(String email) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(context.tr('removeOwnerAccessQ')),
        content: Text(context.tr('removeOwnerAccessConfirm').replaceAll('{email}', email)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(context.tr('revokeAccess')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _loading = true);
    try {
      await _service.deleteAccountFully(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr('revokedOwnerAccessSuccess').replaceAll('{email}', email)),
        backgroundColor: Colors.green.shade700,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr('failedToRevokeAccess').replaceAll('{error}', e.toString())),
        backgroundColor: Colors.red.shade700,
      ));
    }
    _load();
  }

  // ── Plan & Suspension Management ──────────────────────────────────────────

  Future<void> _changePlan(String schoolId, String currentPlan) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(context.tr('changeSubscriptionPlan')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['free', 'basic', 'pro', 'enterprise'].map((plan) {
            final isCurrent = plan == currentPlan;
            return ListTile(
              leading: Icon(
                Icons.stars_rounded,
                color: _getPlanColor(plan),
              ),
              title: Text(
                plan.toUpperCase(),
                style: TextStyle(
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                  color: isCurrent ? AppTheme.primary : AppTheme.textPrimary,
                ),
              ),
              trailing: isCurrent
                  ? const Icon(Icons.check_circle, color: AppTheme.primary)
                  : null,
              onTap: () => Navigator.pop(ctx, plan),
            );
          }).toList(),
        ),
      ),
    );
    
    if (selected == null || selected == currentPlan) return;
    if (!mounted) return;
    
    setState(() => _loading = true);
    try {
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .update({'subscriptionPlan': selected});
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr('updatedPlanSuccess').replaceAll('{plan}', selected.toUpperCase())),
        backgroundColor: Colors.green.shade700,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr('failedToUpdatePlan').replaceAll('{error}', e.toString())),
        backgroundColor: Colors.red.shade700,
      ));
    }
    _load();
  }

  Future<void> _toggleSuspension(String schoolId, bool currentActive) async {
    final nextActive = !currentActive;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(nextActive ? context.tr('activateSchoolSystemQ') : context.tr('suspendSchoolSystemQ')),
        content: Text(
          nextActive
              ? context.tr('restoreAccessExplanation')
              : context.tr('suspendWarningExplanation'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: nextActive ? Colors.green : Colors.red,
            ),
            child: Text(nextActive ? context.tr('activate') : context.tr('suspend')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _loading = true);
    try {
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .update({'isActive': nextActive});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(nextActive ? context.tr('schoolSystemActivated') : context.tr('schoolSystemSuspended')),
        backgroundColor: nextActive ? Colors.green.shade700 : Colors.orange.shade800,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr('failedToUpdateStatus').replaceAll('{error}', e.toString())),
        backgroundColor: Colors.red.shade700,
      ));
    }
    _load();
  }

  Future<void> _deleteSchoolSystem(String schoolId, String schoolName) async {
    final confirmCtrl = TextEditingController();
    final schoolOwners = _users
        .where((u) => u['schoolId'] == schoolId)
        .map((u) => u['email'] as String)
        .toList();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final matches =
              confirmCtrl.text.trim().toLowerCase() == schoolName.toLowerCase();
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(context.tr('deleteSchoolSystemQ')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('deleteSchoolSystemWarning').replaceAll('{name}', schoolName).replaceAll('{owners}', schoolOwners.join(", ")),
                  style: const TextStyle(fontSize: 13.5, color: Colors.red),
                ),
                const SizedBox(height: 16),
                Text(context.tr('typeExactSchoolName'),
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmCtrl,
                  autofocus: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    hintText: schoolName,
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onChanged: (_) => setLocal(() {}),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(context.tr('cancel'))),
              TextButton(
                onPressed: matches ? () => Navigator.pop(ctx, true) : null,
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: Text(context.tr('deletePermanently')),
              ),
            ],
          );
        },
      ),
    );
    Future.delayed(const Duration(milliseconds: 350), confirmCtrl.dispose);
    if (ok != true) return;
    if (!mounted) return;

    setState(() => _loading = true);
    try {
      for (final email in schoolOwners) {
        await _service.deleteAccountFully(email);
      }
      await FirebaseFirestore.instance.collection('schools').doc(schoolId).delete();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr('deletedSchoolSystemSuccess').replaceAll('{name}', schoolName)),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 5),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr('couldNotDeleteSchoolSystem').replaceAll('{error}', e.toString())),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 8),
      ));
    }
    _load();
  }

  Future<void> _deleteAllSchools() async {
    final confirmCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final matches = confirmCtrl.text.trim().toLowerCase() == 'delete all';
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(context.tr('deleteAllSchoolsQ')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('deleteAllSchoolsWarning'),
                  style: const TextStyle(fontSize: 13.5, color: Colors.red),
                ),
                const SizedBox(height: 16),
                Text(context.tr('typeDeleteAllToConfirm'),
                     style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmCtrl,
                  autofocus: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    hintText: 'delete all',
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onChanged: (_) => setLocal(() {}),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(context.tr('cancel'))),
              TextButton(
                onPressed: matches ? () => Navigator.pop(ctx, true) : null,
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: Text(context.tr('deleteAllPermanently')),
              ),
            ],
          );
        },
      ),
    );
    Future.delayed(const Duration(milliseconds: 350), confirmCtrl.dispose);
    if (ok != true) return;
    if (!mounted) return;

    setState(() => _loading = true);
    try {
      final allSchoolIds = List<String>.from(_schoolsMap.keys);
      for (final schoolId in allSchoolIds) {
        final schoolOwners = _users
            .where((u) => u['schoolId'] == schoolId)
            .map((u) => u['email'] as String)
            .toList();
        for (final email in schoolOwners) {
          try {
            await _service.deleteAccountFully(email);
          } catch (e) {
            AppLogger.e('AdminScreen', 'Failed to delete owner account $email: $e');
          }
        }
        await FirebaseFirestore.instance.collection('schools').doc(schoolId).delete();
      }

      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr('deletedAllSchoolsSuccess')),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      AppLogger.e('AdminScreen', '_deleteAllSchools failed: $e', e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr('failedToDeleteAllSchools').replaceAll('{error}', e.toString())),
        backgroundColor: Colors.red,
      ));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Color _getPlanColor(String plan) {
    switch (plan.toLowerCase().trim()) {
      case 'free':
        return Colors.grey.shade600;
      case 'basic':
        return Colors.blue.shade600;
      case 'pro':
        return Colors.indigo.shade600;
      case 'enterprise':
        return Colors.teal.shade600;
      default:
        return Colors.grey.shade600;
    }
  }

  // ── Logout ───────────────────────────────────────────────────────────────────

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
              child: Text(context.tr('cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            child: Text(context.tr('logOut')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AuthService().clearSession();
    if (!mounted) return;
    Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => const RoleSelectionScreen()));
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _snack(String msg) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));

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
    final double statusBarHeight = MediaQuery.of(context).padding.top;
    final double headerHeight = 140.0 + statusBarHeight;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: RefreshIndicator(
              onRefresh: _load,
              color: AppTheme.primary,
              displacement: headerHeight + 10,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(16, headerHeight - 15, 16, 28),
                children: [
                  _buildAddCard(),
                  const SizedBox(height: 16),
                  _buildInfoBanner(),
                  const SizedBox(height: 22),
                  _buildSearchAndFilter(),
                  const SizedBox(height: 16),
                  Row(children: [
                    _fieldLabel(context.tr('registeredSchoolSystems')),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('${_filteredSchools.length}',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary)),
                    ),
                    const Spacer(),
                    if (_schoolsMap.isNotEmpty)
                      TextButton.icon(
                        onPressed: _deleteAllSchools,
                        icon: const Icon(Icons.delete_sweep_outlined, color: AppTheme.danger, size: 16),
                        label: Text(context.tr('deleteAll'), style: const TextStyle(color: AppTheme.danger, fontSize: 11.5, fontWeight: FontWeight.bold)),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                  ]),
                  const SizedBox(height: 10),
                  _buildUsersSection(),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _AdminHero(
              onBack: () => Navigator.maybePop(context),
              onLogout: _logout,
            ),
          ),
        ],
      ),
    );
  }

  // ── Search & Filter ────────────────────────────────────────────────────────

  Widget _buildSearchAndFilter() {
    return Column(
      children: [
        TextField(
          controller: _searchCtrl,
          decoration: InputDecoration(
            hintText: context.tr('searchTenantsHint'),
            prefixIcon: const Icon(Icons.search, color: AppTheme.textSecondary),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, color: AppTheme.textSecondary),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() {
                        _searchQuery = '';
                      });
                    },
                  )
                : null,
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
            ),
          ),
          onChanged: (val) {
            setState(() {
              _searchQuery = val.trim().toLowerCase();
            });
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _filterChip('all', context.tr('allTenants')),
            const SizedBox(width: 8),
            _filterChip('active', context.tr('activeStatus')),
            const SizedBox(width: 8),
            _filterChip('suspended', context.tr('suspendedStatus')),
          ],
        ),
      ],
    );
  }

  Widget _filterChip(String status, String label) {
    final isSelected = _filterStatus == status;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : AppTheme.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      selected: isSelected,
      selectedColor: AppTheme.primary,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? AppTheme.primary : Colors.grey.shade300,
        ),
      ),
      onSelected: (val) {
        if (val) {
          setState(() {
            _filterStatus = status;
          });
        }
      },
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
              child: const Icon(Icons.add_business_outlined,
                  color: AppTheme.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Text(context.tr('createSchoolSystem'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 18),

          // School Name
          _fieldLabel(context.tr('schoolNameCaps')),
          const SizedBox(height: 6),
          TextField(
            controller: _schoolNameCtrl,
            enabled: !_saving,
            decoration: InputDecoration(
              hintText: context.tr('schoolNameHint'),
              hintStyle: TextStyle(color: Colors.grey.shade500),
              prefixIcon: const Icon(Icons.school_outlined,
                  color: AppTheme.primary, size: 20),
              filled: true,
              fillColor: _saving ? Colors.grey.shade100 : Colors.white,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade400)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade400)),
              disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppTheme.primary, width: 2.0)),
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 12),

          // School Address
          _fieldLabel(context.tr('schoolAddressCaps')),
          const SizedBox(height: 6),
          TextField(
            controller: _schoolAddressCtrl,
            enabled: !_saving,
            decoration: InputDecoration(
              hintText: context.tr('schoolAddressHint'),
              hintStyle: TextStyle(color: Colors.grey.shade500),
              prefixIcon: const Icon(Icons.location_on_outlined,
                  color: AppTheme.primary, size: 20),
              filled: true,
              fillColor: _saving ? Colors.grey.shade100 : Colors.white,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade400)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade400)),
              disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppTheme.primary, width: 2.0)),
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 12),

          // Owner Email
          _fieldLabel(context.tr('primaryOwnerEmailCaps')),
          const SizedBox(height: 6),
          EmailTextFormField(
            controller: _primaryOwnerEmailCtrl,
            enabled: !_saving,
            decoration: InputDecoration(
              hintText: context.tr('emailAddressHint'),
              hintStyle: TextStyle(color: Colors.grey.shade500),
              prefixIcon: const Icon(Icons.email_outlined,
                  color: AppTheme.primary, size: 20),
              filled: true,
              fillColor: _saving ? Colors.grey.shade100 : Colors.white,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade400)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade400)),
              disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppTheme.primary, width: 2.0)),
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
                context.tr('passwordSetupLinkEmailed'),
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
              ),
            ),
          ]),
          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _createSchoolSystem,
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
              label: Text(_saving ? context.tr('sendingEllipsis') : context.tr('createAndSendInvite'),
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
            context.tr('adminCreateOwnersNote'),
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
    final filtered = _filteredSchools;
    if (filtered.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 44),
        alignment: Alignment.center,
        child: Column(children: [
          Icon(Icons.business_outlined, size: 54, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            _searchQuery.isNotEmpty || _filterStatus != 'all'
                ? context.tr('noMatchingSchools')
                : context.tr('noSchoolsRegistered'),
            style: TextStyle(fontSize: 14.5, color: Colors.grey.shade400),
          ),
        ]),
      );
    }
    return Column(children: [for (final sid in filtered) _buildSchoolCard(sid)]);
  }

  Widget _buildSchoolCard(String schoolId) {
    final schoolDoc = _schoolsMap[schoolId];
    final schoolName = schoolDoc?['name'] as String? ?? '';
    final brandName  = schoolDoc?['brandName'] as String? ?? '';
    final plan       = schoolDoc?['subscriptionPlan'] as String? ?? 'free';
    final isActive   = schoolDoc?['isActive'] as bool? ?? true;
    final createdAt  = schoolDoc?['createdAt'] as Timestamp?;

    final formattedDate = createdAt != null
        ? '${createdAt.toDate().day}/${createdAt.toDate().month}/${createdAt.toDate().year}'
        : context.tr('unknownLabel');

    final schoolOwners = _users
        .where((u) => u['schoolId'] == schoolId)
        .map((u) => u['email'] as String)
        .toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      schoolName.isNotEmpty ? schoolName : context.tr('setupPending'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        fontStyle: schoolName.isNotEmpty ? FontStyle.normal : FontStyle.italic,
                        color: schoolName.isNotEmpty ? AppTheme.textPrimary : Colors.grey.shade500,
                      ),
                    ),
                    if (brandName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        brandName,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _getPlanColor(plan).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _getPlanColor(plan).withValues(alpha: 0.3)),
                ),
                child: Text(
                  plan.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: _getPlanColor(plan),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isActive ? AppTheme.success : AppTheme.danger).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: (isActive ? AppTheme.success : AppTheme.danger).withValues(alpha: 0.3)),
                ),
                child: Text(
                  isActive ? context.tr('statusActive').toUpperCase() : context.tr('suspendedStatus').toUpperCase(),
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: isActive ? AppTheme.success : AppTheme.danger,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 20, thickness: 0.8),
          
          _fieldLabel(context.tr('registeredOwnersCaps')),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final email in schoolOwners)
                Chip(
                  label: Text(email, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500)),
                  backgroundColor: AppTheme.background,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  deleteIcon: const Icon(Icons.cancel_outlined, size: 14, color: AppTheme.danger),
                  onDeleted: schoolOwners.length > 1
                      ? () => _removeOwnerEmail(email)
                      : null,
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 14, color: AppTheme.primary),
                label: Text(context.tr('addOwner'), style: const TextStyle(fontSize: 11.5, color: AppTheme.primary, fontWeight: FontWeight.bold)),
                backgroundColor: AppTheme.primary.withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: AppTheme.primaryLight),
                ),
                onPressed: () => _addOwnerToSchool(schoolId),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          InkWell(
            onTap: () {
              if (schoolId.isNotEmpty) {
                Clipboard.setData(ClipboardData(text: schoolId));
                _snack(context.tr('schoolIdCopied'));
              }
            },
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(Icons.vpn_key_outlined, size: 14, color: Colors.grey.shade400),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${context.tr('idLabel')}: $schoolId',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: Colors.grey.shade600,
                        decoration: TextDecoration.underline,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.copy, size: 12, color: Colors.grey.shade400),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey.shade400),
              const SizedBox(width: 6),
              Text(
                context.tr('registeredLabel').replaceAll('{date}', formattedDate),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          const Divider(height: 20, thickness: 0.8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: schoolId.isNotEmpty ? () => _changePlan(schoolId, plan) : null,
                icon: const Icon(Icons.tune_outlined, size: 14),
                label: Text(context.tr('planButton'), style: const TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: schoolId.isNotEmpty ? () => _toggleSuspension(schoolId, isActive) : null,
                icon: Icon(isActive ? Icons.block_outlined : Icons.check_circle_outline, size: 14),
                label: Text(isActive ? context.tr('suspendButton') : context.tr('activateButton'), style: const TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isActive ? AppTheme.danger : AppTheme.success,
                  side: BorderSide(color: isActive ? AppTheme.danger : AppTheme.success),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 18),
                onPressed: () => _deleteSchoolSystem(schoolId, schoolName),
                tooltip: context.tr('deleteSchoolSystemTooltip'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AdminHero extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onLogout;
  const _AdminHero({required this.onBack, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: _AdminWaveClipper(),
      child: Container(
        decoration: const BoxDecoration(
          color: AppTheme.primaryDark,
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
                  Text(context.tr('adminPanel'),
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.1)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: onLogout,
                    icon: const Icon(Icons.logout, color: Colors.white, size: 18),
                    label: Text(context.tr('logOut'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8)),
                  ),
                ]),
                Padding(
                  padding: const EdgeInsets.only(left: 14, top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.tr('manageAccess'),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(context.tr('manageAccessSubtitle'),
                          style: const TextStyle(
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
    path.lineTo(0, size.height - 30);
    path.quadraticBezierTo(
        size.width * 0.25, size.height, size.width * 0.5, size.height - 20);
    path.quadraticBezierTo(
        size.width * 0.75, size.height - 40, size.width, size.height - 20);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_AdminWaveClipper old) => false;
}

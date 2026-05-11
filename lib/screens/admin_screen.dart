import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../services/timetable_service.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _service   = TimetableService();
  final _emailCtrl = TextEditingController();
  final _rollCtrl  = TextEditingController();

  String  _selectedRole           = 'teacher';
  String? _selectedStudentClass;
  List<String> _selectedAssignedClasses = [];
  List<String>              _availableClasses = [];
  List<Map<String, dynamic>> _users           = [];
  bool _loading  = true;
  bool _saving   = false;

  static const _roles = [
    {'value': 'teacher',     'label': 'Teacher',     'icon': Icons.person_outline},
    {'value': 'coordinator', 'label': 'Coordinator', 'icon': Icons.admin_panel_settings_outlined},
    {'value': 'principal',   'label': 'Principal',   'icon': Icons.business_outlined},
    {'value': 'guardian',    'label': 'Guardian',    'icon': Icons.family_restroom_outlined},
  ];

  // Role → accent colour (all purple-family now, semantic distinction by shade/hue)
  static const _roleColors = {
    'teacher':     AppTheme.primary,
    'coordinator': AppTheme.primaryMid,
    'principal':   AppTheme.primaryDark,
    'guardian':    AppTheme.accent,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _rollCtrl.dispose();
    super.dispose();
  }

  // ── Data ───────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _service.getAllowedUsers(),
      _service.getSettings(),
    ]);
    if (!mounted) return;
    final users    = results[0] as List<Map<String, dynamic>>;
    final settings = results[1] as Map<String, dynamic>;
    setState(() {
      _users            = users;
      _availableClasses = List<String>.from(settings['classes'] as List? ?? []);
      _loading          = false;
    });
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

    int?    studentRoll;
    String? studentClass;
    if (_selectedRole == 'guardian') {
      if (_selectedStudentClass == null) {
        _snack("Select the student's class");
        return;
      }
      final rollText = _rollCtrl.text.trim();
      studentRoll = int.tryParse(rollText);
      if (studentRoll == null || studentRoll < 1 || studentRoll > 999) {
        _snack('Roll number must be between 1 and 999');
        return;
      }
      studentClass = _selectedStudentClass;
    }

    setState(() => _saving = true);
    await _service.addAllowedUser(
      email, null, _selectedRole,
      studentClass:    studentClass,
      studentRoll:     studentRoll,
      assignedClasses: (_selectedRole == 'coordinator' ||
                        _selectedRole == 'principal')
          ? _selectedAssignedClasses
          : null,
    );
    _emailCtrl.clear();
    _rollCtrl.clear();
    setState(() {
      _selectedStudentClass    = null;
      _selectedAssignedClasses = [];
      _saving                  = false;
    });
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$email added as $_selectedRole'),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  // ── Edit ───────────────────────────────────────────────────────────────────

  Future<void> _edit(Map<String, dynamic> user) async {
    final email        = user['email'] as String;
    String editRole    = user['role']  as String;
    String editClass   = (user['studentClass'] as String?) ?? '';
    int    editRoll    = (user['studentRoll']  as int?)    ?? 0;
    List<String> editAssigned =
        List<String>.from((user['assignedClasses'] as List?) ?? []);

    final rollCtrl  = TextEditingController(text: editRoll > 0 ? '$editRoll' : '');
    String? selClass = editClass.isNotEmpty ? editClass : null;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final roleColor = _roleColors[editRole] ?? AppTheme.primary;
            return Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        width: 36, height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Header
                    Row(children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: roleColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(_roleIcon(editRole),
                            color: roleColor, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Edit User',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)),
                            Text(email,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade500),
                                overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ]),
                    const SizedBox(height: 20),

                    // Role selector chips
                    Text('ROLE',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade500,
                            letterSpacing: 0.8)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: _roles.map((r) {
                        final val  = r['value'] as String;
                        final lbl  = r['label'] as String;
                        final ico  = r['icon']  as IconData;
                        final sel  = val == editRole;
                        final rCol = _roleColors[val] ?? AppTheme.primary;
                        return GestureDetector(
                          onTap: () => setLocal(() {
                            editRole = val;
                            if (val != 'guardian') {
                              selClass = null;
                              rollCtrl.clear();
                            }
                            if (val != 'coordinator' && val != 'principal') {
                              editAssigned = [];
                            }
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: sel
                                  ? rCol.withOpacity(0.12)
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: sel
                                    ? rCol
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min,
                                children: [
                              Icon(ico,
                                  size: 14,
                                  color: sel
                                      ? rCol
                                      : Colors.grey.shade500),
                              const SizedBox(width: 5),
                              Text(lbl,
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: sel
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: sel
                                          ? rCol
                                          : Colors.grey.shade600)),
                            ]),
                          ),
                        );
                      }).toList(),
                    ),

                    // Coordinator / Principal — assigned classes
                    if (editRole == 'coordinator' ||
                        editRole == 'principal') ...[
                      const SizedBox(height: 16),
                      Text('ASSIGNED CLASSES',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade500,
                              letterSpacing: 0.8)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _availableClasses.map((cls) {
                          final sel = editAssigned.contains(cls);
                          final rCol = _roleColors[editRole] ?? AppTheme.primary;
                          return GestureDetector(
                            onTap: () => setLocal(() {
                              sel
                                  ? editAssigned.remove(cls)
                                  : editAssigned.add(cls);
                            }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: sel
                                    ? rCol.withOpacity(0.12)
                                    : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: sel
                                        ? rCol
                                        : Colors.grey.shade300),
                              ),
                              child: Text(cls,
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: sel
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: sel
                                          ? rCol
                                          : Colors.grey.shade600)),
                            ),
                          );
                        }).toList(),
                      ),
                    ],

                    // Guardian extras
                    if (editRole == 'guardian') ...[
                      const SizedBox(height: 16),
                      Text("STUDENT'S CLASS & ROLL",
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade500,
                              letterSpacing: 0.8)),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<String>(
                            value: selClass,
                            decoration: InputDecoration(
                              labelText: 'Class',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                    color: AppTheme.primary, width: 1.5),
                              ),
                            ),
                            hint: const Text('Select class'),
                            items: _availableClasses
                                .map((c) => DropdownMenuItem(
                                      value: c, child: Text(c)))
                                .toList(),
                            onChanged: (v) =>
                                setLocal(() => selClass = v),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: rollCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            maxLength: 3,
                            maxLengthEnforcement: MaxLengthEnforcement.enforced,
                            decoration: InputDecoration(
                              labelText: 'Roll No.',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                    color: AppTheme.primary, width: 1.5),
                              ),
                              counterText: '',
                            ),
                          ),
                        ),
                      ]),
                    ],

                    // Save button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          // Validate guardian fields
                          if (editRole == 'guardian') {
                            if (selClass == null) {
                              _snack("Select the student's class");
                              return;
                            }
                            final roll =
                                int.tryParse(rollCtrl.text.trim());
                            if (roll == null || roll < 1 || roll > 999) {
                              _snack('Roll number must be between 1 and 999');
                              return;
                            }
                          }
                          Navigator.pop(ctx);
                          final roll = int.tryParse(rollCtrl.text.trim());
                          await _service.updateAllowedUser(
                            email,
                            role:            editRole,
                            studentClass:    editRole == 'guardian' ? selClass : null,
                            studentRoll:     editRole == 'guardian' ? roll     : null,
                            assignedClasses: (editRole == 'coordinator' ||
                                              editRole == 'principal')
                                ? editAssigned
                                : null,
                          );
                          await _load();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('$email updated'),
                                backgroundColor: Colors.green.shade700,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                        child: const Text('Save Changes',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    rollCtrl.dispose();
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
      default:            return Icons.person_outline;
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Admin Panel',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text('Manage login access',
                style: TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
      ),
      body: Column(children: [

        // ── Add user form ─────────────────────────────────────────────────
        Container(
          color: AppTheme.primary,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(children: [
            // Role dropdown
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedRole,
                  isExpanded: true,
                  dropdownColor: AppTheme.primaryDark,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 14),
                  iconEnabledColor: Colors.white70,
                  items: _roles.map((r) {
                    return DropdownMenuItem<String>(
                      value: r['value'] as String,
                      child: Row(children: [
                        Icon(r['icon'] as IconData,
                            color: Colors.white70, size: 18),
                        const SizedBox(width: 10),
                        Text(r['label'] as String,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600)),
                      ]),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedRole = v);
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Guardian extras
            if (_selectedRole == 'guardian') ...[
              Row(children: [
                Expanded(
                  flex: 3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedStudentClass,
                        isExpanded: true,
                        hint: const Text("Child's class",
                            style: TextStyle(
                                color: Colors.white60, fontSize: 14)),
                        dropdownColor: AppTheme.primaryDark,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14),
                        iconEnabledColor: Colors.white70,
                        items: _availableClasses
                            .map((c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(c,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight:
                                              FontWeight.w600)),
                                ))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedStudentClass = v),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _rollCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    maxLength: 3,
                    maxLengthEnforcement: MaxLengthEnforcement.enforced,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Roll no.',
                      hintStyle:
                          const TextStyle(color: Colors.white60),
                      prefixIcon: const Icon(Icons.tag,
                          color: Colors.white70, size: 18),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.15),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none),
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 12),
                      counterText: '',
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
            ],

            // Coordinator / Principal — assigned classes
            if (_selectedRole == 'coordinator' ||
                _selectedRole == 'principal') ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('ASSIGNED CLASSES (tap to toggle)',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.7)),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _availableClasses.map((cls) {
                  final sel = _selectedAssignedClasses.contains(cls);
                  return GestureDetector(
                    onTap: () => setState(() {
                      sel
                          ? _selectedAssignedClasses.remove(cls)
                          : _selectedAssignedClasses.add(cls);
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: sel
                            ? Colors.white
                            : Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: sel
                                ? Colors.white
                                : Colors.white30),
                      ),
                      child: Text(cls,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: sel
                                  ? AppTheme.primaryDark
                                  : Colors.white)),
                    ),
                  );
                }).toList(),
              ),
              if (_availableClasses.isEmpty)
                Text('No classes configured yet',
                    style: TextStyle(
                        color: Colors.white60, fontSize: 12)),
              const SizedBox(height: 8),
            ],

            // Email field + Add button
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Email address…',
                    hintStyle:
                        const TextStyle(color: Colors.white60),
                    prefixIcon: const Icon(Icons.email_outlined,
                        color: Colors.white70),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.15),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _saving ? null : _add,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.primary))
                    : const Text('Add',
                        style: TextStyle(
                            fontWeight: FontWeight.bold)),
              ),
            ]),
          ]),
        ),

        // ── Info banner ───────────────────────────────────────────────────
        Container(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Row(children: [
            Icon(Icons.info_outline,
                color: Colors.orange.shade700, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Only registered emails can sign in. '
                'Tap the pencil icon on any user to edit their role or configuration.',
                style: TextStyle(
                    fontSize: 12, color: Colors.orange.shade800),
              ),
            ),
          ]),
        ),

        // ── Users list ────────────────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _users.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.person_add_alt_1_outlined,
                              size: 56, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          Text('No users registered yet',
                              style: TextStyle(
                                  fontSize: 15,
                                  color: Colors.grey.shade400)),
                          const SizedBox(height: 4),
                          Text('Add email addresses above',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade400)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: AppTheme.primary,
                      child: ListView.separated(
                        physics:
                            const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(
                            12, 0, 12, 20),
                        itemCount: _users.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 72),
                        itemBuilder: (_, i) {
                          final user  = _users[i];
                          final email = user['email'] as String;
                          final role  = user['role']  as String;
                          final cls   = user['studentClass'] as String;
                          final roll  = user['studentRoll']  as int;
                          final color = _roleColor(role);

                          return Container(
                            color: Colors.white,
                            child: ListTile(
                              contentPadding:
                                  const EdgeInsets.fromLTRB(
                                      16, 8, 6, 8),
                              leading: Container(
                                width: 44, height: 44,
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.1),
                                  borderRadius:
                                      BorderRadius.circular(12),
                                ),
                                child: Icon(_roleIcon(role),
                                    color: color, size: 22),
                              ),
                              title: Text(email,
                                  style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 2),
                                  // Role badge
                                  Container(
                                    padding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3),
                                    decoration: BoxDecoration(
                                      color:
                                          color.withOpacity(0.1),
                                      borderRadius:
                                          BorderRadius.circular(20),
                                      border: Border.all(
                                          color: color
                                              .withOpacity(0.3)),
                                    ),
                                    child: Text(
                                      role[0].toUpperCase() +
                                          role.substring(1),
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight:
                                              FontWeight.w600,
                                          color: color),
                                    ),
                                  ),
                                  // Guardian student link
                                  if (role == 'guardian' &&
                                      cls.isNotEmpty &&
                                      roll > 0) ...[
                                    const SizedBox(height: 3),
                                    Row(children: [
                                      Icon(
                                          Icons
                                              .school_outlined,
                                          size: 11,
                                          color: Colors
                                              .grey.shade400),
                                      const SizedBox(width: 3),
                                      Text(
                                          'Student: $cls  •  Roll $roll',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Colors
                                                  .grey.shade500)),
                                    ]),
                                  ],
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Edit button
                                  IconButton(
                                    icon: Icon(
                                        Icons.edit_outlined,
                                        color: AppTheme.primary,
                                        size: 20),
                                    onPressed: () => _edit(user),
                                    tooltip: 'Edit',
                                  ),
                                  // Delete button
                                  IconButton(
                                    icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.red,
                                        size: 20),
                                    onPressed: () => _remove(email),
                                    tooltip: 'Remove',
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ]),
    );
  }
}

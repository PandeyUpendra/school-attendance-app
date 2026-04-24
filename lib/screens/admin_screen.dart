import 'package:flutter/material.dart';
import '../services/timetable_service.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _service      = TimetableService();
  final _emailCtrl    = TextEditingController();
  final _passCtrl     = TextEditingController();
  final _rollCtrl     = TextEditingController();
  String _selectedRole = 'teacher';
  String? _selectedStudentClass;
  List<String> _availableClasses = [];
  List<Map<String, String>> _users = [];
  bool _loading = true;
  bool _saving  = false;
  bool _showPass = false;

  static const _roles = [
    {'value': 'teacher',     'label': 'Teacher',     'color': 0xFFD32F2F},
    {'value': 'coordinator', 'label': 'Coordinator', 'color': 0xFF3949AB},
    {'value': 'principal',   'label': 'Principal',   'color': 0xFF00796B},
    {'value': 'guardian',    'label': 'Guardian',    'color': 0xFF7B1FA2},
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _rollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _service.getAllowedUsers(),
      _service.getSettings(),
    ]);
    if (!mounted) return;
    final users    = results[0] as List<Map<String, String>>;
    final settings = results[1] as Map<String, dynamic>;
    setState(() {
      _users = users;
      _availableClasses =
          List<String>.from(settings['classes'] as List? ?? const []);
      _loading = false;
    });
  }

  Future<void> _add() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    final pass  = _passCtrl.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      _snack('Enter a valid email address');
      return;
    }
    if (pass.isEmpty) {
      _snack('Enter a password for this user');
      return;
    }
    if (_users.any((u) => u['email'] == email)) {
      _snack('Email already registered');
      return;
    }

    // Guardian-specific validation: class + roll required so they can
    // see their child's attendance after login.
    int?    studentRoll;
    String? studentClass;
    if (_selectedRole == 'guardian') {
      if (_selectedStudentClass == null) {
        _snack("Select the student's class");
        return;
      }
      final rollText = _rollCtrl.text.trim();
      studentRoll = int.tryParse(rollText);
      if (studentRoll == null || studentRoll <= 0) {
        _snack("Enter a valid roll number");
        return;
      }
      studentClass = _selectedStudentClass;
    }

    setState(() => _saving = true);
    await _service.addAllowedUser(
      email,
      pass,
      _selectedRole,
      studentClass: studentClass,
      studentRoll:  studentRoll,
    );
    _emailCtrl.clear();
    _passCtrl.clear();
    _rollCtrl.clear();
    setState(() => _selectedStudentClass = null);
    await _load();
    setState(() => _saving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$email added as $_selectedRole'),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 2),
      ));
    }
  }

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

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Color _roleColor(String role) {
    final r = _roles.firstWhere(
        (e) => e['value'] == role,
        orElse: () => {'color': 0xFF9E9E9E});
    return Color(r['color'] as int);
  }

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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
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
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(children: [
        // ── Add user form ───────────────────────────────────────────────────
        Container(
          color: Colors.deepOrange,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(children: [
            // Role dropdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedRole,
                  isExpanded: true,
                  dropdownColor: Colors.deepOrange.shade700,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  iconEnabledColor: Colors.white70,
                  items: _roles.map((r) {
                    return DropdownMenuItem<String>(
                      value: r['value'] as String,
                      child: Row(children: [
                        Icon(_roleIcon(r['value'] as String),
                            color: Colors.white70, size: 18),
                        const SizedBox(width: 10),
                        Text(r['label'] as String,
                            style: const TextStyle(color: Colors.white,
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

            // Guardian-only: link to a specific student (class + roll)
            if (_selectedRole == 'guardian') ...[
              Row(children: [
                // Class dropdown
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
                        hint: const Text(
                          "Child's class",
                          style: TextStyle(color: Colors.white60, fontSize: 14),
                        ),
                        dropdownColor: Colors.deepOrange.shade700,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14),
                        iconEnabledColor: Colors.white70,
                        items: _availableClasses
                            .map((c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(c,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600)),
                                ))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedStudentClass = v),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Roll number
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _rollCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Roll no.',
                      hintStyle: const TextStyle(color: Colors.white60),
                      prefixIcon: const Icon(Icons.tag,
                          color: Colors.white70, size: 18),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.15),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
            ],

            // Email field
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Email address…',
                hintStyle: const TextStyle(color: Colors.white60),
                prefixIcon: const Icon(Icons.email_outlined, color: Colors.white70),
                filled: true,
                fillColor: Colors.white.withOpacity(0.15),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 8),

            // Password field + Add button row
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _passCtrl,
                  obscureText: !_showPass,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Password…',
                    hintStyle: const TextStyle(color: Colors.white60),
                    prefixIcon: const Icon(Icons.lock_outline,
                        color: Colors.white70),
                    suffixIcon: IconButton(
                      icon: Icon(
                          _showPass ? Icons.visibility_off : Icons.visibility,
                          color: Colors.white70, size: 18),
                      onPressed: () => setState(() => _showPass = !_showPass),
                    ),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.15),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _saving ? null : _add,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.deepOrange,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.deepOrange))
                    : const Text('Add',
                        style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ]),
          ]),
        ),

        // ── Info banner ─────────────────────────────────────────────────────
        Container(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Row(children: [
            Icon(Icons.info_outline, color: Colors.orange.shade700, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Only registered emails with a password can sign in. '
                'Admin can register Coordinator, Teacher, Principal or Guardian.',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
              ),
            ),
          ]),
        ),

        // ── Users list ──────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(children: [
            Text('REGISTERED USERS (${_users.length})',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade500,
                    letterSpacing: 0.6)),
          ]),
        ),

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
                      color: Colors.deepOrange,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                        itemCount: _users.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 56),
                        itemBuilder: (_, i) {
                          final user  = _users[i];
                          final email = user['email']!;
                          final role  = user['role']!;
                          final color = _roleColor(role);
                          return Container(
                            color: Colors.white,
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 6),
                              leading: Container(
                                width: 40, height: 40,
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(_roleIcon(role),
                                    color: color, size: 22),
                              ),
                              title: Text(email,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                role[0].toUpperCase() + role.substring(1),
                                style: TextStyle(fontSize: 12, color: color),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.red, size: 20),
                                onPressed: () => _remove(email),
                                tooltip: 'Remove',
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

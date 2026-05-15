import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../services/timetable_service.dart';

/// Shows a bottom sheet for creating a new school account.
///
/// [targetRole] must be 'coordinator', 'teacher', or 'guardian'.
/// Returns true if an account was successfully created.
Future<bool> showCreateAccountSheet(
  BuildContext context, {
  required String targetRole,
  required String schoolId,
  required List<String> availableClasses,
  String? defaultClass,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CreateAccountSheet(
      targetRole: targetRole,
      schoolId: schoolId,
      availableClasses: availableClasses,
      defaultClass: defaultClass,
    ),
  );
  return result == true;
}

class _CreateAccountSheet extends StatefulWidget {
  final String targetRole;
  final String schoolId;
  final List<String> availableClasses;
  final String? defaultClass;

  const _CreateAccountSheet({
    required this.targetRole,
    required this.schoolId,
    required this.availableClasses,
    this.defaultClass,
  });

  @override
  State<_CreateAccountSheet> createState() => _CreateAccountSheetState();
}

class _CreateAccountSheetState extends State<_CreateAccountSheet> {
  final _nameCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _rollCtrl  = TextEditingController();

  bool _saving  = false;
  bool _obscure = true;
  String? _selectedClass;
  List<String> _selectedClasses = [];

  @override
  void initState() {
    super.initState();
    _selectedClass = widget.defaultClass;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _rollCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name  = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim().toLowerCase();
    final pass  = _passCtrl.text.trim();

    if (name.isEmpty) {
      _snack('Enter a name');
      return;
    }
    if (email.isEmpty || !RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(email)) {
      _snack('Enter a valid email address');
      return;
    }
    if (pass.length < 6) {
      _snack('Password must be at least 6 characters');
      return;
    }

    if (widget.targetRole == 'guardian') {
      if (_selectedClass == null) {
        _snack("Select the student's class");
        return;
      }
      final roll = int.tryParse(_rollCtrl.text.trim());
      if (roll == null || roll < 1 || roll > 999) {
        _snack('Enter a valid roll number (1–999)');
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final svc = TimetableService();

      final exists = await svc.userExists(email);
      if (exists) {
        _snack('An account with this email already exists');
        setState(() => _saving = false);
        return;
      }

      int? roll;
      if (widget.targetRole == 'guardian') {
        roll = int.parse(_rollCtrl.text.trim());
      }

      await svc.addAllowedUser(
        email,
        pass,
        widget.targetRole,
        name: name,
        schoolId: widget.schoolId,
        studentClass:
            widget.targetRole == 'guardian' ? _selectedClass : null,
        studentRoll: widget.targetRole == 'guardian' ? roll : null,
        assignedClasses:
            widget.targetRole == 'coordinator' ? _selectedClasses : null,
      );

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _saving = false);
      _snack('Failed to create account: $e');
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  String get _title {
    switch (widget.targetRole) {
      case 'coordinator': return 'Create Coordinator Account';
      case 'teacher':     return 'Create Teacher Account';
      default:            return 'Create Guardian Account';
    }
  }

  IconData get _icon {
    switch (widget.targetRole) {
      case 'coordinator': return Icons.admin_panel_settings_outlined;
      case 'teacher':     return Icons.person_outlined;
      default:            return Icons.family_restroom_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Header
              Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_icon, color: AppTheme.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Text(_title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 20),

              // Name
              _InputField(
                controller: _nameCtrl,
                hint: 'Full Name',
                icon: Icons.person_outline,
              ),
              const SizedBox(height: 12),

              // Email
              _InputField(
                controller: _emailCtrl,
                hint: 'Email Address',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),

              // Password
              TextField(
                controller: _passCtrl,
                obscureText: _obscure,
                decoration: InputDecoration(
                  hintText: 'Password (min 6 chars)',
                  prefixIcon:
                      const Icon(Icons.lock_outline, color: Colors.grey),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: Colors.grey,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: AppTheme.primary, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 14),
                ),
              ),

              // ── Coordinator: assigned classes dropdown ─────────────────
              if (widget.targetRole == 'coordinator') ...[
                const SizedBox(height: 16),
                Text(
                  'RESPONSIBLE FOR (CLASSES)',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade500,
                      letterSpacing: 0.8),
                ),
                const SizedBox(height: 8),
                if (widget.availableClasses.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      Icon(Icons.class_outlined,
                          color: Colors.grey.shade400, size: 20),
                      const SizedBox(width: 10),
                      Text('No classes configured yet',
                          style: TextStyle(
                              color: Colors.grey.shade400, fontSize: 14)),
                    ]),
                  )
                else
                  _ClassDropdownField(
                    availableClasses: widget.availableClasses,
                    selectedClasses: _selectedClasses,
                    onChanged: (updated) =>
                        setState(() => _selectedClasses = updated),
                  ),
              ],

              // ── Guardian: student class + roll ─────────────────────────
              if (widget.targetRole == 'guardian') ...[
                const SizedBox(height: 16),
                Text(
                  "STUDENT'S CLASS & ROLL",
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade500,
                      letterSpacing: 0.8),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<String>(
                      value: _selectedClass,
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
                      items: widget.availableClasses
                          .map((c) =>
                              DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedClass = v),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _rollCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
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

              const SizedBox(height: 20),

              // Submit
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Create Account',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClassDropdownField extends StatefulWidget {
  final List<String> availableClasses;
  final List<String> selectedClasses;
  final ValueChanged<List<String>> onChanged;

  const _ClassDropdownField({
    required this.availableClasses,
    required this.selectedClasses,
    required this.onChanged,
  });

  @override
  State<_ClassDropdownField> createState() => _ClassDropdownFieldState();
}

class _ClassDropdownFieldState extends State<_ClassDropdownField> {
  Future<void> _openPicker() async {
    // Work on a local copy so Cancel discards changes.
    final temp = List<String>.from(widget.selectedClasses);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          title: Row(children: [
            const Icon(Icons.class_outlined,
                color: AppTheme.primary, size: 20),
            const SizedBox(width: 8),
            const Text('Select Classes',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton(
              onPressed: () {
                setLocal(() {
                  if (temp.length == widget.availableClasses.length) {
                    temp.clear();
                  } else {
                    temp
                      ..clear()
                      ..addAll(widget.availableClasses);
                  }
                });
              },
              child: Text(
                temp.length == widget.availableClasses.length
                    ? 'None'
                    : 'All',
                style: const TextStyle(
                    color: AppTheme.primary, fontSize: 13),
              ),
            ),
          ]),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.availableClasses.length,
              itemBuilder: (_, i) {
                final cls = widget.availableClasses[i];
                final checked = temp.contains(cls);
                return CheckboxListTile(
                  value: checked,
                  title: Text(cls,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: checked
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: checked
                              ? AppTheme.primary
                              : Colors.black87)),
                  activeColor: AppTheme.primary,
                  checkboxShape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4)),
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  onChanged: (_) => setLocal(() => checked
                      ? temp.remove(cls)
                      : temp.add(cls)),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      widget.onChanged(temp);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sel = widget.selectedClasses;
    final label = sel.isEmpty
        ? 'Tap to select classes…'
        : sel.length == 1
            ? sel.first
            : '${sel.length} classes selected';

    return InkWell(
      onTap: _openPicker,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(
            color: sel.isEmpty
                ? Colors.grey.shade400
                : AppTheme.primary,
            width: sel.isEmpty ? 1.0 : 1.5,
          ),
          borderRadius: BorderRadius.circular(10),
          color: sel.isEmpty
              ? Colors.transparent
              : AppTheme.primary.withOpacity(0.04),
        ),
        child: Row(children: [
          Icon(Icons.class_outlined,
              color: sel.isEmpty
                  ? Colors.grey.shade500
                  : AppTheme.primary,
              size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                  fontSize: 14,
                  color: sel.isEmpty
                      ? Colors.grey.shade500
                      : AppTheme.primary,
                  fontWeight: sel.isEmpty
                      ? FontWeight.normal
                      : FontWeight.w600),
            ),
          ),
          if (sel.isNotEmpty)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('${sel.length}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ),
          const SizedBox(width: 6),
          Icon(Icons.arrow_drop_down,
              color: sel.isEmpty
                  ? Colors.grey.shade500
                  : AppTheme.primary),
        ]),
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType keyboardType;

  const _InputField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, color: Colors.grey),
          border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                const BorderSide(color: AppTheme.primary, width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
      );
}

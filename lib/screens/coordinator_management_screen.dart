import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/timetable_service.dart';
import '../theme.dart';

/// Principal-only screen to create, edit, and delete coordinator accounts.
class CoordinatorManagementScreen extends StatefulWidget {
  final String principalEmail;

  const CoordinatorManagementScreen({super.key, required this.principalEmail});

  @override
  State<CoordinatorManagementScreen> createState() =>
      _CoordinatorManagementScreenState();
}

class _CoordinatorManagementScreenState
    extends State<CoordinatorManagementScreen> {
  final _service = TimetableService();
  final _firestore = FirebaseFirestore.instance;

  List<Map<String, dynamic>> _coordinators = [];
  List<String> _allClasses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await _service.getSettings();
    final coords = await _service.getCoordinators('school_1');
    if (!mounted) return;
    setState(() {
      _allClasses = List<String>.from(settings['classes'] ?? []);
      _coordinators = coords;
      _loading = false;
    });
  }

  // ── Add / Edit sheet ───────────────────────────────────────────────────────

  Future<void> _openForm({Map<String, dynamic>? existing}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CoordinatorForm(
        allClasses: _allClasses,
        existing: existing,
        principalEmail: widget.principalEmail,
        onSaved: _load,
      ),
    );
  }

  // ── Delete ─────────────────────────────────────────────────────────────────

  Future<void> _delete(Map<String, dynamic> coord) async {
    final email = coord['email'] as String;
    final name  = coord['name'] as String? ?? email;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Coordinator'),
        content: Text('Remove $name and revoke their login access?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await _firestore.collection('allowed_users').doc(email.toLowerCase().trim()).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$name removed'), backgroundColor: Colors.green),
        );
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        title: const Text('Manage Coordinators', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () { setState(() => _loading = true); _load(); },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Add Coordinator'),
        onPressed: () => _openForm(),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _coordinators.isEmpty
              ? _emptyState()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: _coordinators.length,
                    itemBuilder: (_, i) => _CoordCard(
                      coord: _coordinators[i],
                      onEdit: () => _openForm(existing: _coordinators[i]),
                      onDelete: () => _delete(_coordinators[i]),
                    ),
                  ),
                ),
    );
  }

  Widget _emptyState() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.supervisor_account_outlined, size: 72, color: AppTheme.primary.withValues(alpha: 0.3)),
        const SizedBox(height: 16),
        Text('No coordinators yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
        const SizedBox(height: 8),
        Text('Tap "Add Coordinator" to create the first one',
            style: TextStyle(color: Colors.grey.shade500)),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Coordinator card
// ─────────────────────────────────────────────────────────────────────────────

class _CoordCard extends StatelessWidget {
  final Map<String, dynamic> coord;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CoordCard({required this.coord, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final name    = coord['name']  as String? ?? coord['email'] as String? ?? '—';
    final email   = coord['email'] as String? ?? '—';
    final phone   = coord['phone'] as String?;
    final desig   = coord['designation'] as String?;
    final classes = coord['assignedClasses'] != null
        ? List<String>.from(coord['assignedClasses'] as List)
        : <String>[];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.primary, AppTheme.primaryMid],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  radius: 24,
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      if (desig != null && desig.isNotEmpty)
                        Text(desig, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: Colors.white),
                  onPressed: onEdit,
                  tooltip: 'Edit',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.white70),
                  onPressed: onDelete,
                  tooltip: 'Remove',
                ),
              ],
            ),
          ),
          // Details
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(Icons.email_outlined, email),
                if (phone != null && phone.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _InfoRow(Icons.phone_outlined, phone),
                ],
                if (classes.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('Assigned Classes', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6, runSpacing: 6,
                    children: classes.map((c) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                      ),
                      child: Text(c, style: TextStyle(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                    )).toList(),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Icon(Icons.warning_amber_outlined, size: 14, color: Colors.orange.shade600),
                    const SizedBox(width: 4),
                    Text('No classes assigned yet', style: TextStyle(fontSize: 12, color: Colors.orange.shade600)),
                  ]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 14, color: Colors.grey.shade500),
      const SizedBox(width: 6),
      Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: Colors.grey.shade700))),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Add / Edit form (bottom sheet)
// ─────────────────────────────────────────────────────────────────────────────

class _CoordinatorForm extends StatefulWidget {
  final List<String> allClasses;
  final Map<String, dynamic>? existing;
  final String principalEmail;
  final VoidCallback onSaved;

  const _CoordinatorForm({
    required this.allClasses,
    required this.principalEmail,
    required this.onSaved,
    this.existing,
  });

  @override
  State<_CoordinatorForm> createState() => _CoordinatorFormState();
}

class _CoordinatorFormState extends State<_CoordinatorForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _passCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _desigCtrl;

  late Set<String> _selectedClasses;
  bool _saving = false;
  bool _obscure = true;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl  = TextEditingController(text: e?['name']        as String? ?? '');
    _emailCtrl = TextEditingController(text: e?['email']       as String? ?? '');
    _passCtrl  = TextEditingController();
    _phoneCtrl = TextEditingController(text: e?['phone']       as String? ?? '');
    _desigCtrl = TextEditingController(text: e?['designation'] as String? ?? '');
    _selectedClasses = e?['assignedClasses'] != null
        ? Set<String>.from(e!['assignedClasses'] as List)
        : {};
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _emailCtrl.dispose(); _passCtrl.dispose();
    _phoneCtrl.dispose(); _desigCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final email = _emailCtrl.text.trim().toLowerCase();
    final name  = _nameCtrl.text.trim();
    final pass  = _passCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final desig = _desigCtrl.text.trim();
    final classes = _selectedClasses.toList();

    try {
      final svc = TimetableService();
      if (_isEdit) {
        await svc.updateAllowedUser(
          email,
          role: 'coordinator',
          newPassword: pass.isNotEmpty ? pass : null,
          assignedClasses: classes,
        );
        // Update extra fields
        final extraData = <String, dynamic>{
          'name': name,
          if (phone.isNotEmpty) 'phone': phone else 'phone': FieldValue.delete(),
          if (desig.isNotEmpty) 'designation': desig else 'designation': FieldValue.delete(),
        };
        await FirebaseFirestore.instance
            .collection('allowed_users')
            .doc(email)
            .update(extraData);
      } else {
        await svc.addAllowedUser(
          email, pass, 'coordinator',
          name: name,
          schoolId: 'school_1',
          assignedClasses: classes,
          createdByEmail: widget.principalEmail,
          createdByRole: 'principal',
        );
        // Add extra fields
        final extraData = <String, dynamic>{
          if (phone.isNotEmpty) 'phone': phone,
          if (desig.isNotEmpty) 'designation': desig,
        };
        if (extraData.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('allowed_users')
              .doc(email)
              .update(extraData);
        }
      }

      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: const EdgeInsets.only(top: 60),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(children: [
              Icon(Icons.supervisor_account_outlined, color: AppTheme.primary),
              const SizedBox(width: 10),
              Text(
                _isEdit ? 'Edit Coordinator' : 'Add Coordinator',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ]),
          ),
          const Divider(height: 20),
          // Form
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Field(controller: _nameCtrl, label: 'Full Name', icon: Icons.person_outline,
                        validator: (v) => v!.trim().isEmpty ? 'Name is required' : null),
                    const SizedBox(height: 14),
                    _Field(controller: _emailCtrl, label: 'Email Address', icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        readOnly: _isEdit,
                        validator: (v) {
                          if (v!.trim().isEmpty) return 'Email is required';
                          if (!v.contains('@')) return 'Enter a valid email';
                          return null;
                        }),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passCtrl,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: _isEdit ? 'New Password (leave blank to keep)' : 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                      validator: (v) {
                        if (!_isEdit && (v == null || v.trim().isEmpty)) return 'Password is required';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    _Field(controller: _phoneCtrl, label: 'Phone Number (optional)', icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone),
                    const SizedBox(height: 14),
                    _Field(controller: _desigCtrl, label: 'Designation (optional)', icon: Icons.badge_outlined,
                        hint: 'e.g. Science Coordinator'),
                    const SizedBox(height: 20),

                    // Class selection
                    Text('Assigned Classes',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                    const SizedBox(height: 4),
                    Text('Select all classes this coordinator will manage',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                    const SizedBox(height: 10),
                    if (widget.allClasses.isEmpty)
                      Text('No classes configured in school settings',
                          style: TextStyle(color: Colors.orange.shade600, fontSize: 13))
                    else
                      Wrap(
                        spacing: 8, runSpacing: 8,
                        children: widget.allClasses.map((cls) {
                          final selected = _selectedClasses.contains(cls);
                          return FilterChip(
                            label: Text(cls),
                            selected: selected,
                            onSelected: (v) => setState(() {
                              if (v) { _selectedClasses.add(cls); }
                              else   { _selectedClasses.remove(cls); }
                            }),
                            selectedColor: AppTheme.primary.withValues(alpha: 0.15),
                            checkmarkColor: AppTheme.primary,
                            labelStyle: TextStyle(
                              color: selected ? AppTheme.primary : Colors.grey.shade700,
                              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                            ),
                            side: BorderSide(
                              color: selected ? AppTheme.primary : Colors.grey.shade300,
                            ),
                          );
                        }).toList(),
                      ),
                    const SizedBox(height: 8),
                    // Select all / none shortcuts
                    if (widget.allClasses.isNotEmpty)
                      Row(children: [
                        TextButton.icon(
                          icon: const Icon(Icons.select_all, size: 16),
                          label: const Text('Select All'),
                          onPressed: () => setState(() => _selectedClasses = Set.from(widget.allClasses)),
                          style: TextButton.styleFrom(foregroundColor: AppTheme.primary, padding: EdgeInsets.zero),
                        ),
                        const SizedBox(width: 12),
                        TextButton.icon(
                          icon: const Icon(Icons.deselect, size: 16),
                          label: const Text('Clear'),
                          onPressed: () => setState(() => _selectedClasses = {}),
                          style: TextButton.styleFrom(foregroundColor: Colors.grey, padding: EdgeInsets.zero),
                        ),
                      ]),

                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Text(_isEdit ? 'Save Changes' : 'Create Coordinator Account',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Reusable text field
// ─────────────────────────────────────────────────────────────────────────────

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool readOnly;
  final String? hint;
  final String? Function(String?)? validator;

  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.readOnly = false,
    this.hint,
    this.validator,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: keyboardType,
    readOnly: readOnly,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: readOnly ? Colors.grey.shade100 : Colors.grey.shade50,
    ),
    validator: validator,
  );
}

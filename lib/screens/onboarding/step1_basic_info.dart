import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/school_onboarding.dart';
import '../../services/school_settings_service.dart';
import '../../theme.dart';

class Step1BasicInfo extends StatefulWidget {
  final SchoolOnboarding initial;
  final void Function(SchoolOnboarding) onChanged;

  const Step1BasicInfo({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  @override
  State<Step1BasicInfo> createState() => Step1BasicInfoState();
}

class Step1BasicInfoState extends State<Step1BasicInfo> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _principalCtrl;
  late final TextEditingController _yearCtrl;

  String _schoolType = 'Private';
  String _board = 'CBSE';
  String _logoUrl = '';
  bool _uploadingLogo = false;

  static const _types = ['Private', 'Government', 'Government-Aided'];
  static const _boards = ['CBSE', 'ICSE', 'State Board', 'IGCSE', 'Other'];

  @override
  void initState() {
    super.initState();
    final d = widget.initial;
    _nameCtrl = TextEditingController(text: d.schoolName);
    _phoneCtrl = TextEditingController(text: d.phone);
    _emailCtrl = TextEditingController(text: d.email);
    _principalCtrl = TextEditingController(text: d.principalName);
    _yearCtrl = TextEditingController(text: d.establishedYear);
    _schoolType = _types.contains(d.schoolType) ? d.schoolType : 'Private';
    _board = _boards.contains(d.board) ? d.board : 'CBSE';
    _logoUrl = d.logoUrl;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _principalCtrl.dispose();
    _yearCtrl.dispose();
    super.dispose();
  }

  void _notify() {
    widget.onChanged(widget.initial.copyWith(
      schoolName: _nameCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      principalName: _principalCtrl.text.trim(),
      establishedYear: _yearCtrl.text.trim(),
      schoolType: _schoolType,
      board: _board,
      logoUrl: _logoUrl,
    ));
  }

  bool validate() => _formKey.currentState?.validate() ?? false;

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (file == null) return;
    setState(() => _uploadingLogo = true);
    try {
      final ref = FirebaseStorage.instance
          .ref('schools/${SchoolSettingsService.schoolId}/logo.jpg');
      await ref.putFile(File(file.path));
      final url = await ref.getDownloadURL();
      setState(() {
        _logoUrl = url;
        _uploadingLogo = false;
      });
      _notify();
    } catch (e) {
      setState(() => _uploadingLogo = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Logo upload failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _logoSection(),
          const SizedBox(height: 20),
          _field(
            controller: _nameCtrl,
            label: 'School Name *',
            icon: Icons.school_outlined,
            onChanged: (_) => _notify(),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 14),
          _dropdown(
            label: 'School Type *',
            value: _schoolType,
            items: _types,
            icon: Icons.business_outlined,
            onChanged: (v) {
              setState(() => _schoolType = v!);
              _notify();
            },
          ),
          const SizedBox(height: 14),
          _dropdown(
            label: 'Board *',
            value: _board,
            items: _boards,
            icon: Icons.menu_book_outlined,
            onChanged: (v) {
              setState(() => _board = v!);
              _notify();
            },
          ),
          const SizedBox(height: 14),
          _field(
            controller: _phoneCtrl,
            label: 'School Phone *',
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            onChanged: (_) => _notify(),
            validator: (v) {
              final s = (v ?? '').trim();
              if (s.isEmpty) return 'Required';
              if (s.length != 10 || !RegExp(r'^\d{10}$').hasMatch(s)) {
                return 'Enter a valid 10-digit number';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          _field(
            controller: _emailCtrl,
            label: 'School Email *',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => _notify(),
            validator: (v) {
              final s = (v ?? '').trim();
              if (s.isEmpty) return 'Required';
              if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(s)) {
                return 'Enter a valid email';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          _field(
            controller: _principalCtrl,
            label: 'Principal Name *',
            icon: Icons.person_outline,
            onChanged: (_) => _notify(),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 14),
          _field(
            controller: _yearCtrl,
            label: 'Established Year (optional)',
            icon: Icons.calendar_today_outlined,
            keyboardType: TextInputType.number,
            maxLength: 4,
            onChanged: (_) => _notify(),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _logoSection() {
    return Center(
      child: Column(children: [
        GestureDetector(
          onTap: _pickLogo,
          child: Stack(
            children: [
              CircleAvatar(
                radius: 52,
                backgroundColor: AppTheme.primaryLight.withOpacity(0.3),
                backgroundImage:
                    _logoUrl.isNotEmpty ? NetworkImage(_logoUrl) : null,
                child: _logoUrl.isEmpty
                    ? const Icon(Icons.school, size: 40, color: AppTheme.primary)
                    : null,
              ),
              if (_uploadingLogo)
                const Positioned.fill(
                  child: CircleAvatar(
                    radius: 52,
                    backgroundColor: Colors.black38,
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: AppTheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt, color: Colors.white, size: 14),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _logoUrl.isEmpty ? 'Tap to add school logo' : 'Tap to change logo',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
        ),
      ]),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int? maxLength,
    void Function(String)? onChanged,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLength: maxLength,
      textCapitalization: TextCapitalization.words,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        counterText: '',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        isDense: true,
      ),
      onChanged: onChanged,
      validator: validator,
    );
  }

  Widget _dropdown({
    required String label,
    required String value,
    required List<String> items,
    required IconData icon,
    required void Function(String?) onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        isDense: true,
      ),
      items: items
          .map((i) => DropdownMenuItem(value: i, child: Text(i)))
          .toList(),
      onChanged: onChanged,
    );
  }
}

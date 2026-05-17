import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../models/student.dart';
import '../services/student_service.dart';
import '../theme.dart';

class AddStudentScreen extends StatefulWidget {
  final String className;
  final String section;
  final Student? existing;
  /// Class teacher's ID — stamped onto every new student so records are
  /// scoped to this teacher and not visible to other teachers.
  final String? teacherId;
  const AddStudentScreen(
      {super.key, required this.className, this.section = '', this.existing, this.teacherId});

  @override
  State<AddStudentScreen> createState() => _AddStudentScreenState();
}

class _AddStudentScreenState extends State<AddStudentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _rollCtrl            = TextEditingController();
  final _nameCtrl            = TextEditingController();
  final _fatherCtrl          = TextEditingController();
  final _motherCtrl          = TextEditingController();
  final _phoneCtrl           = TextEditingController();
  final _parentPhoneCtrl     = TextEditingController();
  final _addressCtrl         = TextEditingController();
  final _prevSchoolCtrl      = TextEditingController();
  final _emergencyCtrl       = TextEditingController();
  final _allergiesCtrl       = TextEditingController();
  String _feeStatus    = 'Pending';
  String? _feeDueDate;
  final _feeAmountCtrl = TextEditingController();
  String? _photoPath;
  DateTime? _dateOfBirth;
  String? _gender;
  String? _bloodGroup;
  String? _transportMode;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final s = widget.existing!;
      _rollCtrl.text        = s.roll.toString();
      _nameCtrl.text        = s.name;
      _fatherCtrl.text      = s.fatherName;
      _motherCtrl.text      = s.motherName ?? '';
      _phoneCtrl.text       = s.phone;
      _parentPhoneCtrl.text = s.parentPhone ?? '';
      _addressCtrl.text     = s.address ?? '';
      _prevSchoolCtrl.text  = s.previousSchool ?? '';
      _emergencyCtrl.text   = s.emergencyContact ?? '';
      _allergiesCtrl.text   = s.allergies ?? '';
      _feeStatus            = s.feeStatus;
      _feeDueDate           = s.feeDueDate;
      _feeAmountCtrl.text   = s.feeAmount?.toStringAsFixed(0) ?? '';
      _photoPath            = s.photoPath;
      _dateOfBirth          = s.dateOfBirth?.toDate();
      _gender               = s.gender;
      _bloodGroup           = s.bloodGroup;
      _transportMode        = s.transportMode;
    }
  }

  @override
  void dispose() {
    _rollCtrl.dispose();
    _nameCtrl.dispose();
    _fatherCtrl.dispose();
    _motherCtrl.dispose();
    _phoneCtrl.dispose();
    _parentPhoneCtrl.dispose();
    _addressCtrl.dispose();
    _prevSchoolCtrl.dispose();
    _emergencyCtrl.dispose();
    _allergiesCtrl.dispose();
    _feeAmountCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: const Text('Take Photo'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Choose from Gallery'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null) return;
    final picked =
        await ImagePicker().pickImage(source: source, imageQuality: 70);
    if (picked != null) setState(() => _photoPath = picked.path);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final student = Student(
      roll: int.parse(_rollCtrl.text.trim()),
      name: _nameCtrl.text.trim(),
      className: widget.className,
      section: widget.section,
      fatherName: _fatherCtrl.text.trim(),
      motherName: _motherCtrl.text.trim().isEmpty ? null : _motherCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      parentPhone: _parentPhoneCtrl.text.trim().isEmpty ? null : _parentPhoneCtrl.text.trim(),
      address: _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
      previousSchool: _prevSchoolCtrl.text.trim().isEmpty ? null : _prevSchoolCtrl.text.trim(),
      emergencyContact: _emergencyCtrl.text.trim().isEmpty ? null : _emergencyCtrl.text.trim(),
      allergies: _allergiesCtrl.text.trim().isEmpty ? null : _allergiesCtrl.text.trim(),
      gender: _gender,
      bloodGroup: _bloodGroup,
      transportMode: _transportMode,
      photoPath: _photoPath,
      photoUrl: widget.existing?.photoUrl,
      feeStatus: _feeStatus,
      feeDueDate: _feeDueDate,
      feeAmount: double.tryParse(_feeAmountCtrl.text.trim()),
      teacherId: widget.teacherId ?? widget.existing?.teacherId,
      dateOfBirth: _dateOfBirth != null ? Timestamp.fromDate(_dateOfBirth!) : null,
    );

    final service = StudentService();
    if (_isEdit) {
      await service.updateStudent(updated: student);
      if (mounted) Navigator.pop(context, student);
    } else {
      final error = await service.addStudent(student: student);
      if (!mounted) return;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error), backgroundColor: Colors.red));
        setState(() => _saving = false);
      } else {
        Navigator.pop(context, student);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Student' : 'Add Student'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Save',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(children: [
            // Class label
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.primary.withOpacity(0.25)),
              ),
              child: Row(children: [
                const Icon(Icons.class_, color: AppTheme.primary, size: 18),
                const SizedBox(width: 8),
                const Text('Adding to: ',
                    style: TextStyle(color: AppTheme.primary)),
                Text(
                  widget.section.isEmpty
                      ? widget.className
                      : '${widget.className} — Section ${widget.section}',
                  style: const TextStyle(
                      color: AppTheme.primaryDark,
                      fontWeight: FontWeight.bold)),
              ]),
            ),
            const SizedBox(height: 20),

            // Photo
            GestureDetector(
              onTap: _pickPhoto,
              child: Stack(alignment: Alignment.bottomRight, children: [
                CircleAvatar(
                  radius: 52,
                  backgroundColor: AppTheme.primary.withOpacity(0.08),
                  backgroundImage: _photoPath != null
                      ? FileImage(File(_photoPath!))
                      : null,
                  child: _photoPath == null
                      ? const Icon(Icons.person,
                          size: 52, color: AppTheme.primaryLight)
                      : null,
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                      color: AppTheme.primary, shape: BoxShape.circle),
                  child: const Icon(Icons.camera_alt,
                      size: 16, color: Colors.white),
                ),
              ]),
            ),
            const SizedBox(height: 6),
            Text('Tap to add photo',
                style:
                    TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            const SizedBox(height: 20),

            _Field(
              controller: _rollCtrl,
              label: 'Roll Number',
              icon: Icons.tag,
              keyboard: TextInputType.number,
              enabled: !_isEdit,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                final n = int.tryParse(v.trim());
                if (n == null) return 'Must be a number';
                if (n < 1 || n > 999) return 'Must be 1–999';
                return null;
              },
            ),
            const SizedBox(height: 14),
            _Field(
              controller: _nameCtrl,
              label: 'Full Name',
              icon: Icons.person_outline,
              caps: TextCapitalization.words,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z ]')),
              ],
              maxLength: 50,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 14),
            _Field(
              controller: _fatherCtrl,
              label: "Father's Name",
              icon: Icons.man_outlined,
              caps: TextCapitalization.words,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z ]')),
              ],
              maxLength: 50,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 14),
            _Field(
              controller: _motherCtrl,
              label: "Mother's Name (optional)",
              icon: Icons.woman_outlined,
              caps: TextCapitalization.words,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z ]')),
              ],
              maxLength: 50,
            ),
            const SizedBox(height: 14),
            _Field(
              controller: _phoneCtrl,
              label: 'Primary Contact (Phone)',
              icon: Icons.phone_outlined,
              keyboard: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 10,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (v.trim().length != 10) return 'Must be exactly 10 digits';
                return null;
              },
            ),
            const SizedBox(height: 14),
            _Field(
              controller: _parentPhoneCtrl,
              label: 'Secondary Contact (optional)',
              icon: Icons.phone_android_outlined,
              keyboard: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 10,
            ),
            const SizedBox(height: 14),
            // Gender dropdown
            DropdownButtonFormField<String>(
              value: _gender,
              decoration: InputDecoration(
                labelText: 'Gender (optional)',
                prefixIcon: const Icon(Icons.wc_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
              hint: const Text('Select gender'),
              items: const [
                DropdownMenuItem(value: 'Male',   child: Text('Male')),
                DropdownMenuItem(value: 'Female', child: Text('Female')),
                DropdownMenuItem(value: 'Other',  child: Text('Other')),
              ],
              onChanged: (v) => setState(() => _gender = v),
            ),
            const SizedBox(height: 14),
            _Field(
              controller: _addressCtrl,
              label: 'Address (optional)',
              icon: Icons.home_outlined,
              caps: TextCapitalization.sentences,
              maxLength: 150,
            ),
            const SizedBox(height: 14),
            _Field(
              controller: _prevSchoolCtrl,
              label: 'Previous School (optional)',
              icon: Icons.account_balance_outlined,
              caps: TextCapitalization.words,
              maxLength: 80,
            ),
            const SizedBox(height: 14),
            _Field(
              controller: _emergencyCtrl,
              label: 'Emergency Contact (optional)',
              icon: Icons.contact_emergency_outlined,
              keyboard: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 10,
            ),
            const SizedBox(height: 14),
            // Blood Group dropdown
            DropdownButtonFormField<String>(
              value: _bloodGroup,
              decoration: InputDecoration(
                labelText: 'Blood Group (optional)',
                prefixIcon: const Icon(Icons.bloodtype_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
              hint: const Text('Select blood group'),
              items: const [
                DropdownMenuItem(value: 'A+',  child: Text('A+')),
                DropdownMenuItem(value: 'A-',  child: Text('A-')),
                DropdownMenuItem(value: 'B+',  child: Text('B+')),
                DropdownMenuItem(value: 'B-',  child: Text('B-')),
                DropdownMenuItem(value: 'O+',  child: Text('O+')),
                DropdownMenuItem(value: 'O-',  child: Text('O-')),
                DropdownMenuItem(value: 'AB+', child: Text('AB+')),
                DropdownMenuItem(value: 'AB-', child: Text('AB-')),
              ],
              onChanged: (v) => setState(() => _bloodGroup = v),
            ),
            const SizedBox(height: 14),
            _Field(
              controller: _allergiesCtrl,
              label: 'Allergies / Conditions (optional)',
              icon: Icons.medical_information_outlined,
              caps: TextCapitalization.sentences,
              maxLength: 150,
            ),
            const SizedBox(height: 14),
            // Transport Mode dropdown
            DropdownButtonFormField<String>(
              value: _transportMode,
              decoration: InputDecoration(
                labelText: 'Transport Mode (optional)',
                prefixIcon: const Icon(Icons.directions_bus_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
              hint: const Text('Select transport mode'),
              items: const [
                DropdownMenuItem(value: 'School Bus',       child: Text('School Bus')),
                DropdownMenuItem(value: 'Walking',          child: Text('Walking')),
                DropdownMenuItem(value: 'Personal Vehicle', child: Text('Personal Vehicle')),
                DropdownMenuItem(value: 'Auto / Rickshaw',  child: Text('Auto / Rickshaw')),
                DropdownMenuItem(value: 'Other',            child: Text('Other')),
              ],
              onChanged: (v) => setState(() => _transportMode = v),
            ),
            const SizedBox(height: 14),
            // Student Date of Birth
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _dateOfBirth ??
                      DateTime.now().subtract(const Duration(days: 365 * 10)),
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                  helpText: 'Student Date of Birth',
                );
                if (picked != null) setState(() => _dateOfBirth = picked);
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Student Date of Birth',
                  prefixIcon: const Icon(Icons.cake_outlined),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                  suffixIcon: _dateOfBirth != null
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () =>
                              setState(() => _dateOfBirth = null),
                        )
                      : null,
                ),
                child: Text(
                  _dateOfBirth != null
                      ? '${_dateOfBirth!.day.toString().padLeft(2,'0')} / '
                        '${_dateOfBirth!.month.toString().padLeft(2,'0')} / '
                        '${_dateOfBirth!.year}'
                      : 'Tap to select',
                  style: TextStyle(
                      fontSize: 15,
                      color: _dateOfBirth != null
                          ? Colors.black87
                          : Colors.grey.shade500),
                ),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _feeStatus,
              decoration: InputDecoration(
                labelText: 'Fee Status',
                prefixIcon: const Icon(Icons.currency_rupee),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 14),
              ),
              items: const [
                DropdownMenuItem(
                    value: 'Paid',
                    child: Row(children: [
                      Icon(Icons.check_circle,
                          color: Colors.green, size: 18),
                      SizedBox(width: 8),
                      Text('Paid'),
                    ])),
                DropdownMenuItem(
                    value: 'Pending',
                    child: Row(children: [
                      Icon(Icons.cancel, color: Colors.red, size: 18),
                      SizedBox(width: 8),
                      Text('Pending'),
                    ])),
                DropdownMenuItem(
                    value: 'Partial',
                    child: Row(children: [
                      Icon(Icons.timelapse,
                          color: Colors.orange, size: 18),
                      SizedBox(width: 8),
                      Text('Partial'),
                    ])),
              ],
              onChanged: (v) => setState(() => _feeStatus = v!),
            ),
            const SizedBox(height: 14),

            // Fee Amount (optional)
            _Field(
              controller: _feeAmountCtrl,
              label: 'Fee Amount (optional)',
              icon: Icons.currency_rupee,
              keyboard: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
            ),
            const SizedBox(height: 14),

            // Fee Due Date (optional)
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _feeDueDate != null
                      ? (DateTime.tryParse(_feeDueDate!) ?? DateTime.now())
                      : DateTime.now().add(const Duration(days: 30)),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  setState(() {
                    _feeDueDate =
                        '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                  });
                }
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Fee Due Date (optional)',
                  prefixIcon: const Icon(Icons.calendar_today_outlined),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                  suffixIcon: _feeDueDate != null
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () =>
                              setState(() => _feeDueDate = null),
                        )
                      : null,
                ),
                child: Text(
                  _feeDueDate ?? 'Tap to select a date',
                  style: TextStyle(
                      fontSize: 15,
                      color: _feeDueDate != null
                          ? Colors.black87
                          : Colors.grey.shade500),
                ),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                child: Text(
                    _saving
                        ? 'Saving...'
                        : (_isEdit ? 'Update Student' : 'Add Student'),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType keyboard;
  final TextCapitalization caps;
  final String? Function(String?)? validator;
  final bool enabled;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;

  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboard = TextInputType.text,
    this.caps = TextCapitalization.none,
    this.validator,
    this.enabled = true,
    this.inputFormatters,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboard,
      textCapitalization: caps,
      validator: validator,
      inputFormatters: inputFormatters,
      maxLength: maxLength,
      maxLengthEnforcement: MaxLengthEnforcement.enforced,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}

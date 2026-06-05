import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/student.dart';
import '../models/guardian_student_details.dart';
import '../models/guardian_provided_details.dart';
import '../models/school_provided_details.dart';
import '../services/student_service.dart';
import '../theme.dart';

class GuardianStudentDetailsScreen extends StatefulWidget {
  final Student student;

  const GuardianStudentDetailsScreen({super.key, required this.student});

  @override
  State<GuardianStudentDetailsScreen> createState() => _GuardianStudentDetailsScreenState();
}

class _GuardianStudentDetailsScreenState extends State<GuardianStudentDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = StudentService();

  // Student Profile
  late TextEditingController _nameController;
  late TextEditingController _dobController;
  String _gender = '';

  // Parent Details
  late TextEditingController _fatherNameController;
  late TextEditingController _motherNameController;
  late TextEditingController _phoneController;
  late TextEditingController _parentPhoneController;
  late TextEditingController _addressController;

  // Academic Info
  late TextEditingController _previousSchoolController;

  // Medical Info
  late TextEditingController _bloodGroupController;
  late TextEditingController _emergencyNameController;
  late TextEditingController _emergencyPhoneController;
  late TextEditingController _allergiesController;

  // Others
  late TextEditingController _transportController;

  File? _imageFile;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.student;
    final d = s.guardianDetails;

    _nameController = TextEditingController(text: s.name);
    _dobController = TextEditingController(text: d?.dob ?? '');
    _gender = d?.gender ?? '';

    _fatherNameController = TextEditingController(text: s.fatherName);
    _motherNameController = TextEditingController(text: s.motherName ?? '');
    _phoneController = TextEditingController(text: s.phone);
    _parentPhoneController = TextEditingController(text: s.parentPhone ?? '');
    _addressController = TextEditingController(text: d?.address ?? '');

    _previousSchoolController = TextEditingController(text: d?.previousSchool ?? '');

    _bloodGroupController = TextEditingController(text: d?.bloodGroup ?? '');
    _emergencyNameController = TextEditingController(text: d?.emergencyContactName ?? '');
    _emergencyPhoneController = TextEditingController(text: d?.emergencyContactPhone ?? '');
    _allergiesController = TextEditingController(text: d?.allergies ?? '');

    _transportController = TextEditingController(text: d?.transportMode ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dobController.dispose();
    _fatherNameController.dispose();
    _motherNameController.dispose();
    _phoneController.dispose();
    _parentPhoneController.dispose();
    _addressController.dispose();
    _previousSchoolController.dispose();
    _bloodGroupController.dispose();
    _emergencyNameController.dispose();
    _emergencyPhoneController.dispose();
    _allergiesController.dispose();
    _transportController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
    if (picked != null) {
      setState(() => _imageFile = File(picked.path));
    }
  }

  Timestamp? _parseDob(String dob) {
    try {
      final parts = dob.split('/');
      if (parts.length == 3) {
        final day = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final year = int.parse(parts[2]);
        return Timestamp.fromDate(DateTime(year, month, day));
      }
    } catch (_) {}
    return null;
  }

  Future<void> _acceptSchoolDetails(SchoolProvidedDetails details) async {
    setState(() => _isSaving = true);
    try {
      final newDetails = GuardianStudentDetails(
        dob: details.dob,
        gender: details.gender,
        address: details.address,
        bloodGroup: details.bloodGroup,
        emergencyContactName: details.emergencyContactName,
        emergencyContactPhone: details.emergencyContactPhone,
        allergies: details.allergies,
        transportMode: details.transportMode,
        previousSchool: details.previousSchool,
        lastUpdated: DateTime.now().toIso8601String(),
      );

      final updatedStudent = widget.student.copyWith(
        name: details.name,
        fatherName: details.fatherName,
        motherName: details.motherName,
        phone: details.phone,
        parentPhone: details.parentPhone,
        guardianDetails: newDetails,
        dateOfBirth: _parseDob(details.dob),
        gender: details.gender,
        address: details.address,
        previousSchool: details.previousSchool,
        bloodGroup: details.bloodGroup,
        allergies: details.allergies,
        transportMode: details.transportMode,
        emergencyContact: details.emergencyContactName.isNotEmpty || details.emergencyContactPhone.isNotEmpty
            ? '${details.emergencyContactName} (${details.emergencyContactPhone})'
            : null,
      );

      await _service.updateStudent(updated: updatedStudent);
      await _service.updateSchoolProvidedDetailsStatus(widget.student.id, details.id, 'accepted');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('School updates accepted and applied')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to accept updates: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _requestSchoolClarification(SchoolProvidedDetails details) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Request Clarification'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter why you are requesting clarification...',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Submit'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      setState(() => _isSaving = true);
      try {
        await _service.updateSchoolProvidedDetailsStatus(
          widget.student.id,
          details.id,
          'clarification_requested',
          remarks: result,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Clarification request sent to school')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to request clarification: $e')),
        );
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
    }
  }

  Widget _buildSchoolDetailsSection(SchoolProvidedDetails details) {
    final diffs = <String, List<String>>{};

    void compare(String fieldName, String currentValue, String newValue) {
      if (newValue.trim().isNotEmpty && currentValue.trim() != newValue.trim()) {
        diffs[fieldName] = [currentValue, newValue];
      }
    }

    final s = widget.student;
    final d = s.guardianDetails;

    compare('Full Name', s.name, details.name);
    compare('Date of Birth', d?.dob ?? '', details.dob);
    compare('Gender', d?.gender ?? '', details.gender);
    compare("Father's Name", s.fatherName, details.fatherName);
    compare("Mother's Name", s.motherName ?? '', details.motherName);
    compare('Primary Phone', s.phone, details.phone);
    compare('Secondary Phone', s.parentPhone ?? '', details.parentPhone);
    compare('Address', d?.address ?? '', details.address);
    compare('Previous School', d?.previousSchool ?? '', details.previousSchool);
    compare('Blood Group', d?.bloodGroup ?? '', details.bloodGroup);
    compare('Emergency Contact Name', d?.emergencyContactName ?? '', details.emergencyContactName);
    compare('Emergency Contact Phone', d?.emergencyContactPhone ?? '', details.emergencyContactPhone);
    compare('Allergies', d?.allergies ?? '', details.allergies);
    compare('Transport Mode', d?.transportMode ?? '', details.transportMode);

    if (diffs.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.only(bottom: 24),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.amber.shade800),
                const SizedBox(width: 8),
                Text(
                  'Details updated by school',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...diffs.entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(color: Colors.black87, fontSize: 14),
                    children: [
                      TextSpan(
                        text: '${entry.key}: ',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(
                        text: entry.value[0].isEmpty ? '[Empty]' : entry.value[0],
                        style: const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.red),
                      ),
                      const TextSpan(text: '  ➔  '),
                      TextSpan(
                        text: entry.value[1],
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade700),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
            if (details.remarks.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Remarks: ${details.remarks}',
                style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.black54),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _requestSchoolClarification(details),
                  child: Text(
                    'Request Clarification',
                    style: TextStyle(color: Colors.amber.shade900),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _acceptSchoolDetails(details),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber.shade800,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Accept Changes'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final newDetails = GuardianProvidedDetails(
        name: _nameController.text.trim(),
        dob: _dobController.text.trim(),
        gender: _gender,
        fatherName: _fatherNameController.text.trim(),
        motherName: _motherNameController.text.trim(),
        phone: _phoneController.text.trim(),
        parentPhone: _parentPhoneController.text.trim(),
        address: _addressController.text.trim(),
        previousSchool: _previousSchoolController.text.trim(),
        bloodGroup: _bloodGroupController.text.trim(),
        emergencyContactName: _emergencyNameController.text.trim(),
        emergencyContactPhone: _emergencyPhoneController.text.trim(),
        allergies: _allergiesController.text.trim(),
        transportMode: _transportController.text.trim(),
        guardianUid: FirebaseAuth.instance.currentUser?.uid ?? '',
        status: 'pending',
        remarks: '',
      );

      await _service.submitGuardianProvidedDetails(widget.student.id, newDetails);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Details submitted to class teacher for verification')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit updates: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Details'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<SchoolProvidedDetails>>(
        stream: _service.watchSchoolProvidedDetails(widget.student.id),
        builder: (context, snapshot) {
          final list = snapshot.data ?? [];
          final pendingSchoolDetails = list.firstWhere(
            (d) => d.status == 'pending',
            orElse: () => const SchoolProvidedDetails(id: ''),
          );

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (pendingSchoolDetails.id.isNotEmpty)
                    _buildSchoolDetailsSection(pendingSchoolDetails),

                  // ── DOCUMENTS / PHOTO ──
              _buildSectionTitle('Documents & Photo'),
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: _imageFile != null
                          ? FileImage(_imageFile!)
                          : (widget.student.photoUrl != null
                              ? CachedNetworkImageProvider(widget.student.photoUrl!)
                              : (widget.student.photoPath != null
                                  ? FileImage(File(widget.student.photoPath!))
                                  : null)) as ImageProvider?,
                      child: (_imageFile == null && widget.student.photoUrl == null && widget.student.photoPath == null)
                          ? const Icon(Icons.person, size: 50, color: Colors.grey)
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: CircleAvatar(
                        backgroundColor: AppTheme.primary,
                        radius: 18,
                        child: IconButton(
                          icon: const Icon(Icons.camera_alt, size: 18, color: Colors.white),
                          onPressed: _pickImage,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── STUDENT PROFILE ──
              _buildSectionTitle('Student Profile'),
              _buildTextField(_nameController, 'Full Name', Icons.person),
              _buildTextField(_dobController, 'Date of Birth (DD/MM/YYYY)', Icons.cake),
              _buildGenderDropdown(),
              _buildReadOnlyField('Class / Section', '${widget.student.className} ${widget.student.section}'),
              _buildReadOnlyField('Roll Number', widget.student.roll.toString()),

              const SizedBox(height: 24),

              // ── PARENT DETAILS ──
              _buildSectionTitle('Parent Details'),
              _buildTextField(_fatherNameController, "Father's Name", Icons.man),
              _buildTextField(_motherNameController, "Mother's Name", Icons.woman),
              _buildTextField(_phoneController, 'Primary Contact Number', Icons.phone, keyboardType: TextInputType.phone),
              _buildTextField(_parentPhoneController, 'Secondary Contact Number', Icons.phone_android, keyboardType: TextInputType.phone),
              _buildTextField(_addressController, 'Home Address', Icons.home, maxLines: 2),

              const SizedBox(height: 24),

              // ── ACADEMIC INFO ──
              _buildSectionTitle('Academic Info'),
              _buildTextField(_previousSchoolController, 'Previous School (if any)', Icons.school),

              const SizedBox(height: 24),

              // ── MEDICAL INFO ──
              _buildSectionTitle('Medical Info'),
              _buildTextField(_bloodGroupController, 'Blood Group', Icons.bloodtype),
              _buildTextField(_emergencyNameController, 'Emergency Contact Name', Icons.contact_phone),
              _buildTextField(_emergencyPhoneController, 'Emergency Contact Phone', Icons.phone_callback, keyboardType: TextInputType.phone),
              _buildTextField(_allergiesController, 'Allergies / Medical Conditions', Icons.medical_services, maxLines: 2),

              const SizedBox(height: 24),

              // ── TRANSPORT ──
              _buildSectionTitle('Others'),
              _buildTextField(_transportController, 'Mode of Transport', Icons.directions_bus),

              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSaving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Save All Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      );
    },
  ),
);
}

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primary, letterSpacing: 1.1),
          ),
          const Divider(thickness: 1),
        ],
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: AppTheme.primary, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        keyboardType: keyboardType,
        maxLines: maxLines,
      ),
    );
  }

  Widget _buildReadOnlyField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        initialValue: value,
        readOnly: true,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.lock_outline, color: Colors.grey, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.grey.shade50,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildGenderDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        value: _gender.isEmpty ? null : _gender,
        decoration: InputDecoration(
          labelText: 'Gender',
          prefixIcon: const Icon(Icons.people_outline, color: AppTheme.primary, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        items: ['Male', 'Female', 'Other']
            .map((g) => DropdownMenuItem(value: g, child: Text(g)))
            .toList(),
        onChanged: (val) => setState(() => _gender = val ?? ''),
      ),
    );
  }
}

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../l10n/app_strings.dart';
import '../models/student.dart';
import '../models/school_provided_details.dart';
import '../services/auth_service.dart';
import '../services/base_firestore_service.dart';
import '../services/student_service.dart';
import '../services/timetable_service.dart';
import '../utils/app_logger.dart';
import '../theme.dart';
import '../widgets/email_text_form_field.dart';
import '../widgets/managed_dropdown.dart';
import 'consent/parental_consent_flow.dart';

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
  final _guardianEmailCtrl   = TextEditingController();
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
      _parentPhoneCtrl.text     = s.parentPhone ?? '';
      _guardianEmailCtrl.text   = s.guardianEmail ?? '';
      _addressCtrl.text         = s.address ?? '';
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
    _guardianEmailCtrl.dispose();
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
            title: Text(context.tr('takePhoto')),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: Text(context.tr('chooseFromGallery')),
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

  /// Looks for an existing student in the same class/section whose identifying
  /// details (name + father's name, and phone when given) match what's being
  /// entered. If found, asks the user to confirm before saving a likely
  /// duplicate. Returns true to proceed, false to cancel.
  Future<bool> _confirmNotDuplicate() async {
    String norm(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final name   = norm(_nameCtrl.text);
    final father = norm(_fatherCtrl.text);
    final phone  = norm(_phoneCtrl.text);
    if (name.isEmpty) return true;

    List<Student> existing;
    try {
      existing = await StudentService().getStudentsByClass(
        className: widget.className,
        section:   widget.section,
        teacherId: widget.teacherId,
      );
    } catch (_) {
      return true; // don't block saving if the lookup fails
    }

    final match = existing.where((s) {
      final sameName   = norm(s.name) == name;
      final sameFather = norm(s.fatherName) == father;
      final samePhone  = phone.isNotEmpty && norm(s.phone) == phone;
      // Same name + (same father OR same phone) is a strong duplicate signal.
      return sameName && (sameFather || samePhone);
    }).toList();
    if (match.isEmpty) return true;
    if (!mounted) return true;

    final dup = match.first;
    final sec = widget.section.isNotEmpty ? '-${widget.section}' : '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('possibleDuplicate')),
        content: Text(
          '${context.tr('dupDialogPart1')}\n\n'
          '${dup.name} (${context.tr('roll')} ${dup.roll}, ${widget.className}$sec).\n\n'
          '${context.tr('dupDialogPart2')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('saveAnyway')),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // Warn before adding what looks like a record that already exists. Only on
    // the add path — editing an existing student is expected to "match".
    if (!_isEdit && !await _confirmNotDuplicate()) return;

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
      guardianEmail: _guardianEmailCtrl.text.trim().isEmpty
          ? null
          : _guardianEmailCtrl.text.trim().toLowerCase(),
      feeStatus: _feeStatus,
      feeDueDate: _feeDueDate,
      feeAmount: double.tryParse(_feeAmountCtrl.text.trim()),
      teacherId: widget.teacherId ?? widget.existing?.teacherId,
      dateOfBirth: _dateOfBirth != null ? Timestamp.fromDate(_dateOfBirth!) : null,
    );

    // Diagnostic context: capture the caller's role + schoolId so a
    // permission-denied surfaces enough info to fix the actual rule path.
    // This block is cheap (SharedPreferences) and runs before any write.
    final session = await AuthService().getSession();
    final role    = (session?['role']     as String?) ?? '(no role)';
    final sid     = BaseFirestoreService.currentSchoolId ?? '(null)';
    // Debug-only (AppLogger is a no-op in release) so student/guardian PII
    // never reaches the release binary's logs (#25, #86).
    AppLogger.d('AddStudent',
        'starting save · role=$role · schoolId=$sid · '
        'class=${widget.className} · section=${widget.section} · '
        'roll=${student.roll} · guardian=${student.guardianEmail ?? "—"}');

    String? failedStep;
    final service = StudentService();
    try {
      if (_isEdit) {
        final dobStr = _dateOfBirth != null
            ? '${_dateOfBirth!.day.toString().padLeft(2, '0')}/${_dateOfBirth!.month.toString().padLeft(2, '0')}/${_dateOfBirth!.year}'
            : '';
        final newDetails = SchoolProvidedDetails(
          name: _nameCtrl.text.trim(),
          dob: dobStr,
          gender: _gender ?? '',
          fatherName: _fatherCtrl.text.trim(),
          motherName: _motherCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
          parentPhone: _parentPhoneCtrl.text.trim(),
          address: _addressCtrl.text.trim(),
          previousSchool: _prevSchoolCtrl.text.trim(),
          bloodGroup: _bloodGroup ?? '',
          emergencyContactName: _emergencyCtrl.text.trim(),
          emergencyContactPhone: '',
          allergies: _allergiesCtrl.text.trim(),
          transportMode: _transportMode ?? '',
          teacherUid: FirebaseAuth.instance.currentUser?.uid ?? '',
          teacherName: (session?['name'] as String?) ?? FirebaseAuth.instance.currentUser?.displayName ?? '',
          status: 'pending',
          remarks: '',
        );

        failedStep = 'submit school provided details proposal';
        await service.submitSchoolProvidedDetails(widget.existing!.id, newDetails);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.tr('detailsProposalSubmitted'))),
          );
          Navigator.pop(context, widget.existing);
        }
      } else {
        failedStep = 'create student record';
        final error = await service.addStudent(student: student);
        if (!mounted) return;
        if (error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(error), backgroundColor: Colors.red));
          setState(() => _saving = false);
          return;
        }

        // ── Guardian portal login ─────────────────────────────────────────
        // If a guardian email was provided, provision a Firebase Auth account
        // and send the password-setup / invite email so the parent can log in.
        // Without this, the email typed into the form never receives anything
        // (the edit path does this via addAllowedUser; the add path used to
        // skip it entirely). Kept non-fatal: the student record is already
        // saved, so an invite failure must not lose the student or block the
        // consent flow — it surfaces a non-blocking warning the admin can act
        // on (resend invite) instead.
        final guardianEmail = student.guardianEmail?.trim().toLowerCase() ?? '';
        if (guardianEmail.isNotEmpty) {
          try {
            await TimetableService().provisionGuardianLoginAccess(
              email:        guardianEmail,
              studentClass: student.className,
              studentRoll:  student.roll,
              studentName:  student.name,
              schoolId:     BaseFirestoreService.currentSchoolId,
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('${context.tr('loginInviteSentTo')} $guardianEmail'),
                backgroundColor: AppTheme.success,
              ));
            }
          } catch (e) {
            AppLogger.e('AddStudent',
                'guardian invite failed for $guardianEmail · '
                'role=$role · schoolId=$sid', e);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(
                  '${context.tr('inviteFailedPrefix')} $guardianEmail '
                  '${context.tr('inviteFailedSuffix')}',
                ),
                backgroundColor: AppTheme.warning,
                duration: const Duration(seconds: 8),
              ));
            }
          }
        }

        // ── Parental consent flow ─────────────────────────────────────────
        // Build the canonical student doc ID that StudentService uses.
        final studentDocId = Student.buildDocId(student.roll, widget.className, widget.section);

        if (!mounted) return;
        failedStep = 'open parental consent';
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ParentalConsentFlow(
              studentDocId:        studentDocId,
              studentName:         student.name,
              prefillGuardianName: student.fatherName.isNotEmpty
                                       ? student.fatherName
                                       : null,
              prefillGuardianPhone: (student.parentPhone?.isNotEmpty == true)
                                        ? student.parentPhone
                                        : (student.phone.isNotEmpty
                                              ? student.phone
                                              : null),
            ),
            fullscreenDialog: true,
          ),
        );
        if (mounted) Navigator.pop(context, student);
      }
    } catch (e) {
      // Surface BOTH which step failed and the caller context so the next
      // diagnosis is one shot. `failedStep` tells us the exact write whose
      // rule branch is the culprit.
      AppLogger.e('AddStudent',
          'FAILED at step "${failedStep ?? "unknown"}" · '
          'role=$role · schoolId=$sid', e);
      // Pull the caller's own allowed_users classIds so a permission-denied
      // shows exactly why isClassTeacher() failed (the #1 cause is a class the
      // teacher isn't assigned to, or a schoolId mismatch).
      List<dynamic> classIds = const [];
      try {
        final email = session?['email'] as String?;
        if (email != null) {
          final doc = await TimetableService().getAllowedUserDoc(email);
          classIds = (doc?['classIds'] as List?) ?? const [];
        }
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Failed at "${failedStep ?? "save"}" (role=$role)\n'
          'school=$sid · class=${widget.className}-${widget.section}\n'
          'your classes=$classIds\n$e',
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 12),
      ));
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(_isEdit ? context.tr('editStudent') : context.tr('addStudent')),
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
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
              ),
              child: Row(children: [
                const Icon(Icons.class_, color: AppTheme.primary, size: 18),
                const SizedBox(width: 8),
                Text(context.tr('addingTo'),
                    style: const TextStyle(color: AppTheme.primary)),
                Text(
                  widget.section.isEmpty
                      ? widget.className
                      : '${widget.className} — ${context.tr('sectionWord')} ${widget.section}',
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
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.08),
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
            Text(context.tr('tapToAddPhoto'),
                style:
                    TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            const SizedBox(height: 20),

            _Field(
              controller: _rollCtrl,
              label: context.tr('rollNumber'),
              icon: Icons.tag,
              keyboard: TextInputType.number,
              enabled: !_isEdit,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) {
                if (v == null || v.trim().isEmpty) return context.tr('validationRequired');
                final n = int.tryParse(v.trim());
                if (n == null) return context.tr('mustBeNumber');
                if (n < 1 || n > 999) return context.tr('mustBe1to999');
                return null;
              },
            ),
            const SizedBox(height: 14),
            _Field(
              controller: _nameCtrl,
              label: context.tr('fullName'),
              icon: Icons.person_outline,
              caps: TextCapitalization.words,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z ]')),
              ],
              maxLength: 50,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? context.tr('validationRequired') : null,
            ),
            const SizedBox(height: 14),
            _Field(
              controller: _fatherCtrl,
              label: context.tr('fathersName'),
              icon: Icons.man_outlined,
              caps: TextCapitalization.words,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z ]')),
              ],
              maxLength: 50,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? context.tr('validationRequired') : null,
            ),
            const SizedBox(height: 14),
            _Field(
              controller: _motherCtrl,
              label: context.tr('mothersNameOpt'),
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
              label: context.tr('primaryContactPhone'),
              icon: Icons.phone_outlined,
              keyboard: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 10,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return context.tr('validationRequired');
                if (v.trim().length != 10) return context.tr('mustBe10Digits');
                return null;
              },
            ),
            const SizedBox(height: 14),
            _Field(
              controller: _parentPhoneCtrl,
              label: context.tr('secondaryContactOpt'),
              icon: Icons.phone_android_outlined,
              keyboard: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 10,
            ),
            const SizedBox(height: 14),
            _Field(
              controller: _guardianEmailCtrl,
              label: context.tr('guardianEmailPortal'),
              icon: Icons.email_outlined,
              keyboard: TextInputType.emailAddress,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(v.trim())) {
                  return context.tr('enterValidEmail');
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            // Gender dropdown
            DropdownButtonFormField<String>(
              value: _gender,
              decoration: InputDecoration(
                labelText: context.tr('genderOpt'),
                prefixIcon: const Icon(Icons.wc_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
              hint: Text(context.tr('selectGender')),
              items: [
                DropdownMenuItem(value: 'Male',   child: Text(context.tr('genderMale'))),
                DropdownMenuItem(value: 'Female', child: Text(context.tr('genderFemale'))),
                DropdownMenuItem(value: 'Other',  child: Text(context.tr('genderOther'))),
              ],
              onChanged: (v) => setState(() => _gender = v),
            ),
            const SizedBox(height: 14),
            _Field(
              controller: _addressCtrl,
              label: context.tr('addressOpt'),
              icon: Icons.home_outlined,
              caps: TextCapitalization.sentences,
              maxLength: 150,
            ),
            const SizedBox(height: 14),
            _Field(
              controller: _prevSchoolCtrl,
              label: context.tr('previousSchoolOpt'),
              icon: Icons.account_balance_outlined,
              caps: TextCapitalization.words,
              maxLength: 80,
            ),
            const SizedBox(height: 14),
            _Field(
              controller: _emergencyCtrl,
              label: context.tr('emergencyContactOpt'),
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
                labelText: context.tr('bloodGroupOpt'),
                prefixIcon: const Icon(Icons.bloodtype_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
              hint: Text(context.tr('selectBloodGroup')),
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
              label: context.tr('allergiesConditionsOpt'),
              icon: Icons.medical_information_outlined,
              caps: TextCapitalization.sentences,
              maxLength: 150,
            ),
            const SizedBox(height: 14),
            // Transport Mode dropdown
            ManagedDropdown(
              fieldKey: 'student_transport_mode',
              label: context.tr('transportModeOpt'),
              hint: context.tr('selectTransportMode'),
              prefixIcon: const Icon(Icons.directions_bus_outlined),
              isDense: false,
              value: _transportMode,
              seeds: const [
                'School Bus',
                'Walking',
                'Personal Vehicle',
                'Auto / Rickshaw',
                'Other',
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
                  helpText: context.tr('studentDateOfBirth'),
                );
                if (picked != null) setState(() => _dateOfBirth = picked);
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: context.tr('studentDateOfBirth'),
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
                      : context.tr('tapToSelect'),
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
                labelText: context.tr('feeStatus'),
                prefixIcon: const Icon(Icons.currency_rupee),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 14),
              ),
              items: [
                DropdownMenuItem(
                    value: 'Paid',
                    child: Row(children: [
                      const Icon(Icons.check_circle,
                          color: Colors.green, size: 18),
                      const SizedBox(width: 8),
                      Text(context.tr('paidLabel')),
                    ])),
                DropdownMenuItem(
                    value: 'Pending',
                    child: Row(children: [
                      const Icon(Icons.cancel, color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Text(context.tr('statusPending')),
                    ])),
                DropdownMenuItem(
                    value: 'Partial',
                    child: Row(children: [
                      const Icon(Icons.timelapse,
                          color: Colors.orange, size: 18),
                      const SizedBox(width: 8),
                      Text(context.tr('partialLabel')),
                    ])),
              ],
              onChanged: (v) => setState(() => _feeStatus = v!),
            ),
            const SizedBox(height: 14),

            // Fee Amount (optional)
            _Field(
              controller: _feeAmountCtrl,
              label: context.tr('feeAmountOpt'),
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
                  labelText: context.tr('feeDueDateOpt'),
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
                  _feeDueDate ?? context.tr('tapToSelectDate'),
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
                        ? context.tr('savingEllipsis')
                        : (_isEdit ? context.tr('updateStudent') : context.tr('addStudent')),
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
    final isEmail = keyboard == TextInputType.emailAddress;
    if (isEmail) {
      return EmailTextFormField(
        controller: controller,
        enabled: enabled,
        textCapitalization: caps,
        validator: validator,
        inputFormatters: inputFormatters,
        maxLength: maxLength,
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
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboard,
      autocorrect: true,
      enableSuggestions: true,
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

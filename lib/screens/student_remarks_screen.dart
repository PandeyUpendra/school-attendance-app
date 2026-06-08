import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_strings.dart';
import '../models/student.dart';
import '../models/student_remark.dart';
import '../services/auth_service.dart';
import '../services/student_service.dart';
import '../services/timetable_service.dart';
import '../services/consent_service.dart';
import '../theme.dart';
import '../utils/phone_utils.dart';

// ── Remark presets ────────────────────────────────────────────────────────────

class _RemarkPreset {
  final String label;
  final String messageTemplate; // {name} is replaced with student name
  _RemarkPreset(this.label, this.messageTemplate);
}

// ── Teacher → Parent presets ──────────────────────────────────────────────────

final _kNegativePresets = [
  _RemarkPreset('Not completing homework',
      'Dear Parent, we want to inform you that {name} has not been completing homework regularly. Please encourage regular practice at home.'),
  _RemarkPreset('Frequently late to class',
      'Dear Parent, {name} has been frequently late to class. Please ensure timely arrival to school.'),
  _RemarkPreset('Very talkative in class',
      'Dear Parent, {name} tends to be very talkative during class and it is affecting the learning environment. Please discuss this at home.'),
  _RemarkPreset('Needs to improve focus',
      'Dear Parent, {name} needs to improve focus during lessons. Limiting distractions at home during study time will help greatly.'),
  _RemarkPreset('Missing school supplies',
      'Dear Parent, {name} has been coming to school without necessary supplies. Please ensure all required materials are available.'),
  _RemarkPreset('Disruptive behavior in class',
      'Dear Parent, we have noticed some disruptive behavior from {name} in class. We request your cooperation in addressing this.'),
  _RemarkPreset('Needs extra academic support',
      'Dear Parent, {name} is struggling with certain topics and may need extra academic support. Please consider additional practice or tutoring.'),
  _RemarkPreset('Irregular attendance',
      'Dear Parent, {name} has been absent frequently. Regular attendance is important for academic progress. Please ensure timely presence.'),
];

final _kPositivePresets = [
  _RemarkPreset('Excellent class participation',
      'Dear Parent, we are delighted to share that {name} has been showing excellent participation in class. Keep encouraging this enthusiasm!'),
  _RemarkPreset('Great improvement shown',
      'Dear Parent, {name} has shown great improvement recently. This is wonderful progress and we appreciate your support at home.'),
  _RemarkPreset('Outstanding behavior',
      'Dear Parent, {name} has been displaying outstanding behavior in school. We are very proud of this conduct!'),
  _RemarkPreset('Consistently completes work',
      'Dear Parent, {name} consistently completes all class and homework on time. This is commendable dedication!'),
  _RemarkPreset('Helping and respectful',
      'Dear Parent, {name} has been very helpful and respectful towards classmates and teachers. A great role model!'),
  _RemarkPreset('Excellent test performance',
      'Dear Parent, {name} has performed excellently in recent tests. All your efforts at home are clearly paying off!'),
];

// ── Guardian → School presets ─────────────────────────────────────────────────

final _kGuardianConcernPresets = [
  _RemarkPreset('Child is unwell today',
      'Dear Teacher, I want to inform you that {name} is not feeling well today and may need extra attention or rest.'),
  _RemarkPreset('Will be absent tomorrow',
      'Dear Teacher, I wish to inform you that {name} will be absent tomorrow due to personal reasons. Kindly note the absence.'),
  _RemarkPreset('Struggling with homework',
      'Dear Teacher, {name} has been finding the homework difficult lately. Could you please provide some extra guidance or simplified notes?'),
  _RemarkPreset('Requesting parent meeting',
      'Dear Teacher, I would like to schedule a meeting to discuss {name}\'s progress. Please let me know a convenient time.'),
  _RemarkPreset('Family emergency',
      'Dear Teacher, due to a family emergency, {name} may miss school for a few days. I will keep you updated. Please help with any missed work.'),
  _RemarkPreset('Late arrival today',
      'Dear Teacher, {name} will be arriving late today. I apologise for the inconvenience.'),
  _RemarkPreset('Please send study material',
      'Dear Teacher, could you please share any study material or notes for {name} that can help with exam preparation? Thank you.'),
  _RemarkPreset('Medical condition update',
      'Dear Teacher, I wanted to inform you about a recent medical condition of {name} that may affect attendance or performance in class.'),
];

final _kGuardianPraisePresets = [
  _RemarkPreset('Thank you for your support',
      'Dear Teacher, I want to sincerely thank you for the wonderful support and guidance you have been providing to {name}. We truly appreciate it.'),
  _RemarkPreset('Child enjoying school',
      'Dear Teacher, {name} has been very excited about school lately and speaks highly of your teaching. Thank you for making learning enjoyable!'),
  _RemarkPreset('Improvement noticed at home',
      'Dear Teacher, we have noticed a great improvement in {name}\'s studies and attitude at home. Your efforts are clearly making a difference.'),
  _RemarkPreset('Excellent exam preparation',
      'Dear Teacher, thank you for the thorough exam preparation provided to {name}. The extra effort from your side is greatly appreciated.'),
  _RemarkPreset('Great class environment',
      'Dear Teacher, {name} loves the class environment you have created. It is encouraging and motivating for the children. Keep up the great work!'),
];

// ── Screen ────────────────────────────────────────────────────────────────────

class StudentRemarksScreen extends StatefulWidget {
  final String   role;
  final String?  teacherClassName;
  final String?  teacherSection;
  final String?  teacherId;
  final Student? guardianStudent;

  const StudentRemarksScreen({
    super.key,
    required this.role,
    this.teacherClassName,
    this.teacherSection,
    this.teacherId,
    this.guardianStudent,
  });

  @override
  State<StudentRemarksScreen> createState() => _StudentRemarksScreenState();
}

class _StudentRemarksScreenState extends State<StudentRemarksScreen> {
  final _studentService = StudentService();
  final _ttService      = TimetableService();
  final _consentSvc     = ConsentService();
  final _customCtrl     = TextEditingController();

  String  _myEmail     = '';
  String  _myRole      = '';
  String? _myTeacherId;

  List<String>  _classes        = [];
  String?       _selectedClass;
  List<Student> _classStudents  = [];
  Student?      _selectedStudent;
  bool          _loadingStudents = false;

  // Remark input state
  _RemarkPreset? _selectedPreset;
  String         _selectedType = 'negative'; // 'positive' | 'negative'
  bool           _saving       = false;

  List<StudentRemark> _remarks        = [];
  bool                _loadingRemarks = false;

  @override
  void initState() {
    super.initState();
    _customCtrl.addListener(() => setState(() {}));
    _init();
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final session = await AuthService().getSession();
    _myEmail     = session?['email']     as String? ?? '';
    _myRole      = session?['role']      as String? ?? widget.role;
    _myTeacherId = session?['teacherId'] as String?;

    if (widget.role == 'guardian' && widget.guardianStudent != null) {
      setState(() => _selectedStudent = widget.guardianStudent);
      _loadRemarks(widget.guardianStudent!);
      return;
    }

    if (widget.role == 'teacher' && widget.teacherClassName != null) {
      setState(() {
        _selectedClass   = widget.teacherClassName;
        _loadingStudents = true;
      });
      final list = await _studentService.getStudentsByClass(
        className: widget.teacherClassName!,
        section:   widget.teacherSection ?? '',
        teacherId: widget.teacherId,
      );
      if (!mounted) return;
      setState(() { _classStudents = list; _loadingStudents = false; });
      return;
    }

    final settings = await _ttService.getSettings();
    final classes  = List<String>.from(settings['classes'] as List? ?? []);
    if (!mounted) return;
    setState(() => _classes = classes);
  }

  Future<void> _onClassSelected(String cls) async {
    setState(() {
      _selectedClass   = cls;
      _selectedStudent = null;
      _classStudents   = [];
      _loadingStudents = true;
      _remarks         = [];
      _resetInput();
    });
    final list = await _studentService.getStudentsByClass(className: cls);
    if (!mounted) return;
    setState(() { _classStudents = list; _loadingStudents = false; });
  }

  void _onStudentSelected(Student s) {
    setState(() {
      _selectedStudent = s;
      _resetInput();
    });
    _loadRemarks(s);
  }

  Future<void> _loadRemarks(Student s) async {
    setState(() => _loadingRemarks = true);
    final list = await _studentService.getStudentRemarks(
        s.className, s.roll, section: s.section);
    if (!mounted) return;
    setState(() { _remarks = list; _loadingRemarks = false; });
  }

  void _resetInput() {
    _selectedPreset = null;
    _customCtrl.clear();
  }

  bool get _canSubmit => _customCtrl.text.trim().isNotEmpty;

  /// Save remark to Firestore, optionally also send via WhatsApp.
  Future<void> _submit({bool sendWhatsApp = false}) async {
    final s = _selectedStudent;
    if (s == null || !_canSubmit) return;

    final text = _customCtrl.text.trim();
    setState(() => _saving = true);
    try {
      await _studentService.addStudentRemark(
        s.className, s.roll, _myEmail, _myRole, text,
        section:      s.section,
        teacherId:    _myTeacherId,
        type:         _selectedType,
        whatsappSent: sendWhatsApp,
      );
      if (!mounted) return;
      setState(() { _saving = false; _resetInput(); });

      _snack(context.tr('remarkSaved'), color: Colors.green);
      _loadRemarks(s);

      if (sendWhatsApp) {
        // Consent gate (#108): sending a child's behavioural remark over
        // WhatsApp transmits their personal data to a third party, so it
        // requires parental consent on record. The remark itself is still
        // saved (internal processing) — only the third-party send is gated.
        final hasConsent = await _consentSvc.hasActiveConsent(
            Student.buildDocId(s.roll, s.className, s.section));
        if (!mounted) return;
        if (!hasConsent) {
          _snack(
            context.tr('remarkSavedNoConsent'),
            color: Colors.orange,
          );
        } else {
          final phone = (s.parentPhone?.isNotEmpty == true)
              ? s.parentPhone!
              : s.phone;
          await _openWhatsApp(phone, text, s.name);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack(e.toString(), color: Colors.red);
    }
  }

  Future<void> _openWhatsApp(String rawPhone, String message, String studentName) async {
    final phone = PhoneUtils.whatsAppNumber(rawPhone);
    if (phone.isEmpty) {
      _snack(context.tr('noPhoneSaved'), color: Colors.orange);
      return;
    }
    final encoded = Uri.encodeComponent(message);
    final uri = Uri.parse('https://wa.me/$phone?text=$encoded');
    // launchUrl can throw (e.g. WhatsApp not installed) even when canLaunchUrl
    // is true, so guard the launch itself rather than only the precheck (#108).
    try {
      final launched = await canLaunchUrl(uri) &&
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        _snack(context.tr('whatsappNotAvailable'), color: Colors.orange);
      }
    } catch (_) {
      if (mounted) _snack(context.tr('whatsappNotAvailable'), color: Colors.orange);
    }
  }

  Future<void> _deleteRemark(StudentRemark r) async {
    final s = _selectedStudent;
    if (s == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(context.tr('deleteRemarkTitle')),
        content: Text(context.tr('removeRemarkPermanently')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.tr('cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _studentService.deleteStudentRemark(
          className: s.className, roll: s.roll, remarkId: r.id,
          currentUserEmail: _myEmail, section: s.section);
      _loadRemarks(s);
    } catch (e) {
      if (mounted) _snack(e.toString(), color: Colors.red);
    }
  }

  void _snack(String msg, {Color color = Colors.green}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryDark,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('studentRemarks'),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text(
              widget.role == 'guardian'
                  ? context.tr('sendMessageToSchool')
                  : context.tr('sendObservationsToParents'),
              style: const TextStyle(fontSize: 11, color: Colors.white60),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // Class picker (coordinator)
          if (widget.role == 'coordinator' || widget.role == 'ownerPrincipal') ...[
            _sectionLabel(context.tr('selectClass')),
            _ClassDropdown(
              classes: _classes, selected: _selectedClass,
              onChanged: _onClassSelected,
            ),
            const SizedBox(height: 16),
          ],

          // Student picker (teacher / coordinator)
          if (widget.role != 'guardian') ...[
            _sectionLabel(context.tr('selectStudent')),
            if (_selectedClass == null &&
                (widget.role == 'coordinator' || widget.role == 'ownerPrincipal'))
              _hintCard(context.tr('pickClassFirst'))
            else if (_loadingStudents)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_classStudents.isEmpty)
              _hintCard(context.tr('noStudentsFound'))
            else
              _StudentDropdown(
                students: _classStudents, selected: _selectedStudent,
                onChanged: _onStudentSelected,
              ),
            const SizedBox(height: 20),
          ],

          // Guardian: student card
          if (widget.role == 'guardian' && widget.guardianStudent != null) ...[
            _StudentCard(student: widget.guardianStudent!),
            const SizedBox(height: 20),
          ],

          // Add remark panel
          if (_selectedStudent != null) ...[
            _sectionLabel(context.tr('addRemark')),
            _AddRemarkPanel(
              role:           widget.role,
              student:        _selectedStudent!,
              selectedPreset: _selectedPreset,
              selectedType:   _selectedType,
              customCtrl:     _customCtrl,
              saving:         _saving,
              canSubmit:      _canSubmit,
              onPresetSelected: (preset, type) => setState(() {
                _selectedPreset = preset;
                _selectedType   = type;
                _customCtrl.text = preset.messageTemplate
                    .replaceAll('{name}', _selectedStudent!.name);
                _customCtrl.selection = TextSelection.collapsed(
                    offset: _customCtrl.text.length);
              }),
              onSubmitSave:      () => _submit(sendWhatsApp: false),
              onSubmitWhatsApp:  () => _submit(sendWhatsApp: true),
            ),
            const SizedBox(height: 24),

            // Remarks history
            _sectionLabel(context.tr('remarksHistory')),
            if (_loadingRemarks)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_remarks.isEmpty)
              _hintCard(context.tr('noRemarksForStudent'))
            else
              ..._remarks.map((r) => _RemarkCard(
                    remark:   r,
                    isOwn:    r.createdBy == _myEmail,
                    onDelete: r.createdBy == _myEmail
                        ? () => _deleteRemark(r)
                        : null,
                  )),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w700,
          color: Colors.grey.shade500, letterSpacing: 0.8),
    ),
  );

  Widget _hintCard(String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 18),
    margin: const EdgeInsets.only(bottom: 4),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Text(text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
  );
}

// ── Add remark panel ──────────────────────────────────────────────────────────

class _AddRemarkPanel extends StatelessWidget {
  final String           role;
  final Student          student;
  final _RemarkPreset?   selectedPreset;
  final String           selectedType;
  final TextEditingController customCtrl;
  final bool             saving;
  final bool             canSubmit;
  final void Function(_RemarkPreset preset, String type) onPresetSelected;
  final VoidCallback     onSubmitSave;
  final VoidCallback     onSubmitWhatsApp;

  const _AddRemarkPanel({
    required this.role,
    required this.student,
    required this.selectedPreset,
    required this.selectedType,
    required this.customCtrl,
    required this.saving,
    required this.canSubmit,
    required this.onPresetSelected,
    required this.onSubmitSave,
    required this.onSubmitWhatsApp,
  });

  bool get _isGuardian => role == 'guardian';

  @override
  Widget build(BuildContext context) {
    final concernPresets = _isGuardian ? _kGuardianConcernPresets : _kNegativePresets;
    final praisePresets  = _isGuardian ? _kGuardianPraisePresets  : _kPositivePresets;
    final concernLabel   = _isGuardian ? context.tr('concernInformation') : context.tr('concernNegative');
    final praiseLabel    = _isGuardian ? context.tr('praiseAppreciation') : context.tr('praisePositive');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Concern section ───────────────────────────────────────────────
        _ChipSection(
          label:    concernLabel,
          icon:     Icons.warning_amber_rounded,
          color:    Colors.red.shade600,
          presets:  concernPresets,
          type:     'negative',
          selected: selectedType == 'negative' ? selectedPreset : null,
          onTap:    (p) => onPresetSelected(p, 'negative'),
        ),
        const SizedBox(height: 12),

        // ── Praise section ────────────────────────────────────────────────
        _ChipSection(
          label:    praiseLabel,
          icon:     Icons.star_rounded,
          color:    Colors.green.shade600,
          presets:  praisePresets,
          type:     'positive',
          selected: selectedType == 'positive' ? selectedPreset : null,
          onTap:    (p) => onPresetSelected(p, 'positive'),
        ),
        const SizedBox(height: 14),

        // ── Text box (auto-filled or editable) ────────────────────────────
        StatefulBuilder(builder: (_, setInner) {
          return TextField(
            controller: customCtrl,
            maxLength:  300,
            maxLines:   4,
            onChanged:  (_) => setInner(() {}),
            decoration: InputDecoration(
              hintText: _isGuardian
                  ? context.tr('guardianRemarkHint')
                  : context.tr('teacherRemarkHint'),
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              counterStyle: TextStyle(color: Colors.grey.shade400, fontSize: 11),
              filled: true,
              fillColor: Colors.grey.shade50,
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
            ),
          );
        }),
        const SizedBox(height: 12),

        // ── Action buttons ────────────────────────────────────────────────
        if (_isGuardian)
          // Guardian: single Save button (no WhatsApp — message goes to school)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (canSubmit && !saving) ? onSubmitSave : null,
              icon: saving
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, size: 17),
              label: Text(context.tr('sendToSchool'),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          )
        else
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: (canSubmit && !saving) ? onSubmitSave : null,
                icon: saving
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_alt_rounded, size: 17),
                label: Text(context.tr('save'), style: const TextStyle(fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: const BorderSide(color: AppTheme.primary),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: (canSubmit && !saving) ? onSubmitWhatsApp : null,
                icon: saving
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, size: 17),
                label: Text(context.tr('saveAndSendWhatsApp'),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ]),
      ]),
    );
  }
}

// ── Chip section (positive / negative) ───────────────────────────────────────

class _ChipSection extends StatelessWidget {
  final String          label;
  final IconData        icon;
  final Color           color;
  final List<_RemarkPreset> presets;
  final String          type;
  final _RemarkPreset?  selected;
  final void Function(_RemarkPreset) onTap;

  const _ChipSection({
    required this.label,
    required this.icon,
    required this.color,
    required this.presets,
    required this.type,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: color, letterSpacing: 0.3)),
      ]),
      const SizedBox(height: 7),
      Wrap(
        spacing: 7,
        runSpacing: 6,
        children: presets.map((p) {
          final isSelected = selected == p;
          return GestureDetector(
            onTap: () => onTap(p),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? color : color.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: isSelected ? color : color.withValues(alpha: 0.3)),
              ),
              child: Text(p.label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : color)),
            ),
          );
        }).toList(),
      ),
    ]);
  }
}

// ── Remark card (history) ─────────────────────────────────────────────────────

class _RemarkCard extends StatelessWidget {
  final StudentRemark remark;
  final bool          isOwn;
  final VoidCallback? onDelete;

  const _RemarkCard({
    required this.remark,
    required this.isOwn,
    this.onDelete,
  });

  bool get _isNew {
    final diff = DateTime.now().difference(remark.timestamp);
    return diff.inHours < 24;
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'principal':   return AppTheme.primary;
      case 'coordinator': return const Color(0xFF1565C0);
      case 'guardian':    return const Color(0xFF2E7D32);
      default:            return const Color(0xFF37474F);
    }
  }

  String _roleLabel(BuildContext context, String role) {
    switch (role) {
      case 'principal':   return context.trRole('principal');
      case 'coordinator': return context.trRole('coordinator');
      case 'guardian':    return context.trRole('guardian');
      default:            return context.trRole('teacher');
    }
  }

  String _fmtTime(DateTime dt) {
    final d  = dt.toLocal();
    final h  = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m  = d.minute.toString().padLeft(2, '0');
    final am = d.hour < 12 ? 'AM' : 'PM';
    const mo = ['Jan','Feb','Mar','Apr','May','Jun',
                 'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${mo[d.month - 1]}  $h:$m $am';
  }

  @override
  Widget build(BuildContext context) {
    final isPositive = remark.isPositive;
    final accentColor = isPositive ? Colors.green.shade600 : Colors.red.shade600;
    final roleColor   = _roleColor(remark.role);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: accentColor, width: 3)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            // Type badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(isPositive ? Icons.star_rounded : Icons.warning_amber_rounded,
                    size: 10, color: accentColor),
                const SizedBox(width: 3),
                Text(isPositive ? context.tr('positiveLabel') : context.tr('concernLabelShort'),
                    style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700,
                        color: accentColor)),
              ]),
            ),
            const SizedBox(width: 6),
            // Role badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: roleColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: roleColor.withValues(alpha: 0.3)),
              ),
              child: Text(_roleLabel(context, remark.role),
                  style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700,
                      color: roleColor)),
            ),
            if (_isNew) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.accent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(context.tr('newBadge'),
                    style: const TextStyle(
                        fontSize: 9, fontWeight: FontWeight.w800,
                        color: Colors.white, letterSpacing: 0.5)),
              ),
            ],
            const Spacer(),
            // WhatsApp sent indicator
            if (remark.whatsappSent)
              Tooltip(
                message: context.tr('sentViaWhatsapp'),
                child: const Icon(Icons.send_rounded, size: 13, color: Color(0xFF25D366)),
              ),
            const SizedBox(width: 6),
            Text(_fmtTime(remark.timestamp),
                style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
            if (onDelete != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onDelete,
                child: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade300),
              ),
            ],
          ]),
          const SizedBox(height: 4),
          Text(remark.createdBy,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
          const SizedBox(height: 6),
          Text(remark.remark,
              style: const TextStyle(fontSize: 13.5, height: 1.4)),
        ]),
      ),
    );
  }
}

// ── Class dropdown ────────────────────────────────────────────────────────────

class _ClassDropdown extends StatelessWidget {
  final List<String> classes;
  final String?      selected;
  final ValueChanged<String> onChanged;

  const _ClassDropdown({
    required this.classes, required this.selected, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: selected, isExpanded: true,
        hint: Text(context.tr('chooseClass'),
            style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
        items: classes.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
        onChanged: (v) { if (v != null) onChanged(v); },
      ),
    ),
  );
}

// ── Student dropdown ──────────────────────────────────────────────────────────

class _StudentDropdown extends StatelessWidget {
  final List<Student> students;
  final Student?      selected;
  final ValueChanged<Student> onChanged;

  const _StudentDropdown({
    required this.students, required this.selected, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<Student>(
        value: selected, isExpanded: true,
        hint: Text(context.tr('chooseStudent'),
            style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
        items: students.map((s) => DropdownMenuItem(
          value: s,
          child: Text('${context.tr('roll')} ${s.roll}  —  ${s.name}',
              overflow: TextOverflow.ellipsis),
        )).toList(),
        onChanged: (v) { if (v != null) onChanged(v); },
      ),
    ),
  );
}

// ── Student card (guardian view) ──────────────────────────────────────────────

class _StudentCard extends StatelessWidget {
  final Student student;
  const _StudentCard({required this.student});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
    ),
    child: Row(children: [
      CircleAvatar(
        radius: 24,
        backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
        child: Text(
          student.name.isNotEmpty ? student.name[0].toUpperCase() : '?',
          style: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primary),
        ),
      ),
      const SizedBox(width: 14),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(student.name,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        Text('${student.className}  ·  ${context.tr('roll')} ${student.roll}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      ]),
    ]),
  );
}

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../models/student.dart';
import '../models/student_remark.dart';
import '../services/auth_service.dart';
import '../services/student_service.dart';
import '../services/timetable_service.dart';
import '../theme.dart';

// ── Common predefined remark options ─────────────────────────────────────────

const List<String> _kCommonRemarks = [
  'Not completing homework',
  'Frequently late to class',
  'Very talkative in class',
  'Needs to improve focus',
  'Missing school supplies',
  'Disruptive behavior in class',
  'Excellent class participation',
  'Great improvement shown',
  'Needs extra academic support',
  'Outstanding behavior',
];

// ── Screen ────────────────────────────────────────────────────────────────────

/// Dedicated Student Remarks screen accessible from teacher / coordinator /
/// guardian home screens.
///
/// [role]               — 'teacher' | 'coordinator' | 'guardian'
/// [teacherClassName]   — set for class teacher; null for subject teachers
/// [teacherSection]     — section of teacher's assigned class
/// [teacherId]          — teacher's Firestore ID
/// [guardianStudent]    — pre-loaded Student for guardian role
class StudentRemarksScreen extends StatefulWidget {
  final String  role;
  final String? teacherClassName;
  final String? teacherSection;
  final String? teacherId;
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
  final _studentService  = StudentService();
  final _ttService       = TimetableService();
  final _customCtrl      = TextEditingController();

  // Session
  String  _myEmail     = '';
  String  _myRole      = '';
  String? _myTeacherId;

  // Class/student selection
  Map<String, List<String>> _classToSections = {};
  List<String>  _classes        = [];
  String?       _selectedClass;
  List<String>  _sections       = [];
  String?       _selectedSection;
  List<Student> _classStudents  = [];
  Student?      _selectedStudent;
  bool          _loadingStudents = false;

  // Remark input
  String? _selectedChip;   // text of selected common remark (null = none)
  bool    _customMode = false; // true = show custom text field
  bool    _saving     = false;

  // Existing remarks for selected student
  List<StudentRemark> _remarks        = [];
  bool                _loadingRemarks = false;

  @override
  void initState() {
    super.initState();
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
      // Guardian: student pre-selected
      setState(() => _selectedStudent = widget.guardianStudent);
      _loadRemarks(widget.guardianStudent!);
      return;
    }

    if (widget.role == 'teacher') {
      final taught = <String>{};
      if (widget.teacherClassName != null) {
        final combo = (widget.teacherSection ?? '').isEmpty
            ? widget.teacherClassName!
            : '${widget.teacherClassName!} ${widget.teacherSection!}';
        taught.add(combo);
      }
      if (_myTeacherId != null) {
        final fromTT = await _ttService.getClassesTaughtByTeacher(_myTeacherId!);
        taught.addAll(fromTT);
      }

      final map = <String, List<String>>{};
      for (final combo in taught) {
        var cls = combo;
        var sec = '';
        if (combo.contains(' ')) {
          final parts = combo.split(' ');
          final last = parts.last;
          if (last.length <= 5) {
            sec = last;
            cls = parts.sublist(0, parts.length - 1).join(' ');
          }
        }
        map.putIfAbsent(cls, () => []).add(sec);
      }
      for (final list in map.values) {
        list.sort();
      }

      if (mounted) {
        setState(() {
          _classToSections = map;
          _classes = map.keys.toList()..sort();
        });

        // Auto-select if there's only one class or a specific class was passed
        if (_classes.length == 1) {
          _onClassSelected(_classes.first);
        } else if (widget.teacherClassName != null && _classes.contains(widget.teacherClassName)) {
          _onClassSelected(widget.teacherClassName!);
          if (widget.teacherSection != null && _sections.contains(widget.teacherSection)) {
            _onSectionSelected(widget.teacherSection!);
          }
        }
      }
    } else if (widget.role != 'guardian') {
      final settings = await _ttService.getSettings();
      final classes  = List<String>.from(settings['classes'] as List? ?? []);
      if (mounted) setState(() => _classes = classes);
    }
  }

  void _onClassSelected(String cls) {
    final sections = _classToSections[cls] ?? [];
    setState(() {
      _selectedClass   = cls;
      _sections        = sections;
      _selectedSection = null;
      _selectedStudent = null;
      _classStudents   = [];
      _remarks         = [];
      _resetInput();
    });

    if (widget.role != 'teacher') {
      _loadStudents(cls, '');
      return;
    }

    // If there's only one section and it's empty, or no sections defined,
    // load students immediately.
    if (sections.isEmpty || (sections.length == 1 && sections.first.isEmpty)) {
      final sec = sections.isNotEmpty ? sections.first : '';
      setState(() => _selectedSection = sec);
      _loadStudents(cls, sec);
    }
  }

  void _onSectionSelected(String sec) {
    setState(() {
      _selectedSection = sec;
      _selectedStudent = null;
      _classStudents   = [];
      _remarks         = [];
      _resetInput();
    });
    _loadStudents(_selectedClass!, sec);
  }

  Future<void> _loadStudents(String cls, String sec) async {
    setState(() => _loadingStudents = true);
    final list = await _studentService.getStudentsByClass(cls, section: sec);
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
    _selectedChip = null;
    _customMode   = false;
    _customCtrl.clear();
  }

  Future<void> _submit({bool sendWhatsApp = false}) async {
    final s = _selectedStudent;
    if (s == null) return;

    final text = _customMode
        ? _customCtrl.text.trim()
        : _selectedChip ?? '';
    if (text.isEmpty) return;

    setState(() => _saving = true);
    try {
      await _studentService.addStudentRemark(
        s.className, s.roll, _myEmail, _myRole, text,
        section:   s.section,
        teacherId: _myTeacherId,
      );
      if (!mounted) return;
      setState(() { _saving = false; _resetInput(); });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Remark saved'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      _loadRemarks(s);

      if (sendWhatsApp) {
        _sendToWhatsApp(text);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _deleteRemark(StudentRemark r) async {
    final s = _selectedStudent;
    if (s == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Remark'),
        content: const Text('Remove this remark permanently?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _studentService.deleteStudentRemark(
          s.className, s.roll, r.id, _myEmail, section: s.section);
      _loadRemarks(s);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _sendToWhatsApp(String text) async {
    final s = _selectedStudent;
    if (s == null) return;

    final phone = s.parentPhone ?? s.phone;
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No guardian phone number found'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Basic cleaning of phone number
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    String finalPhone = cleanPhone;
    // Assume Indian country code if 10 digits
    if (finalPhone.length == 10) {
      finalPhone = '91$finalPhone';
    }

    final message = Uri.encodeComponent("School Remark for ${s.name}:\n$text");
    final url = 'https://wa.me/$finalPhone?text=$message';

    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw 'Could not launch WhatsApp';
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Student Remarks',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text('Add or view student observations',
                style: TextStyle(fontSize: 11, color: Colors.white60)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // ── Step 1: class picker (teacher / coordinator / principal) ─────
          if (widget.role != 'guardian') ...[
            _sectionLabel('Select Class'),
            _ClassDropdown(
              classes:  _classes,
              selected: _selectedClass,
              onChanged: _onClassSelected,
            ),
            const SizedBox(height: 16),

            if (_sections.isNotEmpty && !(_sections.length == 1 && _sections.first.isEmpty)) ...[
              _sectionLabel('Select Section'),
              _SectionDropdown(
                sections: _sections,
                selected: _selectedSection,
                onChanged: _onSectionSelected,
              ),
              const SizedBox(height: 16),
            ],
          ],

          // ── Step 2: student picker (teacher / coordinator) ───────────────
          if (widget.role != 'guardian') ...[
            _sectionLabel('Select Student'),
            if (_selectedClass == null && widget.role != 'guardian')
              _hintCard('Pick a class above first')
            else if (_sections.isNotEmpty && _selectedSection == null && !(_sections.length == 1 && _sections.first.isEmpty))
              _hintCard('Pick a section first')
            else if (_loadingStudents)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_classStudents.isEmpty)
              _hintCard('No students found')
            else
              _StudentDropdown(
                students: _classStudents,
                selected: _selectedStudent,
                onChanged: _onStudentSelected,
              ),
            const SizedBox(height: 20),
          ],

          // ── Guardian: student card ────────────────────────────────────────
          if (widget.role == 'guardian' && widget.guardianStudent != null) ...[
            _StudentCard(student: widget.guardianStudent!),
            const SizedBox(height: 20),
          ],

          // ── Add remark section ────────────────────────────────────────────
          if (_selectedStudent != null) ...[
            _sectionLabel('Add Remark'),
            _AddRemarkPanel(
              selectedChip: _selectedChip,
              customMode:   _customMode,
              customCtrl:   _customCtrl,
              saving:       _saving,
              showWhatsApp: widget.role != 'guardian',
              onChipSelected: (text) => setState(() {
                _selectedChip = text;
                _customMode   = false;
                _customCtrl.clear();
              }),
              onCustomToggle: () => setState(() {
                _customMode   = !_customMode;
                _selectedChip = null;
              }),
              onTextChanged: () => setState(() {}),
              onSubmit: () => _submit(),
              onWhatsAppSubmit: () => _submit(sendWhatsApp: true),
            ),
            const SizedBox(height: 24),

            // ── Existing remarks ─────────────────────────────────────────
            _sectionLabel('Remarks History'),
            if (_loadingRemarks)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_remarks.isEmpty)
              _hintCard('No remarks yet for this student')
            else
              ..._remarks.map((r) => _RemarkCard(
                    remark:   r,
                    isOwn:    r.createdBy == _myEmail,
                    onDelete: r.createdBy == _myEmail
                        ? () => _deleteRemark(r)
                        : null,
                    onWhatsApp: widget.role != 'guardian'
                        ? () => _sendToWhatsApp(r.remark)
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
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade500,
          letterSpacing: 0.8),
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
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
    ),
  );
}

// ── Class dropdown ────────────────────────────────────────────────────────────

class _ClassDropdown extends StatelessWidget {
  final List<String> classes;
  final String?      selected;
  final ValueChanged<String> onChanged;

  const _ClassDropdown({
    required this.classes,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selected,
          isExpanded: true,
          hint: Text('Choose a class',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
          items: classes
              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
              .toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
      ),
    );
  }
}

// ── Section dropdown ──────────────────────────────────────────────────────────

class _SectionDropdown extends StatelessWidget {
  final List<String> sections;
  final String?      selected;
  final ValueChanged<String> onChanged;

  const _SectionDropdown({
    required this.sections,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selected,
          isExpanded: true,
          hint: Text('Choose a section',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
          items: sections
              .map((s) => DropdownMenuItem(
                  value: s, child: Text(s.isEmpty ? 'No Section' : 'Section $s')))
              .toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
      ),
    );
  }
}

// ── Student dropdown ──────────────────────────────────────────────────────────

class _StudentDropdown extends StatelessWidget {
  final List<Student> students;
  final Student?      selected;
  final ValueChanged<Student> onChanged;

  const _StudentDropdown({
    required this.students,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<Student>(
          value: selected,
          isExpanded: true,
          hint: Text('Choose a student',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
          items: students.map((s) => DropdownMenuItem(
            value: s,
            child: Text('Roll ${s.roll}  —  ${s.name}',
                overflow: TextOverflow.ellipsis),
          )).toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
      ),
    );
  }
}

// ── Student card (guardian view) ──────────────────────────────────────────────

class _StudentCard extends StatelessWidget {
  final Student student;
  const _StudentCard({required this.student});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withOpacity(0.25)),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: AppTheme.primaryLight.withOpacity(0.25),
          child: Text(
            student.name.isNotEmpty ? student.name[0].toUpperCase() : '?',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.primary),
          ),
        ),
        const SizedBox(width: 14),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(student.name,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold)),
          Text(
            '${student.className}  ·  Roll ${student.roll}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ]),
      ]),
    );
  }
}

// ── Add remark panel ──────────────────────────────────────────────────────────

class _AddRemarkPanel extends StatelessWidget {
  final String?  selectedChip;
  final bool     customMode;
  final TextEditingController customCtrl;
  final bool     saving;
  final bool     showWhatsApp;
  final ValueChanged<String> onChipSelected;
  final VoidCallback onCustomToggle;
  final VoidCallback onTextChanged;
  final VoidCallback onSubmit;
  final VoidCallback onWhatsAppSubmit;

  const _AddRemarkPanel({
    required this.selectedChip,
    required this.customMode,
    required this.customCtrl,
    required this.saving,
    required this.showWhatsApp,
    required this.onChipSelected,
    required this.onCustomToggle,
    required this.onTextChanged,
    required this.onSubmit,
    required this.onWhatsAppSubmit,
  });

  bool get _canSubmit {
    if (customMode) return customCtrl.text.trim().isNotEmpty;
    return selectedChip != null;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Common problem chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ..._kCommonRemarks.map((text) {
                final selected = selectedChip == text && !customMode;
                return _RemarkChip(
                  label:    text,
                  selected: selected,
                  onTap:    () => onChipSelected(text),
                );
              }),
              // Custom chip
              _RemarkChip(
                label:    'Custom…',
                selected: customMode,
                isCustom: true,
                onTap:    onCustomToggle,
              ),
            ],
          ),

          // Custom text field
          if (customMode) ...[
            const SizedBox(height: 12),
            TextField(
              controller: customCtrl,
              maxLength:  200,
              maxLines:   3,
              autofocus:  true,
              onChanged:  (_) => onTextChanged(),
              decoration: InputDecoration(
                hintText: 'Write your own remark…',
                hintStyle: TextStyle(
                    color: Colors.grey.shade400, fontSize: 13),
                counterStyle: TextStyle(
                    color: Colors.grey.shade400, fontSize: 11),
                filled: true,
                fillColor: Colors.grey.shade50,
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        BorderSide(color: Colors.grey.shade300)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        BorderSide(color: Colors.grey.shade300)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                        color: AppTheme.primary, width: 1.5)),
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Submit buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (_canSubmit && !saving) ? onSubmit : null,
                  icon: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_alt_rounded, size: 18),
                  label: const Text('Save',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              if (showWhatsApp) ...[
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: (_canSubmit && !saving) ? onWhatsAppSubmit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Icon(FontAwesomeIcons.whatsapp, size: 18),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _RemarkChip extends StatelessWidget {
  final String   label;
  final bool     selected;
  final bool     isCustom;
  final VoidCallback onTap;

  const _RemarkChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.isCustom = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isCustom ? AppTheme.accent : AppTheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color : color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? color : color.withOpacity(0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : color),
        ),
      ),
    );
  }
}

// ── Remark card ───────────────────────────────────────────────────────────────

class _RemarkCard extends StatelessWidget {
  final StudentRemark remark;
  final bool          isOwn;
  final VoidCallback? onDelete;
  final VoidCallback? onWhatsApp;

  const _RemarkCard({
    required this.remark,
    required this.isOwn,
    this.onDelete,
    this.onWhatsApp,
  });

  Color _roleColor(String role) {
    switch (role) {
      case 'principal':   return const Color(0xFF6A1B9A);
      case 'coordinator': return const Color(0xFF1565C0);
      case 'guardian':    return const Color(0xFF2E7D32);
      default:            return const Color(0xFF37474F);
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'principal':   return 'Principal';
      case 'coordinator': return 'Coordinator';
      case 'guardian':    return 'Guardian';
      default:            return 'Teacher';
    }
  }

  String _fmtTime(DateTime dt) {
    final d  = dt.toLocal();
    final h  = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m  = d.minute.toString().padLeft(2, '0');
    final am = d.hour < 12 ? 'AM' : 'PM';
    const mo = ['Jan','Feb','Mar','Apr','May','Jun',
                 'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${mo[d.month-1]}  $h:$m $am';
  }

  @override
  Widget build(BuildContext context) {
    final roleColor = _roleColor(remark.role);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: roleColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: roleColor.withOpacity(0.35)),
              ),
              child: Text(
                _roleLabel(remark.role),
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: roleColor),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                remark.createdBy,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              _fmtTime(remark.timestamp),
              style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
            ),
            if (onWhatsApp != null) ...[
              const SizedBox(width: 12),
              GestureDetector(
                onTap: onWhatsApp,
                child: const Icon(FontAwesomeIcons.whatsapp,
                    size: 16, color: Colors.green),
              ),
            ],
            if (onDelete != null) ...[
              const SizedBox(width: 12),
              GestureDetector(
                onTap: onDelete,
                child: Icon(Icons.delete_outline,
                    size: 16, color: Colors.red.shade300),
              ),
            ],
          ]),
          const SizedBox(height: 8),
          Text(remark.remark,
              style: const TextStyle(fontSize: 13.5, height: 1.4)),
        ],
      ),
    );
  }
}

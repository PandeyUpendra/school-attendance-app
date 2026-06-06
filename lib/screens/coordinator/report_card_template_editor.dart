import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import '../../models/exam.dart';
import '../../models/report_card_template.dart';
import '../../models/student.dart';
import '../../services/auth_service.dart';
import '../../services/report_card_template_service.dart';
import '../../services/school_service.dart';
import '../../theme.dart';
import '../../utils/report_card_pdf_builder.dart';

// ─── Template list screen ─────────────────────────────────────────────────────

/// Shows all templates for the school and lets the coordinator
/// create, clone, edit (own copies) or delete (own copies).
class ReportCardTemplateListScreen extends StatefulWidget {
  const ReportCardTemplateListScreen({super.key});

  @override
  State<ReportCardTemplateListScreen> createState() =>
      _ReportCardTemplateListScreenState();
}

class _ReportCardTemplateListScreenState
    extends State<ReportCardTemplateListScreen> {
  final _svc        = ReportCardTemplateService();
  final _schoolSvc  = SchoolService();
  bool _loading     = true;
  List<ReportCardTemplate> _templates = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // Auto-seed the 3 system presets the first time a school uses templates.
    // seedDefaultTemplates is idempotent — safe to call every load.
    final sid   = AuthService.currentSchoolId;
    final brand = await _schoolSvc.getBrandName(sid);
    await _svc.seedDefaultTemplates(schoolId: sid, brandName: brand);

    final list = await _svc.getTemplates();
    if (!mounted) return;
    setState(() { _templates = list; _loading = false; });
  }

  Future<void> _openEditor(ReportCardTemplate? template) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReportCardTemplateEditor(existing: template),
      ),
    );
    _load();
  }

  Future<void> _clone(ReportCardTemplate t) async {
    try {
      await _svc.cloneTemplate(t);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cloned as "Copy of ${t.name}"')),
      );
      _load();
    } catch (e) {
      _showErr(e);
    }
  }

  Future<void> _delete(ReportCardTemplate t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Template'),
        content: Text('Delete "${t.name}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _svc.deleteTemplate(t.id);
      _load();
    } catch (e) {
      _showErr(e);
    }
  }

  void _showErr(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(e.toString()),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Report Card Templates'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New Template',
            onPressed: () => _openEditor(null),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _templates.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.description_outlined,
                          size: 52, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text('No templates yet.',
                          style: TextStyle(color: Colors.grey.shade500)),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () => _openEditor(null),
                        icon: const Icon(Icons.add),
                        label: const Text('Create Template'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppTheme.primary,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _templates.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) =>
                        _TemplateCard(
                          template:  _templates[i],
                          onClone:   () => _clone(_templates[i]),
                          onEdit:    _templates[i].isSystemPreset
                              ? null
                              : () => _openEditor(_templates[i]),
                          onDelete:  _templates[i].isSystemPreset
                              ? null
                              : () => _delete(_templates[i]),
                        ),
                  ),
                ),
    );
  }
}

// ─── Template card ────────────────────────────────────────────────────────────

class _TemplateCard extends StatelessWidget {
  final ReportCardTemplate template;
  final VoidCallback? onEdit;
  final VoidCallback  onClone;
  final VoidCallback? onDelete;

  const _TemplateCard({
    required this.template,
    required this.onClone,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final t = template;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Board badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              t.board.label,
              style: const TextStyle(
                  color: AppTheme.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(t.name,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                  ),
                  if (t.isSystemPreset)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Text('System',
                          style: TextStyle(
                              fontSize: 9, color: Colors.amber.shade800)),
                    ),
                ]),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  children: [
                    if (t.showRank)
                      _chip('Rank', Icons.leaderboard_outlined),
                    if (t.showAttendance)
                      _chip('Attendance', Icons.calendar_today_outlined),
                    if (t.showCoCurricular)
                      _chip('Co-Curricular', Icons.sports_outlined),
                    _chip(
                        '${t.pageSize} ${t.orientation[0].toUpperCase()}',
                        Icons.description_outlined),
                  ],
                ),
                const SizedBox(height: 8),
                Row(children: [
                  // Clone always available
                  _ActionBtn(
                    label: 'Clone',
                    icon: Icons.copy_outlined,
                    color: AppTheme.primaryMid,
                    onTap: onClone,
                  ),
                  if (onEdit != null) ...[
                    const SizedBox(width: 8),
                    _ActionBtn(
                      label: 'Edit',
                      icon: Icons.edit_outlined,
                      color: AppTheme.primary,
                      onTap: onEdit!,
                    ),
                  ],
                  if (onDelete != null) ...[
                    const SizedBox(width: 8),
                    _ActionBtn(
                      label: 'Delete',
                      icon: Icons.delete_outline,
                      color: Colors.red,
                      onTap: onDelete!,
                    ),
                  ],
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 10, color: Colors.grey.shade600),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade700)),
        ]),
      );
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// Template editor
// ═══════════════════════════════════════════════════════════════════════════════

class ReportCardTemplateEditor extends StatefulWidget {
  /// Pass null to create a new template.
  final ReportCardTemplate? existing;

  const ReportCardTemplateEditor({super.key, this.existing});

  @override
  State<ReportCardTemplateEditor> createState() =>
      _ReportCardTemplateEditorState();
}

class _ReportCardTemplateEditorState
    extends State<ReportCardTemplateEditor> {
  final _svc     = ReportCardTemplateService();
  final _formKey = GlobalKey<FormState>();

  // ── Form state ─────────────────────────────────────────────────────────────
  late TextEditingController _nameCtrl;
  late TextEditingController _headerTextCtrl;
  late TextEditingController _headerLogoCtrl;
  late TextEditingController _footerCtrl;

  late ReportCardBoard _board;
  late bool            _showRank;
  late bool            _showAttendance;
  late bool            _showCoCurricular;
  late String          _pageSize;
  late String          _orientation;

  late List<SubjectColumn> _subjects;
  late List<GradeBand>     _gradeBands;

  bool _saving      = false;
  bool _previewing  = false;

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    _nameCtrl       = TextEditingController(text: t?.name ?? '');
    _headerTextCtrl = TextEditingController(text: t?.headerText ?? '');
    _headerLogoCtrl = TextEditingController(text: t?.headerLogo ?? '');
    _footerCtrl     = TextEditingController(text: t?.footerText ?? '');

    _board            = t?.board            ?? ReportCardBoard.custom;
    _showRank         = t?.showRank         ?? true;
    _showAttendance   = t?.showAttendance   ?? false;
    _showCoCurricular = t?.showCoCurricular ?? false;
    _pageSize         = t?.pageSize         ?? 'A4';
    _orientation      = t?.orientation      ?? 'portrait';

    _subjects   = t != null
        ? List<SubjectColumn>.from(t.subjects)
        : [
            const SubjectColumn(subject: 'Hindi',   maxMarks: 100),
            const SubjectColumn(subject: 'English',  maxMarks: 100),
            const SubjectColumn(subject: 'Maths',    maxMarks: 100),
            const SubjectColumn(subject: 'Science',  maxMarks: 100),
            const SubjectColumn(subject: 'S.St.',    maxMarks: 100),
          ];

    _gradeBands = t != null && t.gradeScheme.isNotEmpty
        ? List<GradeBand>.from(t.gradeScheme)
        : _defaultGradeBands();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _headerTextCtrl.dispose();
    _headerLogoCtrl.dispose();
    _footerCtrl.dispose();
    super.dispose();
  }

  // ── Default grade bands ────────────────────────────────────────────────────

  List<GradeBand> _defaultGradeBands() => [
    const GradeBand(minPercent: 90, maxPercent: 100, grade: 'A+', gpa: 4.0),
    const GradeBand(minPercent: 80, maxPercent: 89.9, grade: 'A',  gpa: 3.7),
    const GradeBand(minPercent: 70, maxPercent: 79.9, grade: 'B+', gpa: 3.3),
    const GradeBand(minPercent: 60, maxPercent: 69.9, grade: 'B',  gpa: 3.0),
    const GradeBand(minPercent: 50, maxPercent: 59.9, grade: 'C',  gpa: 2.0),
    const GradeBand(minPercent: 33, maxPercent: 49.9, grade: 'D',  gpa: 1.0),
    const GradeBand(minPercent: 0,  maxPercent: 32.9, grade: 'F',  gpa: 0.0),
  ];

  // ── Board preset grade schemes ─────────────────────────────────────────────

  void _applyBoardPreset(ReportCardBoard b) {
    setState(() {
      _board = b;
      switch (b) {
        case ReportCardBoard.cbse:
          _gradeBands = [
            const GradeBand(minPercent: 91, maxPercent: 100, grade: 'A1', gpa: 10),
            const GradeBand(minPercent: 81, maxPercent: 90,  grade: 'A2', gpa: 9),
            const GradeBand(minPercent: 71, maxPercent: 80,  grade: 'B1', gpa: 8),
            const GradeBand(minPercent: 61, maxPercent: 70,  grade: 'B2', gpa: 7),
            const GradeBand(minPercent: 51, maxPercent: 60,  grade: 'C1', gpa: 6),
            const GradeBand(minPercent: 41, maxPercent: 50,  grade: 'C2', gpa: 5),
            const GradeBand(minPercent: 33, maxPercent: 40,  grade: 'D',  gpa: 4),
            const GradeBand(minPercent: 0,  maxPercent: 32.9,grade: 'E',  gpa: 0),
          ];
        case ReportCardBoard.icse:
        case ReportCardBoard.cisce:
          _gradeBands = [
            const GradeBand(minPercent: 90, maxPercent: 100, grade: 'A+', gpa: 4.0),
            const GradeBand(minPercent: 80, maxPercent: 89.9,grade: 'A',  gpa: 4.0),
            const GradeBand(minPercent: 70, maxPercent: 79.9,grade: 'B+', gpa: 3.5),
            const GradeBand(minPercent: 60, maxPercent: 69.9,grade: 'B',  gpa: 3.0),
            const GradeBand(minPercent: 50, maxPercent: 59.9,grade: 'C+', gpa: 2.5),
            const GradeBand(minPercent: 40, maxPercent: 49.9,grade: 'C',  gpa: 2.0),
            const GradeBand(minPercent: 35, maxPercent: 39.9,grade: 'D',  gpa: 1.0),
            const GradeBand(minPercent: 0,  maxPercent: 34.9,grade: 'F',  gpa: 0.0),
          ];
        default:
          break; // keep existing bands for UP / State / Custom
      }
    });
  }

  // ── Build template from form state ─────────────────────────────────────────

  ReportCardTemplate _buildTemplate({String id = ''}) => ReportCardTemplate(
    id:             id,
    name:           _nameCtrl.text.trim(),
    board:          _board,
    headerLogo:     _headerLogoCtrl.text.trim(),
    headerText:     _headerTextCtrl.text.trim(),
    subjects:       _subjects,
    showRank:          _showRank,
    showAttendance:    _showAttendance,
    showCoCurricular:  _showCoCurricular,
    gradeScheme:    _gradeBands,
    footerText:     _footerCtrl.text.trim(),
    pageSize:       _pageSize,
    orientation:    _orientation,
    isSystemPreset: false,
    createdAt:      widget.existing?.createdAt ?? DateTime.now(),
  );

  // ── Save ───────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final t = _buildTemplate(id: widget.existing?.id ?? '');
      if (widget.existing == null) {
        await _svc.createTemplate(t);
      } else {
        await _svc.updateTemplate(t);
      }
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      setState(() => _saving = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  // ── Live preview ───────────────────────────────────────────────────────────

  Future<void> _preview() async {
    setState(() => _previewing = true);
    try {
      final template = _buildTemplate(id: 'preview');

      // Sample data for preview
      final sampleExam = Exam(
        id:        'preview',
        name:      _nameCtrl.text.trim().isEmpty
            ? 'Sample Exam'
            : _nameCtrl.text.trim(),
        className: 'Class X',
        subjects:  _subjects.isNotEmpty
            ? _subjects.map((s) => s.subject).toList()
            : ['Hindi', 'English', 'Maths'],
        maxMarks:  _subjects.isNotEmpty ? _subjects.first.maxMarks : 100,
        examDate:  DateTime.now(),
        createdBy: 'preview',
      );
      const sampleStudent = Student(
        name:      'Ramesh Kumar',
        roll:      5,
        className: 'Class X',
        section:   'A',
        fatherName: 'Mr. Kumar',
        parentPhone: '9999999999',
      );
      // Vary marks to make preview interesting
      final subList = sampleExam.subjects;
      final variedMarks = <String, double?>{
        for (int i = 0; i < subList.length; i++)
          subList[i]: 60.0 + (i % 4) * 10,
      };
      final sampleResult = ExamResult(
        roll:        5,
        studentName: 'Ramesh Kumar',
        className:   'Class X',
        examId:      'preview',
        examName:    sampleExam.name,
        marks:       variedMarks,
        maxMarks:    sampleExam.maxMarks,
        enteredBy:   'preview',
      );

      final bytes = await buildReportCardPdf(
        template: template,
        result:   sampleResult,
        student:  sampleStudent,
        exam:     sampleExam,
        rank:     template.showRank ? 3 : null,
        totalPresent: template.showAttendance ? 182 : null,
        totalDays:    template.showAttendance ? 210 : null,
      );

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(
              title: const Text('Template Preview'),
              backgroundColor: AppTheme.primaryDark,
            ),
            body: PdfPreview(
              build: (_) async => bytes,
              allowPrinting: false,
              allowSharing:  false,
              canChangeOrientation: false,
              canChangePageFormat:  false,
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Preview failed: $e'),
            backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(isNew ? 'New Template' : 'Edit Template'),
        actions: [
          if (_previewing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                  child: SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))),
            )
          else
            IconButton(
              icon: const Icon(Icons.visibility_outlined),
              tooltip: 'Preview PDF',
              onPressed: _preview,
            ),
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                  child: SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))),
            )
          else
            IconButton(
              icon: const Icon(Icons.save_outlined),
              tooltip: 'Save',
              onPressed: _save,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionHeader('Template Basics'),
            _buildNameField(),
            const SizedBox(height: 12),
            _buildBoardSelector(),

            const SizedBox(height: 20),
            _sectionHeader('Header'),
            _buildTextField(
              controller: _headerTextCtrl,
              label: 'School Branding / Header Text',
              hint: "Pulled from your school's brandName by default",
              required: false,
              maxLines: 2,
            ),
            const SizedBox(height: 10),
            _buildTextField(
              controller: _headerLogoCtrl,
              label: 'Logo Storage URL (optional)',
              hint: 'Leave blank to skip logo',
              required: false,
            ),

            const SizedBox(height: 20),
            _sectionHeader('Display Options'),
            _buildToggleTile(
              title:    'Show Class Rank',
              subtitle: 'Print the student\'s rank in class on the report',
              value:    _showRank,
              onChanged: (v) => setState(() => _showRank = v),
            ),
            _buildToggleTile(
              title:    'Show Attendance',
              subtitle: 'Print attendance days present / total',
              value:    _showAttendance,
              onChanged: (v) => setState(() => _showAttendance = v),
            ),
            _buildToggleTile(
              title:    'Show Co-Curricular',
              subtitle: 'Add blank rows for activity grades',
              value:    _showCoCurricular,
              onChanged: (v) => setState(() => _showCoCurricular = v),
            ),

            const SizedBox(height: 20),
            _sectionHeader('Page Layout'),
            _buildLayoutRow(),

            const SizedBox(height: 20),
            _sectionHeader('Subject Columns (Preview / Default Config)'),
            _buildSubjectList(),

            const SizedBox(height: 20),
            _sectionHeader('Grade Scheme'),
            _buildGradeSchemeTable(),

            const SizedBox(height: 20),
            _sectionHeader('Footer'),
            _buildTextField(
              controller: _footerCtrl,
              label: 'Footer Text',
              hint: 'e.g. Class Teacher: _____  Principal: _____',
              required: false,
              maxLines: 2,
            ),

            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save),
              label: Text(isNew ? 'Create Template' : 'Save Changes'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ── Section helpers ────────────────────────────────────────────────────────

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(title,
        style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTheme.primary)),
  );

  Widget _buildNameField() => TextFormField(
    controller: _nameCtrl,
    maxLength: 60,
    maxLengthEnforcement: MaxLengthEnforcement.enforced,
    decoration: const InputDecoration(
      labelText: 'Template Name *',
      counterText: '',
      filled: true,
      fillColor: Colors.white,
    ),
    validator: (v) =>
        (v == null || v.trim().isEmpty) ? 'Name is required' : null,
  );

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool required = true,
    int maxLines = 1,
  }) =>
      TextFormField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: Colors.white,
        ),
        validator: required
            ? (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null
            : null,
      );

  Widget _buildBoardSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: ReportCardBoard.values.map((b) {
        final sel = _board == b;
        return ChoiceChip(
          label: Text(b.label),
          selected: sel,
          selectedColor: AppTheme.primary.withValues(alpha: 0.15),
          checkmarkColor: AppTheme.primary,
          labelStyle: TextStyle(
            color: sel ? AppTheme.primary : null,
            fontWeight: sel ? FontWeight.bold : FontWeight.normal,
          ),
          onSelected: (_) => _applyBoardPreset(b),
        );
      }).toList(),
    );
  }

  Widget _buildToggleTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      Card(
        margin: const EdgeInsets.only(bottom: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: SwitchListTile(
          title:    Text(title,   style: const TextStyle(fontSize: 13)),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
          value:    value,
          onChanged: onChanged,
          activeColor: AppTheme.primary,
          dense: true,
        ),
      );

  Widget _buildLayoutRow() => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Page Size',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 4),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'A4',     label: Text('A4')),
                  ButtonSegment(value: 'Letter', label: Text('Letter')),
                ],
                selected: {_pageSize},
                onSelectionChanged: (s) =>
                    setState(() => _pageSize = s.first),
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: AppTheme.primary,
                  selectedForegroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Orientation',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 4),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'portrait',  label: Text('Portrait')),
                  ButtonSegment(value: 'landscape', label: Text('Landscape')),
                ],
                selected: {_orientation},
                onSelectionChanged: (s) =>
                    setState(() => _orientation = s.first),
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: AppTheme.primary,
                  selectedForegroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ]),
    ),
  );

  // ── Subject columns editor ─────────────────────────────────────────────────

  Widget _buildSubjectList() {
    return Column(
      children: [
        for (int i = 0; i < _subjects.length; i++) _subjectRow(i),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: () => setState(() =>
              _subjects.add(const SubjectColumn(subject: '', maxMarks: 100))),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add Subject'),
        ),
      ],
    );
  }

  Widget _subjectRow(int i) {
    final sub = _subjects[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(children: [
          // Subject name
          Expanded(
            flex: 3,
            child: TextFormField(
              initialValue: sub.subject,
              decoration: const InputDecoration(
                labelText: 'Subject',
                isDense: true,
                filled: true,
                fillColor: AppTheme.background,
              ),
              onChanged: (v) => setState(
                  () => _subjects[i] = sub.copyWith(subject: v)),
            ),
          ),
          const SizedBox(width: 8),
          // Max marks
          SizedBox(
            width: 70,
            child: TextFormField(
              initialValue: '${sub.maxMarks}',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Max',
                isDense: true,
                filled: true,
                fillColor: AppTheme.background,
              ),
              onChanged: (v) => setState(() =>
                  _subjects[i] = sub.copyWith(maxMarks: int.tryParse(v) ?? 100)),
            ),
          ),
          const SizedBox(width: 4),
          // Grade checkbox
          Tooltip(
            message: 'Include Grade column',
            child: Checkbox(
              value: sub.includeGrade,
              onChanged: (v) => setState(
                  () => _subjects[i] = sub.copyWith(includeGrade: v ?? true)),
              activeColor: AppTheme.primary,
            ),
          ),
          const Text('G', style: TextStyle(fontSize: 10)),
          // Remarks checkbox
          Tooltip(
            message: 'Include Remarks column',
            child: Checkbox(
              value: sub.includeRemarks,
              onChanged: (v) => setState(
                  () => _subjects[i] = sub.copyWith(includeRemarks: v ?? false)),
              activeColor: AppTheme.primary,
            ),
          ),
          const Text('R', style: TextStyle(fontSize: 10)),
          // Remove
          if (_subjects.length > 1)
            IconButton(
              icon: const Icon(Icons.remove_circle_outline,
                  size: 18, color: Colors.red),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () => setState(() => _subjects.removeAt(i)),
            ),
        ]),
      ),
    );
  }

  // ── Grade scheme editor ────────────────────────────────────────────────────

  Widget _buildGradeSchemeTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          // Header row
          _gradeHeader(),
          const Divider(height: 1),
          for (int i = 0; i < _gradeBands.length; i++) ...[
            _gradeBandRow(i),
            if (i < _gradeBands.length - 1) const Divider(height: 1),
          ],
          const Divider(height: 1),
          // Add button
          TextButton.icon(
            onPressed: () => setState(() {
              _gradeBands.add(
                  const GradeBand(minPercent: 0, maxPercent: 0,
                      grade: '', gpa: 0));
            }),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Band'),
          ),
        ],
      ),
    );
  }

  Widget _gradeHeader() => Container(
    color: Colors.grey.shade50,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: const Row(children: [
      Expanded(flex: 2, child: Text('Min %',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
      Expanded(flex: 2, child: Text('Max %',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
      Expanded(flex: 2, child: Text('Grade',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
      Expanded(flex: 2, child: Text('GPA',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
      SizedBox(width: 32),
    ]),
  );

  Widget _gradeBandRow(int i) {
    final b = _gradeBands[i];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(children: [
        Expanded(flex: 2, child: _gradeTF(
          b.minPercent.toStringAsFixed(0),
          onChanged: (v) => setState(() =>
              _gradeBands[i] = b.copyWith(
                  minPercent: double.tryParse(v) ?? b.minPercent)),
        )),
        const SizedBox(width: 4),
        Expanded(flex: 2, child: _gradeTF(
          b.maxPercent.toStringAsFixed(0),
          onChanged: (v) => setState(() =>
              _gradeBands[i] = b.copyWith(
                  maxPercent: double.tryParse(v) ?? b.maxPercent)),
        )),
        const SizedBox(width: 4),
        Expanded(flex: 2, child: _gradeTF(
          b.grade,
          onChanged: (v) => setState(() =>
              _gradeBands[i] = b.copyWith(grade: v)),
          numeric: false,
        )),
        const SizedBox(width: 4),
        Expanded(flex: 2, child: _gradeTF(
          b.gpa.toStringAsFixed(1),
          onChanged: (v) => setState(() =>
              _gradeBands[i] = b.copyWith(
                  gpa: double.tryParse(v) ?? b.gpa)),
        )),
        SizedBox(
          width: 32,
          child: _gradeBands.length > 1
              ? IconButton(
                  icon: const Icon(Icons.close, size: 14, color: Colors.red),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () =>
                      setState(() => _gradeBands.removeAt(i)),
                )
              : const SizedBox.shrink(),
        ),
      ]),
    );
  }

  Widget _gradeTF(String initial,
      {required ValueChanged<String> onChanged, bool numeric = true}) =>
      TextFormField(
        initialValue: initial,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        inputFormatters: numeric
            ? [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))]
            : null,
        maxLength: numeric ? 5 : 4,
        onChanged: onChanged,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          filled: true,
          fillColor: AppTheme.background,
          counterText: '',
          border: OutlineInputBorder(),
        ),
        style: const TextStyle(fontSize: 12),
      );
}

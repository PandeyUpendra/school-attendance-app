import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../models/meeting.dart';
import '../../models/teacher.dart';
import '../../services/meeting_service.dart';
import '../../services/notification_service.dart';
import '../../services/timetable_service.dart';
import '../../theme.dart';

class MeetingDetailScreen extends StatefulWidget {
  /// Pass null to create a new meeting.
  final String? meetingId;
  final String  createdBy;
  final String  createdByName;
  final String  createdByRole;
  final bool    readOnly;

  const MeetingDetailScreen({
    super.key,
    this.meetingId,
    required this.createdBy,
    required this.createdByName,
    required this.createdByRole,
    this.readOnly = false,
  });

  @override
  State<MeetingDetailScreen> createState() => _MeetingDetailScreenState();
}

class _MeetingDetailScreenState extends State<MeetingDetailScreen> {
  final _svc         = MeetingService();
  final _titleCtrl   = TextEditingController();
  final _pointCtrl   = TextEditingController();
  final _formKey     = GlobalKey<FormState>();

  bool              _isNew    = true;
  bool              _saving   = false;
  List<Teacher>     _teachers = [];
  DateTime          _meetingDate = DateTime.now();
  List<MeetingPoint> _points     = [];
  String?           _meetingId;
  Meeting?          _meeting;
  bool              _generatingPdf = false;

  @override
  void initState() {
    super.initState();
    _isNew = widget.meetingId == null;
    if (!_isNew) {
      _meetingId = widget.meetingId;
    }
    _loadTeachers();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _pointCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTeachers() async {
    final teachers = await TimetableService().getTeachers();
    if (!mounted) return;
    setState(() => _teachers = teachers..sort((a, b) => a.name.compareTo(b.name)));
  }

  bool get _readOnly =>
      widget.readOnly || (_meeting?.isReadOnly ?? false);

  // ── Save new meeting ──────────────────────────────────────────────────────

  Future<void> _createMeeting() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final meeting = Meeting(
        id:                   '',
        title:                _titleCtrl.text.trim(),
        date:                 _meetingDate,
        createdBy:            widget.createdBy,
        createdByName:        widget.createdByName,
        createdByRole:        widget.createdByRole,
        points:               _points,
        assignedTeacherIds:   [],
        assignedTeacherNames: [],
        status:               MeetingStatus.active,
        createdAt:            DateTime.now(),
        updatedAt:            DateTime.now(),
      );
      final id = await _svc.createMeeting(meeting);
      if (!mounted) return;
      setState(() {
        _meetingId = id;
        _isNew     = false;
      });
      _snack('Meeting created');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Add a discussion point ────────────────────────────────────────────────

  void _addPoint() {
    final text = _pointCtrl.text.trim();
    if (text.isEmpty) return;
    final point = MeetingPoint(
      id:      '${DateTime.now().millisecondsSinceEpoch}',
      text:    text,
      addedBy: widget.createdBy,
      addedAt: DateTime.now(),
    );
    final updated = [..._points, point];
    setState(() {
      _points = updated;
      _pointCtrl.clear();
    });
    if (_meetingId != null) {
      final m = _meeting;
      if (m != null) {
        final allPoints = [...m.points, point];
        _svc.updatePoints(_meetingId!, allPoints);
      } else {
        _svc.updatePoints(_meetingId!, updated);
      }
    }
  }

  // ── Toggle checked state ──────────────────────────────────────────────────

  Future<void> _togglePoint(Meeting m, MeetingPoint p) async {
    if (_readOnly) return;
    final updated = m.points.map((pt) {
      if (pt.id == p.id) return pt.copyWith(isChecked: !pt.isChecked);
      return pt;
    }).toList();
    await _svc.updatePoints(m.id, updated);
  }

  // ── Convert point to task ─────────────────────────────────────────────────

  Future<void> _convertToTask(Meeting m, MeetingPoint p) async {
    if (_teachers.isEmpty) {
      _snack('No teachers found');
      return;
    }
    final result = await showDialog<Teacher>(
      context: context,
      builder: (_) => _AssignTeacherDialog(teachers: _teachers),
    );
    if (result == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await _svc.convertPointToTask(
        meeting:     m,
        point:       p,
        teacherId:   result.id,
        teacherName: result.name,
        assignedBy:  widget.createdBy,
      );
      await NotificationService().addMeetingTaskNotification(
        teacherId:    result.id,
        meetingTitle: m.title,
        pointText:    p.text,
      );
      if (mounted) _snack('Task assigned to ${result.name}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Mark as completed ─────────────────────────────────────────────────────

  Future<void> _markCompleted(Meeting m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Complete Meeting?'),
        content: const Text(
            'This will permanently lock the meeting record. Points and tasks will be read-only.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Complete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _svc.markCompleted(m.id);
    if (mounted) _snack('Meeting marked as completed');
  }

  // ── Delete meeting ────────────────────────────────────────────────────────

  Future<void> _deleteMeeting(Meeting m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Meeting?'),
        content: const Text(
            'This permanently removes the meeting record. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _svc.deleteMeeting(m.id);
    if (mounted) Navigator.pop(context);
  }

  // ── PDF generation ────────────────────────────────────────────────────────

  Future<void> _generatePdf(Meeting m) async {
    setState(() => _generatingPdf = true);
    try {
      final pdfBytes = await _buildPdf(m);
      if (!mounted) return;
      await Printing.layoutPdf(
        onLayout: (_) async => pdfBytes,
        name:     '${m.title.replaceAll(' ', '_')}.pdf',
      );
    } catch (e) {
      if (mounted) _snack('PDF error: $e');
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  Future<Uint8List> _buildPdf(Meeting m) async {
    final doc = pw.Document();
    const purple = PdfColor.fromInt(0xFF6A1B9A);

    final dateStr = _fmtDate(m.date);

    // ── Page 1: Meeting Summary ───────────────────────────────────────────
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      header: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('MEETING RECORD',
              style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                  color: purple)),
          pw.SizedBox(height: 4),
          pw.Text(m.title,
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Text('Date: $dateStr  ·  By: ${m.createdByName} (${m.createdByRole})',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
          pw.Text('Status: ${m.status.label}',
              style: pw.TextStyle(fontSize: 10, color: purple)),
          pw.Divider(),
        ],
      ),
      footer: (ctx) => pw.Text(
        '${m.title}  ·  $dateStr  ·  Page ${ctx.pageNumber} of ${ctx.pagesCount}',
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
      ),
      build: (ctx) => [
        pw.Text('Discussion Points',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headers: ['#', 'Point', 'Status', 'Assigned To'],
          data: m.points.asMap().entries.map((entry) {
            final i = entry.key;
            final p = entry.value;
            final assignedName = p.convertedToTask
                ? (m.assignedTeacherNames.isNotEmpty
                    ? m.assignedTeacherNames.join(', ')
                    : 'Teacher')
                : '-';
            return [
              '${i + 1}',
              p.text,
              p.isChecked ? 'Discussed' : 'Pending',
              assignedName,
            ];
          }).toList(),
          headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
              fontSize: 10),
          headerDecoration: const pw.BoxDecoration(color: purple),
          cellStyle: const pw.TextStyle(fontSize: 9),
          rowDecoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
          ),
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
        ),
        pw.SizedBox(height: 20),
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: purple),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Summary',
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold, color: purple)),
              pw.SizedBox(height: 6),
              pw.Text('Total points: ${m.points.length}'),
              pw.Text('Discussed:    ${m.discussedCount}'),
              pw.Text('Tasks created: ${m.tasksCreated}'),
              if (m.assignedTeacherNames.isNotEmpty)
                pw.Text(
                    'Teachers assigned: ${m.assignedTeacherNames.join(', ')}'),
            ],
          ),
        ),
      ],
    ));

    // ── Page 2: Teacher-wise Tasks ────────────────────────────────────────
    final taskPoints = m.points.where((p) => p.convertedToTask).toList();
    if (taskPoints.isNotEmpty) {
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Teacher-wise Tasks — ${m.title}',
                style: pw.TextStyle(
                    fontSize: 16, fontWeight: pw.FontWeight.bold, color: purple)),
            pw.Text('Meeting date: $dateStr',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
            pw.Divider(),
          ],
        ),
        footer: (ctx) => pw.Text(
          '${m.title}  ·  $dateStr  ·  Page ${ctx.pageNumber} of ${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
        ),
        build: (_) => [
          pw.TableHelper.fromTextArray(
            headers: ['Teacher', 'Task', 'Status'],
            data: taskPoints.map((p) => [
                  m.assignedTeacherNames.isNotEmpty
                      ? m.assignedTeacherNames.first
                      : 'Teacher',
                  p.text,
                  p.isChecked ? 'Completed' : 'Pending',
                ]).toList(),
            headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
                fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: purple),
            cellStyle: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ));
    }

    return doc.save();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  String _fmtDate(DateTime d) {
    const mo = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${d.day} ${mo[d.month - 1]} ${d.year}';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _meetingDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
              primary: AppTheme.primary, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _meetingDate = picked);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isNew) return _buildNewMeetingForm();
    return _buildExistingMeeting();
  }

  // ── New meeting form ──────────────────────────────────────────────────────

  Widget _buildNewMeetingForm() {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('New Meeting'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Title
            TextFormField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Meeting Title',
                prefixIcon: Icon(Icons.title),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Enter a title' : null,
            ),
            const SizedBox(height: 16),

            // Date picker
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(10),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Meeting Date',
                  prefixIcon: Icon(Icons.calendar_today_outlined),
                ),
                child: Text(_fmtDate(_meetingDate),
                    style: const TextStyle(fontSize: 15)),
              ),
            ),
            const SizedBox(height: 24),

            // Agenda points
            Text('Agenda Points',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _pointCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Add a discussion point...',
                    prefixIcon: Icon(Icons.add_circle_outline),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _addPoint(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _addPoint,
                child: const Text('Add'),
              ),
            ]),
            const SizedBox(height: 8),
            ..._points.asMap().entries.map((e) => _PointRow(
                  index:   e.key,
                  point:   e.value,
                  readOnly: false,
                  onDelete: () => setState(() => _points.removeAt(e.key)),
                )),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: _saving
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.save_outlined),
                label: const Text('Create Meeting'),
                onPressed: _saving ? null : _createMeeting,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Existing meeting view ─────────────────────────────────────────────────

  Widget _buildExistingMeeting() {
    return StreamBuilder<Meeting?>(
      stream: _svc.streamMeeting(_meetingId!),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
          );
        }
        final m = snap.data;
        if (m == null) {
          return const Scaffold(body: Center(child: Text('Meeting not found')));
        }
        _meeting = m;

        final readOnly = widget.readOnly || m.isReadOnly;
        final isMine   = m.createdBy == widget.createdBy;

        return Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(
            title: Text(m.title,
                style: const TextStyle(fontSize: 16), overflow: TextOverflow.ellipsis),
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            actions: [
              if (!readOnly && m.status != MeetingStatus.completed)
                IconButton(
                  icon: const Icon(Icons.check_circle_outline),
                  tooltip: 'Mark Completed',
                  onPressed: () => _markCompleted(m),
                ),
              if (isMine)
                IconButton(
                  icon: _generatingPdf
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.picture_as_pdf_outlined),
                  tooltip: 'Generate PDF',
                  onPressed: _generatingPdf ? null : () => _generatePdf(m),
                ),
              if (isMine && !m.isCompleted)
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'delete') _deleteMeeting(m);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(Icons.delete_outline, color: Colors.red),
                        title: Text('Delete Meeting', style: TextStyle(color: Colors.red)),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── Meta card ──────────────────────────────────────────────
              _MetaCard(meeting: m, fmtDate: _fmtDate),
              const SizedBox(height: 16),

              // ── Add point row (if editable) ────────────────────────────
              if (!readOnly) ...[
                Text('Discussion Points',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Colors.grey.shade600)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _pointCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Add agenda point...',
                        prefixIcon: Icon(Icons.add_circle_outline),
                        isDense: true,
                      ),
                      onSubmitted: (_) {
                        // add to live meeting
                        final text = _pointCtrl.text.trim();
                        if (text.isEmpty) return;
                        final point = MeetingPoint(
                          id:      '${DateTime.now().millisecondsSinceEpoch}_${Object.hash(DateTime.now(), 0)}',
                          text:    text,
                          addedBy: widget.createdBy,
                          addedAt: DateTime.now(),
                        );
                        _pointCtrl.clear();
                        _svc.updatePoints(m.id, [...m.points, point]);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      final text = _pointCtrl.text.trim();
                      if (text.isEmpty) return;
                      final point = MeetingPoint(
                        id:      '${DateTime.now().millisecondsSinceEpoch}_${Object.hash(DateTime.now(), 0)}',
                        text:    text,
                        addedBy: widget.createdBy,
                        addedAt: DateTime.now(),
                      );
                      _pointCtrl.clear();
                      _svc.updatePoints(m.id, [...m.points, point]);
                    },
                    child: const Text('Add'),
                  ),
                ]),
                const SizedBox(height: 16),
              ],

              // ── Points list ────────────────────────────────────────────
              if (m.points.isEmpty)
                _emptyHint('No agenda points yet')
              else
                ...m.points.map((p) => _LivePointCard(
                      point:    p,
                      readOnly: readOnly,
                      saving:   _saving,
                      onToggle: () => _togglePoint(m, p),
                      onConvert: () => _convertToTask(m, p),
                    )),

              // ── Assigned teachers summary ──────────────────────────────
              if (m.assignedTeacherNames.isNotEmpty) ...[
                const SizedBox(height: 16),
                _AssignedTeachersCard(names: m.assignedTeacherNames),
              ],

              // ── Complete button ────────────────────────────────────────
              if (!readOnly && m.status != MeetingStatus.completed) ...[
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.success),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Mark as Completed'),
                    onPressed: _saving ? null : () => _markCompleted(m),
                  ),
                ),
              ],
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  Widget _emptyHint(String msg) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(Icons.info_outline, color: Colors.grey.shade400, size: 18),
          const SizedBox(width: 8),
          Text(msg, style: TextStyle(color: Colors.grey.shade500)),
        ]),
      );
}

// ── Teacher-select dialog ─────────────────────────────────────────────────────

class _AssignTeacherDialog extends StatelessWidget {
  final List<Teacher> teachers;
  const _AssignTeacherDialog({required this.teachers});

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Assign Task To'),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: teachers.length,
            itemBuilder: (_, i) {
              final t = teachers[i];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppTheme.primary.withOpacity(0.1),
                  child: Text(t.name.isNotEmpty ? t.name[0] : '?',
                      style: const TextStyle(color: AppTheme.primary)),
                ),
                title: Text(t.name),
                subtitle: Text(t.subject, style: const TextStyle(fontSize: 11)),
                onTap: () => Navigator.pop(context, t),
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
        ],
      );
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _MetaCard extends StatelessWidget {
  final Meeting  meeting;
  final String Function(DateTime) fmtDate;
  const _MetaCard({required this.meeting, required this.fmtDate});

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (meeting.status) {
      MeetingStatus.active    => AppTheme.primary,
      MeetingStatus.completed => AppTheme.success,
      MeetingStatus.draft     => Colors.grey,
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(meeting.title,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(meeting.status.label,
                style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Icon(Icons.calendar_today_outlined,
              size: 14, color: Colors.grey.shade500),
          const SizedBox(width: 4),
          Text(fmtDate(meeting.date),
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(width: 12),
          Icon(Icons.person_outline, size: 14, color: Colors.grey.shade500),
          const SizedBox(width: 4),
          Text('${meeting.createdByName} · ${meeting.createdByRole}',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        ]),
        const SizedBox(height: 12),
        Divider(height: 1, color: Colors.grey.shade100),
        const SizedBox(height: 10),
        Row(children: [
          _StatChip(label: '${meeting.points.length}', sub: 'Points'),
          const SizedBox(width: 12),
          _StatChip(
              label: '${meeting.discussedCount}',
              sub: 'Discussed',
              color: AppTheme.success),
          const SizedBox(width: 12),
          _StatChip(
              label: '${meeting.tasksCreated}',
              sub: 'Tasks',
              color: AppTheme.warning),
        ]),
      ]),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label, sub;
  final Color  color;
  const _StatChip({required this.label, required this.sub, this.color = AppTheme.primary});

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(label,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Text(sub,
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
      ]);
}

class _PointRow extends StatelessWidget {
  final int          index;
  final MeetingPoint point;
  final bool         readOnly;
  final VoidCallback onDelete;
  const _PointRow(
      {required this.index,
      required this.point,
      required this.readOnly,
      required this.onDelete});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200)),
        child: Row(children: [
          Text('${index + 1}.',
              style: TextStyle(
                  color: Colors.grey.shade400,
                  fontWeight: FontWeight.w600,
                  fontSize: 12)),
          const SizedBox(width: 8),
          Expanded(child: Text(point.text, style: const TextStyle(fontSize: 14))),
          if (!readOnly)
            IconButton(
              icon: Icon(Icons.close, size: 18, color: Colors.grey.shade400),
              onPressed: onDelete,
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(4),
            ),
        ]),
      );
}

class _LivePointCard extends StatelessWidget {
  final MeetingPoint point;
  final bool         readOnly;
  final bool         saving;
  final VoidCallback onToggle;
  final VoidCallback onConvert;

  const _LivePointCard({
    required this.point,
    required this.readOnly,
    required this.saving,
    required this.onToggle,
    required this.onConvert,
  });

  @override
  Widget build(BuildContext context) {
    final border = point.convertedToTask
        ? AppTheme.success
        : point.isChecked
            ? AppTheme.primary
            : Colors.grey.shade200;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: border, width: 3)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!readOnly)
            GestureDetector(
              onTap: saving ? null : onToggle,
              child: Container(
                width: 22, height: 22,
                margin: const EdgeInsets.only(top: 1, right: 10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: point.isChecked
                      ? AppTheme.primary
                      : Colors.transparent,
                  border: Border.all(
                      color: point.isChecked
                          ? AppTheme.primary
                          : Colors.grey.shade300),
                ),
                child: point.isChecked
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 1, right: 10),
              child: Icon(
                point.isChecked
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                size: 20,
                color: point.isChecked ? AppTheme.success : Colors.grey.shade400,
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(point.text,
                    style: TextStyle(
                        fontSize: 14,
                        decoration: point.isChecked && !point.convertedToTask
                            ? TextDecoration.lineThrough
                            : null,
                        color: point.isChecked && !point.convertedToTask
                            ? Colors.grey.shade400
                            : Colors.black87)),
                if (point.convertedToTask) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.task_alt,
                        size: 12, color: AppTheme.success),
                    const SizedBox(width: 4),
                    Text('Task assigned',
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.success,
                            fontWeight: FontWeight.w500)),
                  ]),
                ],
              ],
            ),
          ),
          if (!readOnly && !point.convertedToTask)
            TextButton.icon(
              style: TextButton.styleFrom(
                  foregroundColor: AppTheme.warning,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
              icon: const Icon(Icons.assignment_ind_outlined, size: 15),
              label: const Text('Assign', style: TextStyle(fontSize: 12)),
              onPressed: saving ? null : onConvert,
            ),
        ]),
      ),
    );
  }
}

class _AssignedTeachersCard extends StatelessWidget {
  final List<String> names;
  const _AssignedTeachersCard({required this.names});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.success.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.success.withOpacity(0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.people_outline, size: 16, color: AppTheme.success),
            const SizedBox(width: 6),
            Text('Teachers Assigned (${names.length})',
                style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppTheme.success)),
          ]),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: names
                .map((n) => Chip(
                      label: Text(n, style: const TextStyle(fontSize: 11)),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor: AppTheme.success.withOpacity(0.08),
                      labelStyle: const TextStyle(color: AppTheme.success),
                    ))
                .toList(),
          ),
        ]),
      );
}

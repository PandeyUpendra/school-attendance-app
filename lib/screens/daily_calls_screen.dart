import 'dart:io';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../theme.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/student.dart';
import '../models/teacher.dart';
import '../services/student_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  DailyCallsScreen — permanent calls tracking for class teacher
// ─────────────────────────────────────────────────────────────────────────────

class DailyCallsScreen extends StatefulWidget {
  final Teacher teacher;
  const DailyCallsScreen({super.key, required this.teacher});

  @override
  State<DailyCallsScreen> createState() => _DailyCallsScreenState();
}

class _DailyCallsScreenState extends State<DailyCallsScreen>
    with SingleTickerProviderStateMixin {
  final _service = StudentService();
  late final TabController _tabCtrl;

  String get _className => widget.teacher.classTeacherOf ?? '';
  String get _section   => widget.teacher.section;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Daily Calls',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text('Guardian follow-up & history',
                style: TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.today_outlined, size: 18), text: 'Today'),
            Tab(icon: Icon(Icons.history_outlined, size: 18), text: 'History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _TodayCallsTab(className: _className, section: _section, service: _service),
          _HistoryTab(className: _className, section: _section, service: _service),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Today's calls tab
// ─────────────────────────────────────────────────────────────────────────────

class _TodayCallsTab extends StatefulWidget {
  final String         className;
  final String         section;
  final StudentService service;
  const _TodayCallsTab({required this.className, required this.section, required this.service});

  @override
  State<_TodayCallsTab> createState() => _TodayCallsTabState();
}

class _TodayCallsTabState extends State<_TodayCallsTab> {
  List<Student>    _students    = [];
  Map<int, String> _attendance  = {};
  Map<int, String> _reasons     = {};
  Map<int, bool>   _called      = {};
  bool _loading = true;

  String get _attendanceKey => widget.section.trim().isEmpty
      ? widget.className
      : '${widget.className} ${widget.section.trim()}';

  List<Student> get _absentLeave => _students
      .where((s) =>
          _attendance[s.roll] == 'Absent' ||
          _attendance[s.roll] == 'Leave')
      .toList();

  int get _calledCount =>
      _absentLeave.where((s) => _called[s.roll] == true).length;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      widget.service.getStudentsByClass(widget.className, section: widget.section),
      widget.service.loadTodayAttendance(_attendanceKey),
      widget.service.loadTodayReasons(_attendanceKey),
      widget.service.loadTodayCalled(_attendanceKey),
    ]);
    final students = results[0] as List<Student>;
    assert(students.length == {for (final s in students) s.roll: s}.length,
        'Duplicate rolls detected in class ${widget.className}');
    debugPrint('[StudentList][${widget.className}] count=${students.length}');

    if (!mounted) return;
    setState(() {
      _students   = students;
      _attendance = results[1] as Map<int, String>;
      _reasons    = results[2] as Map<int, String>;
      _called     = results[3] as Map<int, bool>;
      _loading    = false;
    });
  }

  // ── Call + reason ─────────────────────────────────────────────────────────
  Future<void> _callStudent(Student s) async {
    if (s.phone.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: s.phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
    if (!mounted) return;
    await _recordCall(s);
  }

  Future<void> _openWhatsApp(Student s) async {
    if (s.phone.isEmpty) return;
    final msg = _waMessage(s);
    final digits = s.phone.replaceAll(RegExp(r'[^0-9]'), '');
    final url = Uri.parse(
        'https://wa.me/$digits?text=${Uri.encodeComponent(msg)}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
    if (!mounted) return;
    await _recordCall(s);
  }

  String _waMessage(Student s) {
    final status = _attendance[s.roll] ?? 'Absent';
    final word = status == 'Leave' ? 'on leave' : 'absent';
    final d = DateTime.now();
    const mo = ['Jan','Feb','Mar','Apr','May','Jun',
                 'Jul','Aug','Sep','Oct','Nov','Dec'];
    final dt = '${d.day} ${mo[d.month - 1]} ${d.year}';
    return 'Dear Parent/Guardian,\n\n'
        'Your child *${s.name}* (Roll No. ${s.roll}) of '
        '*${widget.className}* is *$word* in school today ($dt).\n\n'
        'Consistent school attendance is crucial for your child\'s '
        'academic success. Please ensure regular attendance.\n\n'
        'Thank you.\n— School Management';
  }

  Future<void> _recordCall(Student s) async {
    const presets = [
      'Health Issue', 'Family Function', 'Personal Emergency',
      'Travel', 'Not Reachable', 'Other'
    ];
    final ctrl = TextEditingController(text: _reasons[s.roll]);
    String? chipSel = _reasons[s.roll] != null &&
            presets.contains(_reasons[s.roll]) &&
            _reasons[s.roll] != 'Other'
        ? _reasons[s.roll]
        : (_reasons[s.roll] != null ? 'Other' : null);

    final reason = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Call Notes — ${s.name}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Reason for absence:',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: presets.map((chip) {
                  return ChoiceChip(
                    label: Text(chip, style: const TextStyle(fontSize: 12)),
                    selected: chipSel == chip,
                    selectedColor: Colors.red.shade50,
                    onSelected: (_) => setS(() {
                      chipSel = chip;
                      if (chip != 'Other') ctrl.text = chip;
                      else ctrl.clear();
                    }),
                  );
                }).toList(),
              ),
              if (chipSel == 'Other' || chipSel == null) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  autofocus: chipSel == null,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Enter reason…',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                          color: Colors.red.shade700, width: 1.5),
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final r = (chipSel != null && chipSel != 'Other')
                    ? chipSel!
                    : ctrl.text.trim();
                Navigator.pop(ctx, r);
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || reason == null) return;
    setState(() {
      _called[s.roll] = true;
      if (reason.isNotEmpty) _reasons[s.roll] = reason;
    });
    await Future.wait([
      widget.service.saveReasons(_attendanceKey, _reasons),
      widget.service.saveCalled(_attendanceKey, _called),
    ]);
  }

  // ── PDF export ────────────────────────────────────────────────────────────
  Future<void> _exportPdf() async {
    final doc = pw.Document();
    final d = DateTime.now();
    const mo = ['Jan','Feb','Mar','Apr','May','Jun',
                 'Jul','Aug','Sep','Oct','Nov','Dec'];
    final dateStr = '${d.day} ${mo[d.month - 1]} ${d.year}';

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Daily Call Report',
              style: pw.TextStyle(
                  fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text('Class: ${widget.className}   Date: $dateStr',
              style: const pw.TextStyle(fontSize: 12,
                  color: PdfColors.grey700)),
          pw.SizedBox(height: 4),
          pw.Text(
            'Total Absent/Leave: ${_absentLeave.length}   '
            'Called: $_calledCount   '
            'Pending: ${_absentLeave.length - _calledCount}',
            style: const pw.TextStyle(fontSize: 11,
                color: PdfColors.grey600),
          ),
          pw.SizedBox(height: 16),
          pw.Divider(),
          pw.SizedBox(height: 8),
          // Table
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            columnWidths: {
              0: const pw.FlexColumnWidth(1),
              1: const pw.FlexColumnWidth(3),
              2: const pw.FlexColumnWidth(1.5),
              3: const pw.FlexColumnWidth(1),
              4: const pw.FlexColumnWidth(3),
            },
            children: [
              // Header
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.red900),
                children: [
                  _pdfCell('Roll', isHeader: true),
                  _pdfCell('Name', isHeader: true),
                  _pdfCell('Status', isHeader: true),
                  _pdfCell('Called', isHeader: true),
                  _pdfCell('Reason', isHeader: true),
                ],
              ),
              // Data rows
              ..._absentLeave.map((s) => pw.TableRow(
                children: [
                  _pdfCell('${s.roll}'),
                  _pdfCell(s.name),
                  _pdfCell(_attendance[s.roll] ?? ''),
                  _pdfCell(_called[s.roll] == true ? '✓' : '—'),
                  _pdfCell(_reasons[s.roll] ?? '—'),
                ],
              )),
            ],
          ),
          pw.SizedBox(height: 24),
          pw.Text(
            'Generated by School App on $dateStr',
            style: const pw.TextStyle(
                fontSize: 9, color: PdfColors.grey500),
          ),
        ],
      ),
    ));

    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: 'calls_${widget.className.replaceAll(' ', '_')}_$dateStr.pdf',
    );
  }

  pw.Widget _pdfCell(String text, {bool isHeader = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: isHeader ? PdfColors.white : PdfColors.black,
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (widget.className.isEmpty) {
      return _emptyHint(
        Icons.class_outlined,
        'Not a class teacher',
        'Only class teachers can access Daily Calls',
      );
    }

    final absent  = _absentLeave.where((s) => _attendance[s.roll] == 'Absent').toList();
    final onLeave = _absentLeave.where((s) => _attendance[s.roll] == 'Leave').toList();

    return RefreshIndicator(
      onRefresh: _load,
      color: Colors.red.shade700,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          // ── Summary card ───────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.className,
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold)),
                          Text(
                            _absentLeave.isEmpty
                                ? 'No absent/leave students today'
                                : '$_calledCount of ${_absentLeave.length} called',
                            style: TextStyle(
                                fontSize: 12,
                                color: _calledCount == _absentLeave.length &&
                                        _absentLeave.isNotEmpty
                                    ? Colors.green
                                    : Colors.grey.shade500),
                          ),
                        ]),
                  ),
                  if (_absentLeave.isNotEmpty)
                    TextButton.icon(
                      onPressed: _exportPdf,
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                      label: const Text('Export PDF'),
                      style: TextButton.styleFrom(
                          foregroundColor: Colors.red.shade700),
                    ),
                ]),
                if (_absentLeave.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _absentLeave.isEmpty
                          ? 0
                          : _calledCount / _absentLeave.length,
                      minHeight: 5,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          _calledCount == _absentLeave.length
                              ? Colors.green
                              : Colors.red.shade700),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          if (_absentLeave.isEmpty)
            _emptyHint(
              Icons.check_circle_outline,
              'No follow-ups today',
              _attendance.isEmpty
                  ? 'Attendance has not been marked yet today'
                  : 'All students are present today 🎉',
            )
          else ...[
            if (absent.isNotEmpty) ...[
              _sectionLabel('Absent (${absent.length})',
                  const Color(0xFFC62828)),
              ...absent.map((s) => _CallCard(
                    student:    s,
                    status:     'Absent',
                    called:     _called[s.roll] ?? false,
                    reason:     _reasons[s.roll],
                    onCall:     () => _callStudent(s),
                    onWhatsApp: () => _openWhatsApp(s),
                    onNote:     () => _recordCall(s),
                  )),
            ],
            if (onLeave.isNotEmpty) ...[
              _sectionLabel('On Leave (${onLeave.length})',
                  const Color(0xFFF57F17)),
              ...onLeave.map((s) => _CallCard(
                    student:    s,
                    status:     'Leave',
                    called:     _called[s.roll] ?? false,
                    reason:     _reasons[s.roll],
                    onCall:     () => _callStudent(s),
                    onWhatsApp: () => _openWhatsApp(s),
                    onNote:     () => _recordCall(s),
                  )),
            ],
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 6),
      child: Row(children: [
        Container(width: 8, height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(text,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: color, letterSpacing: 0.5)),
      ]),
    );
  }

  Widget _emptyHint(IconData icon, String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(title,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade500)),
          const SizedBox(height: 6),
          Text(subtitle,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Individual call card
// ─────────────────────────────────────────────────────────────────────────────

class _CallCard extends StatelessWidget {
  final Student    student;
  final String     status;
  final bool       called;
  final String?    reason;
  final VoidCallback onCall, onWhatsApp, onNote;

  const _CallCard({
    required this.student,
    required this.status,
    required this.called,
    required this.reason,
    required this.onCall,
    required this.onWhatsApp,
    required this.onNote,
  });

  @override
  Widget build(BuildContext context) {
    final color = status == 'Absent'
        ? const Color(0xFFC62828)
        : const Color(0xFFF57F17);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: called ? Colors.green.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: called ? Colors.green.shade200 : Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: color.withOpacity(0.1),
            backgroundImage: student.photoPath != null
                ? FileImage(File(student.photoPath!))
                : null,
            child: student.photoPath == null
                ? Text(student.name[0].toUpperCase(),
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: color))
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(student.name,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                'Roll ${student.roll}  ·  '
                '${student.phone.isNotEmpty ? student.phone : "No phone"}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          )),
          // Called badge
          if (called)
            GestureDetector(
              onTap: onNote,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle, color: Colors.green.shade700, size: 13),
                  const SizedBox(width: 4),
                  Text('Called',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.green.shade700)),
                ]),
              ),
            ),
        ]),

        if (student.phone.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(children: [
            // Phone call button
            Expanded(
              child: _ActionButton(
                icon: Icons.phone_outlined,
                label: 'Call',
                color: Colors.blue.shade600,
                onTap: onCall,
              ),
            ),
            const SizedBox(width: 8),
            // WhatsApp button
            Expanded(
              child: _ActionButton(
                icon: FontAwesomeIcons.whatsapp,
                label: 'WhatsApp',
                color: const Color(0xFF25D366),
                onTap: onWhatsApp,
              ),
            ),
            const SizedBox(width: 8),
            // Note button
            Expanded(
              child: _ActionButton(
                icon: Icons.edit_note_outlined,
                label: 'Note',
                color: Colors.orange.shade700,
                onTap: onNote,
              ),
            ),
          ]),
        ] else ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: _ActionButton(
                icon: Icons.edit_note_outlined,
                label: 'Add Note',
                color: Colors.orange.shade700,
                onTap: onNote,
              ),
            ),
          ]),
        ],

        // Reason note
        if (reason != null && reason!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.notes_outlined,
                    size: 13, color: Colors.grey.shade500),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(reason!,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade700)),
                ),
                GestureDetector(
                  onTap: onNote,
                  child: Icon(Icons.edit_outlined,
                      size: 13, color: Colors.grey.shade400),
                ),
              ],
            ),
          ),
        ],
      ]),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final Color        color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  History tab — past 7 days
// ─────────────────────────────────────────────────────────────────────────────

class _HistoryTab extends StatefulWidget {
  final String         className;
  final String         section;
  final StudentService service;
  const _HistoryTab({required this.className, required this.section, required this.service});

  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  static const _historyDays = 14;

  List<_DayRecord> _records = [];
  bool _loading = true;

  String get _attendanceKey => widget.section.trim().isEmpty
      ? widget.className
      : '${widget.className} ${widget.section.trim()}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final now = DateTime.now();
    // Skip today (index 0), show past 14 days
    final futures = List.generate(_historyDays, (i) {
      final date = now.subtract(Duration(days: i + 1));
      return widget.service.loadAttendanceForDate(_attendanceKey, date)
          .then((data) => _DayRecord(date: date, data: data));
    });
    final records = await Future.wait(futures);
    if (!mounted) return;
    setState(() {
      _records = records.where((r) => r.data != null).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_records.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.history_outlined, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text('No history found',
              style: TextStyle(fontSize: 15, color: Colors.grey.shade500)),
          const SizedBox(height: 4),
          Text('Past call records will appear here',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
        ]),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: Colors.red.shade700,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: _records.length,
        itemBuilder: (_, i) => _DayCard(record: _records[i]),
      ),
    );
  }
}

class _DayRecord {
  final DateTime date;
  final Map<String, dynamic>? data;
  const _DayRecord({required this.date, required this.data});
}

class _DayCard extends StatefulWidget {
  final _DayRecord record;
  const _DayCard({required this.record});

  @override
  State<_DayCard> createState() => _DayCardState();
}

class _DayCardState extends State<_DayCard> {
  bool _expanded = false;

  String _dateLabel() {
    final d = widget.record.date;
    const mo = ['Jan','Feb','Mar','Apr','May','Jun',
                 'Jul','Aug','Sep','Oct','Nov','Dec'];
    const dy = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return '${dy[d.weekday - 1]}, ${d.day} ${mo[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.record.data!;
    final rollsRaw = Map<String, dynamic>.from(
        (data['rolls'] as Map?) ?? {});
    final reasonsRaw = Map<String, dynamic>.from(
        (data['reasons'] as Map?) ?? {});
    final calledRaw = Map<String, dynamic>.from(
        (data['called'] as Map?) ?? {});

    final absent = rollsRaw.entries
        .where((e) => e.value == 'Absent')
        .length;
    final leave = rollsRaw.entries
        .where((e) => e.value == 'Leave')
        .length;
    final called = calledRaw.values.where((v) => v == true).length;
    final total  = rollsRaw.length;

    // Absent+leave entries for expansion
    final absentLeaveRolls = rollsRaw.entries
        .where((e) => e.value == 'Absent' || e.value == 'Leave')
        .toList();

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.event_note_outlined,
                    color: Colors.red.shade700, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_dateLabel(),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    'Total $total  ·  Absent $absent  ·  Leave $leave  ·  Called $called',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              )),
              Icon(
                _expanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                color: Colors.grey.shade400,
              ),
            ]),
          ),

          // Expanded details
          if (_expanded && absentLeaveRolls.isNotEmpty) ...[
            const Divider(height: 1),
            ...absentLeaveRolls.map((entry) {
              final roll   = entry.key;
              final status = entry.value as String;
              final reason = reasonsRaw[roll] as String?;
              final wasCalled = calledRaw[roll] == true;
              final color  = status == 'Absent'
                  ? const Color(0xFFC62828)
                  : const Color(0xFFF57F17);
              return Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 26, height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                          roll,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: color)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(status,
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: color)),
                          ),
                          const SizedBox(width: 6),
                          if (wasCalled)
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.check_circle,
                                  size: 12, color: Colors.green.shade600),
                              const SizedBox(width: 3),
                              Text('Called',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.green.shade600)),
                            ]),
                        ]),
                        if (reason != null && reason.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(reason,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600)),
                          ),
                      ],
                    )),
                  ],
                ),
              );
            }),
            const SizedBox(height: 6),
          ],
        ]),
      ),
    );
  }
}

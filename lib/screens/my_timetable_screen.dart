import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/teacher.dart';
import '../models/timetable_entry.dart';
import '../services/timetable_service.dart';
import '../theme.dart';

class MyTimetableScreen extends StatefulWidget {
  /// When provided → shows this teacher's personal schedule.
  /// When null    → shows the full school timetable (coordinator / read-only).
  final Teacher? teacher;
  const MyTimetableScreen({super.key, this.teacher});

  @override
  State<MyTimetableScreen> createState() => _MyTimetableScreenState();
}

class _MyTimetableScreenState extends State<MyTimetableScreen> {
  final _service = TimetableService();
  List<String>  _classes  = [];
  int           _bellCount = 8;
  List<Map<String, dynamic>> _bells = [];
  Map<String, Map<String, Map<int, TimetableEntry>>> _timetable = {};
  List<Teacher> _teachers = [];
  bool   _loading     = true;
  String _selectedDay = 'Monday';

  static const _days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'
  ];
  static const _dayAbbr = {
    'Monday': 'Mon', 'Tuesday': 'Tue', 'Wednesday': 'Wed',
    'Thursday': 'Thu', 'Friday': 'Fri', 'Saturday': 'Sat',
  };

  static const List<Color> _palette = [
    Color(0xFF009688), Color(0xFF3F51B5), Color(0xFFFF9800), Color(0xFFE91E63),
    Color(0xFF9C27B0), Color(0xFF4CAF50), Color(0xFFF44336), Color(0xFF795548),
    Color(0xFF00BCD4), Color(0xFF673AB7),
  ];

  bool get _isPersonal => widget.teacher != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings  = await _service.getSettings();
    final tt        = await _service.getTimetable();
    final teachers  = await _service.getTeachers();
    if (!mounted) return;

    final bellsRaw = settings['bells'] as List? ?? [];
    final List<Map<String, dynamic>> bells;
    if (bellsRaw.isNotEmpty) {
      bells = bellsRaw.cast<Map<String, dynamic>>();
    } else {
      final n = settings['numberOfBells'] as int? ?? 8;
      bells = List.generate(n, (_) => {'isLunch': false, 'duration': 45});
    }

    setState(() {
      _classes   = List<String>.from(settings['classes'] as List);
      _bells     = bells;
      _bellCount = bells.length;
      _timetable = tt;
      _teachers  = teachers;
      _loading   = false;
    });
  }

  bool _isLunchBell(int zeroIdx) =>
      zeroIdx < _bells.length &&
      (_bells[zeroIdx]['isLunch'] as bool? ?? false);

  int _bellDisplayNumber(int zeroIdx) {
    int count = 0;
    for (int i = 0; i <= zeroIdx; i++) {
      if (!(_bells[i]['isLunch'] as bool? ?? false)) count++;
    }
    return count;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  String _teacherName(TimetableEntry? e) {
    if (e == null || e.isEmpty) return '—';
    final t = _teachers.firstWhere((t) => t.id == e.teacherId,
        orElse: () => Teacher(id: '', name: '—', subject: '', email: '', schoolId: ''));
    return t.name;
  }

  String _subjectLabel(TimetableEntry? e) {
    if (e == null || e.isEmpty) return '';
    if (e.subject?.isNotEmpty == true) return e.subject!;
    final t = _teachers.firstWhere((t) => t.id == e.teacherId,
        orElse: () => Teacher(id: '', name: '', subject: '', email: '', schoolId: ''));
    return t.subject;
  }

  Color _teacherColor(TimetableEntry? e) {
    if (e == null || e.isEmpty) return Colors.grey.shade300;
    final idx = _teachers.indexWhere((t) => t.id == e.teacherId);
    return idx < 0 ? Colors.grey.shade300 : _palette[idx % _palette.length];
  }

  /// Personal view: for [_selectedDay], return list of (bell, className, subject)
  /// where this teacher is assigned.
  List<_PersonalSlot> get _mySlots {
    if (!_isPersonal) return [];
    final tid = widget.teacher!.id;
    final slots = <_PersonalSlot>[];
    for (final cls in _classes) {
      for (int b = 1; b <= _bellCount; b++) {
        if (_isLunchBell(b - 1)) continue; // skip lunch positions
        final entry = _timetable[cls]?[_selectedDay]?[b];
        if (entry?.teacherId == tid) {
          slots.add(_PersonalSlot(
            bell:      b,
            bellDisplayNum: _bellDisplayNumber(b - 1),
            className: cls,
            subject:   _subjectLabel(entry),
          ));
        }
      }
    }
    slots.sort((a, b) => a.bell.compareTo(b.bell));
    return slots;
  }

  // ── PDF generation ───────────────────────────────────────────────────────────

  Future<void> _sharePdf(String? forClass) async {
    final pdf = pw.Document();

    // Collect data
    final classes = forClass != null ? [forClass] : _classes;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (ctx) => [
          pw.Text(
            forClass != null
                ? '$forClass — Timetable'
                : 'School Timetable',
            style: pw.TextStyle(
                fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 12),
          for (final cls in classes) ...[
            if (classes.length > 1)
              pw.Text(cls,
                  style: pw.TextStyle(
                      fontSize: 13, fontWeight: pw.FontWeight.bold)),
            if (classes.length > 1) pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400),
              columnWidths: {
                0: const pw.FixedColumnWidth(60),
                for (int b = 1; b <= _bellCount; b++)
                  b: const pw.FlexColumnWidth(1),
              },
              children: [
                // Header
                pw.TableRow(
                  decoration:
                      const pw.BoxDecoration(color: PdfColors.indigo700),
                  children: [
                    _pdfCell('Day', bold: true, light: true),
                    for (int b = 1; b <= _bellCount; b++)
                      _pdfCell(
                        _isLunchBell(b - 1)
                            ? 'Lunch'
                            : 'Bell ${_bellDisplayNumber(b - 1)}',
                        bold: true,
                        light: true,
                      ),
                  ],
                ),
                // Days
                for (final day in _days)
                  pw.TableRow(children: [
                    _pdfCell(day, bold: true),
                    for (int b = 1; b <= _bellCount; b++)
                      _pdfCell(
                        _subjectLabel(_timetable[cls]?[day]?[b]).isEmpty
                            ? '—'
                            : _subjectLabel(_timetable[cls]?[day]?[b]),
                      ),
                  ]),
              ],
            ),
            if (classes.length > 1) pw.SizedBox(height: 16),
          ],
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: forClass != null
          ? '${forClass.replaceAll(' ', '_')}_Timetable.pdf'
          : 'School_Timetable.pdf',
    );
  }

  pw.Widget _pdfCell(String text,
      {bool bold = false, bool light = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: light ? PdfColors.white : PdfColors.black,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(_isPersonal ? 'My Timetable' : 'School Timetable'),
        actions: [
          if (!_isPersonal && !_loading && _classes.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              tooltip: 'Share PDF',
              onPressed: () => _showPdfOptions(context),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _classes.isEmpty
              ? _emptyState()
              : _isPersonal
                  ? _buildPersonalView()
                  : _buildFullGrid(),
    );
  }

  Widget _emptyState() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.calendar_today_outlined,
          size: 64, color: Colors.grey.shade300),
      const SizedBox(height: 16),
      Text('Timetable not set up yet',
          style: TextStyle(fontSize: 16, color: Colors.grey.shade400)),
      const SizedBox(height: 6),
      Text('Ask the coordinator to configure it',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
    ]),
  );

  // ── Personal view (teacher's own schedule) ───────────────────────────────────

  Widget _buildPersonalView() {
    final slots = _mySlots;
    return Column(children: [
      // Day selector
      _daySelector(),
      const Divider(height: 1),

      // Slots
      Expanded(
        child: slots.isEmpty
            ? Center(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  Icon(Icons.event_available_outlined,
                      size: 48, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text('No classes on ${_dayAbbr[_selectedDay]}',
                      style: TextStyle(
                          fontSize: 15, color: Colors.grey.shade400)),
                ]),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                itemCount: slots.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _PersonalSlotCard(slot: slots[i]),
              ),
      ),
    ]);
  }

  // ── Full school grid (coordinator) ───────────────────────────────────────────

  Widget _buildFullGrid() {
    final regularBells =
        _bells.where((b) => !(b['isLunch'] as bool? ?? false)).length;
    return Column(children: [
      // Info strip
      Container(
        color: AppTheme.primary,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Row(children: [
          _Badge(label: 'Classes',   value: '${_classes.length}'),
          const SizedBox(width: 8),
          _Badge(label: 'Bells/Day', value: '$regularBells'),
        ]),
      ),
      _daySelector(),
      const Divider(height: 1),
      Expanded(
        child: SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  _HeaderCell('Class', width: 90, isCorner: true),
                  for (int b = 1; b <= _bellCount; b++)
                    _isLunchBell(b - 1)
                        ? _LunchHeaderCell(width: 110)
                        : _HeaderCell(
                            'Bell ${_bellDisplayNumber(b - 1)}',
                            width: 110),
                ]),
                for (int i = 0; i < _classes.length; i++)
                  GestureDetector(
                    onTap: () => _showPdfOptions(context, cls: _classes[i]),
                    child: Row(children: [
                      Container(
                        width: 90, height: 58,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: i % 2 == 0
                              ? AppTheme.primary.withOpacity(0.06)
                              : Colors.white,
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Text(_classes[i],
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ),
                      for (int b = 1; b <= _bellCount; b++)
                        _isLunchBell(b - 1)
                            ? _LunchCell(isEven: i % 2 == 0)
                            : _ReadCell(
                                name:    _teacherName(
                                    _timetable[_classes[i]]?[_selectedDay]?[b]),
                                subject: _subjectLabel(
                                    _timetable[_classes[i]]?[_selectedDay]?[b]),
                                color:   _teacherColor(
                                    _timetable[_classes[i]]?[_selectedDay]?[b]),
                                isEven:  i % 2 == 0,
                              ),
                    ]),
                  ),
              ],
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _daySelector() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: _days.map((d) {
            final sel = d == _selectedDay;
            return GestureDetector(
              onTap: () => setState(() => _selectedDay = d),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 7),
                decoration: BoxDecoration(
                  color: sel ? AppTheme.primary : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: sel
                          ? AppTheme.primary
                          : Colors.grey.shade300),
                ),
                child: Text(_dayAbbr[d]!,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: sel
                            ? Colors.white
                            : Colors.grey.shade600)),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showPdfOptions(BuildContext context, {String? cls}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom + 16,
            top: 16, left: 20, right: 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
          ),
          Text(
            cls != null
                ? 'Timetable PDF — $cls'
                : 'School Timetable PDF',
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            cls != null
                ? 'Full weekly timetable for $cls'
                : 'Full timetable for all ${_classes.length} classes',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _sharePdf(cls);
              },
              icon: const Icon(Icons.share_outlined),
              label: const Text('Download / Share PDF'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Personal slot data ────────────────────────────────────────────────────────

class _PersonalSlot {
  final int    bell;
  final int    bellDisplayNum;
  final String className;
  final String subject;
  const _PersonalSlot({
    required this.bell,
    required this.bellDisplayNum,
    required this.className,
    required this.subject,
  });
}

// ── Personal slot card ────────────────────────────────────────────────────────

class _PersonalSlotCard extends StatelessWidget {
  final _PersonalSlot slot;
  const _PersonalSlotCard({required this.slot});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primary.withOpacity(0.18)),
      ),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${slot.bellDisplayNum}',
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(slot.className,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600)),
          ]),
        ),
        Text('Bell ${slot.bellDisplayNum}',
            style: const TextStyle(
                fontSize: 11,
                color: AppTheme.primaryMid,
                fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

// ── Badge ────────────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final String label, value;
  const _Badge({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          Text(label,
              style:
                  const TextStyle(fontSize: 11, color: Colors.white70)),
        ]),
      ),
    );
  }
}

// ── Grid widgets ─────────────────────────────────────────────────────────────

class _HeaderCell extends StatelessWidget {
  final String text;
  final double width;
  final bool isCorner;
  const _HeaderCell(this.text, {required this.width, this.isCorner = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width, height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isCorner ? AppTheme.primaryDark : AppTheme.primary,
        border: Border.all(color: AppTheme.primaryDark),
      ),
      child: Text(text,
          style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontSize: 12)),
    );
  }
}

class _LunchHeaderCell extends StatelessWidget {
  final double width;
  const _LunchHeaderCell({required this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width, height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.orange.shade700,
        border: Border.all(color: Colors.orange.shade900),
      ),
      child: const Text('🍽 Lunch',
          style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontSize: 11)),
    );
  }
}

class _LunchCell extends StatelessWidget {
  final bool isEven;
  const _LunchCell({required this.isEven});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 110, height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        border: Border.all(color: Colors.orange.shade100),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.restaurant, color: Colors.orange.shade300, size: 18),
        Text('Lunch',
            style:
                TextStyle(fontSize: 9, color: Colors.orange.shade400)),
      ]),
    );
  }
}

class _ReadCell extends StatelessWidget {
  final String name, subject;
  final Color  color;
  final bool   isEven;
  const _ReadCell({
    required this.name,
    required this.subject,
    required this.color,
    required this.isEven,
  });

  @override
  Widget build(BuildContext context) {
    final hasTeacher = name != '—';
    return Container(
      width: 110, height: 72,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: hasTeacher
            ? color.withOpacity(0.12)
            : (isEven ? Colors.grey.shade50 : Colors.white),
        border: Border.all(
            color: hasTeacher
                ? color.withOpacity(0.3)
                : Colors.grey.shade200),
      ),
      child: hasTeacher
          ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              CircleAvatar(
                  radius: 11,
                  backgroundColor: color,
                  child: Text(name[0].toUpperCase(),
                      style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.bold))),
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(name,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: color.withOpacity(0.9)),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    textAlign: TextAlign.center),
              ),
              if (subject.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(subject,
                      style: TextStyle(
                          fontSize: 9, color: color.withOpacity(0.7)),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      textAlign: TextAlign.center),
                ),
            ])
          : Text('—',
              style:
                  TextStyle(color: Colors.grey.shade300, fontSize: 16)),
    );
  }
}

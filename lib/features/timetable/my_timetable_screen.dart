import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../shared/utils/pdf_theme.dart';
import 'package:provider/provider.dart';
import '../../shared/providers/school_settings_provider.dart';
import '../../shared/utils/pdf_branding_helper.dart';
import '../../models/teacher.dart';
import '../../models/timetable_entry.dart';
import '../../services/timetable_service.dart';
import '../../theme.dart';
import '../../l10n/app_strings.dart';

class MyTimetableScreen extends StatefulWidget {
  /// When provided → shows this teacher's personal schedule.
  /// When null    → shows the full school timetable (coordinator / read-only).
  final Teacher? teacher;
  const MyTimetableScreen({super.key, this.teacher});

  @override
  State<MyTimetableScreen> createState() => _MyTimetableScreenState();
}

class _MyTimetableScreenState extends State<MyTimetableScreen> {
  final _service = TimetableService.instance;
  Map<String, dynamic> _rawSettings = {};
  List<String>  _classes  = [];
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

  static const List<Color> _palette = AppTheme.timetablePalette;

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
      _rawSettings = settings;
      _classes   = List<String>.from(settings['classes'] as List);
      _bells     = bells;
      _timetable = tt;
      _teachers  = teachers;
      _loading   = false;
    });
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  String _teacherName(TimetableEntry? e) {
    if (e == null || e.isEmpty) return '—';
    final t = _teachers.firstWhere((t) => t.id == e.teacherId,
        orElse: () => const Teacher(id: '', name: '—', subject: '', email: '', schoolId: ''));
    return t.name;
  }

  String _subjectLabel(TimetableEntry? e) {
    if (e == null || e.isEmpty) return '';
    if (e.subject?.isNotEmpty == true) return e.subject!;
    final t = _teachers.firstWhere((t) => t.id == e.teacherId,
        orElse: () => const Teacher(id: '', name: '', subject: '', email: '', schoolId: ''));
    return t.subject;
  }

  Color _teacherColor(TimetableEntry? e) {
    if (e == null || e.isEmpty) return Colors.grey.shade300;
    final idx = _teachers.indexWhere((t) => t.id == e.teacherId);
    return idx < 0 ? Colors.grey.shade300 : _palette[idx % _palette.length];
  }

  String _fmt12(TimeOfDay t) {
    final h = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
    final m = t.minute.toString().padLeft(2, '0');
    final period = t.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $period';
  }

  /// Personal view: for [_selectedDay], return list of (bell, className, subject)
  /// where this teacher is assigned.
  List<_PersonalSlot> get _mySlots {
    if (!_isPersonal) return [];
    final tid = widget.teacher?.id;
    if (tid == null) return [];
    final slots = <_PersonalSlot>[];
    for (final cls in _classes) {
      final classBells = _service.getBellsForClass(_rawSettings, cls);
      for (int b = 1; b <= classBells.length; b++) {
        final bMap = classBells[b - 1];
        final isLunch = bMap['isLunch'] as bool? ?? false;
        if (isLunch) continue; // skip lunch positions
        final entry = _timetable[cls]?[_selectedDay]?[b];
        if (entry?.teacherId == tid) {
          // Format start and end time
          String timeStr = '';
          try {
            final startStr = bMap['start'] as String? ?? '08:00';
            final duration = bMap['duration'] as int? ?? 45;
            final parts = startStr.split(':');
            final startMinutes = (int.tryParse(parts[0]) ?? 8) * 60 + (int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0);
            
            final startTodo = TimeOfDay(hour: (startMinutes ~/ 60) % 24, minute: startMinutes % 60);
            final endMinutes = startMinutes + duration;
            final endTodo = TimeOfDay(hour: (endMinutes ~/ 60) % 24, minute: endMinutes % 60);
            timeStr = '${_fmt12(startTodo)}–${_fmt12(endTodo)}';
          } catch (_) {}

          int displayNum = 0;
          for (int i = 0; i < b; i++) {
            if (!(classBells[i]['isLunch'] as bool? ?? false)) displayNum++;
          }

          slots.add(_PersonalSlot(
            bell:      b,
            bellDisplayNum: displayNum,
            className: cls,
            subject:   _subjectLabel(entry),
            timeRange: timeStr,
          ));
        }
      }
    }
    slots.sort((a, b) => a.bell.compareTo(b.bell));
    return slots;
  }

  // ── PDF generation ───────────────────────────────────────────────────────────

  int _bellDisplayNumberForClassBells(List classBells, int zeroIdx) {
    int count = 0;
    for (int i = 0; i <= zeroIdx; i++) {
      if (i < classBells.length && !(classBells[i]['isLunch'] as bool? ?? false)) count++;
    }
    return count;
  }

  Future<void> _sharePdf(String? forClass) async {
    final settings = Provider.of<SchoolSettingsProvider>(context, listen: false);
    final branding = await PdfBrandingHelper.load(
      schoolName: settings.schoolName,
      schoolLogoUrl: settings.schoolLogo,
    );

    final pdf = pw.Document();

    // Collect data
    final classes = forClass != null ? [forClass] : _classes;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (ctx) => [
          PdfBrandingHelper.buildHeader(branding),
          pw.Text(
            forClass != null
                ? '$forClass — Timetable'
                : 'School Timetable',
            style: pw.TextStyle(
                fontSize: 18, fontWeight: pw.FontWeight.bold,
                color: PdfTheme.primary),
          ),
          pw.SizedBox(height: 12),
          ...classes.map((cls) {
            final classBells = _service.getBellsForClass(_rawSettings, cls);
            final classBellCount = classBells.length;
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (classes.length > 1) ...[
                  pw.Text(cls,
                      style: pw.TextStyle(
                          fontSize: 13, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 6),
                ],
                pw.Table(
                  border: pw.TableBorder.all(color: PdfTheme.primaryLight),
                  columnWidths: {
                    0: const pw.FixedColumnWidth(60),
                    for (int b = 1; b <= classBellCount; b++)
                      b: const pw.FlexColumnWidth(1),
                  },
                  children: [
                    // Header
                    pw.TableRow(
                      decoration:
                          const pw.BoxDecoration(color: PdfTheme.primary),
                      children: [
                        _pdfCell('Day', bold: true, light: true),
                        for (int b = 1; b <= classBellCount; b++)
                          _pdfCell(
                            (classBells[b - 1]['isLunch'] as bool? ?? false)
                                ? 'Lunch'
                                : 'Bell ${_bellDisplayNumberForClassBells(classBells, b - 1)}',
                            bold: true,
                            light: true,
                          ),
                      ],
                    ),
                    // Days
                    for (final day in _days)
                      pw.TableRow(children: [
                        _pdfCell(day, bold: true),
                        for (int b = 1; b <= classBellCount; b++)
                          _pdfCell(
                            (classBells[b - 1]['isLunch'] as bool? ?? false)
                                ? 'Lunch'
                                : (_subjectLabel(_timetable[cls]?[day]?[b]).isEmpty
                                    ? '—'
                                    : _subjectLabel(_timetable[cls]?[day]?[b])),
                          ),
                      ]),
                  ],
                ),
                if (classes.length > 1) pw.SizedBox(height: 16),
              ],
            );
          }),
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
        title: Text(_isPersonal ? context.tr('myTimetable') : context.tr('schoolTimetable')),
        actions: [
          if (!_isPersonal && !_loading && _classes.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              tooltip: context.tr('sharePdf'),
              onPressed: () => _showPdfOptions(context),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_classes.isEmpty || _timetable.isEmpty)
              ? _emptyState(context)
              : _isPersonal
                  ? _buildPersonalView()
                  : _buildFullGrid(context),
    );
  }

  Widget _emptyState(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.calendar_today_outlined,
          size: 64, color: Colors.grey.shade300),
      const SizedBox(height: 16),
      Text(context.tr('timetableNotSetUp'),
          style: TextStyle(fontSize: 16, color: Colors.grey.shade400)),
      const SizedBox(height: 6),
      Text(context.tr('askCoordinatorConfigure'),
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

  Widget _buildFullGrid(BuildContext context) {
    final maxBells = _service.getMaxBellsCount(_rawSettings);
    final regularBells =
        _bells.where((b) => !(b['isLunch'] as bool? ?? false)).length;
    return Column(children: [
      // Info strip
      Container(
        color: AppTheme.primary,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Row(children: [
          _Badge(label: context.tr('classesLabel'),   value: '${_classes.length}'),
          const SizedBox(width: 8),
          _Badge(label: context.tr('bellsPerDay'), value: '$regularBells'),
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
                  _HeaderCell(context.tr('classLabel'), width: 90, isCorner: true),
                  for (int b = 1; b <= maxBells; b++)
                    _HeaderCell(
                        context.tr('bellWithNum').replaceAll('{num}', b.toString()),
                        width: 110),
                ]),
                for (int i = 0; i < _classes.length; i++)
                  GestureDetector(
                    onTap: () => _showPdfOptions(context, cls: _classes[i]),
                    child: Row(children: [
                      Container(
                        width: 90, height: 72,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: i % 2 == 0
                              ? AppTheme.primary.withValues(alpha: 0.06)
                              : Colors.white,
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Text(_classes[i],
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ),
                      for (int b = 1; b <= maxBells; b++) ...[
                        Builder(builder: (context) {
                          final classBells = _service.getBellsForClass(_rawSettings, _classes[i]);
                          final bellIdx = b - 1;
                          if (bellIdx >= classBells.length) {
                            return Container(
                              width: 110, height: 72,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: const Text('—', style: TextStyle(color: Colors.grey)),
                            );
                          }
                          final isLunch = classBells[bellIdx]['isLunch'] as bool? ?? false;
                          if (isLunch) {
                            return _LunchCell(isEven: i % 2 == 0);
                          }
                          return _ReadCell(
                            name:    _teacherName(
                                _timetable[_classes[i]]?[_selectedDay]?[b]),
                            subject: _subjectLabel(
                                _timetable[_classes[i]]?[_selectedDay]?[b]),
                            color:   _teacherColor(
                                _timetable[_classes[i]]?[_selectedDay]?[b]),
                            isEven:  i % 2 == 0,
                          );
                        }),
                      ],
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
              label: Text(context.tr('downloadSharePdf')),
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
  final String timeRange;
  const _PersonalSlot({
    required this.bell,
    required this.bellDisplayNum,
    required this.className,
    required this.subject,
    required this.timeRange,
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
        color: AppTheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.18)),
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
            if (slot.timeRange.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                slot.timeRange,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ]),
        ),
        Text(
          slot.subject.isNotEmpty ? slot.subject : 'Bell ${slot.bellDisplayNum}',
          style: const TextStyle(
              fontSize: 12,
              color: AppTheme.primaryMid,
              fontWeight: FontWeight.w600),
        ),
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
          color: Colors.white.withValues(alpha: 0.15),
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



class _LunchCell extends StatelessWidget {
  final bool isEven;
  const _LunchCell({required this.isEven});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 110, height: 72,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        border: Border.all(color: Colors.orange.shade100),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.restaurant, color: Colors.orange.shade300, size: 18),
        Text(context.tr('lunch'),
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
            ? color.withValues(alpha: 0.12)
            : (isEven ? Colors.grey.shade50 : Colors.white),
        border: Border.all(
            color: hasTeacher
                ? color.withValues(alpha: 0.3)
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
                        color: color.withValues(alpha: 0.9)),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    textAlign: TextAlign.center),
              ),
              if (subject.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(subject,
                      style: TextStyle(
                          fontSize: 9, color: color.withValues(alpha: 0.7)),
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

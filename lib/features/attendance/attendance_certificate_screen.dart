import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../../shared/providers/school_settings_provider.dart';
import '../../shared/utils/pdf_branding_helper.dart';
import '../../l10n/app_strings.dart';
import '../../shared/utils/consent_gate.dart';
import '../../shared/utils/pdf_theme.dart';
import '../../models/student.dart';
import '../../shared/utils/class_name_utils.dart';
import '../../services/student_service.dart';
import '../../services/timetable_service.dart';
import '../../theme.dart';
import '../../shared/widgets/refreshable_data.dart';

/// One-click attendance certificate for a student.
/// Can be opened from the guardian dashboard or student list.
class AttendanceCertificateScreen extends StatefulWidget {
  final Student student;

  const AttendanceCertificateScreen({super.key, required this.student});

  @override
  State<AttendanceCertificateScreen> createState() =>
      _AttendanceCertificateScreenState();
}

class _AttendanceCertificateScreenState
    extends State<AttendanceCertificateScreen> {
  final _service = StudentService.instance;

  // Date range — default: start of current academic year to today
  late DateTime _from;
  late DateTime _to;

  bool _loading = false;

  // Computed stats
  int _workingDays = 0;
  int _presentDays = 0;
  int _absentDays  = 0;
  int _leaveDays   = 0;
  double _percentage = 0;
  bool _computed = false;

  // School name from timetable settings
  String _schoolName = 'The School';

  // Attendance docs are keyed by the teacher's section-scoped key
  // ('$className $section' when a section exists). Reading with the class name
  // alone misses every doc, so the certificate would report 0 days. Mirror
  // AttendanceScreen._attendanceKey exactly.
  String get _attendanceKey =>
      widget.student.section.trim().isEmpty
          ? widget.student.className
          : '${widget.student.className} ${widget.student.section.trim()}';

  @override
  void initState() {
    super.initState();
    // Academic year: April of current year if month ≥ April, else last April
    final now = DateTime.now();
    final yearStart = now.month >= 4 ? now.year : now.year - 1;
    _from = DateTime(yearStart, 4, 1);
    _to   = now;
    _loadSchoolName();
    _computeStats();
  }

  Future<void> _loadSchoolName() async {
    final settings = await TimetableService.instance.getSettings();
    final name = settings['schoolName'] as String? ?? '';
    if (!mounted) return;
    if (name.isNotEmpty) setState(() => _schoolName = name);
  }

  Future<void> _computeStats() async {
    setState(() { _loading = true; _computed = false; });

    int working = 0, present = 0, absent = 0, leave = 0;

    // Iterate month by month over [_from, _to]
    DateTime cursor = DateTime(_from.year, _from.month);
    while (!cursor.isAfter(DateTime(_to.year, _to.month))) {
      final monthData = await _service.loadMonthAttendance(
          className: _attendanceKey, year: cursor.year, month: cursor.month);

      for (final entry in monthData.entries) {
        final day  = entry.key;
        final date = DateTime(cursor.year, cursor.month, day);

        // Only count days within [_from, _to]
        if (date.isBefore(_from) || date.isAfter(_to)) continue;

        final status = entry.value[widget.student.roll];
        if (status == null) continue; // not in this class at the time

        working++;
        if (status == 'Present') {
          present++;
        } else if (status == 'Leave') {
          leave++;
        } else {
          absent++;
        }
      }

      // Advance to next month
      cursor = DateTime(cursor.year, cursor.month + 1);
    }

    if (!mounted) return;
    setState(() {
      _workingDays = working;
      _presentDays = present;
      _absentDays  = absent;
      _leaveDays   = leave;
      _percentage  = working > 0 ? (present / working * 100) : 0;
      _computed    = true;
      _loading     = false;
    });
  }

  Future<void> _pickFrom() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(2020),
      lastDate: _to,
    );
    if (d != null) { setState(() => _from = d); _computeStats(); }
  }

  Future<void> _pickTo() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: _from,
      lastDate: DateTime.now(),
    );
    if (d != null) { setState(() => _to = d); _computeStats(); }
  }

  Future<void> _exportPdf() async {
    // Exporting/sharing the certificate is third-party egress of a minor's
    // data — gate on parental consent (#17).
    if (!await ConsentGate.allowsForStudent(context, widget.student)) return;
    final settings = Provider.of<SchoolSettingsProvider>(context, listen: false);
    final branding = await PdfBrandingHelper.load(
      schoolName: settings.schoolName,
      schoolLogoUrl: settings.schoolLogo,
    );
    final pdf = _buildPdf(branding);
    await Printing.layoutPdf(
      onLayout: (_) async => pdf.save(),
      name: 'Attendance_Certificate_${widget.student.name.replaceAll(' ', '_')}.pdf',
    );
  }

  pw.Document _buildPdf(PdfBrandingData branding) {
    final doc = pw.Document();
    final s   = widget.student;
    final fromStr = _fmtDate(_from);
    final toStr   = _fmtDate(_to);
    final issueStr = _fmtDate(DateTime.now());

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(48),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            PdfBrandingHelper.buildHeader(branding),
            // ── Header ─────────────────────────────────────────────────────
            pw.Text(
              _schoolName.toUpperCase(),
              style: pw.TextStyle(
                  fontSize: 20, fontWeight: pw.FontWeight.bold,
                  color: PdfTheme.primaryDark),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 4),
            pw.Divider(thickness: 2, color: PdfTheme.primary),
            pw.SizedBox(height: 16),

            // ── Certificate title ──────────────────────────────────────────
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                  horizontal: 24, vertical: 10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(width: 1.5, color: PdfTheme.primary),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Text(
                'ATTENDANCE CERTIFICATE',
                style: pw.TextStyle(
                    fontSize: 16, fontWeight: pw.FontWeight.bold,
                    letterSpacing: 2, color: PdfTheme.primaryDark),
              ),
            ),
            pw.SizedBox(height: 24),

            // ── Certification statement ────────────────────────────────────
            pw.Text(
              'This is to certify that the following student is enrolled at this institution and '
              'has the attendance record as stated below for the period from $fromStr to $toStr.',
              style: const pw.TextStyle(fontSize: 11),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 24),

            // ── Student details table ──────────────────────────────────────
            pw.Table(
              border: pw.TableBorder.all(color: PdfTheme.primaryLight),
              columnWidths: {
                0: const pw.FlexColumnWidth(2),
                1: const pw.FlexColumnWidth(3),
              },
              children: [
                _row('Student Name', s.name),
                _row('Roll Number', '${s.roll}'),
                _row('Class / Section', ClassName.format(s.className, s.section)),
                _row("Father's Name",
                    s.fatherName.isNotEmpty ? s.fatherName : '—'),
                _row('Academic Period', '$fromStr  to  $toStr'),
              ],
            ),
            pw.SizedBox(height: 20),

            // ── Attendance stats ───────────────────────────────────────────
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: PdfTheme.primaryTint,
                border: pw.Border.all(color: PdfTheme.primaryLight),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('ATTENDANCE SUMMARY',
                      style: pw.TextStyle(
                          fontSize: 12, fontWeight: pw.FontWeight.bold,
                          color: PdfTheme.primaryDark)),
                  pw.SizedBox(height: 10),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                    children: [
                      _statCell('Working Days', '$_workingDays'),
                      _statCell('Present', '$_presentDays'),
                      _statCell('Absent', '$_absentDays'),
                      _statCell('Leave', '$_leaveDays'),
                      _statCell('Attendance %',
                          '${_percentage.toStringAsFixed(2)}%'),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                  pw.Text(
                    _percentage >= 75
                        ? '✔  Attendance is SATISFACTORY (≥ 75%)'
                        : '✘  Attendance is BELOW REQUIRED THRESHOLD (< 75%)',
                    style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: _percentage >= 75
                            ? PdfColors.green800
                            : PdfColors.red700),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 32),

            // ── Signature row ──────────────────────────────────────────────
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                // Class Teacher
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Container(
                        width: 120, height: 40,
                        decoration: const pw.BoxDecoration(
                            border: pw.Border(
                                bottom: pw.BorderSide(width: 1)))),
                    pw.SizedBox(height: 4),
                    pw.Text('Class Teacher',
                        style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),

                // School Stamp
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Container(
                      width: 90, height: 90,
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(
                            width: 1, style: pw.BorderStyle.dashed),
                        borderRadius: pw.BorderRadius.circular(45),
                      ),
                      alignment: pw.Alignment.center,
                      child: pw.Text('SCHOOL\nSTAMP',
                          style: pw.TextStyle(
                              fontSize: 9,
                              color: PdfColors.grey500,
                              fontWeight: pw.FontWeight.bold),
                          textAlign: pw.TextAlign.center),
                    ),
                  ],
                ),

                // Principal
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Container(
                        width: 120, height: 40,
                        decoration: const pw.BoxDecoration(
                            border: pw.Border(
                                bottom: pw.BorderSide(width: 1)))),
                    pw.SizedBox(height: 4),
                    pw.Text('Principal / Head of Institution',
                        style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 24),

            // ── Footer ─────────────────────────────────────────────────────
            pw.Divider(thickness: 1),
            pw.SizedBox(height: 6),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(context.tr('dateOfIssueWithDate').replaceAll('{date}', issueStr),
                    style: const pw.TextStyle(fontSize: 9)),
                pw.Text(context.tr('generatedBySchoolApp'),
                    style: const pw.TextStyle(
                        fontSize: 9, color: PdfColors.grey500)),
              ],
            ),
          ],
        ),
      ),
    );
    return doc;
  }

  pw.TableRow _row(String label, String value) => pw.TableRow(
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.all(8),
            child: pw.Text(label,
                style:
                    pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(8),
            child: pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
          ),
        ],
      );

  pw.Widget _statCell(String label, String value) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 2),
          pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
        ],
      );

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final s          = widget.student;
    final pctColor   = _percentage >= 75 ? Colors.green : Colors.red;
    final fromStr    = _fmtDate(_from);
    final toStr      = _fmtDate(_to);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('attendanceCertificate'),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text(context.tr('officialAttendanceRecord'),
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          if (_computed)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              tooltip: context.tr('exportPdf'),
              onPressed: _exportPdf,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Student info card ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                child: Text(
                  s.name.isNotEmpty ? s.name[0].toUpperCase() : '?',
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.name,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    Text('${context.tr('rollPrefix')} ${s.roll}  •  ${ClassName.format(s.className, s.section)}',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade600)),
                    if (s.fatherName.isNotEmpty)
                      Text('${context.tr('fatherPrefix')}: ${s.fatherName}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade500)),
                  ],
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // ── Date range picker ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('dateRange'),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: _DateButton(
                      label: context.tr('rangeFrom'),
                      date: fromStr,
                      onTap: _pickFrom,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DateButton(
                      label: context.tr('rangeTo'),
                      date: toStr,
                      onTap: _pickTo,
                    ),
                  ),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Stats card ─────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: _loading
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: LoadingState(message: context.tr('computingAttendance')),
                  )
                : _computed
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text(context.tr('attendanceSummary'),
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold)),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: pctColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${_percentage.toStringAsFixed(1)}%',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: pctColor),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: (_percentage / 100).clamp(0.0, 1.0),
                              minHeight: 10,
                              backgroundColor: Colors.grey.shade200,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(pctColor),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              _StatCell(context.tr('workingDaysLabel'), '$_workingDays',
                                  AppTheme.primary),
                              _StatCell(context.tr('presentLabel'), '$_presentDays',
                                  Colors.green),
                              _StatCell(context.tr('absentLabel'), '$_absentDays',
                                  Colors.red),
                              _StatCell(context.tr('leaveLabel'), '$_leaveDays',
                                  Colors.orange),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: pctColor.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: pctColor.withValues(alpha: 0.3)),
                            ),
                            child: Row(children: [
                              Icon(
                                _percentage >= 75
                                    ? Icons.check_circle_outline
                                    : Icons.warning_amber_rounded,
                                color: pctColor,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _percentage >= 75
                                      ? context.tr('attendanceSatisfactoryMsg')
                                      : context.tr('attendanceBelowMsg'),
                                  style: TextStyle(
                                      fontSize: 12, color: pctColor),
                                ),
                              ),
                            ]),
                          ),
                        ],
                      )
                    : const SizedBox(),
          ),
          const SizedBox(height: 16),

          // ── Certificate preview card ───────────────────────────────────────
          if (_computed) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.primaryLight, width: 1.5),
              ),
              child: Column(
                children: [
                  Row(children: [
                    const Icon(Icons.workspace_premium_outlined,
                        color: AppTheme.primary),
                    const SizedBox(width: 8),
                    Text(context.tr('certificatePreview'),
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 12),
                  _previewRow(context.tr('studentLabelField'), s.name),
                  _previewRow(context.tr('rollPrefix'), '${s.roll}'),
                  _previewRow(context.tr('classLabel'), ClassName.format(s.className, s.section)),
                  _previewRow(context.tr('periodWord'), '$fromStr to $toStr'),
                  _previewRow(context.tr('attendanceLabel'),
                      '$_presentDays / $_workingDays ${context.tr('daysLower')} (${_percentage.toStringAsFixed(2)}%)'),
                  _previewRow(
                      context.tr('status'),
                      _percentage >= 75
                          ? context.tr('statusSatisfactory')
                          : context.tr('statusBelowThreshold')),
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 4),
                  Text(context.tr('certificateIncludesStamp'),
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade500)),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Export button ────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: Text(context.tr('exportCertificatePdf'),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
                onPressed: _exportPdf,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _previewRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade500)),
          ),
          const Text(':  '),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ]),
      );
}

// ─── Small widgets ────────────────────────────────────────────────────────────

class _DateButton extends StatelessWidget {
  final String label, date;
  final VoidCallback onTap;
  const _DateButton(
      {required this.label, required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 10, color: Colors.grey.shade500)),
                Text(date,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
            const Spacer(),
            const Icon(Icons.calendar_today_outlined,
                size: 16, color: AppTheme.primary),
          ]),
        ),
      );
}

class _StatCell extends StatelessWidget {
  final String label, value;
  final Color  color;
  const _StatCell(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value,
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color)),
        const SizedBox(height: 2),
        Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
      ]);
}

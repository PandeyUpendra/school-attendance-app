import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/student.dart';
import '../services/student_service.dart';
import '../services/timetable_service.dart';
import '../theme.dart';

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
  final _service = StudentService();

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
    final settings = await TimetableService().getSettings();
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
          widget.student.className, cursor.year, cursor.month);

      for (final entry in monthData.entries) {
        final day  = entry.key;
        final date = DateTime(cursor.year, cursor.month, day);

        // Only count days within [_from, _to]
        if (date.isBefore(_from) || date.isAfter(_to)) continue;

        final status = entry.value[widget.student.roll];
        if (status == null) continue; // not in this class at the time

        working++;
        if (status == 'Present') present++;
        else if (status == 'Leave') leave++;
        else absent++;
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
    final pdf = _buildPdf();
    await Printing.layoutPdf(
      onLayout: (_) async => pdf.save(),
      name: 'Attendance_Certificate_${widget.student.name.replaceAll(' ', '_')}.pdf',
    );
  }

  pw.Document _buildPdf() {
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
            // ── Header ─────────────────────────────────────────────────────
            pw.Text(
              _schoolName.toUpperCase(),
              style: pw.TextStyle(
                  fontSize: 20, fontWeight: pw.FontWeight.bold),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 4),
            pw.Divider(thickness: 2),
            pw.SizedBox(height: 16),

            // ── Certificate title ──────────────────────────────────────────
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                  horizontal: 24, vertical: 10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(width: 1.5),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Text(
                'ATTENDANCE CERTIFICATE',
                style: pw.TextStyle(
                    fontSize: 16, fontWeight: pw.FontWeight.bold,
                    letterSpacing: 2),
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
              border: pw.TableBorder.all(color: PdfColors.grey400),
              columnWidths: {
                0: const pw.FlexColumnWidth(2),
                1: const pw.FlexColumnWidth(3),
              },
              children: [
                _row('Student Name', s.name),
                _row('Roll Number', '${s.roll}'),
                _row('Class / Section', s.className),
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
                color: PdfColors.grey100,
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('ATTENDANCE SUMMARY',
                      style: pw.TextStyle(
                          fontSize: 12, fontWeight: pw.FontWeight.bold)),
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
                        decoration: pw.BoxDecoration(
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
                        decoration: pw.BoxDecoration(
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
                pw.Text('Date of Issue: $issueStr',
                    style: const pw.TextStyle(fontSize: 9)),
                pw.Text('Generated by School App',
                    style: pw.TextStyle(
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
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Attendance Certificate',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text('Official attendance record',
                style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          if (_computed)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              tooltip: 'Export PDF',
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
                backgroundColor: AppTheme.primary.withOpacity(0.12),
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
                    Text('Roll ${s.roll}  •  ${s.className}',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade600)),
                    if (s.fatherName.isNotEmpty)
                      Text('Father: ${s.fatherName}',
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
                const Text('Date Range',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: _DateButton(
                      label: 'From',
                      date: fromStr,
                      onTap: _pickFrom,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DateButton(
                      label: 'To',
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
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : _computed
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Text('Attendance Summary',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold)),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: pctColor.withOpacity(0.1),
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
                              _StatCell('Working\nDays', '$_workingDays',
                                  Colors.indigo),
                              _StatCell('Present', '$_presentDays',
                                  Colors.green),
                              _StatCell('Absent', '$_absentDays',
                                  Colors.red),
                              _StatCell('Leave', '$_leaveDays',
                                  Colors.orange),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: pctColor.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: pctColor.withOpacity(0.3)),
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
                                      ? 'Attendance is SATISFACTORY — eligible for certificate issuance.'
                                      : 'Attendance is BELOW the 75% requirement.',
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
                border: Border.all(color: Colors.indigo.shade200, width: 1.5),
              ),
              child: Column(
                children: [
                  Row(children: [
                    Icon(Icons.workspace_premium_outlined,
                        color: Colors.indigo.shade400),
                    const SizedBox(width: 8),
                    const Text('Certificate Preview',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 12),
                  _previewRow('Student', s.name),
                  _previewRow('Roll', '${s.roll}'),
                  _previewRow('Class', s.className),
                  _previewRow('Period', '$fromStr to $toStr'),
                  _previewRow('Attendance',
                      '$_presentDays / $_workingDays days (${_percentage.toStringAsFixed(2)}%)'),
                  _previewRow(
                      'Status',
                      _percentage >= 75
                          ? 'SATISFACTORY'
                          : 'BELOW THRESHOLD'),
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 4),
                  Text('Certificate includes school stamp area & signatures',
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
                label: const Text('Export Certificate as PDF',
                    style: TextStyle(
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
            Icon(Icons.calendar_today_outlined,
                size: 16, color: Colors.indigo.shade400),
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

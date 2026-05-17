import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../services/principal_digest_service.dart';

/// One-screen end-of-day summary for the principal.
/// Markers viewed-today via SharedPreferences so the dashboard auto-prompt
/// doesn't fire twice on the same day.
class PrincipalDigestScreen extends StatefulWidget {
  const PrincipalDigestScreen({super.key});

  static const _viewedKeyPrefix = 'digest_viewed_';

  static String _todayKey() {
    final n = DateTime.now();
    return '$_viewedKeyPrefix${n.year}-${n.month}-${n.day}';
  }

  /// Returns true if today's digest has already been opened by the principal.
  /// Used by the principal dashboard to avoid re-prompting after 5pm.
  static Future<bool> hasViewedToday() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_todayKey()) ?? false;
  }

  static Future<void> _markViewedToday() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_todayKey(), true);
  }

  @override
  State<PrincipalDigestScreen> createState() => _PrincipalDigestScreenState();
}

class _PrincipalDigestScreenState extends State<PrincipalDigestScreen> {
  DigestSnapshot? _snap;
  bool   _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    PrincipalDigestScreen._markViewedToday();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final snap = await PrincipalDigestService().buildTodayDigest();
      if (!mounted) return;
      setState(() { _snap = snap; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _previewPdf() async {
    if (_snap == null) return;
    await Printing.layoutPdf(
      onLayout: (_) async => _buildPdf(_snap!).save(),
      name: _pdfFileName(_snap!),
    );
  }

  Future<void> _sharePdf() async {
    if (_snap == null) return;
    final bytes = await _buildPdf(_snap!).save();
    await Printing.sharePdf(bytes: bytes, filename: _pdfFileName(_snap!));
  }

  String _pdfFileName(DigestSnapshot s) {
    final d = s.generatedAt;
    return 'EOD_Digest_${d.year}-${_pad(d.month)}-${_pad(d.day)}.pdf';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
  static String _fmtDate(DateTime d) =>
      '${_pad(d.day)}/${_pad(d.month)}/${d.year}';
  static String _fmtTime(DateTime d) =>
      '${_pad(d.hour)}:${_pad(d.minute)}';
  static String _money(double v) => '₹${v.toStringAsFixed(0)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Today's Digest",
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text('End-of-day summary',
                style: TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : _snap == null
                  ? const SizedBox.shrink()
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: AppTheme.primary,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                        children: _buildBody(_snap!),
                      ),
                    ),
      bottomNavigationBar: _snap == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _previewPdf,
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Preview PDF'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _sharePdf,
                      icon: const Icon(Icons.share),
                      label: const Text('Share PDF'),
                    ),
                  ),
                ]),
              ),
            ),
    );
  }

  // ── UI sections ─────────────────────────────────────────────────────────────

  List<Widget> _buildBody(DigestSnapshot s) => [
        _HeaderCard(snap: s),
        const SizedBox(height: 14),

        _SectionHeader('ATTENDANCE'),
        _AttendanceCard(snap: s),
        const SizedBox(height: 12),

        _SectionHeader('TEACHERS'),
        _TeachersCard(snap: s),
        const SizedBox(height: 12),

        _SectionHeader('LEAVES'),
        _LeavesCard(snap: s),
        const SizedBox(height: 12),

        _SectionHeader("INCIDENTS / REMARKS  (${s.remarksToday.length})"),
        _RemarksCard(snap: s),
        const SizedBox(height: 12),

        _SectionHeader('FEES COLLECTED TODAY'),
        _FeesCard(snap: s),
        const SizedBox(height: 12),

        _SectionHeader('COPY-CHECK BACKLOG (last 7 days)'),
        _CopyBacklogCard(snap: s),
      ];

  // ── PDF ─────────────────────────────────────────────────────────────────────

  pw.Document _buildPdf(DigestSnapshot s) {
    final doc = pw.Document();

    pw.Widget kv(String k, String v, {PdfColor? color}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(children: [
            pw.SizedBox(
              width: 130,
              child: pw.Text(k,
                  style: const pw.TextStyle(
                      fontSize: 10, color: PdfColors.grey700)),
            ),
            pw.Expanded(
              child: pw.Text(v,
                  style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: color ?? PdfColors.black)),
            ),
          ]),
        );

    pw.Widget section(String title, List<pw.Widget> children) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 12),
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(title,
                  style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey800,
                      letterSpacing: 1.2)),
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 0.5, color: PdfColors.grey300),
              ...children,
            ],
          ),
        );

    final attColor = s.attendancePct >= 90
        ? PdfColors.green800
        : s.attendancePct >= 75
            ? PdfColors.orange700
            : PdfColors.red700;

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (ctx) => [
        // Header
        pw.Text(s.schoolName.toUpperCase(),
            style: pw.TextStyle(
                fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 2),
        pw.Text("End-of-Day Principal Digest",
            style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
        pw.SizedBox(height: 2),
        pw.Text(
            '${_fmtDate(s.generatedAt)} · generated ${_fmtTime(s.generatedAt)}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
        pw.SizedBox(height: 6),
        pw.Divider(thickness: 1.5),

        // Headline %
        pw.SizedBox(height: 8),
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text("Today's attendance",
                      style: const pw.TextStyle(
                          fontSize: 10, color: PdfColors.grey700)),
                  pw.Text('${s.attendancePct.toStringAsFixed(1)}%',
                      style: pw.TextStyle(
                          fontSize: 28,
                          fontWeight: pw.FontWeight.bold,
                          color: attColor)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                      '${s.presentToday} / ${s.totalStudents} present',
                      style: const pw.TextStyle(fontSize: 10)),
                  pw.Text('${s.absentToday} absent · ${s.leaveToday} on leave',
                      style: const pw.TextStyle(
                          fontSize: 10, color: PdfColors.grey700)),
                  pw.Text(
                      '${s.classesMarked} / ${s.classesTotal} classes marked',
                      style: const pw.TextStyle(
                          fontSize: 10, color: PdfColors.grey700)),
                ],
              ),
            ],
          ),
        ),

        // Per-class table
        section('PER-CLASS BREAKDOWN', [
          pw.SizedBox(height: 4),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.4),
            columnWidths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FlexColumnWidth(1),
              3: const pw.FlexColumnWidth(1),
              4: const pw.FlexColumnWidth(1),
              5: const pw.FlexColumnWidth(1.2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _hdr('Class'),
                  _hdr('Total'),
                  _hdr('Pres.'),
                  _hdr('Abs.'),
                  _hdr('Leave'),
                  _hdr('%'),
                ],
              ),
              for (final c in s.classSummaries)
                pw.TableRow(children: [
                  _cell(c.className),
                  _cell('${c.total}'),
                  _cell('${c.present}'),
                  _cell('${c.absent}'),
                  _cell('${c.leave}'),
                  _cell(c.marked && c.total > 0
                      ? '${(c.present / c.total * 100).toStringAsFixed(0)}%'
                      : '—'),
                ]),
            ],
          ),
        ]),

        section('TEACHERS', [
          kv('Absent today', '${s.absentTeachers.length}'),
          if (s.absentTeachers.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4, left: 4),
              child: pw.Text(
                  s.absentTeachers.map((t) => '• ${t.name}').join('\n'),
                  style: const pw.TextStyle(fontSize: 10)),
            ),
        ]),

        section('LEAVES', [
          kv('Pending review', '${s.pendingLeaves}',
              color: s.pendingLeaves > 0 ? PdfColors.red700 : null),
          kv('Approved today', '${s.approvedToday}'),
          kv('Rejected today', '${s.rejectedToday}'),
        ]),

        section('INCIDENTS / REMARKS  (${s.remarksToday.length})',
          s.remarksToday.isEmpty
              ? [pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 4),
                  child: pw.Text('No remarks logged today.',
                      style: const pw.TextStyle(
                          fontSize: 10, color: PdfColors.grey600)))]
              : [
                  for (final r in s.remarksToday.take(20))
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 3),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                              '[${r.role}] ${r.studentId} — ${_fmtTime(r.timestamp)}',
                              style: pw.TextStyle(
                                  fontSize: 9,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.grey700)),
                          pw.Text(r.remark,
                              style: const pw.TextStyle(fontSize: 10)),
                        ],
                      ),
                    ),
                  if (s.remarksToday.length > 20)
                    pw.Text(
                        '… and ${s.remarksToday.length - 20} more',
                        style: const pw.TextStyle(
                            fontSize: 9, color: PdfColors.grey600)),
                ],
        ),

        section('FEES COLLECTED TODAY', [
          kv('Total', _money(s.feesCollected),
              color: PdfColors.green800),
          kv('Payments', '${s.paymentsCount}'),
          if (s.feesByMode.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4),
              child: pw.Text(
                  s.feesByMode.entries
                      .map((e) => '${e.key}: ${_money(e.value)}')
                      .join('   ·   '),
                  style: const pw.TextStyle(fontSize: 10)),
            ),
        ]),

        section('COPY-CHECK BACKLOG (last 7 days)', [
          kv('Pending students', '${s.copyBacklog}',
              color: s.copyBacklog > 0 ? PdfColors.orange700 : null),
          if (s.copyBacklogByTeacher.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4, left: 4),
              child: pw.Text(
                  s.copyBacklogByTeacher.entries
                      .map((e) => '• ${e.key}: ${e.value}')
                      .join('\n'),
                  style: const pw.TextStyle(fontSize: 10)),
            ),
        ]),

        pw.SizedBox(height: 16),
        pw.Divider(thickness: 0.5, color: PdfColors.grey400),
        pw.Text('Generated by School App',
            style: pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
      ],
    ));
    return doc;
  }

  pw.Widget _hdr(String s) => pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Text(s,
            style: pw.TextStyle(
                fontSize: 9, fontWeight: pw.FontWeight.bold)),
      );

  pw.Widget _cell(String s) => pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Text(s, style: const pw.TextStyle(fontSize: 9)),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Card widgets
// ─────────────────────────────────────────────────────────────────────────────

class _HeaderCard extends StatelessWidget {
  final DigestSnapshot snap;
  const _HeaderCard({required this.snap});

  @override
  Widget build(BuildContext context) {
    final pct = snap.attendancePct;
    final color = pct >= 90
        ? AppTheme.success
        : pct >= 75
            ? AppTheme.warning
            : AppTheme.danger;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primaryDark, AppTheme.primaryMid],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(snap.schoolName.toUpperCase(),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0)),
          const SizedBox(height: 2),
          Text(
              '${_PrincipalDigestScreenState._fmtDate(snap.generatedAt)} · ${_PrincipalDigestScreenState._fmtTime(snap.generatedAt)}',
              style: const TextStyle(
                  color: Colors.white70, fontSize: 11)),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${pct.toStringAsFixed(1)}%',
                  style: TextStyle(
                      color: color == AppTheme.success
                          ? const Color(0xFFA5D6A7)
                          : color == AppTheme.warning
                              ? const Color(0xFFFFCC80)
                              : const Color(0xFFEF9A9A),
                      fontSize: 38,
                      fontWeight: FontWeight.bold,
                      height: 1.0)),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                    '${snap.presentToday} / ${snap.totalStudents} present',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
              '${snap.absentToday} absent · ${snap.leaveToday} on leave · ${snap.classesMarked}/${snap.classesTotal} classes marked',
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }
}

class _AttendanceCard extends StatelessWidget {
  final DigestSnapshot snap;
  const _AttendanceCard({required this.snap});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        children: [
          for (final c in snap.classSummaries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Expanded(
                  flex: 3,
                  child: Text(c.className,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                if (!c.marked)
                  Text('Not marked',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade400,
                          fontStyle: FontStyle.italic))
                else ...[
                  _Pill('${c.present}', AppTheme.success),
                  const SizedBox(width: 4),
                  _Pill('${c.absent}', AppTheme.danger),
                  const SizedBox(width: 4),
                  _Pill('${c.leave}', AppTheme.warning),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 44,
                    child: Text(
                      c.total > 0
                          ? '${(c.present / c.total * 100).toStringAsFixed(0)}%'
                          : '—',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ]),
            ),
        ],
      ),
    );
  }
}

class _TeachersCard extends StatelessWidget {
  final DigestSnapshot snap;
  const _TeachersCard({required this.snap});

  @override
  Widget build(BuildContext context) {
    final t = snap.absentTeachers;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
                t.isEmpty ? Icons.check_circle_outline : Icons.person_off_outlined,
                color: t.isEmpty ? AppTheme.success : AppTheme.danger,
                size: 18),
            const SizedBox(width: 8),
            Text(
                t.isEmpty
                    ? 'All teachers present today'
                    : '${t.length} teacher${t.length == 1 ? '' : 's'} absent',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
          if (t.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final teacher in t)
              Padding(
                padding: const EdgeInsets.only(left: 26, top: 2, bottom: 2),
                child: Text('• ${teacher.name}',
                    style: const TextStyle(fontSize: 12)),
              ),
          ],
        ],
      ),
    );
  }
}

class _LeavesCard extends StatelessWidget {
  final DigestSnapshot snap;
  const _LeavesCard({required this.snap});

  @override
  Widget build(BuildContext context) => _Card(
        child: Row(children: [
          _StatColumn(
              label: 'Pending',
              value: '${snap.pendingLeaves}',
              color: snap.pendingLeaves > 0 ? AppTheme.danger : Colors.grey),
          _StatColumn(
              label: 'Approved today',
              value: '${snap.approvedToday}',
              color: AppTheme.success),
          _StatColumn(
              label: 'Rejected today',
              value: '${snap.rejectedToday}',
              color: Colors.grey),
        ]),
      );
}

class _RemarksCard extends StatelessWidget {
  final DigestSnapshot snap;
  const _RemarksCard({required this.snap});

  @override
  Widget build(BuildContext context) {
    if (snap.remarksToday.isEmpty) {
      return _Card(
        child: Row(children: [
          Icon(Icons.check_circle_outline,
              color: AppTheme.success, size: 18),
          const SizedBox(width: 8),
          const Text('No remarks logged today',
              style: TextStyle(fontSize: 13)),
        ]),
      );
    }
    return _Card(
      child: Column(
        children: [
          for (final r in snap.remarksToday.take(10))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    width: 6, height: 6,
                    decoration: BoxDecoration(
                      color: AppTheme.accent,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '${r.role.toUpperCase()} · ${r.studentId} · ${_PrincipalDigestScreenState._fmtTime(r.timestamp)}',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade600)),
                        const SizedBox(height: 2),
                        Text(r.remark,
                            style: const TextStyle(fontSize: 12.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (snap.remarksToday.length > 10)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  '… and ${snap.remarksToday.length - 10} more in the PDF',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                      fontStyle: FontStyle.italic)),
            ),
        ],
      ),
    );
  }
}

class _FeesCard extends StatelessWidget {
  final DigestSnapshot snap;
  const _FeesCard({required this.snap});

  @override
  Widget build(BuildContext context) => _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _StatColumn(
                  label: 'Collected',
                  value: _PrincipalDigestScreenState._money(snap.feesCollected),
                  color: AppTheme.success),
              _StatColumn(
                  label: 'Payments',
                  value: '${snap.paymentsCount}',
                  color: AppTheme.primary),
            ]),
            if (snap.feesByMode.isNotEmpty) ...[
              const Divider(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final e in snap.feesByMode.entries)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryLight.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                          '${e.key}: ${_PrincipalDigestScreenState._money(e.value)}',
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
            ],
          ],
        ),
      );
}

class _CopyBacklogCard extends StatelessWidget {
  final DigestSnapshot snap;
  const _CopyBacklogCard({required this.snap});

  @override
  Widget build(BuildContext context) => _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(
                  snap.copyBacklog == 0
                      ? Icons.check_circle_outline
                      : Icons.assignment_late_outlined,
                  color: snap.copyBacklog == 0
                      ? AppTheme.success
                      : AppTheme.warning,
                  size: 18),
              const SizedBox(width: 8),
              Text(
                  snap.copyBacklog == 0
                      ? 'No copy-check backlog'
                      : '${snap.copyBacklog} student${snap.copyBacklog == 1 ? '' : 's'} pending',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
            if (snap.copyBacklogByTeacher.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final e in snap.copyBacklogByTeacher.entries)
                Padding(
                  padding:
                      const EdgeInsets.only(left: 26, top: 2, bottom: 2),
                  child: Text('• ${e.key}: ${e.value}',
                      style: const TextStyle(fontSize: 12)),
                ),
            ],
          ],
        ),
      );
}

// ─── Shared small bits ────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: child,
      );
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
        child: Text(title,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade600,
                letterSpacing: 0.8)),
      );
}

class _Pill extends StatelessWidget {
  final String text;
  final Color  color;
  const _Pill(this.text, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold)),
      );
}

class _StatColumn extends StatelessWidget {
  final String label, value;
  final Color  color;
  const _StatColumn({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: TextStyle(
                    color: color,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    height: 1.1)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 11, color: Colors.grey.shade600)),
          ],
        ),
      );
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 40, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text('Could not build digest',
                  style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade500)),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
}

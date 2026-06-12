import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../shared/utils/pdf_theme.dart';
import '../../l10n/app_strings.dart';
import '../../services/audit_log_service.dart';
import '../../theme.dart';
import '../../shared/utils/app_logger.dart';

// ─── Entity labels ────────────────────────────────────────────────────────────

const _kEntities = [
  '',
  'student',
  'attendance',
  'fee_payment',
  'fee_structure',
  'exam',
  'exam_result',
  'auth',
];

/// Localised display label for a stored entity key (keys stay English).
String _entityLabel(BuildContext c, String key) => switch (key) {
      'student' => c.tr('studentLabelField'),
      'attendance' => c.tr('attendanceLabel'),
      'fee_payment' => c.tr('entFeePayment'),
      'fee_structure' => c.tr('feeStructure'),
      'exam' => c.tr('entExam'),
      'exam_result' => c.tr('entExamResult'),
      'auth' => c.tr('entAuthUser'),
      _ => c.tr('entAllTypes'),
    };

// ─── Screen ───────────────────────────────────────────────────────────────────

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  final _svc = AuditService();

  // ── Filter state ───────────────────────────────────────────────────────────
  String    _entityFilter = '';
  String    _actorFilter  = ''; // selected actorUid, '' = all actors
  DateTime? _from;
  DateTime? _to;

  // ── Actor dropdown state ─────────────────────────────────────────────────────
  List<AuditActor> _actors        = [];
  bool             _actorsLoading = true;

  // ── Pagination state ───────────────────────────────────────────────────────
  static const _pageSize = 50;
  final List<AuditEntry>   _entries = [];
  DocumentSnapshot?        _cursor;
  bool _loading       = false;
  bool _hasMore       = true;
  bool _exporting     = false;

  @override
  void initState() {
    super.initState();
    _fetchPage();
    _loadActors();
  }

  // ── Actor dropdown ───────────────────────────────────────────────────────────

  Future<void> _loadActors() async {
    try {
      final actors = await _svc.fetchActors();
      if (!mounted) return;
      setState(() {
        _actors        = actors;
        _actorsLoading = false;
      });
    } catch (e, st) {
      AppLogger.e('AuditLogScreen', 'Failed to load actors for filter dropdown', e, st);
      if (mounted) setState(() => _actorsLoading = false);
    }
  }

  // ── Fetch ──────────────────────────────────────────────────────────────────

  Future<void> _fetchPage({bool reset = false}) async {
    if (_loading) return;
    setState(() => _loading = true);

    if (reset) {
      _entries.clear();
      _cursor  = null;
      _hasMore = true;
    }

    try {
      final page = await _svc.fetchPage(
        limit:        _pageSize,
        entityFilter: _entityFilter.isEmpty ? null : _entityFilter,
        actorFilter:  _actorFilter.isEmpty  ? null : _actorFilter,
        from:         _from,
        to:           _to,
        after:        _cursor,
      );
      if (!mounted) return;
      setState(() {
        _entries.addAll(page.entries);
        _cursor  = page.cursor;
        _hasMore = page.entries.length >= _pageSize;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.tr('loadErrorPrefix')} $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilters() => _fetchPage(reset: true);

  // ── Date pickers ───────────────────────────────────────────────────────────

  Future<void> _pickFrom() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _from ?? DateTime.now().subtract(const Duration(days: 30)),
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() => _from = d);
  }

  Future<void> _pickTo() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _to ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() => _to = d);
  }

  // ── CSV Export ─────────────────────────────────────────────────────────────

  Future<void> _exportCsv() async {
    setState(() => _exporting = true);
    try {
      final all = await _svc.fetchAll(
        entityFilter: _entityFilter.isEmpty ? null : _entityFilter,
        actorFilter:  _actorFilter.isEmpty  ? null : _actorFilter,
        from:         _from,
        to:           _to,
      );

      final rows = <List<dynamic>>[
        ['Timestamp', 'Actor', 'Role', 'Action', 'Entity', 'Entity ID',
         'Reason', 'Before (summary)', 'After (summary)'],
        ...all.map((e) => [
          e.timestamp.toIso8601String(),
          e.actorName,
          e.actorRole,
          e.action,
          e.entity,
          e.entityId,
          e.reason ?? '',
          _mapSummary(e.before),
          _mapSummary(e.after),
        ]),
      ];

      final csv = const ListToCsvConverter().convert(rows);
      final dir  = await getTemporaryDirectory();
      final ts   = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/audit_log_$ts.csv');
      await file.writeAsString(csv);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        subject: 'Audit Log Export',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.tr('exportFailedPrefix')} $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportPdf() async {
    setState(() => _exporting = true);
    try {
      final all = await _svc.fetchAll(
        entityFilter: _entityFilter.isEmpty ? null : _entityFilter,
        actorFilter:  _actorFilter.isEmpty  ? null : _actorFilter,
        from:         _from,
        to:           _to,
      );

      final doc = pw.Document();
      final now = DateTime.now();

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          header: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(context.tr('auditLogReport'),
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold,
                      color: PdfTheme.primary)),
              pw.SizedBox(height: 4),
              pw.Text(
                'Generated on: ${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} '
                '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}   |   '
                'Total Entries: ${all.length}',
                style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
              ),
              pw.Divider(color: PdfTheme.primary, thickness: 1),
              pw.SizedBox(height: 6),
            ],
          ),
          footer: (context) => pw.Column(
            children: [
              pw.Divider(color: PdfColors.grey300, thickness: 0.5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'School Management System  •  Confidential',
                    style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey500),
                  ),
                  pw.Text(
                    'Page ${context.pageNumber} of ${context.pagesCount}',
                    style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey500),
                  ),
                ],
              ),
            ],
          ),
          build: (_) => [
            pw.Table(
              border: pw.TableBorder.all(
                  color: PdfTheme.primaryLight, width: 0.5),
              columnWidths: {
                0: const pw.FixedColumnWidth(95),  // Timestamp
                1: const pw.FlexColumnWidth(2.2),  // Actor (Name & Role)
                2: const pw.FixedColumnWidth(110), // Action & Type
                3: const pw.FlexColumnWidth(2),    // Entity ID
                4: const pw.FlexColumnWidth(3),    // Reason
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfTheme.primaryTint),
                  children: [
                    'Timestamp',
                    'Actor (Role)',
                    'Action & Type',
                    'Entity ID',
                    'Reason'
                  ].map((h) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: pw.Text(
                      h,
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 8.5,
                        color: PdfTheme.primaryDark,
                      ),
                    ),
                  )).toList(),
                ),
                ...all.map((e) {
                  final ts = e.timestamp;
                  final tsStr =
                      '${ts.day.toString().padLeft(2, '0')}/${ts.month.toString().padLeft(2, '0')}/${ts.year} '
                      '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';
                  
                  final actionType = '${e.action.toUpperCase()} ${_entityLabel(context, e.entity)}';

                  return pw.TableRow(
                    children: [
                      tsStr,
                      '${e.actorName} (${e.actorRole})',
                      actionType,
                      e.entityId,
                      e.reason ?? '',
                    ].map((cell) => pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                      child: pw.Text(
                        cell,
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    )).toList(),
                  );
                }),
              ],
            ),
          ],
        ),
      );

      final ts = DateTime.now().millisecondsSinceEpoch;
      await Printing.sharePdf(
        bytes: await doc.save(),
        filename: 'audit_log_$ts.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.tr('exportFailedPrefix')} $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _mapSummary(Map<String, dynamic>? m) {
    if (m == null || m.isEmpty) return '';
    final pairs = m.entries.take(4).map((e) => '${e.key}=${e.value}').join('; ');
    return m.length > 4 ? '$pairs...' : pairs;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(context.tr('auditLog')),
        actions: [
          if (_exporting)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                child: SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                ),
              ),
            )
          else
            PopupMenuButton<String>(
              icon: const Icon(Icons.download_outlined),
              tooltip: 'Export options',
              onSelected: (value) {
                if (value == 'csv') {
                  _exportCsv();
                } else if (value == 'pdf') {
                  _exportPdf();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'csv',
                  child: Row(
                    children: [
                      const Icon(Icons.description_outlined, size: 20),
                      const SizedBox(width: 8),
                      Text(context.tr('exportCsv')),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'pdf',
                  child: Row(
                    children: [
                      const Icon(Icons.picture_as_pdf_outlined, size: 20),
                      const SizedBox(width: 8),
                      Text(context.tr('exportPdf')),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          _FilterBar(
            entityFilter:  _entityFilter,
            actorFilter:   _actorFilter,
            actors:        _actors,
            actorsLoading: _actorsLoading,
            from:          _from,
            to:            _to,
            onEntityChanged: (v) {
              setState(() => _entityFilter = v);
            },
            onActorChanged: (v) {
              setState(() => _actorFilter = v);
              _applyFilters();
            },
            onPickFrom:   _pickFrom,
            onPickTo:     _pickTo,
            onClear:      () {
              setState(() {
                _entityFilter = '';
                _actorFilter  = '';
                _from = null;
                _to   = null;
              });
              _applyFilters();
            },
            onApply:      _applyFilters,
          ),
          Expanded(
            child: _entries.isEmpty && !_loading
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.history_outlined,
                            size: 52, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text(context.tr('noAuditEntries'),
                            style:
                                TextStyle(color: Colors.grey.shade500)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    itemCount: _entries.length + (_hasMore ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == _entries.length) {
                        return _LoadMoreButton(
                          loading: _loading,
                          onTap:   () => _fetchPage(),
                        );
                      }
                      return _AuditEntryCard(entry: _entries[i]);
                    },
                  ),
          ),
          if (_loading && _entries.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}

// ─── Filter bar ───────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final String            entityFilter;
  final String            actorFilter;
  final List<AuditActor>  actors;
  final bool              actorsLoading;
  final DateTime?         from;
  final DateTime?         to;
  final ValueChanged<String> onEntityChanged;
  final ValueChanged<String> onActorChanged;
  final VoidCallback      onPickFrom;
  final VoidCallback      onPickTo;
  final VoidCallback      onClear;
  final VoidCallback      onApply;

  const _FilterBar({
    required this.entityFilter,
    required this.actorFilter,
    required this.actors,
    required this.actorsLoading,
    required this.from,
    required this.to,
    required this.onEntityChanged,
    required this.onActorChanged,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onClear,
    required this.onApply,
  });

  String _fmt(BuildContext context, DateTime? d) => d == null
      ? context.tr('anyWord')
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final hasFilter = entityFilter.isNotEmpty || from != null || to != null ||
        actorFilter.isNotEmpty;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row 1: Entity type + actor search
          Row(children: [
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                value: entityFilter,
                decoration: InputDecoration(
                  labelText: context.tr('auditTypeLabel'),
                  isDense: true,
                  filled: true,
                  fillColor: AppTheme.background,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                items: _kEntities
                    .map((e) => DropdownMenuItem(
                          value: e,
                          child: Text(_entityLabel(context, e),
                              style: const TextStyle(fontSize: 12)),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) onEntityChanged(v);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<String>(
                value: actorFilter,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: actorsLoading ? context.tr('loadingActors') : context.tr('actorLabel'),
                  isDense: true,
                  filled: true,
                  fillColor: AppTheme.background,
                  prefixIcon: const Icon(Icons.person_outline, size: 16),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(context.tr('allActors'),
                        style: const TextStyle(fontSize: 12)),
                  ),
                  ...actors.map((a) => DropdownMenuItem(
                        value: a.uid,
                        child: Text(a.label,
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: actorsLoading
                    ? null
                    : (v) {
                        if (v != null) onActorChanged(v);
                      },
              ),
            ),
          ]),

          const SizedBox(height: 8),

          // Row 2: Date range + Apply + Clear
          Row(children: [
            _DateChip(
              label: '${context.tr('rangeFrom')}: ${_fmt(context, from)}',
              onTap: onPickFrom,
              active: from != null,
            ),
            const SizedBox(width: 6),
            _DateChip(
              label: '${context.tr('rangeTo')}: ${_fmt(context, to)}',
              onTap: onPickTo,
              active: to != null,
            ),
            const Spacer(),
            if (hasFilter)
              TextButton(
                onPressed: onClear,
                style: TextButton.styleFrom(
                    foregroundColor: Colors.grey,
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: Text(context.tr('clearAction'), style: const TextStyle(fontSize: 12)),
              ),
            ElevatedButton(
              onPressed: onApply,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
              ),
              child:
                  Text(context.tr('applyAction'), style: const TextStyle(fontSize: 12)),
            ),
          ]),
        ],
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  final String   label;
  final bool     active;
  final VoidCallback onTap;
  const _DateChip(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active
                ? AppTheme.primary.withValues(alpha: 0.08)
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: active ? AppTheme.primary : Colors.grey.shade300),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: active ? AppTheme.primary : Colors.grey.shade600,
              fontWeight:
                  active ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      );
}

// ─── Load More button ─────────────────────────────────────────────────────────

class _LoadMoreButton extends StatelessWidget {
  final bool         loading;
  final VoidCallback onTap;
  const _LoadMoreButton({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: loading
              ? const CircularProgressIndicator(strokeWidth: 2)
              : OutlinedButton.icon(
                  onPressed: onTap,
                  icon: const Icon(Icons.expand_more, size: 16),
                  label: Text(context.tr('loadMorePrefix')),
                ),
        ),
      );
}

// ─── Audit entry card ─────────────────────────────────────────────────────────

class _AuditEntryCard extends StatefulWidget {
  final AuditEntry entry;
  const _AuditEntryCard({required this.entry});

  @override
  State<_AuditEntryCard> createState() => _AuditEntryCardState();
}

class _AuditEntryCardState extends State<_AuditEntryCard> {
  bool _expanded = false;

  Color get _actionColor {
    switch (widget.entry.action) {
      case 'create': return Colors.green;
      case 'delete': return Colors.red;
      default:       return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final ts = e.timestamp;
    final dateStr =
        '${ts.day.toString().padLeft(2, '0')}/${ts.month.toString().padLeft(2, '0')}/${ts.year} '
        '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header row ──────────────────────────────────────────────
              Row(children: [
                // Action badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _actionColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    e.action.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _actionColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Entity chip
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _entityLabel(context, e.entity),
                    style: const TextStyle(
                        fontSize: 10, color: AppTheme.primary),
                  ),
                ),
                const Spacer(),
                Text(dateStr,
                    style: TextStyle(
                        fontSize: 10, color: Colors.grey.shade500)),
                const SizedBox(width: 4),
                Icon(
                  _expanded
                      ? Icons.expand_less
                      : Icons.expand_more,
                  size: 16,
                  color: Colors.grey.shade400,
                ),
              ]),

              const SizedBox(height: 6),

              // ── Entity ID + actor ────────────────────────────────────────
              Row(children: [
                Expanded(
                  child: Text(
                    e.entityId,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.person_outline,
                    size: 12, color: Colors.grey.shade500),
                const SizedBox(width: 3),
                Text(
                  '${e.actorName} (${e.actorRole})',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade600),
                ),
              ]),

              if (e.reason != null && e.reason!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.info_outline,
                      size: 11, color: Colors.grey.shade400),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      e.reason!,
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                          fontStyle: FontStyle.italic),
                    ),
                  ),
                ]),
              ],

              // ── Expanded before/after ────────────────────────────────────
              if (_expanded) ...[
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 8),
                if (e.before != null) ...[
                  _DiffSection(label: context.tr('diffBefore'), data: e.before!,
                      color: Colors.red.shade50,
                      borderColor: Colors.red.shade200),
                  const SizedBox(height: 6),
                ],
                if (e.after != null)
                  _DiffSection(label: context.tr('diffAfter'), data: e.after!,
                      color: Colors.green.shade50,
                      borderColor: Colors.green.shade200),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Before/After diff section ────────────────────────────────────────────────

class _DiffSection extends StatelessWidget {
  final String              label;
  final Map<String, dynamic> data;
  final Color               color;
  final Color               borderColor;

  const _DiffSection({
    required this.label,
    required this.data,
    required this.color,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    // Show only top-level scalar fields (skip nested maps for readability)
    final fields = data.entries
        .where((e) => e.value is! Map && e.value is! List)
        .take(10)
        .toList();
    final hasMore = data.length > fields.length;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              ...fields.map((e) => _kv(e.key, '${e.value}')),
              if (hasMore)
                Text('+${data.length - fields.length} ${context.tr('moreSuffix')}',
                    style: TextStyle(
                        fontSize: 10, color: Colors.grey.shade500)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white70,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '$k: $v',
          style: const TextStyle(fontSize: 10),
          overflow: TextOverflow.ellipsis,
        ),
      );
}

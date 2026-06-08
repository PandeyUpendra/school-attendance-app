import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../l10n/app_strings.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../utils/pdf_theme.dart';
import '../models/fee.dart';
import '../models/student.dart';
import '../services/fee_service.dart';
import '../services/student_service.dart';
import '../services/timetable_service.dart';
import '../widgets/refreshable_data.dart';

/// Class-level fee collection screen.
/// Pass [initialClass] to pre-select a class (from FeeOverviewScreen).
class FeeCollectionScreen extends StatefulWidget {
  final String? initialClass;

  const FeeCollectionScreen({super.key, this.initialClass});

  @override
  State<FeeCollectionScreen> createState() => _FeeCollectionScreenState();
}

class _FeeCollectionScreenState extends State<FeeCollectionScreen> {
  final _feeService     = FeeService();
  final _studentService = StudentService();

  bool _loading = true;
  List<String>     _classes   = [];
  String?          _selectedClass;
  List<Student>    _students  = [];
  FeeStructure?    _structure;
  Map<int, double> _paid      = {};   // roll → total paid

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    final settings = await TimetableService().getSettings();
    final classes  = List<String>.from(settings['classes'] as List? ?? []);
    if (!mounted) return;
    setState(() { _classes = classes; });

    // Pre-select from argument or default to first
    final initial = widget.initialClass != null && classes.contains(widget.initialClass)
        ? widget.initialClass!
        : (classes.isNotEmpty ? classes.first : null);

    if (initial != null) await _selectClass(initial);
    setState(() => _loading = false);
  }

  Future<void> _selectClass(String cls) async {
    setState(() { _selectedClass = cls; _loading = true; });
    final results = await Future.wait([
      _studentService.getStudentsByClass(className: cls),
      _feeService.getFeeStructure(className: cls),
    ]);
    final students  = results[0] as List<Student>;
    final structure = results[1] as FeeStructure;

    final rolls = students.map((s) => s.roll).toList();
    final paid  = await _feeService.getClassFeeOverview(className: cls, rolls: rolls);
    if (!mounted) return;
    setState(() {
      _students  = students;
      _structure = structure;
      _paid      = paid;
      _loading   = false;
    });
  }

  Future<void> _refreshStudent(int roll) async {
    final paid = await _feeService.getTotalPaid(
        className: _selectedClass!, roll: roll);
    if (!mounted) return;
    setState(() => _paid[roll] = paid);
  }

  Future<void> _openStudentDetail(Student student) async {
    if (_structure == null || _selectedClass == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _StudentFeeDetailScreen(
          student:        student,
          structure:      _structure!,
          totalPaid:      _paid[student.roll] ?? 0,
          onPaymentAdded: () => _refreshStudent(student.roll),
        ),
      ),
    );
    _refreshStudent(student.roll);
  }

  Color _statusColor(double paid, double total) {
    if (total == 0) return Colors.grey;
    final ratio = paid / total;
    if (ratio >= 1.0) return Colors.green.shade600;
    if (ratio >= 0.5) return const Color(0xFFF57F17);
    return Colors.red.shade400;
  }

  String _statusLabel(double paid, double total) {
    if (total == 0) return 'No fee set';
    if (paid >= total) return 'Paid';
    if (paid > 0) return 'Partial';
    return 'Pending';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _selectedClass != null
                  ? 'Fee Collection — $_selectedClass'
                  : 'Fee Collection',
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.bold),
            ),
            Text(context.tr('tapStudentRecordPayment'),
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
      ),
      body: _loading
          ? const LoadingState()
          : _classes.isEmpty
              ? Center(
                  child: Text(context.tr('noClassesConfiguredShort'),
                      style: TextStyle(color: Colors.grey.shade500)))
              : Column(
                  children: [
                    // ── Class chip selector ────────────────────────────
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _classes.map((cls) {
                            final selected = cls == _selectedClass;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(cls),
                                selected: selected,
                                selectedColor: AppTheme.primary,
                                labelStyle: TextStyle(
                                  color: selected ? Colors.white : null,
                                  fontWeight: selected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                                onSelected: (_) => _selectClass(cls),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const Divider(height: 1),

                    // ── Class summary banner ───────────────────────────
                    if (_structure != null &&
                        _structure!.totalAnnualFee > 0 &&
                        _students.isNotEmpty)
                      _ClassFeeSummary(
                        students:  _students,
                        structure: _structure!,
                        paid:      _paid,
                      ),

                    // ── Installment legend (if configured) ────────────
                    if (_structure != null &&
                        _structure!.installments.isNotEmpty)
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                size: 14, color: Colors.grey.shade500),
                            const SizedBox(width: 6),
                            Text(
                              '${_structure!.installments.length} instalments configured',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade600),
                            ),
                            const Spacer(),
                            _InstallmentLegend(),
                          ],
                        ),
                      ),

                    // ── Student list ───────────────────────────────────
                    Expanded(
                      child: _students.isEmpty
                          ? Center(
                              child: Text(context.tr('noStudentsInClass'),
                                  style: TextStyle(
                                      color: Colors.grey.shade500)),
                            )
                          : RefreshIndicator(
                              onRefresh: () =>
                                  _selectClass(_selectedClass!),
                              color: AppTheme.primary,
                              child: ListView.separated(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 8),
                                itemCount: _students.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1, indent: 72),
                                itemBuilder: (_, i) {
                                  final s     = _students[i];
                                  final total = _structure?.totalAnnualFee ?? 0;
                                  final p     = _paid[s.roll] ?? 0;
                                  final due   = (total - p).clamp(0.0, double.infinity);
                                  final color = _statusColor(p, total);
                                  return ListTile(
                                    tileColor: Colors.white,
                                    leading: CircleAvatar(
                                      backgroundColor:
                                          color.withAlpha(30),
                                      child: Text(
                                        s.name.isNotEmpty
                                            ? s.name[0].toUpperCase()
                                            : '?',
                                        style: TextStyle(
                                            color: color,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    title: Text(s.name,
                                        style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600)),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Roll ${s.roll}  •  Paid ₹${_fmt(p)}'
                                          '${total > 0 ? '  •  Due ₹${_fmt(due)}' : ''}',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600),
                                        ),
                                        // Instalment dots
                                        if (_structure != null &&
                                            _structure!.installments.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                top: 4),
                                            child: _InstallmentDots(
                                              installments:
                                                  _structure!.installments,
                                              totalPaid: p,
                                            ),
                                          ),
                                      ],
                                    ),
                                    isThreeLine: _structure != null &&
                                        _structure!.installments.isNotEmpty,
                                    trailing: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: color.withAlpha(30),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            _statusLabel(p, total),
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: color,
                                                fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Icon(Icons.chevron_right,
                                            color: Colors.grey.shade400,
                                            size: 16),
                                      ],
                                    ),
                                    onTap: () => _openStudentDetail(s),
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }

  String _fmt(double v) =>
      v == v.truncateToDouble()
          ? v.toStringAsFixed(0)
          : v.toStringAsFixed(2);
}

// ─── Instalment dots legend ───────────────────────────────────────────────────

class _InstallmentLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Row(
        children: [
          _Dot(Colors.green.shade600),
          const SizedBox(width: 3),
          Text(context.tr('paidLabel'),
              style:
                  TextStyle(fontSize: 10, color: Colors.grey.shade500)),
          const SizedBox(width: 8),
          const _Dot(Color(0xFFF57F17)),
          const SizedBox(width: 3),
          Text(context.tr('partialLabel'),
              style:
                  TextStyle(fontSize: 10, color: Colors.grey.shade500)),
          const SizedBox(width: 8),
          _Dot(Colors.red.shade400),
          const SizedBox(width: 3),
          Text(context.tr('dueLabel'),
              style:
                  TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        ],
      );
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot(this.color);

  @override
  Widget build(BuildContext context) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// Small row of coloured circles representing instalment statuses.
/// Uses cumulative totalPaid to estimate how many instalments are covered.
class _InstallmentDots extends StatelessWidget {
  final List<FeeInstallment> installments;
  final double               totalPaid;

  const _InstallmentDots({
    required this.installments,
    required this.totalPaid,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    double remaining = totalPaid;

    return Row(
      children: installments.map((inst) {
        Color dotColor;
        if (remaining >= inst.amount) {
          dotColor = Colors.green.shade600; // fully paid
          remaining -= inst.amount;
        } else if (remaining > 0) {
          dotColor = const Color(0xFFF57F17); // partial
          remaining = 0;
        } else if (inst.dueDate.isBefore(now)) {
          dotColor = Colors.red.shade400; // overdue & unpaid
        } else {
          dotColor = Colors.grey.shade400; // upcoming
        }
        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Tooltip(
            message: inst.name,
            child: _Dot(dotColor),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Class-wide fee summary banner ───────────────────────────────────────────

class _ClassFeeSummary extends StatelessWidget {
  final List<Student>    students;
  final FeeStructure     structure;
  final Map<int, double> paid;

  const _ClassFeeSummary({
    required this.students,
    required this.structure,
    required this.paid,
  });

  @override
  Widget build(BuildContext context) {
    final totalDue  = structure.totalAnnualFee * students.length;
    final totalPaid = students.fold(0.0, (s, st) => s + (paid[st.roll] ?? 0));
    final paidCount = students.where((s) {
      final p = paid[s.roll] ?? 0;
      return p >= structure.totalAnnualFee;
    }).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppTheme.primary,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _SumCell('₹${_fmtK(totalPaid)}', 'Collected', Colors.white),
          _SumCell('₹${_fmtK((totalDue - totalPaid).clamp(0, double.infinity))}',
              'Pending', Colors.yellow.shade200),
          _SumCell('$paidCount / ${students.length}', 'Fully Paid',
              Colors.white),
        ],
      ),
    );
  }

  static String _fmtK(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000)   return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

class _SumCell extends StatelessWidget {
  final String value, label;
  final Color  color;
  const _SumCell(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  color: color.withAlpha(178), fontSize: 10)),
        ],
      );
}

// ─── Per-student fee detail screen ───────────────────────────────────────────

class _StudentFeeDetailScreen extends StatefulWidget {
  final Student      student;
  final FeeStructure structure;
  final double       totalPaid;
  final VoidCallback onPaymentAdded;

  const _StudentFeeDetailScreen({
    required this.student,
    required this.structure,
    required this.totalPaid,
    required this.onPaymentAdded,
  });

  @override
  State<_StudentFeeDetailScreen> createState() =>
      _StudentFeeDetailScreenState();
}

class _StudentFeeDetailScreenState extends State<_StudentFeeDetailScreen> {
  final _feeService = FeeService();
  bool _loading = true;
  List<Payment>        _payments          = [];
  List<Payment>        _reversedPayments  = []; // voided receipts (#26/#49)
  bool                 _showReversed      = false;
  Map<String, double>  _installmentPaid   = {}; // installmentName → paid
  double _totalPaid = 0;

  @override
  void initState() {
    super.initState();
    _totalPaid = widget.totalPaid;
    _loadPayments();
  }

  Future<void> _loadPayments() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _feeService.getPayments(
          className: widget.student.className, roll: widget.student.roll,
          includeReversed: true),
      _feeService.getInstallmentPaidAmounts(
          className: widget.student.className, roll: widget.student.roll),
    ]);
    if (!mounted) return;
    final all      = results[0] as List<Payment>;
    final active   = all.where((p) => !p.reversed).toList();
    final reversed = all.where((p) => p.reversed).toList();
    final instPaid = results[1] as Map<String, double>;
    // Totals count only non-reversed payments — voided receipts never inflate
    // the collected figure (#26).
    final paid     = active.fold(0.0, (s, p) => s + p.amount);
    setState(() {
      _payments         = active;
      _reversedPayments = reversed;
      _installmentPaid  = instPaid;
      _totalPaid        = paid;
      _loading          = false;
    });
  }

  double get _due =>
      (widget.structure.totalAnnualFee - _totalPaid).clamp(0.0, double.infinity);

  // ── Record payment bottom sheet ──────────────────────────────────────────

  Future<void> _recordPayment() async {
    final formKey      = GlobalKey<FormState>();
    final amountCtrl   = TextEditingController(
        text: _due > 0 ? _due.toStringAsFixed(0) : '');
    final noteCtrl     = TextEditingController();
    String mode             = 'Cash';
    String? selectedInstalment; // null = no instalment linked
    bool saving = false;

    // Stable id for THIS payment entry, generated once when the sheet opens.
    // Passed to addPayment so a network retry / double-submit writes to the
    // same doc instead of recording the payment twice (#48).
    final clientTxnId = '${DateTime.now().microsecondsSinceEpoch}_${widget.student.roll}';

    final hasInstalments = widget.structure.installments.isNotEmpty;

    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(
            left: 18, right: 18, top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 18,
          ),
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Record Payment — ${widget.student.name}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    'Outstanding Due: ₹${_due.toStringAsFixed(0)}',
                    style: TextStyle(
                        fontSize: 13, color: Colors.red.shade700),
                  ),
                  const SizedBox(height: 14),

                  // Amount
                  TextFormField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9.]')),
                    ],
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Amount (₹)',
                      prefixIcon: const Icon(Icons.currency_rupee),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      final n = double.tryParse(v.trim());
                      if (n == null || n <= 0) {
                        return 'Must be greater than 0';
                      }
                      // Overpayment guard: when a positive annual fee is
                      // configured, a single payment can't exceed the
                      // outstanding due — previously any amount was accepted,
                      // corrupting collected totals (#47). (₹1 tolerance for
                      // rounding.)
                      if (widget.structure.totalAnnualFee > 0 && n > _due + 1) {
                        return 'Cannot exceed outstanding due of ₹${_due.toStringAsFixed(0)}';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),

                  // Instalment selector (only if configured)
                  if (hasInstalments) ...[
                    DropdownButtonFormField<String>(
                      value: selectedInstalment,
                      decoration: InputDecoration(
                        labelText: context.tr('instalmentOptional'),
                        prefixIcon: const Icon(Icons.event_note_outlined),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      items: [
                        DropdownMenuItem(
                            value: null,
                            child: Text(context.tr('noSpecificInstalment'))),
                        ...widget.structure.installments.map((inst) {
                          final pd =
                              _installmentPaid[inst.name] ?? 0;
                          final status = pd >= inst.amount
                              ? ' ✓'
                              : pd > 0
                                  ? ' (partial)'
                                  : '';
                          return DropdownMenuItem(
                            value: inst.name,
                            child: Text(
                                '${inst.name} — ₹${inst.amount.toStringAsFixed(0)}$status'),
                          );
                        }),
                      ],
                      onChanged: (v) {
                        setS(() {
                          selectedInstalment = v;
                          // Pre-fill with instalment remaining due
                          if (v != null) {
                            final inst = widget.structure.installments
                                .firstWhere((i) => i.name == v);
                            final alreadyPaid =
                                _installmentPaid[v] ?? 0;
                            final instDue =
                                (inst.amount - alreadyPaid)
                                    .clamp(0.0, double.infinity);
                            if (instDue > 0) {
                              amountCtrl.text =
                                  instDue.toStringAsFixed(0);
                            }
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Payment mode
                  Text(context.tr('paymentMode'),
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children:
                        ['Cash', 'UPI', 'Bank', 'Cheque'].map((m) {
                      return ChoiceChip(
                        label: Text(m),
                        selected: mode == m,
                        selectedColor: AppTheme.primary,
                        labelStyle: TextStyle(
                            color: mode == m ? Colors.white : null),
                        onSelected: (_) => setS(() => mode = m),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),

                  // Note
                  TextFormField(
                    controller: noteCtrl,
                    maxLength: 200,
                    maxLengthEnforcement: MaxLengthEnforcement.enforced,
                    decoration: InputDecoration(
                      labelText: context.tr('noteOptional'),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Actions
                  Row(children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(context.tr('cancel')),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: saving
                          ? null
                          : () async {
                              if (!formKey.currentState!.validate()) {
                                return;
                              }
                              final amt = double.tryParse(
                                      amountCtrl.text.trim()) ??
                                  0;
                              setS(() => saving = true);
                              // receiptNo is allocated atomically server-side in
                              // addPayment; pass empty here (#46).
                              final payment = Payment(
                                id:              '',
                                amount:          amt,
                                paidOn:          DateTime.now(),
                                mode:            mode,
                                receiptNo:       '',
                                installmentName: selectedInstalment,
                                note: noteCtrl.text.trim().isEmpty
                                    ? null
                                    : noteCtrl.text.trim(),
                              );
                              try {
                                await _feeService.addPayment(
                                  className:   widget.student.className,
                                  roll:        widget.student.roll,
                                  payment:     payment,
                                  clientTxnId: clientTxnId,
                                );
                                if (ctx.mounted) {
                                  Navigator.pop(ctx, true);
                                }
                              } catch (e) {
                                // Over-payment guard or any write failure:
                                // surface it and let the cashier retry/adjust.
                                setS(() => saving = false);
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                                    content: Text(e is FeeOverpaymentException
                                        ? e.message
                                        : 'Could not record payment. Please try again.'),
                                    backgroundColor: Colors.red,
                                  ));
                                }
                              }
                            },
                      icon: const Icon(Icons.check, size: 18),
                      label: Text(context.tr('savePayment')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (added == true) {
      widget.onPaymentAdded();
      await _loadPayments();
    }
  }

  // ── Print receipt ────────────────────────────────────────────────────────

  Future<void> _printReceipt(Payment p) async {
    final doc = pw.Document();
    final s   = widget.student;
    final st  = widget.structure;

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a5,
      build: (pw.Context context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Center(
            child: pw.Text('FEE RECEIPT',
                style: pw.TextStyle(
                    fontSize: 20, fontWeight: pw.FontWeight.bold,
                    color: PdfTheme.primaryDark)),
          ),
          pw.SizedBox(height: 6),
          pw.Center(
            child: pw.Text('Receipt No: ${p.receiptNo}',
                style: const pw.TextStyle(fontSize: 11)),
          ),
          pw.Divider(height: 20, color: PdfTheme.primaryLight),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Student: ${s.name}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text(
                  'Date: ${p.paidOn.day}/${p.paidOn.month}/${p.paidOn.year}'),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Class: ${s.className}  •  Roll: ${s.roll}'),
              pw.Text('Mode: ${p.mode}'),
            ],
          ),
          if (p.installmentName != null) ...[
            pw.SizedBox(height: 4),
            pw.Text('Instalment: ${p.installmentName}'),
          ],
          pw.Divider(height: 20, color: PdfTheme.primaryLight),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Amount Paid',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text('₹${p.amount.toStringAsFixed(0)}',
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold,
                      color: PdfTheme.accent)),
            ],
          ),
          if (st.totalAnnualFee > 0) ...[
            pw.SizedBox(height: 8),
            pw.Text(
                'Annual Fee: ₹${st.totalAnnualFee.toStringAsFixed(0)}'),
            pw.Text(
                'Total Paid: ₹${_totalPaid.toStringAsFixed(0)}   Balance Due: ₹${_due.toStringAsFixed(0)}'),
          ],
          if (p.note != null && p.note!.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text('Note: ${p.note}'),
          ],
          pw.Divider(height: 24, color: PdfTheme.primaryLight),
          pw.Center(
            child: pw.Text(
              'This is a computer-generated receipt.',
              style: const pw.TextStyle(fontSize: 9),
            ),
          ),
        ],
      ),
    ));

    await Printing.layoutPdf(
      onLayout: (_) => doc.save(),
      name: 'receipt_${p.receiptNo}',
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final s     = widget.student;
    final total = widget.structure.totalAnnualFee;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.name,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            Text('Roll ${s.roll}  •  ${s.className}',
                style: const TextStyle(
                    fontSize: 12, color: Colors.white70)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _recordPayment,
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(context.tr('recordPayment')),
      ),
      body: _loading
          ? const LoadingState()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Fee status card ──────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryDark,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceAround,
                        children: [
                          _HeroStat('₹${_fmt(total)}', 'Annual Fee'),
                          _HeroStat('₹${_fmt(_totalPaid)}', 'Paid'),
                          _HeroStat('₹${_fmt(_due)}', 'Due'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: total > 0
                              ? (_totalPaid / total).clamp(0.0, 1.0)
                              : 0,
                          minHeight: 8,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.white),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        total > 0
                            ? '${(_totalPaid / total * 100).clamp(0, 100).toStringAsFixed(1)}% paid'
                            : 'No annual fee configured',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Instalments section ──────────────────────────────
                if (widget.structure.installments.isNotEmpty) ...[
                  Text(context.tr('secInstalmentsShort'),
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey,
                          letterSpacing: 0.8)),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: List.generate(
                        widget.structure.installments.length,
                        (i) {
                          final inst =
                              widget.structure.installments[i];
                          final paidAmt =
                              _installmentPaid[inst.name] ?? 0;
                          return _InstallmentRow(
                            instalment: inst,
                            paidAmount: paidAmt,
                            showDivider: i > 0,
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // ── Payment history ──────────────────────────────────
                Text(context.tr('secPaymentHistory'),
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                        letterSpacing: 0.8)),
                const SizedBox(height: 10),

                if (_payments.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.receipt_long_outlined,
                              size: 40, color: Colors.grey.shade300),
                          const SizedBox(height: 10),
                          Text(context.tr('noPaymentsYet'),
                              style: TextStyle(
                                  color: Colors.grey.shade500)),
                        ],
                      ),
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        for (int i = 0; i < _payments.length; i++) ...[
                          if (i > 0)
                            const Divider(height: 1, indent: 16),
                          _PaymentTile(
                            payment: _payments[i],
                            onPrint: () =>
                                _printReceipt(_payments[i]),
                          ),
                        ],
                      ],
                    ),
                  ),

                // ── Reversed (voided) payments (#26/#49) ──────────────
                if (_reversedPayments.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () =>
                        setState(() => _showReversed = !_showReversed),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        Icon(Icons.history_toggle_off,
                            size: 16, color: Colors.grey.shade600),
                        const SizedBox(width: 6),
                        Text(
                          '${context.tr('reversedPaymentsLabel')} (${_reversedPayments.length})',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700),
                        ),
                        const Spacer(),
                        Icon(
                          _showReversed
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          size: 18,
                          color: Colors.grey.shade500,
                        ),
                      ]),
                    ),
                  ),
                  if (_showReversed)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          for (int i = 0; i < _reversedPayments.length; i++) ...[
                            if (i > 0)
                              const Divider(height: 1, indent: 16),
                            _PaymentTile(
                              payment: _reversedPayments[i],
                              reversed: true,
                              onPrint: () {},
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 80),
              ],
            ),
    );
  }

  String _fmt(double v) =>
      v == v.truncateToDouble()
          ? v.toStringAsFixed(0)
          : v.toStringAsFixed(2);
}

// ─── Instalment row ───────────────────────────────────────────────────────────

class _InstallmentRow extends StatelessWidget {
  final FeeInstallment instalment;
  final double         paidAmount;
  final bool           showDivider;

  const _InstallmentRow({
    required this.instalment,
    required this.paidAmount,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final due = (instalment.amount - paidAmount).clamp(0.0, double.infinity);

    Color  statusColor;
    String statusLabel;
    IconData statusIcon;

    if (paidAmount >= instalment.amount) {
      statusColor  = Colors.green.shade600;
      statusLabel  = 'Paid';
      statusIcon   = Icons.check_circle_outline;
    } else if (paidAmount > 0) {
      statusColor  = const Color(0xFFF57F17);
      statusLabel  = 'Partial';
      statusIcon   = Icons.timelapse_outlined;
    } else if (instalment.dueDate.isBefore(now)) {
      statusColor  = Colors.red.shade400;
      statusLabel  = 'Overdue';
      statusIcon   = Icons.error_outline;
    } else {
      statusColor  = Colors.grey.shade500;
      statusLabel  = 'Upcoming';
      statusIcon   = Icons.schedule_outlined;
    }

    final dueDateStr =
        '${instalment.dueDate.day}/${instalment.dueDate.month}/${instalment.dueDate.year}';

    return Column(
      children: [
        if (showDivider) const Divider(height: 1, indent: 16),
        ListTile(
          dense: true,
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: statusColor.withAlpha(26),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(statusIcon, color: statusColor, size: 20),
          ),
          title: Text(instalment.name,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: Text(
            'Due by $dueDateStr  •  ₹${instalment.amount.toStringAsFixed(0)}'
            '${paidAmount > 0 ? '  •  Paid ₹${paidAmount.toStringAsFixed(0)}' : ''}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(26),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(statusLabel,
                    style: TextStyle(
                        fontSize: 11,
                        color: statusColor,
                        fontWeight: FontWeight.bold)),
              ),
              if (due > 0 && paidAmount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('Due ₹${due.toStringAsFixed(0)}',
                      style: TextStyle(
                          fontSize: 10, color: Colors.grey.shade500)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Hero stat cell ───────────────────────────────────────────────────────────

class _HeroStat extends StatelessWidget {
  final String value, label;
  const _HeroStat(this.value, this.label);

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 11)),
        ],
      );
}

// ─── Payment tile ─────────────────────────────────────────────────────────────

class _PaymentTile extends StatelessWidget {
  final Payment      payment;
  final VoidCallback onPrint;
  final bool         reversed;
  const _PaymentTile({required this.payment, required this.onPrint, this.reversed = false});

  @override
  Widget build(BuildContext context) {
    final p    = payment;
    final date = '${p.paidOn.day}/${p.paidOn.month}/${p.paidOn.year}';
    return ListTile(
      leading: Container(
        width: 42, height: 42,
        decoration: BoxDecoration(
          color: reversed
              ? Colors.grey.withAlpha(30)
              : AppTheme.primary.withAlpha(20),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(reversed ? Icons.receipt_long_outlined : Icons.currency_rupee,
            color: reversed ? Colors.grey.shade500 : AppTheme.primary, size: 20),
      ),
      title: Text(
        '₹${p.amount.toStringAsFixed(0)}  •  ${p.mode}'
        '${p.installmentName != null ? '  •  ${p.installmentName}' : ''}',
        style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: reversed ? Colors.grey.shade500 : null,
            decoration: reversed ? TextDecoration.lineThrough : null),
      ),
      subtitle: Text(
        '$date  •  ${p.receiptNo}'
        '${p.note != null ? '\n${p.note}' : ''}',
        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
      ),
      isThreeLine: p.note != null && p.note!.isNotEmpty,
      trailing: reversed
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(context.tr('reversedBadge'),
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.danger)),
            )
          : IconButton(
              icon: const Icon(Icons.print_outlined,
                  color: AppTheme.primary, size: 20),
              tooltip: context.tr('printReceipt'),
              onPressed: onPrint,
            ),
    );
  }
}

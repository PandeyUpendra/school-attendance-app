import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/fee.dart';
import '../models/student.dart';
import '../services/fee_service.dart';
import '../services/student_service.dart';
import '../services/timetable_service.dart';

/// Fee collection screen — lists all students in a class with paid/due info.
/// Tap a student to record a payment and generate a PDF receipt.
class FeeCollectionScreen extends StatefulWidget {
  const FeeCollectionScreen({super.key});

  @override
  State<FeeCollectionScreen> createState() => _FeeCollectionScreenState();
}

class _FeeCollectionScreenState extends State<FeeCollectionScreen> {
  final _feeService     = FeeService();
  final _studentService = StudentService();

  bool _loading = true;
  List<String>  _classes    = [];
  String?       _selectedClass;
  List<Student> _students   = [];
  FeeStructure? _structure;
  Map<int, double> _paid   = {};   // roll → total paid

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
    if (classes.isNotEmpty) await _selectClass(classes.first);
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

    assert(students.length == {for (final s in students) s.roll: s}.length,
        'Duplicate rolls detected in class $cls');
    debugPrint('[StudentList][$cls] count=${students.length}');

    final rolls     = students.map((s) => s.roll).toList();
    final paid      = await _feeService.getClassFeeOverview(className: cls, rolls: rolls);
    if (!mounted) return;
    setState(() {
      _students  = students;
      _structure = structure;
      _paid      = paid;
      _loading   = false;
    });
  }

  Future<void> _refreshStudent(int roll) async {
    final paid = await _feeService.getTotalPaid(className: _selectedClass!, roll: roll);
    if (!mounted) return;
    setState(() => _paid[roll] = paid);
  }

  Future<void> _openStudentDetail(Student student) async {
    if (_structure == null || _selectedClass == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _StudentFeeDetailScreen(
          student:   student,
          structure: _structure!,
          totalPaid: _paid[student.roll] ?? 0,
          onPaymentAdded: () => _refreshStudent(student.roll),
        ),
      ),
    );
    _refreshStudent(student.roll);
  }

  Color _statusColor(double paid, double total) {
    if (total == 0) return Colors.grey;
    final ratio = paid / total;
    if (ratio >= 1.0) return Colors.green;
    if (ratio >= 0.5) return const Color(0xFFF57F17);
    return Colors.red;
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
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Fee Collection',
                style:
                    TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text('Record payments & view dues',
                style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _classes.isEmpty
              ? Center(
                  child: Text('No classes configured.',
                      style: TextStyle(color: Colors.grey.shade500)))
              : Column(
                  children: [
                    // Class chips
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
                                selectedColor: Colors.green.shade700,
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

                    // Summary banner
                    if (_structure != null &&
                        _structure!.totalAnnualFee > 0 &&
                        _students.isNotEmpty)
                      _ClassFeeSummary(
                        students:  _students,
                        structure: _structure!,
                        paid:      _paid,
                      ),

                    // Student list
                    Expanded(
                      child: _students.isEmpty
                          ? Center(
                              child: Text('No students in this class.',
                                  style: TextStyle(
                                      color: Colors.grey.shade500)),
                            )
                          : RefreshIndicator(
                              onRefresh: () => _selectClass(_selectedClass!),
                              color: Colors.green.shade700,
                              child: ListView.separated(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                itemCount: _students.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1, indent: 72),
                                itemBuilder: (_, i) {
                                  final s = _students[i];
                                  final total = _structure?.totalAnnualFee ?? 0;
                                  final paid  = _paid[s.roll] ?? 0;
                                  final due   = (total - paid).clamp(0.0, double.infinity);
                                  final color = _statusColor(paid, total);
                                  return ListTile(
                                    tileColor: Colors.white,
                                    leading: CircleAvatar(
                                      backgroundColor:
                                          color.withOpacity(0.12),
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
                                    subtitle: Text(
                                      'Roll ${s.roll}  •  Paid ₹${_fmt(paid)}'
                                      '${total > 0 ? '  •  Due ₹${_fmt(due)}' : ''}',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600),
                                    ),
                                    trailing: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: color.withOpacity(0.12),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            _statusLabel(paid, total),
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: color,
                                                fontWeight:
                                                    FontWeight.bold),
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
      v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}

// ─── Class-wide fee summary banner ───────────────────────────────────────────

class _ClassFeeSummary extends StatelessWidget {
  final List<Student>  students;
  final FeeStructure   structure;
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
      color: Colors.green.shade700,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _SumCell('₹${_fmtK(totalPaid)}', 'Collected', Colors.white),
          _SumCell('₹${_fmtK(totalDue - totalPaid)}', 'Pending', Colors.yellow.shade200),
          _SumCell('$paidCount / ${students.length}', 'Fully Paid', Colors.white),
        ],
      ),
    );
  }

  String _fmtK(double v) {
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
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  color: color.withOpacity(0.7), fontSize: 10)),
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
  List<Payment> _payments = [];
  double _totalPaid = 0;

  @override
  void initState() {
    super.initState();
    _totalPaid = widget.totalPaid;
    _loadPayments();
  }

  Future<void> _loadPayments() async {
    setState(() => _loading = true);
    final payments = await _feeService.getPayments(
        className: widget.student.className, roll: widget.student.roll);
    if (!mounted) return;
    final paid = payments.fold(0.0, (s, p) => s + p.amount);
    setState(() {
      _payments  = payments;
      _totalPaid = paid;
      _loading   = false;
    });
  }

  double get _due =>
      (widget.structure.totalAnnualFee - _totalPaid).clamp(0.0, double.infinity);

  Future<void> _recordPayment() async {
    final formKey    = GlobalKey<FormState>();
    final amountCtrl = TextEditingController(
        text: _due > 0 ? _due.toStringAsFixed(0) : '');
    final noteCtrl = TextEditingController();
    String mode = 'Cash';
    bool saving = false;

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
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              const SizedBox(height: 6),
              Text(
                'Outstanding Due: ₹${_due.toStringAsFixed(0)}',
                style: TextStyle(
                    fontSize: 13, color: Colors.red.shade700),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
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
                  if (n == null || n <= 0) return 'Must be greater than 0';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              const Text('Payment Mode',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: ['Cash', 'UPI', 'Bank', 'Cheque'].map((m) {
                  return ChoiceChip(
                    label: Text(m),
                    selected: mode == m,
                    selectedColor: Colors.green.shade700,
                    labelStyle: TextStyle(
                        color: mode == m ? Colors.white : null),
                    onSelected: (_) => setS(() => mode = m),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: noteCtrl,
                maxLength: 200,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                decoration: InputDecoration(
                  labelText: 'Note (optional)',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 14),
              Row(children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          final amt = double.tryParse(
                                  amountCtrl.text.trim()) ??
                              0;
                          setS(() => saving = true);
                          final receiptNo = FeeService.generateReceiptNo(
                            widget.student.className,
                            widget.student.roll,
                          );
                          final payment = Payment(
                            id:        '',
                            amount:    amt,
                            paidOn:    DateTime.now(),
                            mode:      mode,
                            receiptNo: receiptNo,
                            note: noteCtrl.text.trim().isEmpty
                                ? null
                                : noteCtrl.text.trim(),
                          );
                          await _feeService.addPayment(
                            className: widget.student.className,
                            roll: widget.student.roll,
                            payment: payment,
                          );
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        },
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Save Payment'),
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
    );

    if (added == true) {
      widget.onPaymentAdded();
      await _loadPayments();
    }
  }

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
                    fontSize: 20, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 6),
          pw.Center(
            child: pw.Text('Receipt No: ${p.receiptNo}',
                style: const pw.TextStyle(fontSize: 11)),
          ),
          pw.Divider(height: 20),
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
          pw.Divider(height: 20),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Amount Paid',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text('₹${p.amount.toStringAsFixed(0)}',
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold)),
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
          pw.Divider(height: 24),
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

  @override
  Widget build(BuildContext context) {
    final s     = widget.student;
    final total = widget.structure.totalAnnualFee;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
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
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Record Payment'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Fee status card
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.green.shade700,
                        Colors.green.shade500,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
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
                          backgroundColor: Colors.white.withOpacity(0.3),
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

                // Payment history
                const Text('PAYMENT HISTORY',
                    style: TextStyle(
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
                          Text('No payments recorded yet.',
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
                          if (i > 0) const Divider(height: 1, indent: 16),
                          _PaymentTile(
                            payment: _payments[i],
                            onPrint: () => _printReceipt(_payments[i]),
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 80),
              ],
            ),
    );
  }

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}

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

class _PaymentTile extends StatelessWidget {
  final Payment      payment;
  final VoidCallback onPrint;
  const _PaymentTile({required this.payment, required this.onPrint});

  @override
  Widget build(BuildContext context) {
    final p = payment;
    final date =
        '${p.paidOn.day}/${p.paidOn.month}/${p.paidOn.year}';
    return ListTile(
      leading: Container(
        width: 42, height: 42,
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.currency_rupee,
            color: Colors.green.shade700, size: 20),
      ),
      title: Text(
        '₹${p.amount.toStringAsFixed(0)}  •  ${p.mode}',
        style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '$date  •  ${p.receiptNo}'
        '${p.note != null ? '\n${p.note}' : ''}',
        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
      ),
      isThreeLine: p.note != null && p.note!.isNotEmpty,
      trailing: IconButton(
        icon: Icon(Icons.print_outlined,
            color: Colors.green.shade700, size: 20),
        tooltip: 'Print Receipt',
        onPressed: onPrint,
      ),
    );
  }
}

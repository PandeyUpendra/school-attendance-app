import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/student.dart';
import '../models/fee.dart';
import '../services/student_service.dart';
import '../services/fee_service.dart';
import '../utils/currency_utils.dart';
import '../utils/pdf_theme.dart';

class GuardianFeeReceiptsScreen extends StatefulWidget {
  final String className;
  final int roll;

  const GuardianFeeReceiptsScreen({
    super.key,
    required this.className,
    required this.roll,
  });

  @override
  State<GuardianFeeReceiptsScreen> createState() => _GuardianFeeReceiptsScreenState();
}

class _GuardianFeeReceiptsScreenState extends State<GuardianFeeReceiptsScreen> {
  final _studentService = StudentService.instance;
  final _feeService = FeeService();

  bool _loading = true;
  Student? _student;
  FeeStructure? _structure;
  double _totalPaid = 0;
  double _due = 0;
  List<Payment> _payments = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _studentService.getStudentByRoll(widget.className, widget.roll, section: ''),
        _feeService.getFeeStructure(className: widget.className),
        _feeService.getTotalPaid(className: widget.className, roll: widget.roll),
        _feeService.getPayments(className: widget.className, roll: widget.roll, includeReversed: true),
      ]);
      final student = results[0] as Student?;
      final struct = results[1] as FeeStructure? ?? FeeStructure.empty(widget.className);
      final totalPaid = results[2] as double;
      final payments = results[3] as List<Payment>;
      final due = (struct.totalAnnualFee - totalPaid).clamp(0.0, double.infinity);
      if (!mounted) return;
      setState(() {
        _student = student;
        _structure = struct;
        _totalPaid = totalPaid;
        _due = due;
        _payments = payments;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  pw.Document _buildReceiptPdf(Payment p) {
    final doc = pw.Document();
    final s = _student!;
    final st = _structure!;
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a5,
      build: (pw.Context context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Center(
            child: pw.Text(
              p.reversed ? 'VOID / REVERSED RECEIPT' : 'FEE RECEIPT',
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
                color: p.reversed ? PdfColors.red : PdfTheme.primaryDark,
              ),
            ),
          ),
          if (p.reversed) ...[
            pw.SizedBox(height: 6),
            pw.Center(
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.red, width: 2)),
                child: pw.Text('VOID', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.red)),
              ),
            ),
          ],
          pw.SizedBox(height: 6),
          pw.Center(child: pw.Text('Receipt No: ${p.receiptNo}', style: const pw.TextStyle(fontSize: 11))),
          pw.Divider(height: 20, color: PdfTheme.primaryLight),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Student: ${s.name}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text('Date: ${p.paidOn.day}/${p.paidOn.month}/${p.paidOn.year}'),
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
              pw.Text('Amount Paid', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text('₹${CurrencyUtils.formatValues(p.amount)}', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfTheme.accent)),
            ],
          ),
          if (st.totalAnnualFee > 0) ...[
            pw.SizedBox(height: 8),
            pw.Text('Annual Fee: ${CurrencyUtils.formatRupees(st.totalAnnualFee)}'),
            pw.Text('Total Paid: ${CurrencyUtils.formatRupees(_totalPaid)}   Balance Due: ${CurrencyUtils.formatRupees(_due)}'),
          ],
          if (p.note != null && p.note!.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text('Note: ${p.note}'),
          ],
          pw.Divider(height: 24, color: PdfTheme.primaryLight),
          pw.Center(
            child: pw.Text('This is a computer-generated receipt.', style: const pw.TextStyle(fontSize: 9)),
          ),
        ],
      ),
    ));
    return doc;
  }

  Future<void> _printReceipt(Payment p) async {
    final doc = _buildReceiptPdf(p);
    await Printing.layoutPdf(onLayout: (format) async => doc.save(), name: 'receipt_${p.receiptNo}');
  }

  Future<void> _shareReceipt(Payment p) async {
    final doc = _buildReceiptPdf(p);
    await Printing.sharePdf(bytes: await doc.save(), filename: 'receipt_${p.receiptNo}.pdf');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Fee Receipts'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _payments.isEmpty
              ? const Center(child: Text('No receipts found'))
              : ListView.separated(
                  itemCount: _payments.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final p = _payments[i];
                    return ListTile(
                      title: Text('Receipt ${p.receiptNo.isEmpty ? "-" : p.receiptNo}'),
                      subtitle: Text('₹${CurrencyUtils.formatValues(p.amount)} • ${p.paidOn.day}/${p.paidOn.month}/${p.paidOn.year}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.print),
                            tooltip: 'Print',
                            onPressed: () => _printReceipt(p),
                          ),
                          IconButton(
                            icon: const Icon(Icons.share),
                            tooltip: 'Share',
                            onPressed: () => _shareReceipt(p),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

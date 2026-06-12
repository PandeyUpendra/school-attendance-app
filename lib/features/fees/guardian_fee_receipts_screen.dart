import '../../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';

import '../../models/student.dart';
import '../../models/fee.dart';
import '../../services/student_service.dart';
import '../../services/fee_service.dart';
import '../../shared/utils/currency_utils.dart';
import '../../shared/utils/pdf_theme.dart';
import '../../shared/providers/school_settings_provider.dart';

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

  double _getTuitionRatio() {
    final st = _structure;
    if (st == null || st.components.isEmpty) return 1.0;
    
    final tuitionComponents = st.components.where(
      (c) => c.name.toLowerCase().contains('tuition')
    );
    if (tuitionComponents.isEmpty) return 1.0;
    
    final annualTuition = tuitionComponents.fold<double>(
      0.0, (sum, c) => sum + c.amount
    );
    if (st.totalAnnualFee > 0) {
      return annualTuition / st.totalAnnualFee;
    }
    return 1.0;
  }

  pw.Document _buildReceiptPdf(Payment p) {
    final doc = pw.Document();
    final s = _student!;
    final st = _structure!;
    final settings = Provider.of<SchoolSettingsProvider>(context, listen: false);
    final schoolName = settings.schoolName;
    final schoolAddress = '${settings.schoolAddress}, ${settings.schoolCity}, ${settings.schoolState} - ${settings.schoolPinCode}';
    
    final tuitionRatio = _getTuitionRatio();
    final tuitionPaid = p.amount * tuitionRatio;
    final otherPaid = p.amount - tuitionPaid;

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a5,
      build: (pw.Context pdfCtx) => pw.Stack(
        children: [
          if (p.reversed)
            pw.Center(
              child: pw.Transform.rotate(
                angle: -0.5,
                child: pw.Text(
                  'VOID',
                  style: pw.TextStyle(
                    fontSize: 80,
                    fontWeight: pw.FontWeight.bold,
                    color: const PdfColor(1.0, 0.0, 0.0, 0.12),
                  ),
                ),
              ),
            ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  schoolName.toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfTheme.primaryDark,
                  ),
                ),
              ),
              if (settings.schoolAddress.isNotEmpty)
                pw.Center(
                  child: pw.Text(
                    schoolAddress,
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                  ),
                ),
              pw.SizedBox(height: 8),
              pw.Center(
                child: pw.Text(
                  p.reversed ? 'VOID / REVERSED RECEIPT' : 'FEE RECEIPT',
                  style: pw.TextStyle(
                    fontSize: 16,
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
                  pw.Text(context.tr('amountPaid'), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text('₹${CurrencyUtils.formatValues(p.amount)}', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfTheme.accent)),
                ],
              ),
              
              pw.SizedBox(height: 6),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Tuition Fee (Sec 80C eligible)', style: const pw.TextStyle(fontSize: 9)),
                  pw.Text('₹${CurrencyUtils.formatValues(tuitionPaid)}', style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Other Component Fees', style: const pw.TextStyle(fontSize: 9)),
                  pw.Text('₹${CurrencyUtils.formatValues(otherPaid)}', style: const pw.TextStyle(fontSize: 9)),
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
        ],
      ),
    ));
    return doc;
  }

  pw.Document _buildTaxCertificatePdf() {
    final doc = pw.Document();
    final s = _student!;
    final settings = Provider.of<SchoolSettingsProvider>(context, listen: false);
    
    final activePayments = _payments.where((p) => !p.reversed).toList();
    final totalPaidAmt = activePayments.fold<double>(0.0, (sum, p) => sum + p.amount);
    
    final tuitionRatio = _getTuitionRatio();
    final totalTuitionPaid = totalPaidAmt * tuitionRatio;
    final totalOtherPaid = totalPaidAmt - totalTuitionPaid;
    
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (pw.Context context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Center(
            child: pw.Text(
              settings.schoolName.toUpperCase(),
              style: pw.TextStyle(
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
                color: PdfTheme.primaryDark,
              ),
            ),
          ),
          if (settings.schoolAddress.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                '${settings.schoolAddress}, ${settings.schoolCity}, ${settings.schoolState} - ${settings.schoolPinCode}',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
            ),
          ],
          if (settings.schoolPhone.isNotEmpty || settings.schoolEmail.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                'Phone: ${settings.schoolPhone}  |  Email: ${settings.schoolEmail}',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
            ),
          ],
          if (settings.board.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                'Affiliated to ${settings.board}',
                style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic, color: PdfColors.grey700),
              ),
            ),
          ],
          
          pw.Divider(height: 30, color: PdfTheme.primary, thickness: 1.5),
          
          pw.SizedBox(height: 10),
          
          pw.Center(
            child: pw.Text(
              'TUITION FEE CERTIFICATE',
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
                color: PdfTheme.primaryDark,
                decoration: pw.TextDecoration.underline,
              ),
            ),
          ),
          pw.Center(
            child: pw.Text(
              'For the Purpose of Section 80C of the Income Tax Act, 1961',
              style: const pw.TextStyle(
                fontSize: 9,
                color: PdfColors.grey600,
              ),
            ),
          ),
          
          pw.SizedBox(height: 30),
          
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Ref No: TXC-${DateTime.now().year}-${s.roll}-${s.admissionId.hashCode.abs()}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
              ),
              pw.Text(
                'Date: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
              ),
            ],
          ),
          
          pw.SizedBox(height: 30),
          
          pw.RichText(
            text: pw.TextSpan(
              style: const pw.TextStyle(fontSize: 11, color: PdfColors.black, height: 1.5),
              children: [
                const pw.TextSpan(text: 'This is to certify that '),
                pw.TextSpan(text: s.name, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                const pw.TextSpan(text: ', son/daughter of '),
                pw.TextSpan(text: s.fatherName.isNotEmpty ? s.fatherName : (s.motherName ?? 'Guardian'), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                const pw.TextSpan(text: ', is a bonafide student of class '),
                pw.TextSpan(text: s.className, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                if (s.section.isNotEmpty) ...[
                  const pw.TextSpan(text: ' (Section: '),
                  pw.TextSpan(text: s.section, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  const pw.TextSpan(text: ')'),
                ],
                const pw.TextSpan(text: ', Roll No: '),
                pw.TextSpan(text: '${s.roll}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                const pw.TextSpan(text: ', Admission No: '),
                pw.TextSpan(text: s.admissionId, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                const pw.TextSpan(text: ', in our institution.'),
              ],
            ),
          ),
          
          pw.SizedBox(height: 15),
          
          pw.Paragraph(
            text: 'Certified that the school has received fees for the academic year ${settings.academicYearStart} ${DateTime.now().year - 1} to ${DateTime.now().year} as per the payment history details listed below. Out of the total amount paid, the portion eligible for tax deduction under Section 80C is detailed below:',
            style: const pw.TextStyle(fontSize: 11, height: 1.5),
          ),
          
          pw.SizedBox(height: 20),
          
          pw.TableHelper.fromTextArray(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfTheme.primary),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {
              1: pw.Alignment.centerRight,
            },
            headers: ['Fee Category / Description', 'Amount Paid (INR)'],
            data: [
              ['Tuition Fee Component (Eligible under Sec 80C)', 'Rs. ${CurrencyUtils.formatValues(totalTuitionPaid, showDecimals: true)}'],
              ['Other Component Fees (Not eligible under Sec 80C)', 'Rs. ${CurrencyUtils.formatValues(totalOtherPaid, showDecimals: true)}'],
              ['Total Fees Paid (Net of Reversals)', 'Rs. ${CurrencyUtils.formatValues(totalPaidAmt, showDecimals: true)}'],
            ],
          ),
          
          pw.SizedBox(height: 30),
          
          pw.Text(
            'Total Tuition Fee Eligible (in words): Rupees ${_convertToWords(totalTuitionPaid.toInt())} Only',
            style: pw.TextStyle(fontStyle: pw.FontStyle.italic, fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          
          pw.SizedBox(height: 50),
          
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(width: 120, height: 1, color: PdfColors.black),
                  pw.SizedBox(height: 4),
                  pw.Text('School Accountant', style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.SizedBox(height: 15),
                  pw.Text('(School Seal)', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Container(width: 120, height: 1, color: PdfColors.black),
                  pw.SizedBox(height: 4),
                  pw.Text('Principal / Authorized Signatory', style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
            ],
          ),
          
          pw.Spacer(),
          
          pw.Divider(color: PdfColors.grey300),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              'Declaration: This certificate is issued to enable the parent/guardian to claim deduction under Section 80C of the Income Tax Act, 1961.',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
            ),
          ),
          pw.Center(
            child: pw.Text(
              'This is a certified school document generated on behalf of ${settings.schoolName}.',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
            ),
          ),
        ],
      ),
    ));
    return doc;
  }

  String _convertToWords(int number) {
    if (number == 0) return 'Zero';
    final units = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 
                   'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'];
    final tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];
    
    String convertLessThanOneThousand(int n) {
      String current;
      if (n % 100 < 20) {
        current = units[n % 100];
        n = (n / 100).truncate();
      } else {
        current = units[n % 10];
        n = (n / 10).truncate();
        current = '${tens[n % 10]} $current';
        n = (n / 10).truncate();
      }
      if (n == 0) return current.trim();
      return '${units[n]} Hundred $current'.trim();
    }
    
    var numStr = '';
    var temp = number;
    
    if (temp >= 10000000) { // Crore
      final crore = (temp / 10000000).truncate();
      numStr = '$numStr ${convertLessThanOneThousand(crore)} Crore';
      temp = temp % 10000000;
    }
    
    if (temp >= 100000) { // Lakh
      final lakh = (temp / 100000).truncate();
      numStr = '$numStr ${convertLessThanOneThousand(lakh)} Lakh';
      temp = temp % 100000;
    }
    
    if (temp >= 1000) { // Thousand
      final thousand = (temp / 1000).truncate();
      numStr = '$numStr ${convertLessThanOneThousand(thousand)} Thousand';
      temp = temp % 1000;
    }
    
    if (temp > 0) {
      numStr = '$numStr ${convertLessThanOneThousand(temp)}';
    }
    
    return numStr.trim();
  }

  Future<void> _printReceipt(Payment p) async {
    final doc = _buildReceiptPdf(p);
    await Printing.layoutPdf(onLayout: (format) async => doc.save(), name: 'receipt_${p.receiptNo}');
  }

  Future<void> _shareReceipt(Payment p) async {
    final doc = _buildReceiptPdf(p);
    await Printing.sharePdf(bytes: await doc.save(), filename: 'receipt_${p.receiptNo}.pdf');
  }

  Future<void> _printTaxCertificate() async {
    final doc = _buildTaxCertificatePdf();
    final name = _student?.name ?? 'student';
    await Printing.layoutPdf(
      onLayout: (format) async => doc.save(),
      name: 'tax_certificate_${name.replaceAll(" ", "_")}',
    );
  }

  Future<void> _shareTaxCertificate() async {
    final doc = _buildTaxCertificatePdf();
    final name = _student?.name ?? 'student';
    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: 'tax_certificate_${name.replaceAll(" ", "_")}.pdf',
    );
  }

  Widget _buildTaxCertificateCard() {
    final activePayments = _payments.where((p) => !p.reversed).toList();
    if (activePayments.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.teal.shade100, width: 1),
      ),
      color: Colors.teal.shade50.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.receipt_long_outlined, color: Colors.teal),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Section 80C Tax Certificate',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.teal,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Consolidated tuition fee statement for tax claims.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.print, color: Colors.teal),
                  tooltip: 'Print Certificate',
                  onPressed: _printTaxCertificate,
                ),
                IconButton(
                  icon: const Icon(Icons.share, color: Colors.teal),
                  tooltip: 'Share Certificate',
                  onPressed: _shareTaxCertificate,
                ),
              ],
            ),
          ],
        ),
      ),
    );
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
              : Column(
                  children: [
                    _buildTaxCertificateCard(),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
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
                    ),
                  ],
                ),
    );
  }
}


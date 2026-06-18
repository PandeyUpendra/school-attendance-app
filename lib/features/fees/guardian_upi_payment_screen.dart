import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/fee.dart';
import '../../models/student.dart';
import '../../shared/providers/school_settings_provider.dart';
import '../../services/auth_service.dart';
import '../../theme.dart';
import '../../shared/utils/currency_utils.dart';
import '../../l10n/app_strings.dart';

class GuardianUpiPaymentScreen extends StatefulWidget {
  final Student student;
  final FeeStructure structure;
  final double outstandingAmount;

  const GuardianUpiPaymentScreen({
    super.key,
    required this.student,
    required this.structure,
    required this.outstandingAmount,
  });

  @override
  State<GuardianUpiPaymentScreen> createState() => _GuardianUpiPaymentScreenState();
}

class _GuardianUpiPaymentScreenState extends State<GuardianUpiPaymentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _txnIdController = TextEditingController();
  final _noteController = TextEditingController();

  String? _selectedInstallment;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // Default to paying the full outstanding amount
    _amountController.text = widget.outstandingAmount.toStringAsFixed(2);
    
    // Default select first unpaid installment if available
    if (widget.structure.installments.isNotEmpty) {
      _selectedInstallment = widget.structure.installments.first.name;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _txnIdController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _payViaUpi(String merchantUpiId, String merchantName) async {
    if (!_formKey.currentState!.validate()) return;

    final amountStr = _amountController.text.trim();
    final amount = double.tryParse(amountStr) ?? 0.0;
    if (amount <= 0) return;

    // Build UPI URL Scheme
    // upi://pay?pa=merchant@upi&pn=MerchantName&am=Amount&cu=INR&tn=Description
    final note = 'Fee - ${widget.student.name} (Roll ${widget.student.roll}, ${widget.student.className})';
    final uriString = 'upi://pay'
        '?pa=$merchantUpiId'
        '&pn=${Uri.encodeComponent(merchantName)}'
        '&am=${amount.toStringAsFixed(2)}'
        '&cu=INR'
        '&tn=${Uri.encodeComponent(note)}';

    final uri = Uri.parse(uriString);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('upiAppLaunched')),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } else {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(context.tr('upiAppNotFound')),
            content: Text(context.tr('upiAppNotFoundDesc')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(context.tr('ok')),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _submitClaim() async {
    if (!_formKey.currentState!.validate()) return;

    final txnId = _txnIdController.text.trim();
    if (txnId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('pleaseEnterTxnId')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final amountStr = _amountController.text.trim();
    final amount = double.tryParse(amountStr) ?? 0.0;
    if (amount <= 0) return;

    setState(() => _submitting = true);

    try {
      final session = await AuthService().getSession();
      final email = session?['email'] as String? ?? 'guardian';
      final schoolId = AuthService.currentSchoolId;

      final db = FirebaseFirestore.instance;
      final ref = db
          .collection('schools')
          .doc(schoolId)
          .collection('payment_claims')
          .doc();

      final claimPayload = {
        'id': ref.id,
        'studentName': widget.student.name,
        'className': widget.student.className,
        'section': widget.student.section,
        'roll': widget.student.roll,
        'amount': amount,
        'installmentName': _selectedInstallment,
        'transactionId': txnId,
        'status': 'pending',
        'note': _noteController.text.trim(),
        'submittedAt': FieldValue.serverTimestamp(),
        'submittedBy': email,
      };

      await ref.set(claimPayload);

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 28),
                const SizedBox(width: 8),
                Text(context.tr('claimSubmitted')),
              ],
            ),
            content: Text(context.tr('claimSubmittedDesc')),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx); // Close dialog
                  Navigator.pop(context); // Back to dashboard
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                ),
                child: Text(context.tr('backToPortal')),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('errorSubmittingClaim').replaceAll('{error}', e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SchoolSettingsProvider>(context);
    final schoolName = settings.schoolName;
    
    // Get merchant UPI id from config if added, else use a placeholder VPA
    final rawComm = settings.rawComm;
    final merchantUpiId = rawComm['upiId'] as String? ?? 'schoolapp@ybl';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(context.tr('payFeesViaUpi')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Info Card
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('studentDetails'),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.student.name,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        context.tr('classAndRoll')
                            .replaceAll('{class}', widget.student.className)
                            .replaceAll('{roll}', widget.student.roll.toString()),
                        style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                      ),
                      const Divider(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${context.tr('outstandingDue')}:', style: const TextStyle(fontSize: 14)),
                          Text(
                            CurrencyUtils.formatRupees(widget.outstandingAmount),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.danger),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              Text(
                context.tr('paymentOptions'),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 8),

              // Installment selection (if configured)
              if (widget.structure.installments.isNotEmpty) ...[
                DropdownButtonFormField<String>(
                  value: _selectedInstallment,
                  decoration: InputDecoration(
                    labelText: context.tr('selectInstallment'),
                    fillColor: Colors.white,
                    filled: true,
                  ),
                  items: widget.structure.installments.map((i) {
                    return DropdownMenuItem<String>(
                      value: i.name,
                      child: Text('${i.name} (${CurrencyUtils.formatRupees(i.amount)})'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedInstallment = val;
                      final inst = widget.structure.installments.firstWhere((i) => i.name == val);
                      _amountController.text = inst.amount.toStringAsFixed(2);
                    });
                  },
                ),
                const SizedBox(height: 12),
              ],

              // Amount Input
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: context.tr('amountToPay'),
                  fillColor: Colors.white,
                  filled: true,
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return context.tr('pleaseEnterAmount');
                  final amt = double.tryParse(val.trim());
                  if (amt == null || amt <= 0) return context.tr('pleaseEnterValidAmount');
                  if (amt > widget.outstandingAmount) return context.tr('amountExceedsOutstanding');
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Pay Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () => _payViaUpi(merchantUpiId, schoolName),
                  icon: const Icon(Icons.flash_on_outlined),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                  ),
                  label: Text(context.tr('payViaUpi'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 24),

              const Divider(height: 32),

              // Verification Claim Details
              Text(
                context.tr('submitPaymentProof'),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                context.tr('submitPaymentProofDesc'),
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 12),

              // Transaction ID
              TextFormField(
                controller: _txnIdController,
                decoration: InputDecoration(
                  labelText: context.tr('upiTransactionId'),
                  hintText: context.tr('upiTransactionIdHint'),
                  fillColor: Colors.white,
                  filled: true,
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return context.tr('pleaseEnterTransactionId');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Payment Note
              TextFormField(
                controller: _noteController,
                decoration: InputDecoration(
                  labelText: context.tr('paymentNote'),
                  hintText: context.tr('paymentNoteHint'),
                  fillColor: Colors.white,
                  filled: true,
                ),
              ),
              const SizedBox(height: 20),

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submitClaim,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(context.tr('submitClaimToSchool'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}

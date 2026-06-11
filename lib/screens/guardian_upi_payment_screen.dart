import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/fee.dart';
import '../models/student.dart';
import '../providers/school_settings_provider.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../utils/currency_utils.dart';

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
          const SnackBar(
            content: Text('UPI App launched. After payment completes, please paste the Transaction ID below.'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 8),
          ),
        );
      }
    } else {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('UPI App Not Found'),
            content: const Text(
              'No UPI payment apps (like GPay, PhonePe, Paytm) were detected on this device. '
              'You can still transfer the amount manually to the school bank account, '
              'or enter the transaction details if you paid using another device.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
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
        const SnackBar(
          content: Text('Please enter the UPI Transaction ID / UTR reference number.'),
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
                const Text('Claim Submitted'),
              ],
            ),
            content: const Text(
              'Your payment claim has been submitted successfully. '
              'School administrators will verify the receipt of funds and approve this claim. '
              'Once approved, your fee status will be updated automatically.',
            ),
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
                child: const Text('Back to Portal'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error submitting claim: $e'),
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
        title: const Text('Pay Fees via UPI'),
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
                      const Text(
                        'Student Details',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.student.name,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Class ${widget.student.className} • Roll ${widget.student.roll}',
                        style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                      ),
                      const Divider(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Outstanding Dues:', style: TextStyle(fontSize: 14)),
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

              const Text(
                'Payment Options',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 8),

              // Installment selection (if configured)
              if (widget.structure.installments.isNotEmpty) ...[
                DropdownButtonFormField<String>(
                  value: _selectedInstallment,
                  decoration: const InputDecoration(
                    labelText: 'Select Installment',
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
                decoration: const InputDecoration(
                  labelText: 'Amount to Pay (₹)',
                  fillColor: Colors.white,
                  filled: true,
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Please enter amount';
                  final amt = double.tryParse(val.trim());
                  if (amt == null || amt <= 0) return 'Please enter a valid amount';
                  if (amt > widget.outstandingAmount) return 'Amount exceeds total outstanding fees';
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
                  label: const Text('Pay via UPI Apps (PhonePe/GPay)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 24),

              const Divider(height: 32),

              // Verification Claim Details
              const Text(
                'Submit Payment Proof',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 4),
              const Text(
                'After transferring the money, please enter the transaction reference details to confirm receipt of fees.',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 12),

              // Transaction ID
              TextFormField(
                controller: _txnIdController,
                decoration: const InputDecoration(
                  labelText: 'UPI Transaction ID / Reference (UTR)',
                  hintText: '12-digit number (e.g., 314567890123)',
                  fillColor: Colors.white,
                  filled: true,
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter transaction ID / UTR reference';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Payment Note
              TextFormField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: 'Payment Note (Optional)',
                  hintText: 'e.g., Paid via father\'s GPay account',
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
                      : const Text('Submit Claim to School', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
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

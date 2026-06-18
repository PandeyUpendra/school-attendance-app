import '../../l10n/app_strings.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/fee.dart';
import '../../models/student.dart';
import '../../services/auth_service.dart';
import '../../services/fee_service.dart';
import '../../theme.dart';
import '../../shared/utils/app_logger.dart';
import '../../shared/utils/currency_utils.dart';
import '../../shared/utils/class_name_utils.dart';
import '../../shared/utils/app_transitions.dart';

class PaymentClaimsVerificationScreen extends StatefulWidget {
  const PaymentClaimsVerificationScreen({super.key});

  @override
  State<PaymentClaimsVerificationScreen> createState() => _PaymentClaimsVerificationScreenState();
}

class _PaymentClaimsVerificationScreenState extends State<PaymentClaimsVerificationScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Stream<List<Map<String, dynamic>>> _watchClaims(String status) {
    final schoolId = AuthService.currentSchoolId;
    return FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('payment_claims')
        .where('status', isEqualTo: status)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('UPI Payment Claims'),
        backgroundColor: AppTheme.primaryDark,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Approved'),
            Tab(text: 'Rejected'),
          ],
        ),
      ),
      body: PremiumTabBarView(
        controller: _tabController,
        children: [
          _buildClaimsList('pending'),
          _buildClaimsList('approved'),
          _buildClaimsList('rejected'),
        ],
      ),
    );
  }

  Widget _buildClaimsList(String status) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _watchClaims(status),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error loading claims: ${snapshot.error}'));
        }

        final claims = snapshot.data ?? [];
        if (claims.isEmpty) {
          return _buildEmptyState(status);
        }

        // Sort by submittedAt descending
        claims.sort((a, b) {
          final tsA = a['submittedAt'] as Timestamp?;
          final tsB = b['submittedAt'] as Timestamp?;
          if (tsA == null || tsB == null) return 0;
          return tsB.compareTo(tsA);
        });

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: claims.length,
          itemBuilder: (context, index) {
            final claim = claims[index];
            return _buildClaimCard(claim, status);
          },
        );
      },
    );
  }

  Widget _buildEmptyState(String status) {
    IconData icon;
    String message;
    switch (status) {
      case 'approved':
        icon = Icons.verified_outlined;
        message = 'No approved claims yet';
        break;
      case 'rejected':
        icon = Icons.cancel_outlined;
        message = 'No rejected claims';
        break;
      default:
        icon = Icons.hourglass_empty;
        message = 'No pending UPI payment claims!';
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildClaimCard(Map<String, dynamic> claim, String status) {
    final studentName = claim['studentName'] as String? ?? 'Student';
    final className = claim['className'] as String? ?? '';
    final section = claim['section'] as String? ?? '';
    final roll = claim['roll'] as int? ?? 0;
    final amount = (claim['amount'] as num?)?.toDouble() ?? 0.0;
    final installment = claim['installmentName'] as String?;
    final txnId = claim['transactionId'] as String? ?? '';
    final note = claim['note'] as String? ?? '';
    
    final submittedTs = claim['submittedAt'] as Timestamp?;
    final submittedDate = submittedTs?.toDate() ?? DateTime.now();
    final timeStr = '${submittedDate.day}/${submittedDate.month} at ${submittedDate.hour}:${submittedDate.minute.toString().padLeft(2, '0')}';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppTheme.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row: Student details & Amount
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        studentName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary),
                      ),
                      Text(
                        'Class ${ClassName.format(className, section)} · Roll $roll',
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Text(
                  CurrencyUtils.formatRupees(amount, showDecimals: true),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.primary),
                ),
              ],
            ),
            const Divider(height: 24),
            
            // Transaction details
            _buildDetailRow('UPI Ref (UTR):', txnId, trailing: IconButton(
              icon: const Icon(Icons.copy, size: 16, color: AppTheme.primary),
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: txnId));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Transaction ID copied'), duration: Duration(seconds: 1)),
                );
              },
            )),
            if (installment != null) _buildDetailRow('Installment:', installment),
            _buildDetailRow('Submitted:', '$timeStr by ${claim['submittedBy'] ?? ''}'),
            if (note.isNotEmpty) _buildDetailRow('Parent Note:', note),
            
            // Verification metadata for verified/rejected claims
            if (status != 'pending') ...[
              const Divider(height: 24),
              if (status == 'approved') ...[
                Row(
                  children: [
                    const Icon(Icons.verified, color: AppTheme.success, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Approved by ${claim['verifiedBy'] ?? ''}',
                      style: const TextStyle(color: AppTheme.success, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
              ] else if (status == 'rejected') ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.cancel, color: AppTheme.danger, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Rejected by ${claim['verifiedBy'] ?? ''}',
                            style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                          if (claim['rejectionReason'] != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Reason: ${claim['rejectionReason']}',
                                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],

            // Action buttons for pending claims
            if (status == 'pending') ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.danger,
                      side: const BorderSide(color: AppTheme.danger),
                    ),
                    onPressed: () => _rejectClaim(claim),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Approve & Add Receipt'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.success,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => _approveClaim(claim),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.textSecondary),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _approveClaim(Map<String, dynamic> claim) async {
    final studentName = claim['studentName'] as String? ?? 'Student';
    final className = claim['className'] as String? ?? '';
    final roll = claim['roll'] as int? ?? 0;
    final amount = (claim['amount'] as num?)?.toDouble() ?? 0.0;
    final txnId = claim['transactionId'] as String? ?? '';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve Payment Claim?'),
        content: Text(
          'Confirm that UPI transfer of ${CurrencyUtils.formatRupees(amount)} with reference UTR $txnId '
          'for student $studentName has been received in the school bank account?\n\n'
          'This will automatically log the payment and generate a fee receipt.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Approve & Save'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (!mounted) return;

    // Show loading spinner
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final userEmail = AuthService().currentFirebaseUser?.email ?? 'coordinator@schoolapp.org';
      final schoolId = AuthService.currentSchoolId;

      // 1. Log payment in fee_payments ledger
      final payment = Payment(
        id: '', // Generated dynamically
        amount: amount,
        paidOn: DateTime.now(),
        mode: 'UPI',
        receiptNo: '', // Sequential receipt generated server side
        installmentName: claim['installmentName'],
        note: 'Approved UPI Claim: $txnId. Parent Note: ${claim['note'] ?? ''}',
        enteredBy: userEmail,
      );

      final section = claim['section'] as String? ?? '';
      final studentId = Student.buildDocId(roll, className, section);

      await FeeService().addPayment(
        className: className,
        roll: roll,
        payment: payment,
        clientTxnId: 'upi_${claim['id']}', // Idempotency key from claim ID
        studentId: studentId,
      );

      // 2. Mark claim document as approved
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('payment_claims')
          .doc(claim['id'])
          .update({
        'status': 'approved',
        'verifiedBy': userEmail,
        'verifiedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context); // Close loading spinner
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('UPI Claim approved & receipt created'), backgroundColor: AppTheme.success),
        );
      }
    } catch (e) {
      AppLogger.e('PaymentClaimsVerificationScreen', 'Approval failed: $e');
      if (mounted) {
        Navigator.pop(context); // Close loading spinner
        final message = e is FeeOverpaymentException ? e.message : 'Verification failed: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  Future<void> _rejectClaim(Map<String, dynamic> claim) async {
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Payment Claim?'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Please specify the reason for rejecting this claim (e.g., Funds not received, incorrect transaction reference).'),
              const SizedBox(height: 12),
              TextFormField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'Rejection Reason *',
                  border: OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter a reason';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            child: Text(context.tr('rejectClaim')),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (!mounted) return;

    // Show loading spinner
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final userEmail = AuthService().currentFirebaseUser?.email ?? 'coordinator@schoolapp.org';
      final schoolId = AuthService.currentSchoolId;

      await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('payment_claims')
          .doc(claim['id'])
          .update({
        'status': 'rejected',
        'rejectionReason': reasonController.text.trim(),
        'verifiedBy': userEmail,
        'verifiedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context); // Close loading spinner
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('UPI Claim rejected successfully'), backgroundColor: AppTheme.danger),
        );
      }
    } catch (e) {
      AppLogger.e('PaymentClaimsVerificationScreen', 'Rejection failed: $e');
      if (mounted) {
        Navigator.pop(context); // Close loading spinner
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to reject claim: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }
}

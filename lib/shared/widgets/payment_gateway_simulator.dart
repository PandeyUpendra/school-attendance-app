import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/fee_service.dart';
import '../../models/fee.dart';
import '../../theme.dart';
import '../../shared/utils/currency_utils.dart';
import '../../l10n/app_strings.dart';

class PaymentGatewaySimulator extends StatefulWidget {
  final String className;
  final int roll;
  final String studentId;
  final double amount;
  final VoidCallback onSuccess;
  final Function(String) onFailure;

  const PaymentGatewaySimulator({
    super.key,
    required this.className,
    required this.roll,
    required this.studentId,
    required this.amount,
    required this.onSuccess,
    required this.onFailure,
  });

  static void show(
    BuildContext context, {
    required String className,
    required int roll,
    required String studentId,
    required double amount,
    required VoidCallback onSuccess,
    required Function(String) onFailure,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: PaymentGatewaySimulator(
          className: className,
          roll: roll,
          studentId: studentId,
          amount: amount,
          onSuccess: onSuccess,
          onFailure: onFailure,
        ),
      ),
    );
  }

  @override
  State<PaymentGatewaySimulator> createState() => _PaymentGatewaySimulatorState();
}

class _PaymentGatewaySimulatorState extends State<PaymentGatewaySimulator> {
  int _step = 0; // 0 = Input, 1 = Processing, 2 = Success, 3 = Failure
  String _paymentMethod = 'UPI'; // 'UPI' | 'Card'
  final _upiController = TextEditingController(text: 'parent@okhdfcbank');
  final _cardNumberController = TextEditingController(text: '4111 2222 3333 4444');
  final _cardExpiryController = TextEditingController(text: '12/29');
  final _cardCvvController = TextEditingController(text: '123');
  final _cardNameController = TextEditingController(text: 'Guardian User');

  String _currentMilestone = '';
  double _progress = 0.1;
  String _receiptNo = '';
  String _failureReason = '';

  @override
  void dispose() {
    _upiController.dispose();
    _cardNumberController.dispose();
    _cardExpiryController.dispose();
    _cardCvvController.dispose();
    _cardNameController.dispose();
    super.dispose();
  }

  void _startSimulation(bool simulateSuccess) async {
    setState(() {
      _step = 1;
      _progress = 0.1;
      _currentMilestone = context.tr('initiatingSecurePayment');
    });

    final milestones = [
      context.tr('connectingSecureGateway'),
      context.tr('verifyingAccountCredentials'),
      context.tr('authorizingTransactionAmount'),
      context.tr('reconcilingPaymentsLedger'),
      context.tr('generatingReceiptClosing')
    ];

    // Run milestones simulation with visual updates
    for (int i = 0; i < milestones.length; i++) {
      await Future.delayed(const Duration(milliseconds: 650));
      if (!mounted) return;
      setState(() {
        _currentMilestone = milestones[i];
        if (i == 2) {
          _currentMilestone = context.tr('authorizingTransactionAmount') + ' ${CurrencyUtils.formatRupees(widget.amount)}...';
        }
        _progress = 0.2 + (i * 0.15);
      });
    }

    if (!simulateSuccess) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      setState(() {
        _step = 3;
        _failureReason = context.tr('mockDeclinedReason');
      });
      widget.onFailure(_failureReason);
      return;
    }

    // Attempt to write payment to Firestore
    try {
      final clientTxnId = 'MOCK_TXN_${DateTime.now().millisecondsSinceEpoch}';
      final payment = Payment(
        id: '',
        amount: widget.amount,
        paidOn: DateTime.now(),
        mode: _paymentMethod == 'UPI' ? 'UPI' : 'Bank',
        receiptNo: '',
        note: 'Online Gateway Simulator (${_paymentMethod})',
        reconciled: true,
      );

      final receipt = await FeeService().addPayment(
        className: widget.className,
        roll: widget.roll,
        payment: payment,
        clientTxnId: clientTxnId,
        studentId: widget.studentId,
      );

      if (!mounted) return;
      setState(() {
        _receiptNo = receipt;
        _step = 2;
        _progress = 1.0;
      });

      // Give user time to see success checkmark before calling success callback
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) {
          Navigator.pop(context);
          widget.onSuccess();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = 3;
        _failureReason = e.toString();
      });
      widget.onFailure(_failureReason);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          if (_step == 0) _buildInputStep(),
          if (_step == 1) _buildProcessingStep(),
          if (_step == 2) _buildSuccessStep(),
          if (_step == 3) _buildFailureStep(),
        ],
      ),
    );
  }

  Widget _buildInputStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              context.tr('securePaymentGateway'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.primary,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined, size: 14, color: Colors.amber),
                  const SizedBox(width: 4),
                  Text(
                    context.tr('simulatorMode'),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Amount summary
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                context.tr('totalAmountToPay'),
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textSecondary,
                ),
              ),
              Text(
                CurrencyUtils.formatRupees(widget.amount),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Method selector
        Row(
          children: [
            Expanded(
              child: _methodButton('UPI', Icons.qr_code_outlined),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _methodButton('Card', Icons.credit_card_outlined),
            ),
          ],
        ),
        const SizedBox(height: 16),

        if (_paymentMethod == 'UPI') ...[
          Text(
            context.tr('enterUpiId'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _upiController,
            decoration: InputDecoration(
              hintText: 'user@upi',
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.primary),
              ),
            ),
          ),
        ] else ...[
          Text(
            context.tr('cardDetails'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _cardNumberController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: context.tr('cardNumber'),
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.border),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cardExpiryController,
                  decoration: const InputDecoration(
                    hintText: 'MM/YY',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _cardCvvController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    hintText: 'CVV',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),

        // Action buttons: Success/Failure simulations
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _startSimulation(false),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.danger),
                  foregroundColor: AppTheme.danger,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(context.tr('simulateFailure'), style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () => _startSimulation(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(context.tr('simulateSuccess'), style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _methodButton(String method, IconData icon) {
    final active = _paymentMethod == method;
    return InkWell(
      onTap: () => setState(() => _paymentMethod = method),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: active ? AppTheme.primary.withValues(alpha: 0.05) : Colors.white,
          border: Border.all(
            color: active ? AppTheme.primary : AppTheme.border,
            width: active ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: active ? AppTheme.primary : AppTheme.textSecondary),
            const SizedBox(height: 6),
            Text(
              method,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: active ? AppTheme.primary : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProcessingStep() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              strokeWidth: 4,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _currentMilestone,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _progress,
              color: AppTheme.primary,
              backgroundColor: Colors.grey.shade100,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('percentCompleted').replaceAll('{percent}', (_progress * 100).round().toString()),
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessStep() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: AppTheme.successLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle,
              color: AppTheme.success,
              size: 48,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            context.tr('paymentSuccessful'),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.success,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('receiptNoColon').replaceAll('{receiptNo}', _receiptNo),
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('reconcilingSchoolSystem'),
            style: const TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFailureStep() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: AppTheme.dangerLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.error_outline,
              color: AppTheme.danger,
              size: 48,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            context.tr('paymentFailed'),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.danger,
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _failureReason,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.red.shade900,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  _step = 0;
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(context.tr('retry'), style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}

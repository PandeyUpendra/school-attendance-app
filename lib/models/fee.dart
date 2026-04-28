import 'package:cloud_firestore/cloud_firestore.dart';

/// Fee structure for a single class — stored as a single doc per class.
class FeeStructure {
  final String className;
  final double totalAnnualFee;
  final List<FeeComponent> components;

  const FeeStructure({
    required this.className,
    required this.totalAnnualFee,
    required this.components,
  });

  Map<String, dynamic> toJson() => {
        'className': className,
        'totalAnnualFee': totalAnnualFee,
        'components': components.map((c) => c.toJson()).toList(),
      };

  factory FeeStructure.fromJson(Map<String, dynamic> json) => FeeStructure(
        className: json['className'] as String? ?? '',
        totalAnnualFee:
            (json['totalAnnualFee'] as num?)?.toDouble() ?? 0,
        components: ((json['components'] as List?) ?? const [])
            .map((c) => FeeComponent.fromJson(
                Map<String, dynamic>.from(c as Map)))
            .toList(),
      );

  /// Default structure if none has been configured yet.
  factory FeeStructure.empty(String className) => FeeStructure(
        className: className,
        totalAnnualFee: 0,
        components: const [],
      );
}

class FeeComponent {
  final String name;   // e.g. 'Tuition', 'Transport', 'Exam'
  final double amount;

  const FeeComponent({required this.name, required this.amount});

  Map<String, dynamic> toJson() => {'name': name, 'amount': amount};

  factory FeeComponent.fromJson(Map<String, dynamic> json) => FeeComponent(
        name:   json['name']   as String? ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
      );
}

/// A single payment record.
class Payment {
  final String   id;
  final double   amount;
  final DateTime paidOn;
  final String   mode;        // 'Cash' | 'UPI' | 'Bank' | 'Cheque'
  final String   receiptNo;   // auto-generated
  final String?  note;

  const Payment({
    required this.id,
    required this.amount,
    required this.paidOn,
    required this.mode,
    required this.receiptNo,
    this.note,
  });

  Map<String, dynamic> toJson() => {
        'amount':    amount,
        'paidOn':    Timestamp.fromDate(paidOn),
        'mode':      mode,
        'receiptNo': receiptNo,
        'note':      note,
      };

  factory Payment.fromDoc(String id, Map<String, dynamic> data) {
    final ts = data['paidOn'];
    return Payment(
      id:       id,
      amount:   (data['amount']  as num?)?.toDouble() ?? 0,
      paidOn:   ts is Timestamp ? ts.toDate() : DateTime.now(),
      mode:    (data['mode']      as String?) ?? 'Cash',
      receiptNo:(data['receiptNo'] as String?) ?? '',
      note:    (data['note']       as String?),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

/// Fee structure for a single class — stored as a single doc per class.
class FeeStructure {
  final String className;
  final double totalAnnualFee;
  final List<FeeComponent>   components;
  final List<FeeInstallment> installments;

  const FeeStructure({
    required this.className,
    required this.totalAnnualFee,
    required this.components,
    this.installments = const [],
  });

  Map<String, dynamic> toJson() => {
        'className':     className,
        'totalAnnualFee': totalAnnualFee,
        'components':    components.map((c) => c.toJson()).toList(),
        'installments':  installments.map((i) => i.toJson()).toList(),
      };

  factory FeeStructure.fromJson(Map<String, dynamic> json) => FeeStructure(
        className:      json['className']      as String? ?? '',
        totalAnnualFee: (json['totalAnnualFee'] as num?)?.toDouble() ?? 0,
        components:     ((json['components']   as List?) ?? const [])
            .map((c) => FeeComponent.fromJson(
                Map<String, dynamic>.from(c as Map)))
            .toList(),
        installments:   ((json['installments'] as List?) ?? const [])
            .map((i) => FeeInstallment.fromJson(
                Map<String, dynamic>.from(i as Map)))
            .toList(),
      );

  /// Default structure if none has been configured yet.
  factory FeeStructure.empty(String className) => FeeStructure(
        className:      className,
        totalAnnualFee: 0,
        components:     const [],
        installments:   const [],
      );
}

// ─── Fee component (breakdown item, e.g. Tuition / Transport) ────────────────

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

// ─── Installment (scheduled payment slot, e.g. Term 1 / April) ───────────────

/// A scheduled fee instalment — Term 1, Q2, Monthly-April, etc.
/// Defined at the class level (FeeStructure), tracked per-student via Payment.installmentName.
class FeeInstallment {
  final String   name;     // e.g. 'Term 1', 'April', 'Q1'
  final double   amount;
  final DateTime dueDate;

  const FeeInstallment({
    required this.name,
    required this.amount,
    required this.dueDate,
  });

  Map<String, dynamic> toJson() => {
        'name':    name,
        'amount':  amount,
        'dueDate': Timestamp.fromDate(dueDate),
      };

  factory FeeInstallment.fromJson(Map<String, dynamic> json) {
    final ts = json['dueDate'];
    return FeeInstallment(
      name:    json['name']   as String? ?? '',
      amount:  (json['amount'] as num?)?.toDouble() ?? 0,
      dueDate: ts is Timestamp ? ts.toDate() : DateTime.now(),
    );
  }
}

// ─── Payment (single payment record) ─────────────────────────────────────────

/// A single payment record.
class Payment {
  final String   id;
  final double   amount;
  final DateTime paidOn;
  final String   mode;          // 'Cash' | 'UPI' | 'Bank' | 'Cheque'
  final String   receiptNo;     // auto-generated
  final String?  note;
  final String?  installmentName; // optional — which FeeInstallment this covers

  const Payment({
    required this.id,
    required this.amount,
    required this.paidOn,
    required this.mode,
    required this.receiptNo,
    this.note,
    this.installmentName,
  });

  Map<String, dynamic> toJson() => {
        'amount':          amount,
        'paidOn':          Timestamp.fromDate(paidOn),
        'mode':            mode,
        'receiptNo':       receiptNo,
        'note':            note,
        'installmentName': installmentName,
      };

  factory Payment.fromDoc(String id, Map<String, dynamic> data) {
    final ts = data['paidOn'];
    return Payment(
      id:              id,
      amount:          (data['amount']          as num?)?.toDouble() ?? 0,
      paidOn:          ts is Timestamp ? ts.toDate() : DateTime.now(),
      mode:            (data['mode']             as String?) ?? 'Cash',
      receiptNo:       (data['receiptNo']        as String?) ?? '',
      note:            (data['note']             as String?),
      installmentName: (data['installmentName']  as String?),
    );
  }
}

// ─── ClassFeeSummary (aggregated per-class data for overview screen) ──────────

class ClassFeeSummary {
  final String className;
  final int    studentCount;
  final int    fullyPaid;      // students who paid >= totalAnnualFee
  final double totalDue;       // totalAnnualFee * studentCount
  final double totalCollected;
  final double totalAnnualFee; // per student

  const ClassFeeSummary({
    required this.className,
    required this.studentCount,
    required this.fullyPaid,
    required this.totalDue,
    required this.totalCollected,
    required this.totalAnnualFee,
  });

  double get collectionPct =>
      totalDue > 0 ? (totalCollected / totalDue).clamp(0.0, 1.0) : 0.0;
  double get pendingAmount => (totalDue - totalCollected).clamp(0.0, double.infinity);
}

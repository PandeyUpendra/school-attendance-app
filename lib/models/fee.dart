import 'package:cloud_firestore/cloud_firestore.dart';

/// Money is stored canonically as **integer paise** (1 rupee = 100 paise) to
/// eliminate the floating-point rounding drift that accumulates when many
/// `double` amounts are summed (review #31). The public API still exposes
/// rupees as `double` getters so call sites and UI are unchanged; only the
/// stored representation and arithmetic changed.
///
/// • Storage: each money field is written as `<field>Paise` (int) AND the legacy
///   rupee `double` field (for any older reader during the transition).
/// • Reading: the paise field is preferred; a legacy doc without it falls back
///   to the rupee field, rounded to the nearest paisa.
/// • Backfill of existing docs: functions/scripts/backfill_paise.js (idempotent).
int rupeesToPaise(num rupees) => (rupees * 100).round();
double paiseToRupees(int paise) => paise / 100.0;

int _readPaise(Map<String, dynamic> json, String paiseKey, String rupeeKey) {
  final p = json[paiseKey];
  if (p is int) return p;
  if (p is num) return p.round();
  final r = json[rupeeKey];
  return r is num ? rupeesToPaise(r) : 0;
}

/// Fee structure for a single class — stored as a single doc per class.
class FeeStructure {
  final String className;
  final int totalAnnualFeePaise;
  final List<FeeComponent>   components;
  final List<FeeInstallment> installments;

  /// Rupee view of the annual fee (display/compat).
  double get totalAnnualFee => paiseToRupees(totalAnnualFeePaise);

  /// Construct from a rupee amount (UI/legacy call sites stay unchanged).
  FeeStructure({
    required this.className,
    required double totalAnnualFee,
    required this.components,
    this.installments = const [],
  }) : totalAnnualFeePaise = rupeesToPaise(totalAnnualFee);

  const FeeStructure._paise({
    required this.className,
    required this.totalAnnualFeePaise,
    required this.components,
    this.installments = const [],
  });

  Map<String, dynamic> toJson() => {
        'className':            className,
        'totalAnnualFeePaise': totalAnnualFeePaise,
        // Legacy rupee field kept for backward-compatible readers.
        'totalAnnualFee':      totalAnnualFee,
        'components':          components.map((c) => c.toJson()).toList(),
        'installments':        installments.map((i) => i.toJson()).toList(),
      };

  factory FeeStructure.fromJson(Map<String, dynamic> json) => FeeStructure._paise(
        className:           json['className'] as String? ?? '',
        totalAnnualFeePaise: _readPaise(json, 'totalAnnualFeePaise', 'totalAnnualFee'),
        components:          ((json['components']   as List?) ?? const [])
            .map((c) => FeeComponent.fromJson(
                Map<String, dynamic>.from(c as Map)))
            .toList(),
        installments:        ((json['installments'] as List?) ?? const [])
            .map((i) => FeeInstallment.fromJson(
                Map<String, dynamic>.from(i as Map)))
            .toList(),
      );

  /// Default structure if none has been configured yet.
  factory FeeStructure.empty(String className) => FeeStructure._paise(
        className:           className,
        totalAnnualFeePaise: 0,
        components:          const [],
        installments:        const [],
      );
}

// ─── Fee component (breakdown item, e.g. Tuition / Transport) ────────────────

class FeeComponent {
  final String name;   // e.g. 'Tuition', 'Transport', 'Exam'
  final int amountPaise;

  double get amount => paiseToRupees(amountPaise);

  FeeComponent({required this.name, required double amount})
      : amountPaise = rupeesToPaise(amount);

  const FeeComponent._paise({required this.name, required this.amountPaise});

  Map<String, dynamic> toJson() =>
      {'name': name, 'amountPaise': amountPaise, 'amount': amount};

  factory FeeComponent.fromJson(Map<String, dynamic> json) => FeeComponent._paise(
        name:        json['name'] as String? ?? '',
        amountPaise: _readPaise(json, 'amountPaise', 'amount'),
      );
}

// ─── Installment (scheduled payment slot, e.g. Term 1 / April) ───────────────

/// A scheduled fee instalment — Term 1, Q2, Monthly-April, etc.
/// Defined at the class level (FeeStructure), tracked per-student via Payment.installmentName.
class FeeInstallment {
  final String   name;     // e.g. 'Term 1', 'April', 'Q1'
  final int      amountPaise;
  final DateTime dueDate;

  double get amount => paiseToRupees(amountPaise);

  FeeInstallment({
    required this.name,
    required double amount,
    required this.dueDate,
  }) : amountPaise = rupeesToPaise(amount);

  const FeeInstallment._paise({
    required this.name,
    required this.amountPaise,
    required this.dueDate,
  });

  Map<String, dynamic> toJson() => {
        'name':        name,
        'amountPaise': amountPaise,
        'amount':      amount,
        'dueDate':     Timestamp.fromDate(dueDate),
      };

  factory FeeInstallment.fromJson(Map<String, dynamic> json) {
    final ts = json['dueDate'];
    return FeeInstallment._paise(
      name:        json['name'] as String? ?? '',
      amountPaise: _readPaise(json, 'amountPaise', 'amount'),
      dueDate:     ts is Timestamp ? ts.toDate() : DateTime.now(),
    );
  }
}

// ─── Payment (single payment record) ─────────────────────────────────────────

/// A single payment record.
class Payment {
  final String   id;
  final int      amountPaise;
  final DateTime paidOn;
  final String   mode;          // 'Cash' | 'UPI' | 'Bank' | 'Cheque'
  final String   receiptNo;     // auto-generated
  final String?  note;
  final String?  installmentName; // optional — which FeeInstallment this covers
  final bool     reversed;        // soft-reversal flag (money records are never hard-deleted)

  double get amount => paiseToRupees(amountPaise);

  Payment({
    required this.id,
    required double amount,
    required this.paidOn,
    required this.mode,
    required this.receiptNo,
    this.note,
    this.installmentName,
    this.reversed = false,
  }) : amountPaise = rupeesToPaise(amount);

  const Payment._paise({
    required this.id,
    required this.amountPaise,
    required this.paidOn,
    required this.mode,
    required this.receiptNo,
    this.note,
    this.installmentName,
    this.reversed = false,
  });

  Map<String, dynamic> toJson() => {
        'amountPaise':     amountPaise,
        // Legacy rupee field kept for backward-compatible readers.
        'amount':          amount,
        'paidOn':          Timestamp.fromDate(paidOn),
        'mode':            mode,
        'receiptNo':       receiptNo,
        'note':            note,
        'installmentName': installmentName,
        'reversed':        reversed,
      };

  factory Payment.fromDoc(String id, Map<String, dynamic> data) {
    final ts = data['paidOn'];
    return Payment._paise(
      id:              id,
      amountPaise:     _readPaise(data, 'amountPaise', 'amount'),
      paidOn:          ts is Timestamp ? ts.toDate() : DateTime.now(),
      mode:            (data['mode']             as String?) ?? 'Cash',
      receiptNo:       (data['receiptNo']        as String?) ?? '',
      note:            (data['note']             as String?),
      installmentName: (data['installmentName']  as String?),
      reversed:        (data['reversed']         as bool?)   ?? false,
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

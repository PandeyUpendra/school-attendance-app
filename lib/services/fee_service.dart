import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/fee.dart';

/// Firestore-backed fee management service.
///
/// Schema:
///   fee_structures/{className}  → FeeStructure doc
///   fee_payments/{className}/students/{roll}/payments/{auto} → Payment doc
class FeeService {
  static final _db   = FirebaseFirestore.instance;
  static final _feeStructures = _db.collection('fee_structures');

  static final FeeService _instance = FeeService._();
  FeeService._();
  factory FeeService() => _instance;

  CollectionReference _paymentsCol(String className, int roll) => _db
      .collection('fee_payments')
      .doc(className.replaceAll(' ', '_'))
      .collection('students')
      .doc('$roll')
      .collection('payments');

  // ── Fee Structure ──────────────────────────────────────────────────────────

  Future<FeeStructure> getFeeStructure({String? schoolId, required String className}) async {
    final doc =
        await _feeStructures.doc(className.replaceAll(' ', '_')).get();
    if (!doc.exists || doc.data() == null) {
      return FeeStructure.empty(className);
    }
    return FeeStructure.fromJson(
        Map<String, dynamic>.from(doc.data() as Map));
  }

  Future<void> saveFeeStructure({String? schoolId, required FeeStructure structure}) async {
    await _feeStructures
        .doc(structure.className.replaceAll(' ', '_'))
        .set(structure.toJson());
  }

  // ── Payments ───────────────────────────────────────────────────────────────

  Future<List<Payment>> getPayments({String? schoolId, required String className, required int roll}) async {
    final snap = await _paymentsCol(className, roll)
        .orderBy('paidOn', descending: true)
        .get();
    return snap.docs.map((d) {
      return Payment.fromDoc(d.id, Map<String, dynamic>.from(d.data() as Map));
    }).toList();
  }

  Future<void> addPayment({String? schoolId, required String className, required int roll, required Payment payment}) async {
    await _paymentsCol(className, roll).add(payment.toJson());
  }

  Future<double> getTotalPaid({String? schoolId, required String className, required int roll}) async {
    final payments = await getPayments(className: className, roll: roll);
    return payments.fold<double>(0.0, (sum, p) => sum + p.amount);
  }

  // ── Class-wide fee overview ────────────────────────────────────────────────

  /// Returns { roll → totalPaid } for every student in a class.
  /// Fires one query per student in parallel.
  Future<Map<int, double>> getClassFeeOverview({String? schoolId, required String className, required List<int> rolls}) async {
    if (rolls.isEmpty) return {};
    final futures = rolls.map((roll) async {
      final paid = await getTotalPaid(className: className, roll: roll);
      return MapEntry(roll, paid);
    });
    final entries = await Future.wait(futures);
    return Map.fromEntries(entries);
  }

  // ── School-wide summary ────────────────────────────────────────────────────

  /// Aggregates fee data across all students using fee_payments and fee_structures.
  /// Returns {collected, pending, overdue, defaulters}.
  /// collected  = students who have paid their full annual fee
  /// overdue    = students who have not made any payment at all
  /// pending    = students who have made partial payments
  Future<Map<String, dynamic>> getFeesSummary() async {
    final studentSnap = await _db.collection('students').get();

    final byClass = <String, List<Map<String, dynamic>>>{};
    for (final doc in studentSnap.docs) {
      final data = Map<String, dynamic>.from(doc.data() as Map);
      final cls = data['className'] as String? ?? '';
      if (cls.isEmpty) continue;
      byClass.putIfAbsent(cls, () => []).add(data);
    }

    double collected = 0, pending = 0, overdue = 0;
    final defaulters = <Map<String, dynamic>>[];

    for (final entry in byClass.entries) {
      final cls = entry.key;
      final studs = entry.value;
      final rolls = studs
          .map((s) => (s['roll'] as num?)?.toInt() ?? 0)
          .where((r) => r > 0)
          .toList();

      final results = await Future.wait([
        getFeeStructure(className: cls),
        getClassFeeOverview(className: cls, rolls: rolls),
      ]);

      final structure = results[0] as FeeStructure;
      final paidMap = results[1] as Map<int, double>;
      final totalDue = structure.totalAnnualFee;
      if (totalDue <= 0) continue;

      for (final sData in studs) {
        final roll = (sData['roll'] as num?)?.toInt() ?? 0;
        if (roll <= 0) continue;
        final paid = paidMap[roll] ?? 0;

        if (paid >= totalDue) {
          collected += totalDue;
        } else if (paid == 0) {
          overdue += totalDue;
          defaulters.add({
            'name': sData['name'] ?? '',
            'className': cls,
            'amount': totalDue,
            'daysOverdue': 0,
            'phone': sData['parentPhone'] ?? sData['phone'] ?? '',
          });
        } else {
          pending += totalDue - paid;
          defaulters.add({
            'name': sData['name'] ?? '',
            'className': cls,
            'amount': totalDue - paid,
            'daysOverdue': 0,
            'phone': sData['parentPhone'] ?? sData['phone'] ?? '',
          });
        }
      }
    }

    defaulters.sort(
        (a, b) => (b['amount'] as double).compareTo(a['amount'] as double));

    return {
      'collected': collected,
      'pending': pending,
      'overdue': overdue,
      'defaulters': defaulters,
    };
  }

  // ── Receipt numbering ──────────────────────────────────────────────────────

  /// Generates a receipt number in format RCP-{className 3 chars}-{roll}-{timestamp}.
  static String generateReceiptNo(String className, int roll) {
    final prefix = className.replaceAll(' ', '').substring(
        0, className.replaceAll(' ', '').length.clamp(0, 3)).toUpperCase();
    final ts = DateTime.now().millisecondsSinceEpoch % 100000;
    return 'RCP-$prefix-$roll-$ts';
  }
}

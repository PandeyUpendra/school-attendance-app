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

  Future<FeeStructure> getFeeStructure(String className) async {
    final doc =
        await _feeStructures.doc(className.replaceAll(' ', '_')).get();
    if (!doc.exists || doc.data() == null) {
      return FeeStructure.empty(className);
    }
    return FeeStructure.fromJson(
        Map<String, dynamic>.from(doc.data() as Map));
  }

  Future<void> saveFeeStructure(FeeStructure structure) async {
    await _feeStructures
        .doc(structure.className.replaceAll(' ', '_'))
        .set(structure.toJson());
  }

  // ── Payments ───────────────────────────────────────────────────────────────

  Future<List<Payment>> getPayments(String className, int roll) async {
    final snap = await _paymentsCol(className, roll)
        .orderBy('paidOn', descending: true)
        .get();
    return snap.docs.map((d) {
      return Payment.fromDoc(d.id, Map<String, dynamic>.from(d.data() as Map));
    }).toList();
  }

  Future<void> addPayment(
      String className, int roll, Payment payment) async {
    await _paymentsCol(className, roll).add(payment.toJson());
  }

  Future<double> getTotalPaid(String className, int roll) async {
    final payments = await getPayments(className, roll);
    return payments.fold<double>(0.0, (sum, p) => sum + p.amount);
  }

  // ── Class-wide fee overview ────────────────────────────────────────────────

  /// Returns { roll → totalPaid } for every student in a class.
  /// Fires one query per student in parallel.
  Future<Map<int, double>> getClassFeeOverview(
      String className, List<int> rolls) async {
    if (rolls.isEmpty) return {};
    final futures = rolls.map((roll) async {
      final paid = await getTotalPaid(className, roll);
      return MapEntry(roll, paid);
    });
    final entries = await Future.wait(futures);
    return Map.fromEntries(entries);
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

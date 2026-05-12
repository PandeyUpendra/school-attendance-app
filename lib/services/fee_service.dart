import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/fee.dart';
import 'base_firestore_service.dart';

/// Firestore-backed fee management service.
///
/// Schema:
///   fee_structures/{className}  → FeeStructure doc
///   fee_payments/{className}/students/{roll}/payments/{auto} → Payment doc
class FeeService extends BaseFirestoreService {
  static final FeeService _instance = FeeService._();
  FeeService._();
  factory FeeService() => _instance;

  CollectionReference _feeStructures(String schoolId) =>
      db.collection('schools').doc(schoolId).collection('fee_structures');

  CollectionReference _paymentsCol(String schoolId, String className, int roll) => db
      .collection('schools').doc(schoolId)
      .collection('fee_payments')
      .doc(className.replaceAll(' ', '_'))
      .collection('students')
      .doc('$roll')
      .collection('payments');

  // ── Fee Structure ──────────────────────────────────────────────────────────

  Future<FeeStructure> getFeeStructure({String? schoolId, required String className}) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    final doc =
        await _feeStructures(sId).doc(className.replaceAll(' ', '_')).get();
    if (!doc.exists || doc.data() == null) {
      return FeeStructure.empty(className);
    }
    return FeeStructure.fromJson(
        Map<String, dynamic>.from(doc.data() as Map));
  }

  Future<void> saveFeeStructure({String? schoolId, required FeeStructure structure}) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    await _feeStructures(sId)
        .doc(structure.className.replaceAll(' ', '_'))
        .set(structure.toJson());
  }

  // ── Payments ───────────────────────────────────────────────────────────────

  Future<List<Payment>> getPayments({String? schoolId, required String className, required int roll}) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    final snap = await _paymentsCol(sId, className, roll)
        .orderBy('paidOn', descending: true)
        .get();
    return snap.docs.map((d) {
      return Payment.fromDoc(d.id, Map<String, dynamic>.from(d.data() as Map));
    }).toList();
  }

  Future<void> addPayment({
    String? schoolId,
    required String className,
    required int roll,
    required Payment payment,
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    await _paymentsCol(sId, className, roll).add(payment.toJson());
  }

  Future<double> getTotalPaid({String? schoolId, required String className, required int roll}) async {
    final payments = await getPayments(schoolId: schoolId, className: className, roll: roll);
    return payments.fold<double>(0.0, (sum, p) => sum + p.amount);
  }

  // ── Class-wide fee overview ────────────────────────────────────────────────

  /// Returns { roll → totalPaid } for every student in a class.
  /// Fires one query per student in parallel.
  Future<Map<int, double>> getClassFeeOverview({
    String? schoolId,
    required String className,
    required List<int> rolls,
  }) async {
    if (rolls.isEmpty) return {};
    final futures = rolls.map((roll) async {
      final paid = await getTotalPaid(schoolId: schoolId, className: className, roll: roll);
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

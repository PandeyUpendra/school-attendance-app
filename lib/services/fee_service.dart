import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/fee.dart';
import 'audit_log_service.dart';

/// Firestore-backed fee management service.
///
/// Schema:
///   fee_structures/{className}  → FeeStructure doc (components + installments)
///   fee_payments/{className}/students/{roll}/payments/{auto} → Payment doc
class FeeService {
  static final _db            = FirebaseFirestore.instance;
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
    final docId = structure.className.replaceAll(' ', '_');
    final prev  = await _feeStructures.doc(docId).get();
    final before = prev.exists && prev.data() != null
        ? Map<String, dynamic>.from(prev.data()!)
        : null;
    await _feeStructures.doc(docId).set(structure.toJson());
    AuditService.emit(
      action:   before == null ? 'create' : 'update',
      entity:   'fee_structure',
      entityId: docId,
      before:   before,
      after:    structure.toJson(),
    );
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
    final ref = await _paymentsCol(className, roll).add(payment.toJson());
    AuditService.emit(
      action:   'create',
      entity:   'fee_payment',
      entityId: ref.id,
      after:    payment.toJson()
        ..['className'] = className
        ..['roll']      = roll,
    );
  }

  /// Deletes a single payment record. Logs a 'delete' audit entry.
  Future<void> deletePayment({
    required String className,
    required int    roll,
    required String paymentId,
  }) async {
    final doc = await _paymentsCol(className, roll).doc(paymentId).get();
    final before = doc.exists && doc.data() != null
        ? Map<String, dynamic>.from(doc.data()!)
        : null;
    await _paymentsCol(className, roll).doc(paymentId).delete();
    AuditService.emit(
      action:   'delete',
      entity:   'fee_payment',
      entityId: paymentId,
      before:   before,
    );
  }

  Future<double> getTotalPaid({String? schoolId, required String className, required int roll}) async {
    final payments = await getPayments(className: className, roll: roll);
    return payments.fold<double>(0.0, (acc, p) => acc + p.amount);
  }

  // ── Installment-aware helpers ──────────────────────────────────────────────

  /// Returns { installmentName → amountPaid } for a single student.
  /// Only payments that have an installmentName set are counted here.
  Future<Map<String, double>> getInstallmentPaidAmounts({
    required String className,
    required int    roll,
  }) async {
    final payments = await getPayments(className: className, roll: roll);
    final result   = <String, double>{};
    for (final p in payments) {
      final name = p.installmentName;
      if (name != null && name.isNotEmpty) {
        result[name] = (result[name] ?? 0) + p.amount;
      }
    }
    return result;
  }

  // ── Class-wide fee overview ────────────────────────────────────────────────

  /// Returns { roll → totalPaid } for every student in a class.
  Future<Map<int, double>> getClassFeeOverview({String? schoolId, required String className, required List<int> rolls}) async {
    if (rolls.isEmpty) return {};
    final futures = rolls.map((roll) async {
      final paid = await getTotalPaid(className: className, roll: roll);
      return MapEntry(roll, paid);
    });
    final entries = await Future.wait(futures);
    return Map.fromEntries(entries);
  }

  // ── School-wide class summaries (for FeeOverviewScreen) ───────────────────

  /// Returns one [ClassFeeSummary] per entry in [classes].
  /// Fires parallel requests per class; each class fires parallel per-student requests.
  Future<List<ClassFeeSummary>> getClassSummaries({
    required List<String> classes,
  }) async {
    if (classes.isEmpty) return [];

    // Load all students once
    final studentSnap = await _db.collection('students').get();
    final byClass = <String, List<Map<String, dynamic>>>{};
    for (final doc in studentSnap.docs) {
      final data = Map<String, dynamic>.from(doc.data() as Map);
      final cls  = data['className'] as String? ?? '';
      if (cls.isEmpty) continue;
      byClass.putIfAbsent(cls, () => []).add(data);
    }

    // Load structure + paid overview per class in parallel
    final futures = classes.map((cls) async {
      final studs = byClass[cls] ?? [];
      final rolls = studs
          .map((s) => (s['roll'] as num?)?.toInt() ?? 0)
          .where((r) => r > 0)
          .toList();

      final results = await Future.wait([
        getFeeStructure(className: cls),
        getClassFeeOverview(className: cls, rolls: rolls),
      ]);
      final structure = results[0] as FeeStructure;
      final paidMap   = results[1] as Map<int, double>;

      final totalCollected = paidMap.values.fold(0.0, (a, b) => a + b);
      final totalDue       = structure.totalAnnualFee * studs.length;
      final fullyPaid      = studs.where((s) {
        final r = (s['roll'] as num?)?.toInt() ?? 0;
        return r > 0 &&
            structure.totalAnnualFee > 0 &&
            (paidMap[r] ?? 0) >= structure.totalAnnualFee;
      }).length;

      return ClassFeeSummary(
        className:      cls,
        studentCount:   studs.length,
        fullyPaid:      fullyPaid,
        totalDue:       totalDue,
        totalCollected: totalCollected,
        totalAnnualFee: structure.totalAnnualFee,
      );
    });

    return Future.wait(futures);
  }

  // ── School-wide summary ────────────────────────────────────────────────────

  /// Aggregates fee data across all students.
  Future<Map<String, dynamic>> getFeesSummary() async {
    final studentSnap = await _db.collection('students').get();

    final byClass = <String, List<Map<String, dynamic>>>{};
    for (final doc in studentSnap.docs) {
      final data = Map<String, dynamic>.from(doc.data() as Map);
      final cls  = data['className'] as String? ?? '';
      if (cls.isEmpty) continue;
      byClass.putIfAbsent(cls, () => []).add(data);
    }

    double collected = 0, pending = 0, overdue = 0;
    final defaulters = <Map<String, dynamic>>[];

    for (final entry in byClass.entries) {
      final cls   = entry.key;
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
      final paidMap   = results[1] as Map<int, double>;
      final totalDue  = structure.totalAnnualFee;
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
            'name':      sData['name']       ?? '',
            'className': cls,
            'amount':    totalDue,
            'daysOverdue': 0,
            'phone':     sData['parentPhone'] ?? sData['phone'] ?? '',
          });
        } else {
          pending += totalDue - paid;
          defaulters.add({
            'name':      sData['name']       ?? '',
            'className': cls,
            'amount':    totalDue - paid,
            'daysOverdue': 0,
            'phone':     sData['parentPhone'] ?? sData['phone'] ?? '',
          });
        }
      }
    }

    defaulters.sort(
        (a, b) => (b['amount'] as double).compareTo(a['amount'] as double));

    return {
      'collected': collected,
      'pending':   pending,
      'overdue':   overdue,
      'defaulters': defaulters,
    };
  }

  // ── Receipt numbering ──────────────────────────────────────────────────────

  static String generateReceiptNo(String className, int roll) {
    final prefix = className.replaceAll(' ', '').substring(
        0, className.replaceAll(' ', '').length.clamp(0, 3)).toUpperCase();
    final ts = DateTime.now().millisecondsSinceEpoch % 100000;
    return 'RCP-$prefix-$roll-$ts';
  }
}

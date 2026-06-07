import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/fee.dart';
import 'audit_log_service.dart';
import 'auth_service.dart';
import 'base_firestore_service.dart';

/// Firestore-backed fee management service.
///
/// Schema (school-scoped):
///   schools/{schoolId}/fee_structures/{className}  → FeeStructure doc
///   schools/{schoolId}/fee_payments/{className}/students/{roll}/payments/{auto}
class FeeService extends BaseFirestoreService {
  static final FeeService _instance = FeeService._();
  FeeService._();
  factory FeeService() => _instance;

  String get _sid => AuthService.currentSchoolId;

  CollectionReference<Map<String, dynamic>> get _feeStructures =>
      schoolCollection(_sid, 'fee_structures');

  CollectionReference _paymentsCol(String className, int roll) =>
      schoolCollection(_sid, 'fee_payments')
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

  /// Per-school atomic receipt-number counter. Lives outside fee_payments so a
  /// single doc serialises receipt allocation across all cashiers/classes.
  DocumentReference<Map<String, dynamic>> get _receiptCounter =>
      schoolCollection(_sid, 'fee_meta').doc('counters');

  Future<List<Payment>> getPayments({String? schoolId, required String className, required int roll}) async {
    final snap = await _paymentsCol(className, roll)
        .orderBy('paidOn', descending: true)
        .get();
    return snap.docs
        .map((d) =>
            Payment.fromDoc(d.id, Map<String, dynamic>.from(d.data() as Map)))
        // Reversed payments are retained in Firestore (audit/recoverability)
        // but excluded from listings and every total (#53).
        .where((p) => !p.reversed)
        .toList();
  }

  /// Records a payment and returns its allocated receipt number.
  ///
  /// Runs in a single transaction that (a) allocates a GAPLESS, sequential
  /// receipt number from an atomic per-school counter — two cashiers can no
  /// longer collide, and the number is no longer a client-side timestamp
  /// (#46) — and (b) is IDEMPOTENT: pass a stable [clientTxnId] so a retry /
  /// double-submit writes to the same doc id instead of duplicating the
  /// payment (#48).
  Future<String> addPayment({
    String? schoolId,
    required String className,
    required int    roll,
    required Payment payment,
    String? clientTxnId,
  }) async {
    final col = _paymentsCol(className, roll);
    final ref = (clientTxnId != null && clientTxnId.isNotEmpty)
        ? col.doc(clientTxnId)
        : col.doc();

    final receiptNo = await db.runTransaction<String>((tx) async {
      // Idempotency guard — a retry with the same clientTxnId finds the doc
      // already written and reuses its receipt rather than allocating again.
      final existing = await tx.get(ref);
      if (existing.exists) {
        final data = Map<String, dynamic>.from(existing.data()! as Map);
        return (data['receiptNo'] as String?) ?? payment.receiptNo;
      }

      final counterSnap = await tx.get(_receiptCounter);
      final current = counterSnap.exists
          ? ((counterSnap.data()?['receiptSeq']) as num?)?.toInt() ?? 0
          : 0;
      final next = current + 1;
      final rno  = 'RCP-${DateTime.now().year}-${next.toString().padLeft(6, '0')}';

      final data = Map<String, dynamic>.from(payment.toJson())
        ..['receiptNo'] = rno
        // schoolId stamped so the collection-group payments query (EOD digest)
        // can be tenant-filtered once multi-tenancy lands (Phase 1 prep).
        ..['schoolId'] = _sid;
      tx.set(_receiptCounter, {'receiptSeq': next}, SetOptions(merge: true));
      tx.set(ref, data);
      return rno;
    });

    AuditService.emit(
      action:   'create',
      entity:   'fee_payment',
      entityId: ref.id,
      after:    payment.toJson()
        ..['className'] = className
        ..['roll']      = roll
        ..['receiptNo'] = receiptNo,
    );
    return receiptNo;
  }

  /// Reverses a payment. Money records are NEVER hard-deleted (#53): the doc is
  /// flagged `reversed` (excluded from listings/totals) and kept for audit and
  /// recoverability, rather than erased — so collection history can't be wiped.
  Future<void> deletePayment({
    required String className,
    required int    roll,
    required String paymentId,
    String? reason,
  }) async {
    final ref = _paymentsCol(className, roll).doc(paymentId);
    final doc = await ref.get();
    final before = doc.exists && doc.data() != null
        ? Map<String, dynamic>.from(doc.data()! as Map)
        : null;
    await ref.set({
      'reversed':       true,
      'reversedAt':     FieldValue.serverTimestamp(),
      if (reason != null && reason.isNotEmpty) 'reversedReason': reason,
    }, SetOptions(merge: true));
    AuditService.emit(
      action:   'reverse',
      entity:   'fee_payment',
      entityId: paymentId,
      before:   before,
    );
  }

  Future<double> getTotalPaid({String? schoolId, required String className, required int roll}) async {
    final payments = await getPayments(className: className, roll: roll);
    // Sum in integer paise, then convert once — no floating-point drift (#31).
    final paise = payments.fold<int>(0, (acc, p) => acc + p.amountPaise);
    return paiseToRupees(paise);
  }

  // ── Installment-aware helpers ──────────────────────────────────────────────

  /// Returns { installmentName → amountPaid } for a single student.
  /// Only payments that have an installmentName set are counted here.
  Future<Map<String, double>> getInstallmentPaidAmounts({
    required String className,
    required int    roll,
  }) async {
    final payments = await getPayments(className: className, roll: roll);
    final paise    = <String, int>{};
    for (final p in payments) {
      final name = p.installmentName;
      if (name != null && name.isNotEmpty) {
        paise[name] = (paise[name] ?? 0) + p.amountPaise;
      }
    }
    return paise.map((k, v) => MapEntry(k, paiseToRupees(v)));
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
    final studentSnap = await schoolCollection(_sid, 'students').get();
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

      // Aggregate in integer paise to avoid floating-point drift (#31).
      final totalCollected = paiseToRupees(
          paidMap.values.fold<int>(0, (a, b) => a + rupeesToPaise(b)));
      final totalDue       =
          paiseToRupees(structure.totalAnnualFeePaise * studs.length);
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
    final studentSnap = await schoolCollection(_sid, 'students').get();

    final byClass = <String, List<Map<String, dynamic>>>{};
    for (final doc in studentSnap.docs) {
      final data = Map<String, dynamic>.from(doc.data() as Map);
      final cls  = data['className'] as String? ?? '';
      if (cls.isEmpty) continue;
      byClass.putIfAbsent(cls, () => []).add(data);
    }

    // Accumulate in integer paise (no float drift, #31) and convert once.
    //   collected = actual cash received, capped per student at the amount due
    //   pending   = total outstanding (due − paid) across all students
    //   overdue   = the outstanding portion whose instalment due-date has passed
    // Previously "collected" added the full due ONLY for fully-paid students, so
    // partial payments contributed nothing and the figure never reconciled with
    // the receipt ledger (#32); defaulters reported the wrong amount (#33).
    int collectedP = 0, pendingP = 0, overdueP = 0;
    final defaulters = <Map<String, dynamic>>[];
    final now = DateTime.now();

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
      final duePaise  = structure.totalAnnualFeePaise;
      if (duePaise <= 0) continue;

      for (final sData in studs) {
        final roll = (sData['roll'] as num?)?.toInt() ?? 0;
        if (roll <= 0) continue;
        final paidPaise = rupeesToPaise(paidMap[roll] ?? 0);

        // Cash actually collected toward this student's fee, capped at the due.
        collectedP += paidPaise < duePaise ? paidPaise : duePaise;

        final shortfallPaise = duePaise - paidPaise;
        if (shortfallPaise > 0) {
          pendingP += shortfallPaise;
          final days = _daysOverdue(structure, paiseToRupees(paidPaise), now);
          if (days > 0) overdueP += shortfallPaise;
          defaulters.add({
            'name':      sData['name'] ?? '',
            'className': cls,
            'amount':    paiseToRupees(shortfallPaise),
            'daysOverdue': days,
            'phone':     sData['parentPhone'] ?? sData['phone'] ?? '',
          });
        }
      }
    }

    final collected = paiseToRupees(collectedP);
    final pending   = paiseToRupees(pendingP);
    final overdue   = paiseToRupees(overdueP);

    // num→double so a stored int amount can't throw on the cast (#158).
    defaulters.sort((a, b) =>
        (b['amount'] as num).toDouble().compareTo((a['amount'] as num).toDouble()));

    return {
      'collected': collected,
      'pending':   pending,
      'overdue':   overdue,
      'defaulters': defaulters,
    };
  }

  // Receipt numbers are now allocated atomically inside [addPayment] from a
  // per-school counter (gapless + collision-free), replacing the old
  // client-side timestamp generator (#46, #155).

  /// Days a student's fee has been overdue, derived from the class instalment
  /// schedule: the gap between today and the earliest instalment due-date that
  /// the student's payments do not yet cover. Returns 0 when fully covered, not
  /// yet due, or when no instalment schedule is configured (can't age without a
  /// due date) — replacing the hardcoded 0 in the defaulters report (#51).
  static int _daysOverdue(FeeStructure structure, double paid, DateTime now) {
    if (structure.installments.isEmpty) return 0;
    final schedule = [...structure.installments]
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    var cumulative = 0.0;
    for (final inst in schedule) {
      cumulative += inst.amount;
      if (paid < cumulative) {
        // This is the earliest instalment not fully covered by payments.
        return inst.dueDate.isBefore(now)
            ? now.difference(inst.dueDate).inDays
            : 0;
      }
    }
    return 0;
  }
}

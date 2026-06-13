import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../shared/utils/app_logger.dart';
import '../models/fee.dart';
import 'audit_log_service.dart';
import 'auth_service.dart';
import 'base_firestore_service.dart';

/// Raised when a payment would push a student's total paid past the annual fee.
class FeeOverpaymentException implements Exception {
  final String message;
  FeeOverpaymentException(this.message);
  @override
  String toString() => message;
}

/// Firestore-backed fee management service.
///
/// Schema (school-scoped):
///   schools/{schoolId}/fee_structures/{className}  → FeeStructure doc
///   schools/{schoolId}/fee_payments/{className}/students/{roll}/payments/{auto}
class FeeService extends BaseFirestoreService {
  static FeeService? _instance;
  FeeService._();
  factory FeeService() => _instance ??= FeeService._();
  static set mockInstance(FeeService? mock) => _instance = mock;

  String get _sid => AuthService.currentSchoolId;

  CollectionReference<Map<String, dynamic>> get _feeStructures =>
      schoolCollection(_sid, 'fee_structures');

  CollectionReference<Map<String, dynamic>> _paymentsCol() =>
      schoolCollection(_sid, 'payments');

  // ── Masking Helper ─────────────────────────────────────────────────────────

  String maskSensitiveInfo(String input) {
    // Match 13 to 19 digit card/account numbers (allowing spaces or hyphens)
    final cardRegex = RegExp(r'\b(?:\d[ -]*?){13,19}\b');
    return input.replaceAllMapped(cardRegex, (match) {
      final clean = match.group(0)!.replaceAll(RegExp(r'\D'), '');
      if (clean.length >= 13 && clean.length <= 19) {
        return '****-****-****-${clean.substring(clean.length - 4)}';
      }
      return match.group(0)!;
    });
  }

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
    if (structure.installments.isNotEmpty) {
      final sum = structure.installments.map((i) => i.amountPaise).fold(0, (a, b) => a + b);
      if (sum != structure.totalAnnualFeePaise) {
        throw ArgumentError(
            'The sum of installment amounts (₹${paiseToRupees(sum).toStringAsFixed(2)}) '
            'must equal the total annual fee (₹${structure.totalAnnualFee.toStringAsFixed(2)}).');
      }
    }
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

  Future<List<Payment>> getPayments({
    String? schoolId,
    required String className,
    required int roll,
    bool includeReversed = false,
  }) async {
    final snap = await _paymentsCol()
        .where('className', isEqualTo: className)
        .where('roll', isEqualTo: roll)
        .orderBy('paidOn', descending: true)
        .get();
    final all = snap.docs
        .map((d) =>
            Payment.fromDoc(d.id, Map<String, dynamic>.from(d.data() as Map)))
        .toList();
    // Reversed payments are retained in Firestore (audit/recoverability) and by
    // default excluded from listings and every total (#53). Pass
    // [includeReversed] for the reconciliation view (#26/#49) which shows voided
    // receipts so the gapless receipt numbers are accounted for.
    return includeReversed ? all : all.where((p) => !p.reversed).toList();
  }

  /// Records a payment and returns its allocated receipt number.
  ///
  /// Runs in a single transaction that (a) allocates a GAPLESS, sequential
  /// receipt number from an atomic per-school counter — two cashiers can no
  /// longer collide, and the number is no longer a client-side timestamp
  /// (#46) — and (b) is IDEMPOTENT: pass a stable [clientTxnId] so a retry /
  /// double-submit writes to the same doc id instead of duplicating the
  /// payment (#48).
  /// Thrown by [addPayment] when a payment would push the student's total paid
  /// past the configured annual fee. Callers can pass `enforceCap: false` to
  /// deliberately allow it (e.g. recording an advance/adjustment).
  Future<String> addPayment({
    String? schoolId,
    required String className,
    required int    roll,
    required Payment payment,
    String? clientTxnId,
    bool enforceCap = true,
    String? studentId,
  }) async {
    // Sanitize and validate payment mode input (#663)
    const allowedModes = {'Cash', 'UPI', 'Bank', 'Cheque'};
    if (!allowedModes.contains(payment.mode)) {
      throw ArgumentError(
          'Invalid payment mode "${payment.mode}". Allowed modes: ${allowedModes.join(", ")}');
    }

    // Sanitize and mask sensitive info in note (#664)
    final sanitizedNote = payment.note != null ? maskSensitiveInfo(payment.note!) : null;

    final col = _paymentsCol();
    final ref = (clientTxnId != null && clientTxnId.isNotEmpty)
        ? col.doc(clientTxnId)
        : col.doc();

    final studentFeeDocRef = schoolCollection(_sid, 'fee_payments')
        .doc(className.replaceAll(' ', '_'))
        .collection('students')
        .doc('$roll');

    final structureDocRef = _feeStructures.doc(className.replaceAll(' ', '_'));

    // Cold-start fallback calculation outside transaction
    final initialPaidPaise = rupeesToPaise(
        await getTotalPaid(className: className, roll: roll));

    final receiptNo = await db.runTransaction<String>((tx) async {
      // Idempotency guard — a retry with the same clientTxnId finds the doc
      // already written and reuses its receipt rather than allocating again.
      final existing = await tx.get(ref);
      if (existing.exists) {
        final data = Map<String, dynamic>.from(existing.data()! as Map);
        return (data['receiptNo'] as String?) ?? payment.receiptNo;
      }

      var capPaise = 0;

      // Read student custom feeAmount if studentId is provided (#24)
      if (studentId != null && studentId.isNotEmpty) {
        final studentSnap = await tx.get(
            db.collection('schools').doc(_sid).collection('students').doc(studentId));
        if (studentSnap.exists && studentSnap.data() != null) {
          final data = studentSnap.data() as Map?;
          final customFee = (data?['feeAmount'] as num?)?.toDouble();
          if (customFee != null) {
            capPaise = rupeesToPaise(customFee);
          }
        }
      }

      // Read Fee Structure to get cap and check installments (#655)
      final structureSnap = await tx.get(structureDocRef);
      final validInstallmentNames = <String>{};
      if (structureSnap.exists && structureSnap.data() != null) {
        final struct = FeeStructure.fromJson(
            Map<String, dynamic>.from(structureSnap.data()!));
        validInstallmentNames.addAll(struct.installments.map((i) => i.name));
        if (capPaise == 0) {
          capPaise = struct.totalAnnualFeePaise;
        }
      }

      // Validate installment name if provided (#655)
      final instName = payment.installmentName;
      if (instName != null && instName.isNotEmpty) {
        if (!validInstallmentNames.contains(instName)) {
          throw ArgumentError(
              'Invalid installment name "$instName". Must match one of the configured installments: ${validInstallmentNames.join(", ")}');
        }
      }

      // Read current total paid from student summary doc to prevent race conditions (#651)
      final studentFeeSnap = await tx.get(studentFeeDocRef);
      var alreadyPaise = 0;
      if (studentFeeSnap.exists && studentFeeSnap.data() != null && studentFeeSnap.data()?['totalPaidPaise'] != null) {
        alreadyPaise = (studentFeeSnap.data()?['totalPaidPaise'] as num).toInt();
      } else {
        alreadyPaise = initialPaidPaise;
      }

      // Enforce cap check inside transaction (#651)
      if (enforceCap && !payment.reversed) {
        if (capPaise > 0) {
          if (alreadyPaise + payment.amountPaise > capPaise) {
            final remaining = paiseToRupees(
                (capPaise - alreadyPaise).clamp(0, capPaise));
            throw FeeOverpaymentException(
                'Payment exceeds the outstanding due of '
                '₹${remaining.toStringAsFixed(0)}.');
          }
        }
      }

      // Allocate receipt sequence atomically (#654)
      final counterSnap = await tx.get(_receiptCounter);
      final current = counterSnap.exists
          ? ((counterSnap.data()?['receiptSeq']) as num?)?.toInt() ?? 0
          : 0;
      final next = current + 1;

      // Determine academic year prefix dynamically (#32)
      var prefixYear = DateTime.now().year;
      try {
        final academicSnap = await tx.get(schoolCollection(_sid, 'settings').doc('academic'));
        if (academicSnap.exists && academicSnap.data() != null) {
          final academicYearStart = (academicSnap.data()?['academicYearStart'] as String?) ?? 'April';
          const months = {
            'January': 1, 'February': 2, 'March': 3, 'April': 4, 'May': 5, 'June': 6,
            'July': 7, 'August': 8, 'September': 9, 'October': 10, 'November': 11, 'December': 12
          };
          final startMonth = months[academicYearStart] ?? 4;
          final now = DateTime.now();
          if (now.month < startMonth) {
            prefixYear = now.year - 1;
          }
        }
      } catch (_) {}

      final rno  = 'RCP-$prefixYear-${next.toString().padLeft(6, '0')}';

      final currentEmail = AuthService().currentFirebaseUser?.email ?? 'coordinator@schoolapp.org';
      final data = Map<String, dynamic>.from(payment.toJson())
        ..['receiptNo'] = rno
        ..['schoolId'] = _sid
        ..['className'] = className
        ..['roll'] = roll
        ..['note'] = sanitizedNote
        ..['enteredBy'] = payment.enteredBy ?? currentEmail
        ..['reconciled'] = payment.reconciled;
      if (studentId != null && studentId.isNotEmpty) {
        data['studentId'] = studentId;
      }
      tx.set(_receiptCounter, {'receiptSeq': next}, SetOptions(merge: true));
      tx.set(ref, data);

      // Update student fee summary metadata doc (#651)
      final newTotal = (alreadyPaise + payment.amountPaise).toInt();
      tx.set(studentFeeDocRef, {'totalPaidPaise': newTotal}, SetOptions(merge: true));

      // Update parent class summary document to cache rolls map for O(1) overview reads (#25)
      final classKey = className.replaceAll(' ', '_');
      final classDocRef = schoolCollection(_sid, 'fee_payments').doc(classKey);
      tx.set(classDocRef, {
        'rolls': {
          '$roll': newTotal,
        }
      }, SetOptions(merge: true));

      return rno;
    });

    AuditService.emit(
      action:   'create',
      entity:   'fee_payment',
      entityId: ref.id,
      after:    payment.toJson()
        ..['className'] = className
        ..['roll']      = roll
        ..['receiptNo'] = receiptNo
        ..['note']      = sanitizedNote,
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
    required String reason,
  }) async {
    if (reason.trim().isEmpty) {
      throw ArgumentError('Reversal reason is required');
    }
    final ref = _paymentsCol().doc(paymentId);
    final studentFeeDocRef = schoolCollection(_sid, 'fee_payments')
        .doc(className.replaceAll(' ', '_'))
        .collection('students')
        .doc('$roll');

    // Run in transaction to decrement totalPaidPaise atomically (#651)
    await db.runTransaction((tx) async {
      final doc = await tx.get(ref);
      if (!doc.exists) return;
      final data = Map<String, dynamic>.from(doc.data()! as Map);
      if (data['reversed'] == true) return; // already reversed

      final amountPaise = (data['amountPaise'] as num?)?.toInt() ??
          rupeesToPaise((data['amount'] as num?)?.toDouble() ?? 0);

      tx.set(ref, {
        'reversed':       true,
        'reversedAt':     FieldValue.serverTimestamp(),
        'reversedReason': reason.trim(),
      }, SetOptions(merge: true));

      final studentFeeSnap = await tx.get(studentFeeDocRef);
      var totalPaidPaise = 0;
      if (studentFeeSnap.exists && studentFeeSnap.data() != null) {
        totalPaidPaise = (studentFeeSnap.data()?['totalPaidPaise'] as num?)?.toInt() ?? 0;
      }
      final newTotal = (totalPaidPaise - amountPaise).clamp(0, double.infinity).toInt();
      tx.set(studentFeeDocRef, {'totalPaidPaise': newTotal}, SetOptions(merge: true));

      // Update parent class summary document rolls map
      final classKey = className.replaceAll(' ', '_');
      final classDocRef = schoolCollection(_sid, 'fee_payments').doc(classKey);
      tx.set(classDocRef, {
        'rolls': {
          '$roll': newTotal,
        }
      }, SetOptions(merge: true));
    });

    final docAfter = await ref.get();
    AuditService.emit(
      action:   'reverse',
      entity:   'fee_payment',
      entityId: paymentId,
      before:   docAfter.exists ? Map<String, dynamic>.from(docAfter.data()! as Map) : null,
    );
  }

  /// Returns the total paid by a single student, using the student summary cache doc
  /// to avoid O(N) queries on payments listing (#25, #652, #653).
  Future<double> getTotalPaid({String? schoolId, required String className, required int roll}) async {
    final studentFeeDocRef = schoolCollection(_sid, 'fee_payments')
        .doc(className.replaceAll(' ', '_'))
        .collection('students')
        .doc('$roll');

    final snap = await studentFeeDocRef.get();
    if (snap.exists && snap.data() != null && snap.data()?['totalPaidPaise'] != null) {
      return paiseToRupees((snap.data()?['totalPaidPaise'] as num).toInt());
    }

    // Fallback: calculate from payment documents list
    final payments = await getPayments(className: className, roll: roll);
    final paise = payments.fold<int>(0, (acc, p) => acc + p.amountPaise);
    
    // Save to metadata document for future instant loads, but only if not a guardian
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('auth_role');
    if (role != 'guardian') {
      try {
        await studentFeeDocRef.set({'totalPaidPaise': paise}, SetOptions(merge: true));
      } catch (e) {
        AppLogger.w('FeeService', 'Failed to write fee cache doc: $e');
      }
    }
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
      if (p.reversed) continue;
      final name = p.installmentName;
      if (name != null && name.isNotEmpty) {
        paise[name] = (paise[name] ?? 0) + p.amountPaise;
      }
    }
    return paise.map((k, v) => MapEntry(k, paiseToRupees(v)));
  }

  /// Lazy migration: if the parent document does not contain the 'rolls' map
  /// (e.g. legacy data created before pre-aggregation), we fetch the sub-collection
  /// of student documents, construct the map, write it to the parent document,
  /// and return it.
  Future<Map<int, int>> _lazyMigrateClassRolls(String classKey) async {
    final parentRef = schoolCollection(_sid, 'fee_payments').doc(classKey);
    
    // Fetch all student fee summary documents in the sub-collection
    final snap = await parentRef.collection('students').get();
    
    final rollsMap = <String, int>{};
    final classMap = <int, int>{};
    
    for (final doc in snap.docs) {
      final roll = int.tryParse(doc.id);
      if (roll != null) {
        final paise = (doc.data()['totalPaidPaise'] as num?)?.toInt() ?? 0;
        rollsMap[doc.id] = paise;
        classMap[roll] = paise;
      }
    }
    
    // Save to parent document to cache it permanently
    await parentRef.set({'rolls': rollsMap}, SetOptions(merge: true));
    
    return classMap;
  }

  // ── Class-wide fee overview ────────────────────────────────────────────────

  /// Fetches summaries class-wide class-by-class in parallel, reducing database reads
  /// by orders of magnitude and resolving query storm issues (#25, #652, #653).
  Future<Map<String, Map<int, int>>?> _aggregatePaidPaise(
      List<String> classes) async {
    try {
      final out = <String, Map<int, int>>{};
      final futures = classes.map((cls) async {
        final classKey = cls.replaceAll(' ', '_');
        final doc = await schoolCollection(_sid, 'fee_payments')
            .doc(classKey)
            .get();

        final data = doc.data();
        Map<int, int> classMap;
        if (data == null || !data.containsKey('rolls')) {
          classMap = await _lazyMigrateClassRolls(classKey);
        } else {
          classMap = <int, int>{};
          final rollsMap = Map<String, dynamic>.from(data['rolls'] as Map? ?? {});
          rollsMap.forEach((k, v) {
            final roll = int.tryParse(k);
            if (roll != null) {
              classMap[roll] = (v as num).toInt();
            }
          });
        }
        return MapEntry(cls, classMap);
      });

      final entries = await Future.wait(futures);
      out.addEntries(entries);
      return out;
    } catch (e, stack) {
      handleError(e, stack);
      return null; // Fallback to per-roll calculation if aggregation fails
    }
  }

  /// roll → totalPaid (rupees) for [rolls] in [className], sourced from a
  /// pre-fetched aggregation when available.
  ///
  /// When the aggregation map is null (fetch failed) it falls back to a single
  /// class-wide summary query via [getClassFeeOverview] — one Firestore read
  /// per class, not per student (#652). Students not found in either source
  /// default to 0.0 (no payments on record).
  Future<Map<int, double>> _classPaid(
    String className,
    List<int> rolls,
    Map<String, Map<int, int>>? agg,
  ) async {
    if (agg != null) {
      final m = agg[className] ?? const {};
      return {for (final r in rolls) r: paiseToRupees(m[r] ?? 0)};
    }
    return getClassFeeOverview(className: className, rolls: rolls);
  }

  /// Returns { roll → totalPaid } for every student in a class using the
  /// per-class student summary sub-collection.
  ///
  /// Fires a single Firestore read per class. Students absent from the
  /// summary collection (no payment history yet) default to 0.0 — no
  /// sequential per-student fallback (#652).
  Future<Map<int, double>> getClassFeeOverview({String? schoolId, required String className, required List<int> rolls}) async {
    if (rolls.isEmpty) return {};
    final classKey = className.replaceAll(' ', '_');
    final doc = await schoolCollection(_sid, 'fee_payments')
        .doc(classKey)
        .get();

    final data = doc.data();
    Map<int, int> classMap;
    if (data == null || !data.containsKey('rolls')) {
      classMap = await _lazyMigrateClassRolls(classKey);
    } else {
      classMap = <int, int>{};
      final rollsMap = Map<String, dynamic>.from(data['rolls'] as Map? ?? {});
      rollsMap.forEach((k, v) {
        final roll = int.tryParse(k);
        if (roll != null) {
          classMap[roll] = (v as num).toInt();
        }
      });
    }

    // Default to 0 for rolls without a summary doc (no payments yet).
    return {for (final roll in rolls) roll: paiseToRupees(classMap[roll] ?? 0)};
  }

  // ── School-wide class summaries (for FeeOverviewScreen) ───────────────────

  /// Returns one [ClassFeeSummary] per entry in [classes].
  /// Fires parallel requests per class; each class fires parallel per-student requests.
  /// Returns one [ClassFeeSummary] per entry in [classes].
  /// Refactored to read pre-aggregated class summaries from Firestore in a single query (O(C) complexity).
  /// Falls back to O(N) client-side aggregation if class summaries are not initialized.
  Future<List<ClassFeeSummary>> getClassSummaries({
    required List<String> classes,
  }) async {
    if (classes.isEmpty) return [];

    try {
      final summariesSnap = await schoolCollection(_sid, 'class_fee_summaries').get();
      if (summariesSnap.docs.isNotEmpty) {
        final Map<String, Map<String, dynamic>> summaryMap = {
          for (final doc in summariesSnap.docs)
            (doc.data()['className'] as String? ?? ''): doc.data()
        };

        final List<ClassFeeSummary> out = [];
        for (final cls in classes) {
          final data = summaryMap[cls];
          if (data == null) {
            final structure = await getFeeStructure(className: cls);
            out.add(ClassFeeSummary(
              className: cls,
              studentCount: 0,
              fullyPaid: 0,
              totalDue: 0.0,
              totalCollected: 0.0,
              totalAnnualFee: structure.totalAnnualFee,
            ));
          } else {
            final totalCollected = paiseToRupees((data['totalCollectedPaise'] as num?)?.toInt() ?? 0);
            final totalDue = paiseToRupees((data['totalDuePaise'] as num?)?.toInt() ?? 0);
            final totalAnnualFee = paiseToRupees((data['totalAnnualFeePaise'] as num?)?.toInt() ?? 0);
            out.add(ClassFeeSummary(
              className: cls,
              studentCount: (data['studentCount'] as num?)?.toInt() ?? 0,
              fullyPaid: (data['fullyPaid'] as num?)?.toInt() ?? 0,
              totalDue: totalDue,
              totalCollected: totalCollected,
              totalAnnualFee: totalAnnualFee > 0 ? totalAnnualFee : totalDue / ((data['studentCount'] as num?)?.toInt() ?? 1),
            ));
          }
        }
        return out;
      }
    } catch (e) {
      // Fallback to real-time calculation if any read error occurs
    }

    // ── FALLBACK REAL-TIME AGGREGATION ──
    // Load all students once
    final studentSnap = await schoolCollection(_sid, 'students').get();
    final byClass = <String, List<Map<String, dynamic>>>{};
    for (final doc in studentSnap.docs) {
      final data = Map<String, dynamic>.from(doc.data() as Map);
      final cls  = data['className'] as String? ?? '';
      if (cls.isEmpty) continue;
      byClass.putIfAbsent(cls, () => []).add(data);
    }

    final agg = await _aggregatePaidPaise(classes);

    final futures = classes.map((cls) async {
      final studs = byClass[cls] ?? [];
      final rolls = studs
          .map((s) => (s['roll'] as num?)?.toInt() ?? 0)
          .where((r) => r > 0)
          .toList();

      final results = await Future.wait([
        getFeeStructure(className: cls),
        _classPaid(cls, rolls, agg),
      ]);
      final structure = results[0] as FeeStructure;
      final paidMap   = results[1] as Map<int, double>;

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

  /// Aggregates fee data across all students using server-side rollup summaries (O(1) complexity).
  /// Falls back to real-time O(N) calculation if the rollup summary is not initialized.
  Future<Map<String, dynamic>> getFeesSummary() async {
    try {
      final summaryDoc = await schoolCollection(_sid, 'summaries').doc('fees').get();
      if (summaryDoc.exists && summaryDoc.data() != null) {
        final data = summaryDoc.data()!;
        final collected = paiseToRupees((data['collectedPaise'] as num?)?.toInt() ?? 0);
        final pending = paiseToRupees((data['pendingPaise'] as num?)?.toInt() ?? 0);
        final overdue = paiseToRupees((data['overduePaise'] as num?)?.toInt() ?? 0);

        // Fetch top 10 defaulters via indexed query
        final defaultersSnap = await schoolCollection(_sid, 'students')
            .where('promoted', isEqualTo: false)
            .where('deletionPending', isEqualTo: false)
            .where('feePendingPaise', isGreaterThan: 0)
            .orderBy('feePendingPaise', descending: true)
            .limit(10)
            .get();

        final defaulters = defaultersSnap.docs.map((doc) {
          final sData = doc.data();
          final pendingPaise = (sData['feePendingPaise'] as num?)?.toInt() ?? 0;
          final days = (sData['feeDaysOverdue'] as num?)?.toInt() ?? 0;
          return {
            'name':      sData['name'] ?? '',
            'className': sData['className'] ?? '',
            'amount':    paiseToRupees(pendingPaise),
            'daysOverdue': days,
            'phone':     sData['parentPhone'] ?? sData['phone'] ?? '',
          };
        }).toList();

        return {
          'collected': collected,
          'pending':   pending,
          'overdue':   overdue,
          'defaulters': defaulters,
        };
      }
    } catch (e) {
      // Fallback to real-time calculation if any error occurs
    }

    // ── FALLBACK REAL-TIME AGGREGATION ──
    final studentSnap = await schoolCollection(_sid, 'students').get();

    final byClass = <String, List<Map<String, dynamic>>>{};
    for (final doc in studentSnap.docs) {
      final data = Map<String, dynamic>.from(doc.data() as Map);
      final cls  = data['className'] as String? ?? '';
      if (cls.isEmpty) continue;
      byClass.putIfAbsent(cls, () => []).add(data);
    }

    final agg = await _aggregatePaidPaise(byClass.keys.toList());

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
        _classPaid(cls, rolls, agg),
      ]);

      final structure = results[0] as FeeStructure;
      final paidMap   = results[1] as Map<int, double>;
      final duePaise  = structure.totalAnnualFeePaise;
      if (duePaise <= 0) continue;

      for (final sData in studs) {
        final roll = (sData['roll'] as num?)?.toInt() ?? 0;
        if (roll <= 0) continue;
        final paidPaise = rupeesToPaise(paidMap[roll] ?? 0);

        collectedP += paidPaise < duePaise ? paidPaise : duePaise;

        final shortfallPaise = duePaise - paidPaise;
        if (shortfallPaise > 0) {
          pendingP += shortfallPaise;
          final days = daysOverdue(structure, paiseToRupees(paidPaise), now);
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
  static int daysOverdue(FeeStructure structure, double paid, DateTime now) {
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

  /// Updates reconciliation status of a list of payments in a transaction.
  Future<void> reconcilePayments(List<DocumentReference> refs, bool reconciled) async {
    final db = FirebaseFirestore.instance;
    await db.runTransaction((tx) async {
      for (final ref in refs) {
        tx.update(ref, {'reconciled': reconciled});
      }
    });
    
    // Emit audit log for the reconciliation action
    AuditService.emit(
      action: 'update',
      entity: 'fee_reconciliation',
      entityId: 'batch',
      after: {
        'count': refs.length,
        'reconciled': reconciled,
      },
    );
  }

  // ── Stream pending payment claims for coordinator dashboard ──────────────
  Stream<QuerySnapshot<Map<String, dynamic>>> streamPendingPaymentClaims() {
    return schoolCollection(_sid, 'payment_claims')
        .where('status', isEqualTo: 'pending')
        .snapshots();
  }
}

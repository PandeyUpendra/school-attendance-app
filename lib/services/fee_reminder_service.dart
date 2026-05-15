import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/student.dart';

/// Describes the current fee reminder state for a student.
class FeeReminderStatus {
  /// 'paid' | 'dueSoon' | 'overdue' | 'unknown'
  final String type;

  /// Positive = days until due. Negative = days overdue. Null = no due date set.
  final int? daysDiff;

  final double? amount;
  final String? dueDate;
  final String studentName;

  const FeeReminderStatus({
    required this.type,
    this.daysDiff,
    this.amount,
    this.dueDate,
    required this.studentName,
  });

  bool get isPaid => type == 'paid';
  bool get isDueSoon => type == 'dueSoon';
  bool get isOverdue => type == 'overdue';
}

class FeeReminderService {
  static final FeeReminderService _instance = FeeReminderService._();
  FeeReminderService._();
  factory FeeReminderService() => _instance;

  static final _db = FirebaseFirestore.instance;

  // ── Status check ──────────────────────────────────────────────────────────

  /// Returns the current fee reminder status for a student.
  FeeReminderStatus checkFeeStatus(Student student) {
    if (student.feeStatus == 'Paid') {
      return FeeReminderStatus(type: 'paid', studentName: student.name);
    }

    if (student.feeDueDate == null || student.feeDueDate!.isEmpty) {
      // No due date: treat as due soon if Pending/Partial
      return FeeReminderStatus(
        type: 'dueSoon',
        amount: student.feeAmount,
        dueDate: student.feeDueDate,
        studentName: student.name,
      );
    }

    final due = DateTime.tryParse(student.feeDueDate!);
    if (due == null) {
      return FeeReminderStatus(
        type: 'dueSoon',
        amount: student.feeAmount,
        dueDate: student.feeDueDate,
        studentName: student.name,
      );
    }

    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final dueDate = DateTime(due.year, due.month, due.day);
    final diff = dueDate.difference(todayDate).inDays;

    return FeeReminderStatus(
      type: diff < 0 ? 'overdue' : 'dueSoon',
      daysDiff: diff,
      amount: student.feeAmount,
      dueDate: student.feeDueDate,
      studentName: student.name,
    );
  }

  // ── Push reminder ──────────────────────────────────────────────────────────

  /// Writes a fee reminder notification to Firestore for the guardian.
  /// type: "7days" | "duedate" | "overdue"
  Future<void> sendPushReminder(
    String studentId,
    String? guardianFcmToken,
    String type, {
    required String studentName,
    double? amount,
    String? dueDate,
    String? guardianAudience,
  }) async {
    String body;
    final amtStr = amount != null ? '₹${amount.toStringAsFixed(0)}' : 'fee';
    final dateStr = dueDate ?? '';

    switch (type) {
      case '7days':
        body = 'Fee due in 7 days for $studentName. Amount: $amtStr. Due: $dateStr';
      case 'duedate':
        body = 'Fee due TODAY for $studentName. Amount: $amtStr';
      case 'overdue':
        final now = DateTime.now();
        final due = DateTime.tryParse(dueDate ?? '');
        final days = due != null
            ? DateTime(now.year, now.month, now.day)
                .difference(DateTime(due.year, due.month, due.day))
                .inDays
            : 0;
        body = 'Fee OVERDUE for $studentName by $days days. Please pay immediately.';
      default:
        body = 'Fee reminder for $studentName.';
    }

    await _db.collection('notifications').add({
      'type': 'fee_reminder',
      'title': 'Fee Reminder',
      'body': body,
      'audience': guardianAudience ?? 'guardian:$studentId',
      'createdAt': FieldValue.serverTimestamp(),
    });

    await logReminderSent(studentId, type, 'push');
  }

  // ── WhatsApp reminder ─────────────────────────────────────────────────────

  /// Opens WhatsApp with a pre-filled fee reminder message.
  Future<void> sendWhatsAppReminder(
    String phone,
    String studentName,
    double? amount,
    String? dueDate,
  ) async {
    final amtStr = amount != null ? '₹${amount.toStringAsFixed(0)}' : '(amount not set)';
    final dateStr = dueDate?.isNotEmpty == true ? dueDate! : '(date not set)';
    final message =
        'Dear Parent,\n\nFee reminder for $studentName.\nAmount: $amtStr\nDue Date: $dateStr\n\nPlease arrange payment at the earliest. Thank you.';

    final cleaned = phone.replaceAll(RegExp(r'\D'), '');
    final uri = Uri.parse(
        'https://wa.me/$cleaned?text=${Uri.encodeComponent(message)}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // ── Log ───────────────────────────────────────────────────────────────────

  /// Saves a reminder event to Firestore feeReminders collection.
  Future<void> logReminderSent(
      String studentId, String type, String channel) async {
    await _db.collection('feeReminders').add({
      'studentId': studentId,
      'type': type,
      'channel': channel,
      'sentAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Defaulters query ───────────────────────────────────────────────────────

  /// Returns all students across [classNames] whose feeStatus is not 'Paid'.
  Future<List<Student>> getDefaulters(List<String> classNames) async {
    if (classNames.isEmpty) return [];

    final futures = classNames.map((cls) async {
      final snap = await _db
          .collection('students')
          .where('className', isEqualTo: cls)
          .get();
      return snap.docs
          .map((d) => Student.fromJson(Map<String, dynamic>.from(d.data())))
          .where((s) => s.feeStatus != 'Paid')
          .toList();
    });

    final results = await Future.wait(futures);
    final all = results.expand((list) => list).toList()
      ..sort((a, b) {
        // Sort overdue first (by days overdue desc), then pending
        final sa = checkFeeStatus(a);
        final sb = checkFeeStatus(b);
        if (sa.isOverdue && !sb.isOverdue) return -1;
        if (!sa.isOverdue && sb.isOverdue) return 1;
        final da = sa.daysDiff ?? 0;
        final db = sb.daysDiff ?? 0;
        return da.compareTo(db);
      });
    return all;
  }
}

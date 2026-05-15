import 'package:flutter/material.dart';

import '../../models/student.dart';
import '../../services/fee_reminder_service.dart';
import '../../theme.dart';

class FeeDefaultersScreen extends StatefulWidget {
  final List<String> classNames;

  const FeeDefaultersScreen({super.key, required this.classNames});

  @override
  State<FeeDefaultersScreen> createState() => _FeeDefaultersScreenState();
}

class _FeeDefaultersScreenState extends State<FeeDefaultersScreen> {
  final _svc = FeeReminderService();
  bool _loading = true;
  List<Student> _defaulters = [];
  final Set<String> _sending = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _svc.getDefaulters(widget.classNames);
    if (mounted) {
      setState(() {
        _defaulters = list;
        _loading = false;
      });
    }
  }

  // ── Reminder actions ───────────────────────────────────────────────────────

  Future<void> _sendPush(Student student) async {
    final key = student.roll.toString();
    if (_sending.contains(key)) return;
    setState(() => _sending.add(key));
    try {
      final status = _svc.checkFeeStatus(student);
      final type = status.isOverdue ? 'overdue' : 'dueSoon';
      final audience = 'guardian:${student.className}:${student.roll}';
      await _svc.sendPushReminder(
        student.roll.toString(),
        null,
        type,
        studentName: student.name,
        amount: student.feeAmount,
        dueDate: student.feeDueDate,
        guardianAudience: audience,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Reminder sent to ${student.name}'),
        backgroundColor: AppTheme.primary,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _sending.remove(key));
    }
  }

  void _sendWhatsApp(Student student) {
    final phone = student.parentPhone ?? student.phone;
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No contact number available for this student'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    _svc.sendWhatsAppReminder(
        phone, student.name, student.feeAmount, student.feeDueDate);
    _svc.logReminderSent(student.roll.toString(), 'whatsapp', 'whatsapp');
  }

  Future<void> _sendAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Send Reminder to All?'),
        content: Text(
            'This will send push reminders to all ${_defaulters.length} defaulters.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white),
              child: const Text('Send All')),
        ],
      ),
    );
    if (confirmed != true) return;

    for (final student in _defaulters) {
      await _sendPush(student);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(
          _loading
              ? 'Fee Defaulters'
              : 'Fee Defaulters (${_defaulters.length})',
        ),
        actions: [
          if (!_loading && _defaulters.isNotEmpty)
            TextButton.icon(
              icon: const Icon(Icons.notifications_active_outlined,
                  color: Colors.white, size: 18),
              label: const Text('Remind All',
                  style: TextStyle(color: Colors.white, fontSize: 13)),
              onPressed: _sendAll,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _defaulters.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 60, color: Colors.green.shade400),
                      const SizedBox(height: 12),
                      const Text('No fee defaulters!',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('All students are up to date.',
                          style: TextStyle(
                              color: Colors.grey.shade500, fontSize: 13)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
                    itemCount: _defaulters.length,
                    itemBuilder: (context, i) =>
                        _DefaulterCard(
                          student: _defaulters[i],
                          reminder: _svc.checkFeeStatus(_defaulters[i]),
                          isSending:
                              _sending.contains(_defaulters[i].roll.toString()),
                          onPushReminder: () => _sendPush(_defaulters[i]),
                          onWhatsApp: () => _sendWhatsApp(_defaulters[i]),
                        ),
                  ),
                ),
    );
  }
}

// ── Defaulter card ─────────────────────────────────────────────────────────────

class _DefaulterCard extends StatelessWidget {
  final Student student;
  final FeeReminderStatus reminder;
  final bool isSending;
  final VoidCallback onPushReminder;
  final VoidCallback onWhatsApp;

  const _DefaulterCard({
    required this.student,
    required this.reminder,
    required this.isSending,
    required this.onPushReminder,
    required this.onWhatsApp,
  });

  @override
  Widget build(BuildContext context) {
    final isOverdue = reminder.isOverdue;
    final statusColor =
        isOverdue ? Colors.red.shade600 : Colors.amber.shade700;
    final daysDiff = reminder.daysDiff;
    String statusText;
    if (isOverdue) {
      final days = daysDiff != null && daysDiff < 0 ? (-daysDiff) : null;
      statusText = days != null ? 'Overdue $days d' : 'Overdue';
    } else if (daysDiff != null) {
      statusText = 'Due in $daysDiff d';
    } else {
      statusText = student.feeStatus;
    }

    final amtStr = student.feeAmount != null
        ? '₹${student.feeAmount!.toStringAsFixed(0)}'
        : '—';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color ?? Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOverdue
              ? Colors.red.shade200
              : Colors.amber.shade200,
          width: 1,
        ),
        boxShadow: const [
          BoxShadow(
              color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 20,
                backgroundColor: AppTheme.primary.withOpacity(0.12),
                backgroundImage: student.photoUrl?.isNotEmpty == true
                    ? NetworkImage(student.photoUrl!)
                    : null,
                child: student.photoUrl?.isNotEmpty != true
                    ? Text(
                        student.roll.toString(),
                        style: const TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(student.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    Text(
                      '${student.className}  ·  Roll ${student.roll}',
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: statusColor.withOpacity(0.3)),
                ),
                child: Text(statusText,
                    style: TextStyle(
                        fontSize: 11,
                        color: statusColor,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.currency_rupee,
                  size: 13, color: Colors.grey.shade500),
              const SizedBox(width: 2),
              Text('Amount: $amtStr',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.black87)),
              if (student.feeDueDate != null) ...[
                const SizedBox(width: 12),
                Icon(Icons.calendar_today_outlined,
                    size: 13, color: Colors.grey.shade500),
                const SizedBox(width: 2),
                Text(student.feeDueDate!,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.black87)),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: isSending
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.primary))
                      : const Icon(
                          Icons.notifications_outlined,
                          size: 15),
                  label: const Text('Push Reminder',
                      style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: const BorderSide(
                        color: AppTheme.primary, width: 1),
                    padding:
                        const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onPressed: isSending ? null : onPushReminder,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.chat_bubble_outline,
                      size: 15),
                  label: const Text('WhatsApp',
                      style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onPressed: onWhatsApp,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

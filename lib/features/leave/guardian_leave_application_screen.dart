import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../l10n/app_strings.dart';
import '../../theme.dart';
import '../../models/student.dart';
import '../../shared/utils/app_logger.dart';
import '../../services/timetable_service.dart';
import '../../services/notification_service.dart';
import '../../services/auth_service.dart';
import '../../shared/widgets/index_building_notice.dart';
import '../../shared/widgets/managed_dropdown.dart';

/// Guardian applies for leave on behalf of their child.
/// The request is sent to the class teacher who can approve / reject / forward.
class GuardianLeaveApplicationScreen extends StatefulWidget {
  final Student student;

  const GuardianLeaveApplicationScreen({super.key, required this.student});

  @override
  State<GuardianLeaveApplicationScreen> createState() =>
      _GuardianLeaveApplicationScreenState();
}

class _GuardianLeaveApplicationScreenState
    extends State<GuardianLeaveApplicationScreen> {
  final _service = TimetableService.instance;

  DateTime _startDate    = DateTime.now().add(const Duration(days: 1));
  int      _numberOfDays = 1;
  String   _reason       = 'Medical / Health Issue';
  final    _customReasonCtrl = TextEditingController();
  bool     _submitting   = false;
  bool     _overlapping  = false;
  int      _historyLimit = 20;

  static const _reasonOptions = [
    'Medical / Health Issue',
    'Family Function',
    'Personal Emergency',
    'Wedding / Ceremony',
    'Bereavement',
    'Other',
  ];

  @override
  void dispose() {
    _customReasonCtrl.dispose();
    super.dispose();
  }

  // ── Overlap check ─────────────────────────────────────────────────────────

  Future<bool> _hasOverlappingLeave() async {
    final end = _startDate.add(Duration(days: _numberOfDays - 1));
    try {
      final snap = await FirebaseFirestore.instance
          .collection('schools')
          .doc(AuthService.currentSchoolId)
          .collection('leave_applications')
          .where('applicantType', isEqualTo: 'guardian')
          .where('studentClass',  isEqualTo: widget.student.className)
          .where('studentRoll',   isEqualTo: widget.student.roll)
          .get();
      for (final doc in snap.docs) {
        final data   = doc.data();
        final status = (data['status'] as String?) ?? '';
        if (status != 'pending' && status != 'approved') continue;
        final startStr = data['startDate'] as String?;
        if (startStr == null) continue;
        final parts = startStr.split('-');
        if (parts.length != 3) continue;
        final year = int.tryParse(parts[0]);
        final month = int.tryParse(parts[1]);
        final day = int.tryParse(parts[2]);
        if (year == null || month == null || day == null) continue;
        final eStart = DateTime(year, month, day);
        final eDays  = (data['numberOfDays'] as int?) ?? 1;
        final eEnd   = eStart.add(Duration(days: eDays - 1));
        if (_startDate.isBefore(eEnd.add(const Duration(days: 1))) &&
            end.isAfter(eStart.subtract(const Duration(days: 1)))) {
          return true;
        }
      }
    } catch (e, st) {
      AppLogger.e('GuardianLeaveApplicationScreen', 'Failed checking overlapping leave', e, st);
    }
    return false;
  }

  Future<void> _updateOverlapState() async {
    final overlap = await _hasOverlappingLeave();
    if (!mounted) return;
    setState(() => _overlapping = overlap);
  }

  // ── Date picker ───────────────────────────────────────────────────────────

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: context.tr('selectLeaveStartDate'),
    );
    if (picked != null) {
      setState(() => _startDate = picked);
      _updateOverlapState();
    }
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final finalReason =
        _reason == 'Other' ? _customReasonCtrl.text.trim() : _reason;

    if (finalReason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('pleaseSpecifyReason'))));
      return;
    }
    if (_reason == 'Other' && finalReason.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('reasonMin10'))));
      return;
    }

    setState(() => _submitting = true);

    try {
      final overlap = await _hasOverlappingLeave();
      if (overlap) {
        if (!mounted) return;
        setState(() => _submitting = false);
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: AppTheme.warning),
              const SizedBox(width: 8),
              Text(context.tr('leaveAlreadyApplied')),
            ]),
            content: Text(context.tr('leaveOverlapBody')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.tr('ok'),
                    style: const TextStyle(color: AppTheme.primary)),
              ),
            ],
          ),
        );
        return;
      }

      final dateStr =
          '${_startDate.year}-${_startDate.month.toString().padLeft(2, '0')}-'
          '${_startDate.day.toString().padLeft(2, '0')}';

      await _service.submitStudentLeaveApplication(
        studentClass:  widget.student.className,
        studentSection: widget.student.section,
        studentRoll:   widget.student.roll,
        studentName:   widget.student.name,
        guardianName:  widget.student.fatherName.isNotEmpty
            ? widget.student.fatherName
            : widget.student.motherName,
        startDate:     dateStr,
        numberOfDays:  _numberOfDays,
        reason:        finalReason,
        // Pass the stable admissionId so resolved-leave notices use the
        // 'guardian_adm:{id}' audience channel and not the reusable roll (#39).
        admissionId:   widget.student.admissionId,
      );

      // Notify the teacher's dashboard (sent to role 'teacher' audience for the class)
      NotificationService().addStudentLeaveSubmitted(
        studentName:  widget.student.name,
        studentClass: widget.student.className,
        studentRoll:  widget.student.roll,
        days:         _numberOfDays,
        startDate:    dateStr,
      );

      if (!mounted) return;
      setState(() {
        _submitting = false;
      });
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.green),
              SizedBox(width: 8),
              Text(context.tr('success')),
            ],
          ),
          content: Text(context.tr('leaveSubmittedToTeacher')),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext); // pop dialog
                Navigator.pop(context); // pop screen back to dashboard
              },
              child: Text(context.tr('ok'),
                  style: const TextStyle(color: AppTheme.primary)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${context.tr('failedToSubmit')} $e'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ));
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _dateLabel() {
    const m = ['','Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${_startDate.day} ${m[_startDate.month]} ${_startDate.year}';
  }

  String _endDateLabel() {
    final end = _startDate.add(Duration(days: _numberOfDays - 1));
    const m = ['','Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${end.day} ${m[end.month]} ${end.year}';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('applyForLeave'),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text(context.tr('applyForLeaveSubtitle'),
                style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Student info card ─────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15)),
            ),
            child: Row(children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                child: Text(
                  widget.student.name.isNotEmpty
                      ? widget.student.name[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 20),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.student.name,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold)),
                  Text(
                    '${widget.student.className}  •  ${context.tr('rollPrefix')} ${widget.student.roll}',
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey.shade600)),
                ],
              )),
              // "Sent to" tag
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.send_outlined,
                      size: 13, color: AppTheme.primary),
                  const SizedBox(width: 4),
                  Text(context.tr('classTeacherLabel'),
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // ── Leave Duration ────────────────────────────────────────────
          _card(
            label: context.tr('leaveDuration'),
            child: Column(children: [
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(children: [
                    Icon(Icons.calendar_today_outlined,
                        color: Colors.orange.shade700, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.tr('startDate'),
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey)),
                        Text(_dateLabel(),
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                      ],
                    )),
                    Icon(Icons.edit_outlined,
                        size: 16, color: Colors.orange.shade400),
                  ]),
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: Text(context.tr('numberOfDays'),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500))),
                _stepperBtn(
                  icon: Icons.remove,
                  onTap: _numberOfDays > 1
                      ? () {
                          setState(() => _numberOfDays--);
                          _updateOverlapState();
                        }
                      : null,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('$_numberOfDays',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold)),
                ),
                _stepperBtn(
                  icon: Icons.add,
                  onTap: _numberOfDays < 30
                      ? () {
                          setState(() => _numberOfDays++);
                          _updateOverlapState();
                        }
                      : null,
                ),
              ]),
              if (_numberOfDays > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${context.tr('leavePeriodPrefix')} ${_dateLabel()} – ${_endDateLabel()}',
                    style: TextStyle(
                        fontSize: 12, color: Colors.orange.shade700),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 12),

          // ── Reason ───────────────────────────────────────────────────
          _card(
            label: context.tr('reasonForLeave'),
            child: Column(children: [
              ManagedDropdown(
                fieldKey: 'leave_reason',
                seeds: _reasonOptions,
                value: _reason,
                prefixIcon: const Icon(Icons.notes_outlined, size: 20),
                onChanged: (v) {
                  if (v != null) setState(() => _reason = v);
                },
              ),
              if (_reason == 'Other') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _customReasonCtrl,
                  maxLines: 4,
                  keyboardType: TextInputType.multiline,
                  maxLength: 500,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  decoration: InputDecoration(
                    hintText: context.tr('describeReasonHint'),
                    prefixIcon: const Icon(Icons.edit_outlined, size: 20),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 24),

          // ── Overlap warning ───────────────────────────────────────────
          if (_overlapping) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.warningLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.warning),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline, color: AppTheme.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr('leaveOverlapWarning'),
                    style: TextStyle(
                        color: Colors.brown.shade700, fontSize: 13),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 12),
          ],

          // ── Submit ────────────────────────────────────────────────────
          ElevatedButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send_outlined),
            label: Text(
                _submitting ? context.tr('submittingEllipsis') : context.tr('submitLeaveApplication')),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 32),

          // ── Leave History ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              context.tr('leaveHistoryCaps'),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade500,
                  letterSpacing: 0.6),
            ),
          ),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('schools')
                .doc(AuthService.currentSchoolId)
                .collection('leave_applications')
                .where('applicantType', isEqualTo: 'guardian')
                .where('studentClass',  isEqualTo: widget.student.className)
                .where('studentRoll',   isEqualTo: widget.student.roll)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator(),
                ));
              }
              if (snapshot.hasError && isIndexBuildingError(snapshot.error)) {
                return IndexBuildingNotice(onRetry: () => setState(() {}));
              }
              final docs = snapshot.hasData
                  ? snapshot.data!.docs.toList()
                  : <QueryDocumentSnapshot>[];
              docs.sort((a, b) {
                final ta = (a.data() as Map)['createdAt'];
                final tb = (b.data() as Map)['createdAt'];
                if (ta == null && tb == null) return 0;
                if (ta == null) return 1;
                if (tb == null) return -1;
                return (tb as dynamic).compareTo(ta as dynamic);
              });
              if (docs.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(context.tr('noLeaveApplications'),
                        style: TextStyle(
                            color: Colors.grey.shade500, fontSize: 14)),
                  ),
                );
              }
              final display = docs.take(_historyLimit).toList();
              final hasMore = docs.length > _historyLimit;
              return Column(children: [
                ...display.map((doc) => _historyCard(
                    doc.data() as Map<String, dynamic>)),
                if (hasMore)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextButton(
                      onPressed: () =>
                          setState(() => _historyLimit += 20),
                      child: Text(
                        '${context.tr('loadMorePrefix')} (${docs.length - _historyLimit} ${context.tr('remainingSuffix')})',
                        style: const TextStyle(color: AppTheme.primary),
                      ),
                    ),
                  ),
              ]);
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Reusable widgets ──────────────────────────────────────────────────────

  Widget _card({required String label, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade500,
                letterSpacing: 0.6)),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }

  Widget _stepperBtn({required IconData icon, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: onTap != null
              ? Colors.orange.shade50
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: onTap != null
                  ? Colors.orange.shade300
                  : Colors.grey.shade200),
        ),
        child: Icon(icon,
            size: 18,
            color: onTap != null
                ? Colors.orange.shade700
                : Colors.grey.shade400),
      ),
    );
  }

  Widget _historyCard(Map<String, dynamic> data) {
    final status = (data['status'] as String?) ?? 'pending';
    final startDate = (data['startDate'] as String?) ?? '';
    final days      = (data['numberOfDays'] as int?) ?? 1;
    final reason    = (data['reason'] as String?) ?? '';
    final coordinatorNote = data['coordinatorNote'] as String?;

    Color  statusColor;
    String statusLabel;
    IconData statusIcon;
    switch (status) {
      case 'approved':
        statusColor = Colors.green.shade700;
        statusLabel = context.tr('statusApproved');
        statusIcon  = Icons.check_circle_outline;
        break;
      case 'rejected':
        statusColor = Colors.red.shade700;
        statusLabel = context.tr('statusRejected');
        statusIcon  = Icons.cancel_outlined;
        break;
      case 'forwarded_to_coordinator':
        statusColor = Colors.blue.shade700;
        statusLabel = context.tr('statusForwarded');
        statusIcon  = Icons.forward_to_inbox_outlined;
        break;
      case 'forwarded_to_principal':
        statusColor = AppTheme.primaryDark;
        statusLabel = context.tr('statusForwarded');
        statusIcon  = Icons.forward_to_inbox_outlined;
        break;
      default:
        statusColor = Colors.amber.shade700;
        statusLabel = context.tr('statusPending');
        statusIcon  = Icons.pending_outlined;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(statusIcon, color: statusColor, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _formatDateRange(startDate, days),
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(reason.length > 32
                ? '${reason.substring(0, 29)}…'
                : reason,
                style: TextStyle(
                    fontSize: 11, color: Colors.grey.shade500)),
            if (coordinatorNote != null && coordinatorNote.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '${context.tr('remarksTitle')}: $coordinatorNote',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.orange.shade800),
              ),
            ],
          ],
        )),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: statusColor.withValues(alpha: 0.3)),
            ),
            child: Text(statusLabel,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusColor)),
          ),
          const SizedBox(height: 4),
          Text('$days ${context.tr('daysLower')}',
              style: TextStyle(
                  fontSize: 11, color: Colors.grey.shade600)),
        ]),
      ]),
    );
  }

  String _formatDateRange(String startDate, int days) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    try {
      final parts = startDate.split('-');
      if (parts.length < 3) return startDate;
      final year = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final day = int.tryParse(parts[2]);
      if (year == null || month == null || day == null) return startDate;
      final start = DateTime(year, month, day);
      final end = start.add(Duration(days: days - 1));
      if (days == 1) {
        return '${start.day} ${months[start.month]} ${start.year}';
      }
      if (start.month == end.month && start.year == end.year) {
        return '${start.day}–${end.day} ${months[start.month]} ${start.year}';
      }
      return '${start.day} ${months[start.month]} – '
          '${end.day} ${months[end.month]} ${end.year}';
    } catch (_) {
      return startDate;
    }
  }
}

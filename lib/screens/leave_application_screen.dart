import 'package:flutter/material.dart';
import '../models/teacher.dart';
import '../services/timetable_service.dart';
import '../services/notification_service.dart';

class LeaveApplicationScreen extends StatefulWidget {
  final Teacher teacher;
  const LeaveApplicationScreen({super.key, required this.teacher});

  @override
  State<LeaveApplicationScreen> createState() => _LeaveApplicationScreenState();
}

class _LeaveApplicationScreenState extends State<LeaveApplicationScreen> {
  final _service = TimetableService();

  String _toRole = 'coordinator';
  DateTime _startDate = DateTime.now().add(const Duration(days: 1));
  int _numberOfDays = 1;
  String _reason = 'Medical / Health Issue';
  final _customReasonCtrl = TextEditingController();
  bool _submitting = false;

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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Select Leave Start Date',
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _submit() async {
    final finalReason = _reason == 'Other'
        ? _customReasonCtrl.text.trim()
        : _reason;

    if (finalReason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please specify a reason')));
      return;
    }

    setState(() => _submitting = true);

    final dateStr =
        '${_startDate.year}-${_startDate.month.toString().padLeft(2, '0')}-${_startDate.day.toString().padLeft(2, '0')}';

    await _service.submitLeaveApplication(
      teacherId   : widget.teacher.id,
      teacherName : widget.teacher.name,
      teacherEmail: widget.teacher.email,
      toRole      : _toRole,
      startDate   : dateStr,
      numberOfDays: _numberOfDays,
      reason      : finalReason,
    );

    // Notify the recipient role so their dashboard shows a badge.
    NotificationService().addLeaveSubmitted(
      teacherName: widget.teacher.name,
      toRole:      _toRole,
      days:        _numberOfDays,
      startDate:   dateStr,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Leave application submitted successfully ✓'),
      backgroundColor: Colors.green.shade700,
      duration: const Duration(seconds: 3),
    ));
    Navigator.pop(context);
  }

  String _dateLabel() {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${_startDate.day} ${months[_startDate.month]} ${_startDate.year}';
  }

  String _endDateLabel() {
    final end = _startDate.add(Duration(days: _numberOfDays - 1));
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${end.day} ${months[end.month]} ${end.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Apply for Leave',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text('Submit leave application',
                style: TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Teacher info card ─────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.orange.shade100),
            ),
            child: Row(children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.orange.shade100,
                child: Text(widget.teacher.name[0].toUpperCase(),
                    style: TextStyle(
                        color: Colors.orange.shade700,
                        fontWeight: FontWeight.bold,
                        fontSize: 20)),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.teacher.name,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold)),
                  Text(widget.teacher.subject,
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade600)),
                  if (widget.teacher.email.isNotEmpty)
                    Text(widget.teacher.email,
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade400)),
                ],
              )),
            ]),
          ),
          const SizedBox(height: 16),

          // ── Send to ───────────────────────────────────────────────────
          _card(
            label: 'Send Application To',
            child: Column(children: [
              _toOption('coordinator', 'Coordinator',
                  Icons.admin_panel_settings_outlined, Colors.indigo),
              _toOption('principal', 'Principal',
                  Icons.business_outlined, Colors.teal),
            ]),
          ),
          const SizedBox(height: 12),

          // ── Date & Days ───────────────────────────────────────────────
          _card(
            label: 'Leave Duration',
            child: Column(children: [
              // Start date
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
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Start Date',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey)),
                            Text(_dateLabel(),
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600)),
                          ]),
                    ),
                    Icon(Icons.edit_outlined,
                        size: 16, color: Colors.orange.shade400),
                  ]),
                ),
              ),
              const SizedBox(height: 10),

              // Number of days stepper
              Row(children: [
                const Expanded(
                  child: Text('Number of Days',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500)),
                ),
                _stepperBtn(
                  icon: Icons.remove,
                  onTap: _numberOfDays > 1
                      ? () => setState(() => _numberOfDays--)
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
                  onTap: () => setState(() => _numberOfDays++),
                ),
              ]),

              if (_numberOfDays > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Leave period: ${_dateLabel()} – ${_endDateLabel()}',
                    style: TextStyle(
                        fontSize: 12, color: Colors.orange.shade700),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 12),

          // ── Reason ────────────────────────────────────────────────────
          _card(
            label: 'Reason for Leave',
            child: Column(children: [
              DropdownButtonFormField<String>(
                value: _reason,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.notes_outlined, size: 20),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                ),
                items: _reasonOptions
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _reason = v);
                },
              ),
              if (_reason == 'Other') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _customReasonCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'Describe your reason…',
                    prefixIcon: const Icon(Icons.edit_outlined, size: 20),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                  ),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 24),

          // ── Submit ────────────────────────────────────────────────────
          ElevatedButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send_outlined),
            label: Text(_submitting ? 'Submitting…' : 'Submit Application'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

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

  Widget _toOption(String value, String label, IconData icon, Color color) {
    final selected = _toRole == value;
    return InkWell(
      onTap: () => setState(() => _toRole = value),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.08) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? color : Colors.grey.shade200),
        ),
        child: Row(children: [
          Icon(icon, color: selected ? color : Colors.grey.shade500, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: selected ? color : Colors.black87)),
          ),
          if (selected)
            Icon(Icons.check_circle, color: color, size: 18),
        ]),
      ),
    );
  }

  Widget _stepperBtn({required IconData icon, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: onTap != null ? Colors.orange.shade50 : Colors.grey.shade100,
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
}

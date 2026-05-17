import 'package:flutter/material.dart';
import '../models/student.dart';
import '../models/student_remark.dart';
import '../services/auth_service.dart';
import '../services/student_service.dart';
import '../theme.dart';

/// Displays remarks for a student and (optionally) allows adding one.
/// Loads [AuthService] session internally to determine who is logged in.
class StudentRemarksWidget extends StatefulWidget {
  final Student student;
  /// Whether the current user is allowed to add a remark for this student.
  final bool allowAdd;

  const StudentRemarksWidget({
    super.key,
    required this.student,
    this.allowAdd = true,
  });

  @override
  State<StudentRemarksWidget> createState() => _StudentRemarksWidgetState();
}

class _StudentRemarksWidgetState extends State<StudentRemarksWidget> {
  final _service = StudentService();

  List<StudentRemark> _remarks  = [];
  bool   _loading               = true;
  String _currentEmail          = '';
  String _currentRole           = '';
  String? _currentTeacherId;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final session = await AuthService().getSession();
    _currentEmail     = session?['email']     as String? ?? '';
    _currentRole      = session?['role']      as String? ?? '';
    _currentTeacherId = session?['teacherId'] as String?;
    await _loadRemarks();
  }

  Future<void> _loadRemarks() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final list = await _service.getStudentRemarks(
      widget.student.className,
      widget.student.roll,
      section: widget.student.section,
    );
    if (!mounted) return;
    setState(() { _remarks = list; _loading = false; });
  }

  Future<void> _delete(StudentRemark r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Remark'),
        content: const Text('Remove this remark permanently?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _service.deleteStudentRemark(
        className: widget.student.className,
        roll: widget.student.roll,
        remarkId: r.id,
        currentUserEmail: _currentEmail,
        section: widget.student.section,
      );
      await _loadRemarks();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _openAddSheet() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddRemarkSheet(
        student:    widget.student,
        userEmail:  _currentEmail,
        userRole:   _currentRole,
        teacherId:  _currentTeacherId,
      ),
    );
    if (added == true) _loadRemarks();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ──────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 10),
          child: Row(children: [
            const Icon(Icons.comment_outlined,
                size: 18, color: AppTheme.primary),
            const SizedBox(width: 8),
            const Text(
              'Remarks',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary),
            ),
            const Spacer(),
            if (widget.allowAdd)
              GestureDetector(
                onTap: _openAddSheet,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: AppTheme.primary.withOpacity(0.3)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 13, color: AppTheme.primary),
                      SizedBox(width: 3),
                      Text('Add',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primary)),
                    ],
                  ),
                ),
              ),
          ]),
        ),

        // ── Body ─────────────────────────────────────────────────────────────
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))),
          )
        else if (_remarks.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(children: [
              Icon(Icons.chat_bubble_outline,
                  size: 28, color: Colors.grey.shade300),
              const SizedBox(height: 6),
              Text('No remarks yet',
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey.shade400)),
            ]),
          )
        else
          ...List.generate(_remarks.length, (i) {
            final r = _remarks[i];
            final isOwn = r.createdBy == _currentEmail;
            return _RemarkTile(
              remark:  r,
              isOwn:   isOwn,
              isLast:  i == _remarks.length - 1,
              onDelete: isOwn ? () => _delete(r) : null,
            );
          }),
      ],
    );
  }
}

// ── Individual remark tile ────────────────────────────────────────────────────

class _RemarkTile extends StatelessWidget {
  final StudentRemark remark;
  final bool isOwn;
  final bool isLast;
  final VoidCallback? onDelete;

  const _RemarkTile({
    required this.remark,
    required this.isOwn,
    required this.isLast,
    this.onDelete,
  });

  Color _roleColor(String role) {
    switch (role) {
      case 'principal':   return const Color(0xFF6A1B9A);
      case 'coordinator': return const Color(0xFF1565C0);
      case 'guardian':    return const Color(0xFF2E7D32);
      default:            return const Color(0xFF37474F);
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'principal':   return 'Principal';
      case 'coordinator': return 'Coordinator';
      case 'guardian':    return 'Guardian';
      default:            return 'Teacher';
    }
  }

  String _fmtTime(DateTime dt) {
    final d = dt.toLocal();
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    final am = d.hour < 12 ? 'AM' : 'PM';
    const mo = ['Jan','Feb','Mar','Apr','May','Jun',
                 'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${mo[d.month-1]}  $h:$m $am';
  }

  @override
  Widget build(BuildContext context) {
    final roleColor = _roleColor(remark.role);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // meta row
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: roleColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: roleColor.withOpacity(0.35)),
                  ),
                  child: Text(
                    _roleLabel(remark.role),
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: roleColor),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    remark.createdBy,
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  _fmtTime(remark.timestamp),
                  style: TextStyle(
                      fontSize: 10, color: Colors.grey.shade400),
                ),
                if (onDelete != null) ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: onDelete,
                    child: Icon(Icons.delete_outline,
                        size: 16, color: Colors.red.shade300),
                  ),
                ],
              ]),
              const SizedBox(height: 8),
              // remark text
              Text(
                remark.remark,
                style: const TextStyle(
                    fontSize: 13.5, height: 1.4),
              ),
            ],
          ),
        ),
        if (!isLast) const SizedBox(height: 8),
      ],
    );
  }
}

// ── Add-remark bottom sheet ───────────────────────────────────────────────────

class _AddRemarkSheet extends StatefulWidget {
  final Student student;
  final String  userEmail;
  final String  userRole;
  final String? teacherId;

  const _AddRemarkSheet({
    required this.student,
    required this.userEmail,
    required this.userRole,
    this.teacherId,
  });

  @override
  State<_AddRemarkSheet> createState() => _AddRemarkSheetState();
}

class _AddRemarkSheetState extends State<_AddRemarkSheet> {
  final _ctrl    = TextEditingController();
  final _service = StudentService();
  bool _saving   = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _saving = true);
    try {
      await _service.addStudentRemark(
        widget.student.className,
        widget.student.roll,
        widget.userEmail,
        widget.userRole,
        text,
        section:   widget.student.section,
        teacherId: widget.teacherId,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Remark added'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final charCount = _ctrl.text.length;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // handle
        Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          width: 36, height: 4,
          decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(height: 4),
        // header
        Row(children: [
          const Icon(Icons.comment_outlined,
              color: AppTheme.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Add Remark',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                Text(
                  '${widget.student.name}  ·  Roll ${widget.student.roll}',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 16),
        // text field
        TextField(
          controller: _ctrl,
          maxLength: 200,
          maxLines: 4,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Write your remark here…',
            hintStyle: TextStyle(
                color: Colors.grey.shade400, fontSize: 14),
            counterText: '$charCount / 200',
            counterStyle: TextStyle(
                fontSize: 11, color: Colors.grey.shade400),
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppTheme.primary, width: 1.5),
            ),
            contentPadding: const EdgeInsets.all(14),
          ),
        ),
        const SizedBox(height: 12),
        // buttons
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _saving ? null : () => Navigator.pop(context, false),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.grey.shade600,
                side: BorderSide(color: Colors.grey.shade300),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: (_saving || charCount == 0) ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Add Remark',
                      style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ]),
    );
  }
}

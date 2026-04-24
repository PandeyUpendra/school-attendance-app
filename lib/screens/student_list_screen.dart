import 'dart:io';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/student.dart';
import '../services/student_service.dart';
import 'add_student_screen.dart';
import 'attendance_certificate_screen.dart';

class StudentListScreen extends StatefulWidget {
  final String className;
  final bool isClassTeacher;
  const StudentListScreen({
    super.key,
    required this.className,
    this.isClassTeacher = false,
  });

  @override
  State<StudentListScreen> createState() => _StudentListScreenState();
}

class _StudentListScreenState extends State<StudentListScreen> {
  final _service = StudentService();
  List<Student> _students = [];
  String _search = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _service.getStudentsByClass(widget.className);
    if (!mounted) return;
    setState(() { _students = list; _loading = false; });
  }

  Future<void> _refresh() async {
    final list = await _service.getStudentsByClass(widget.className);
    if (!mounted) return;
    setState(() => _students = list);
  }

  List<Student> get _filtered {
    if (_search.trim().isEmpty) return _students;
    final q = _search.toLowerCase();
    return _students
        .where((s) =>
            s.name.toLowerCase().contains(q) ||
            s.roll.toString().contains(q) ||
            s.fatherName.toLowerCase().contains(q) ||
            s.phone.contains(q))
        .toList();
  }

  Future<void> _openAdd() async {
    final result = await Navigator.push<Student>(
      context,
      MaterialPageRoute(
          builder: (_) => AddStudentScreen(className: widget.className)),
    );
    if (result != null) _load();
  }

  Future<void> _openDetail(Student student) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _StudentDetailPage(
          student: student,
          canEdit: widget.isClassTeacher,
        ),
      ),
    );
    _load(); // always refresh — edit or delete may have changed data
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Student List',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text(widget.className,
                style:
                    const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: widget.isClassTeacher
          ? FloatingActionButton.extended(
              onPressed: _openAdd,
              backgroundColor: Colors.teal,
              icon: const Icon(Icons.person_add, color: Colors.white),
              label: const Text('Add Student',
                  style: TextStyle(color: Colors.white)),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              if (_students.isNotEmpty)
                Container(
                  color: Colors.teal,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: TextField(
                    onChanged: (v) => setState(() => _search = v),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search by name, roll, phone…',
                      hintStyle: const TextStyle(color: Colors.white60),
                      prefixIcon: const Icon(Icons.search,
                          color: Colors.white70),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.15),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none),
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              Expanded(
                child: _students.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.group_add,
                                size: 72, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text('No students in ${widget.className}',
                                style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade400)),
                            const SizedBox(height: 6),
                            Text('Tap + Add Student to get started',
                                style: TextStyle(
                                    color: Colors.grey.shade400)),
                          ],
                        ),
                      )
                    : _filtered.isEmpty
                        ? Center(
                            child: Text('No results for "$_search"',
                                style: TextStyle(
                                    color: Colors.grey.shade400)))
                        : RefreshIndicator(
                            onRefresh: _refresh,
                            color: Colors.teal,
                            child: ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(0, 8, 0, 100),
                              itemCount: _filtered.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1, indent: 80),
                              itemBuilder: (_, i) => _StudentCard(
                                student: _filtered[i],
                                onTap: () => _openDetail(_filtered[i]),
                              ),
                            ),
                          ),
              ),
            ]),
    );
  }
}

// ── Student list card ──────────────────────────────────────────────────────────

class _StudentCard extends StatelessWidget {
  final Student student;
  final VoidCallback? onTap;
  const _StudentCard({required this.student, this.onTap});

  Color get _feeColor {
    switch (student.feeStatus) {
      case 'Paid':
        return Colors.green;
      case 'Partial':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: Colors.teal.shade50,
            backgroundImage: student.photoPath != null
                ? FileImage(File(student.photoPath!))
                : null,
            child: student.photoPath == null
                ? Text(
                    student.name.isNotEmpty
                        ? student.name[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal.shade400))
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                        child: Text(student.name,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600))),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _feeColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: _feeColor.withOpacity(0.4)),
                      ),
                      child: Text(student.feeStatus,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _feeColor)),
                    ),
                  ]),
                  const SizedBox(height: 3),
                  Text(
                      'Roll: ${student.roll}  •  Father: ${student.fatherName}',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade500)),
                  if (student.phone.isNotEmpty)
                    Row(children: [
                      Icon(Icons.phone_outlined,
                          size: 12, color: Colors.grey.shade400),
                      const SizedBox(width: 3),
                      Text(student.phone,
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500)),
                    ]),
                ]),
          ),
          Icon(Icons.chevron_right,
              color: Colors.grey.shade300, size: 20),
        ]),
      ),
    );
  }
}

// ── Student detail page ────────────────────────────────────────────────────────

class _StudentDetailPage extends StatefulWidget {
  final Student student;
  final bool canEdit;
  const _StudentDetailPage(
      {required this.student, this.canEdit = false});

  @override
  State<_StudentDetailPage> createState() => _StudentDetailPageState();
}

class _StudentDetailPageState extends State<_StudentDetailPage> {
  late Student _student;

  @override
  void initState() {
    super.initState();
    _student = widget.student;
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  Future<void> _edit() async {
    final updated = await Navigator.push<Student>(
      context,
      MaterialPageRoute(
        builder: (_) => AddStudentScreen(
            className: _student.className, existing: _student),
      ),
    );
    if (updated != null) setState(() => _student = updated);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Student'),
        content:
            Text('Remove ${_student.name} from ${_student.className}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await StudentService()
        .removeStudent(_student.roll, _student.className);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _call() async {
    if (_student.phone.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: _student.phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _whatsapp() async {
    if (_student.phone.isEmpty) return;
    final digits = _student.phone.replaceAll(RegExp(r'\D'), '');
    final uri = Uri.parse('https://wa.me/$digits');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  Color get _feeColor {
    switch (_student.feeStatus) {
      case 'Paid':
        return Colors.green;
      case 'Partial':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  IconData get _feeIcon {
    switch (_student.feeStatus) {
      case 'Paid':
        return Icons.check_circle_outline;
      case 'Partial':
        return Icons.timelapse;
      default:
        return Icons.cancel_outlined;
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Student Profile'),
        actions: [
          if (widget.canEdit) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit',
              onPressed: _edit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remove',
              onPressed: _delete,
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Container(
              color: Colors.teal,
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              child: Column(children: [
                CircleAvatar(
                  radius: 54,
                  backgroundColor: Colors.white.withOpacity(0.2),
                  backgroundImage: _student.photoPath != null
                      ? FileImage(File(_student.photoPath!))
                      : null,
                  child: _student.photoPath == null
                      ? Text(
                          _student.name.isNotEmpty
                              ? _student.name[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                              fontSize: 42,
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                        )
                      : null,
                ),
                const SizedBox(height: 12),
                Text(
                  _student.name,
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _Chip('Roll ${_student.roll}'),
                  const SizedBox(width: 8),
                  _Chip(_student.className),
                ]),
              ]),
            ),

            const SizedBox(height: 8),

            // ── Contact ─────────────────────────────────────────────────────
            _SectionHeader('CONTACT'),
            _InfoRow(
                Icons.phone_outlined,
                'Phone',
                _student.phone.isEmpty ? '—' : _student.phone),
            if (_student.phone.isNotEmpty) ...[
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: Row(children: [
                  Expanded(
                    child: _ActionBtn(
                      icon: Icons.call,
                      label: 'Call',
                      color: Colors.green,
                      onTap: _call,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ActionBtn(
                      iconWidget: const FaIcon(
                        FontAwesomeIcons.whatsapp,
                        color: Color(0xFF25D366),
                        size: 26,
                      ),
                      label: 'WhatsApp',
                      color: const Color(0xFF25D366),
                      onTap: _whatsapp,
                    ),
                  ),
                ]),
              ),
            ] else
              const SizedBox(height: 12),
            const Divider(height: 1),

            // ── Family ──────────────────────────────────────────────────────
            _SectionHeader('FAMILY'),
            _InfoRow(
                Icons.man_outlined,
                "Father's Name",
                _student.fatherName.isNotEmpty
                    ? _student.fatherName
                    : '—'),
            if (_student.motherName != null &&
                _student.motherName!.isNotEmpty)
              _InfoRow(Icons.woman_outlined, "Mother's Name",
                  _student.motherName!),
            const Divider(height: 1),

            // ── Fee ─────────────────────────────────────────────────────────
            _SectionHeader('FEE STATUS'),
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _feeColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                      color: _feeColor.withOpacity(0.4)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_feeIcon, color: _feeColor, size: 18),
                  const SizedBox(width: 6),
                  Text(_student.feeStatus,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _feeColor,
                          fontSize: 14)),
                ]),
              ),
            ),
            const Divider(height: 1),

            // ── Attendance Certificate ───────────────────────────────────
            _SectionHeader('DOCUMENTS'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.workspace_premium_outlined),
                  label: const Text('Generate Attendance Certificate'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.indigo,
                    side: const BorderSide(color: Colors.indigo),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AttendanceCertificateScreen(
                          student: _student),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Reusable sub-widgets ───────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Text(title,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade500,
              letterSpacing: 0.8)),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(this.icon, this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Icon(icon, size: 20, color: Colors.grey.shade400),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w500)),
              ]),
        ),
      ]),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData? icon;
  final Widget?   iconWidget;
  final String    label;
  final Color     color;
  final VoidCallback onTap;
  const _ActionBtn({
    this.icon,
    this.iconWidget,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(children: [
          iconWidget ?? Icon(icon, color: color, size: 26),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ]),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  const _Chip(this.text);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: const TextStyle(fontSize: 13, color: Colors.white)),
    );
  }
}

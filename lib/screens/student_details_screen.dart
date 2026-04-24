import 'dart:io';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/student.dart';
import '../services/student_service.dart';
import '../services/timetable_service.dart';
import '../theme.dart';

class StudentDetailsScreen extends StatefulWidget {
  const StudentDetailsScreen({super.key});

  @override
  State<StudentDetailsScreen> createState() => _StudentDetailsScreenState();
}

class _StudentDetailsScreenState extends State<StudentDetailsScreen> {
  List<String> _classes = [];
  Map<String, int> _studentCounts = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await _reload();
  }

  Future<void> _reload() async {
    final settings = await TimetableService().getSettings();
    final classes  = List<String>.from(settings['classes'] as List);
    final counts   = <String, int>{};
    for (final cls in classes) {
      final students = await StudentService().getStudentsByClass(cls);
      counts[cls] = students.length;
    }
    if (!mounted) return;
    setState(() {
      _classes       = classes;
      _studentCounts = counts;
      _loading       = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Student Details'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _classes.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.class_outlined,
                          size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('No classes configured',
                          style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade400)),
                      const SizedBox(height: 6),
                      Text('Add classes in Bell & Class Settings',
                          style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade400)),
                    ],
                  ),
                )
              : Column(children: [
                  Container(
                    color: Colors.pink,
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: const Text('Select a class to view students',
                        style: TextStyle(
                            color: Colors.white70, fontSize: 13)),
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _reload,
                      color: Colors.pink,
                      child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _classes.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 70),
                      itemBuilder: (_, i) {
                        final cls = _classes[i];
                        final count = _studentCounts[cls] ?? 0;
                        return InkWell(
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      _ClassStudentsView(className: cls)),
                            );
                            _load(); // refresh counts after returning
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            child: Row(children: [
                              Container(
                                width: 44,
                                height: 44,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Colors.pink.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(Icons.school_outlined,
                                    color: Colors.pink.shade400, size: 22),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(cls,
                                          style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600)),
                                      Text(
                                          count == 0
                                              ? 'No students yet'
                                              : '$count student${count == 1 ? '' : 's'}',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade500)),
                                    ]),
                              ),
                              Icon(Icons.chevron_right,
                                  color: Colors.grey.shade400),
                            ]),
                          ),
                        );
                      },
                    ),
                    ),
                  ),
                ]),
    );
  }
}

// ── Class-specific student view (read-only for coordinator) ────────────────────

class _ClassStudentsView extends StatefulWidget {
  final String className;
  const _ClassStudentsView({required this.className});

  @override
  State<_ClassStudentsView> createState() => _ClassStudentsViewState();
}

class _ClassStudentsViewState extends State<_ClassStudentsView> {
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
    final list = await StudentService().getStudentsByClass(widget.className);
    if (!mounted) return;
    setState(() { _students = list; _loading = false; });
  }

  Future<void> _refresh() async {
    final list = await StudentService().getStudentsByClass(widget.className);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Students',
              style:
                  TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          Text(widget.className,
              style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              // Stats + search
              Container(
                color: Colors.pink,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(children: [
                  // Counts row
                  Row(children: [
                    _StatBadge(
                        label: 'Total',
                        value: '${_students.length}'),
                    const SizedBox(width: 8),
                    _StatBadge(
                        label: 'Fee Paid',
                        value: '${_students.where((s) => s.feeStatus == 'Paid').length}'),
                    const SizedBox(width: 8),
                    _StatBadge(
                        label: 'Pending',
                        value: '${_students.where((s) => s.feeStatus != 'Paid').length}'),
                  ]),
                  const SizedBox(height: 8),
                  // Search
                  if (_students.isNotEmpty)
                    TextField(
                      onChanged: (v) => setState(() => _search = v),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Search students…',
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
                ]),
              ),
              Expanded(
                child: _students.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline,
                                size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text('No students in ${widget.className}',
                                style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey.shade400)),
                            const SizedBox(height: 6),
                            Text('Teachers can add students here',
                                style: TextStyle(
                                    fontSize: 13,
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
                            color: Colors.pink,
                            child: ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(0, 8, 0, 20),
                              itemCount: _filtered.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1, indent: 80),
                              itemBuilder: (_, i) =>
                                  _CoordStudentTile(student: _filtered[i]),
                            ),
                          ),
              ),
            ]),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String label;
  final String value;
  const _StatBadge({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.white70)),
        ]),
      ),
    );
  }
}

class _CoordStudentTile extends StatelessWidget {
  final Student student;
  const _CoordStudentTile({required this.student});

  Color get _feeColor {
    switch (student.feeStatus) {
      case 'Paid':    return Colors.green;
      case 'Partial': return Colors.orange;
      default:        return Colors.red;
    }
  }

  // ── Contact bottom sheet ──────────────────────────────────────────────────

  void _showContact(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ContactSheet(student: student),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showContact(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: Colors.pink.shade50,
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
                        color: Colors.pink.shade300))
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
                  if (student.motherName != null &&
                      student.motherName!.isNotEmpty)
                    Text('Mother: ${student.motherName}',
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
              size: 18, color: Colors.grey.shade300),
        ]),
      ),
    );
  }
}

// ── Contact sheet (call + WhatsApp) ───────────────────────────────────────────

class _ContactSheet extends StatelessWidget {
  final Student student;
  const _ContactSheet({required this.student});

  Color get _feeColor {
    switch (student.feeStatus) {
      case 'Paid':    return Colors.green;
      case 'Partial': return Colors.orange;
      default:        return Colors.red;
    }
  }

  Future<void> _call() async {
    final uri = Uri(scheme: 'tel', path: student.phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _whatsapp() async {
    final digits = student.phone.replaceAll(RegExp(r'\D'), '');
    await launchUrl(
      Uri.parse('https://wa.me/$digits'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPhone = student.phone.isNotEmpty;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          width: 36, height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),

        // Avatar + name
        const SizedBox(height: 4),
        CircleAvatar(
          radius: 36,
          backgroundColor: Colors.pink.shade50,
          backgroundImage: student.photoPath != null
              ? FileImage(File(student.photoPath!))
              : null,
          child: student.photoPath == null
              ? Text(
                  student.name.isNotEmpty
                      ? student.name[0].toUpperCase() : '?',
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.pink.shade300))
              : null,
        ),
        const SizedBox(height: 10),
        Text(student.name,
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(
          '${student.className}  ·  Roll ${student.roll}',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
        ),

        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 12),

        // Phone row
        if (hasPhone) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(children: [
              Icon(Icons.phone_outlined,
                  size: 16, color: Colors.grey.shade500),
              const SizedBox(width: 8),
              Text(student.phone,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w500)),
            ]),
          ),
          const SizedBox(height: 16),

          // Action buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(children: [
              Expanded(
                child: _ActionBtn(
                  icon: Icons.call,
                  label: 'Call',
                  color: Colors.green.shade600,
                  onTap: _call,
                ),
              ),
              const SizedBox(width: 14),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(children: [
              Icon(Icons.phone_disabled_outlined,
                  size: 16, color: Colors.grey.shade400),
              const SizedBox(width: 8),
              Text('No phone number on record',
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey.shade400)),
            ]),
          ),

        // Details
        const SizedBox(height: 16),
        const Divider(height: 1),
        _DetailRow(Icons.man_outlined, "Father",
            student.fatherName.isNotEmpty ? student.fatherName : '—'),
        if (student.motherName != null &&
            student.motherName!.isNotEmpty)
          _DetailRow(
              Icons.woman_outlined, "Mother", student.motherName!),
        _DetailRow(
          Icons.currency_rupee,
          "Fee",
          student.feeStatus,
          valueColor: _feeColor,
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

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  const _DetailRow(this.icon, this.label, this.value, {this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Row(children: [
        Icon(icon, size: 18, color: Colors.grey.shade400),
        const SizedBox(width: 12),
        Text('$label  ',
            style: TextStyle(
                fontSize: 13, color: Colors.grey.shade500)),
        Expanded(
          child: Text(value,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: valueColor)),
          ),
      ]),
    );
  }
}

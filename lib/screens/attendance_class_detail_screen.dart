import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/teacher.dart';
import '../services/student_service.dart';
import '../services/timetable_service.dart';
import '../theme.dart';

class AttendanceClassDetailScreen extends StatefulWidget {
  final ClassSummary summary;
  const AttendanceClassDetailScreen({super.key, required this.summary});

  @override
  State<AttendanceClassDetailScreen> createState() =>
      _AttendanceClassDetailScreenState();
}

class _AttendanceClassDetailScreenState
    extends State<AttendanceClassDetailScreen> {
  bool _loading = true;
  String _classTeacherName = '—';
  Map<int, int> _absenceDays = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    // Find class teacher
    final teachers = await TimetableService().getTeachers();
    final ct = teachers.firstWhere(
      (t) =>
          t.isClassTeacher &&
          t.classTeacherOf == widget.summary.className,
      orElse: () =>
          const Teacher(id: '', name: '', subject: '', email: ''),
    );

    // Recent absence days (last 14 days) per student roll
    final absenceDays = await StudentService()
        .loadRecentAbsenceDays(widget.summary.className, days: 14);

    if (!mounted) return;
    setState(() {
      _classTeacherName =
          ct.id.isEmpty ? 'Not assigned' : ct.name;
      _absenceDays = absenceDays;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    final absent  = s.absentLeave.where((n) => n.status == 'Absent').toList();
    final onLeave = s.absentLeave.where((n) => n.status == 'Leave').toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.className,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold)),
            Text('Attendance Detail',
                style: const TextStyle(
                    fontSize: 11, color: Colors.white70)),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: Colors.indigo,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
          children: [
            // ── Summary card ───────────────────────────────────────────────
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Class teacher row
                  Row(children: [
                    Icon(Icons.person_outline,
                        size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 6),
                    Text('Class Teacher: ',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500)),
                    Expanded(
                      child: Text(
                        _loading ? '…' : _classTeacherName,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  // Stat bubbles
                  Row(children: [
                    _StatPill(s.total,   'Total',   const Color(0xFF546E7A)),
                    _StatPill(s.present, 'Present', const Color(0xFF2E7D32)),
                    _StatPill(s.absent,  'Absent',  const Color(0xFFC62828)),
                    _StatPill(s.leave,   'Leave',   const Color(0xFFF57F17)),
                  ]),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: s.total == 0 ? 0 : s.present / s.total,
                      minHeight: 5,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: const AlwaysStoppedAnimation(
                          Color(0xFF2E7D32)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${s.present} of ${s.total} present',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),

            // ── Absent students ─────────────────────────────────────────────
            if (absent.isNotEmpty) ...[
              _sectionHeader(
                  'ABSENT  (${absent.length})', const Color(0xFFC62828)),
              _StudentCard(
                notes: absent,
                absenceDays: _absenceDays,
              ),
              const SizedBox(height: 8),
            ],

            // ── On Leave students ───────────────────────────────────────────
            if (onLeave.isNotEmpty) ...[
              _sectionHeader(
                  'ON LEAVE  (${onLeave.length})', const Color(0xFFF57F17)),
              _StudentCard(
                notes: onLeave,
                absenceDays: _absenceDays,
              ),
              const SizedBox(height: 8),
            ],

            if (s.absentLeave.isEmpty)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  Icon(Icons.check_circle_outline,
                      color: Colors.green.shade400, size: 22),
                  const SizedBox(width: 10),
                  Text('All students present today!',
                      style: TextStyle(
                          fontSize: 13, color: Colors.green.shade600)),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Text(text,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.6)),
    );
  }
}

// ── Card holding a group of students ─────────────────────────────────────────

class _StudentCard extends StatelessWidget {
  final List<StudentNote> notes;
  final Map<int, int>     absenceDays;

  const _StudentCard({required this.notes, required this.absenceDays});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(children: [
        for (int i = 0; i < notes.length; i++) ...[
          _StudentDetailRow(
              note: notes[i],
              absenceDays: absenceDays[notes[i].roll] ?? 0),
          if (i < notes.length - 1)
            const Divider(height: 1, indent: 52),
        ],
      ]),
    );
  }
}

// ── Per-student detail row ────────────────────────────────────────────────────

class _StudentDetailRow extends StatelessWidget {
  final StudentNote note;
  final int         absenceDays;

  const _StudentDetailRow(
      {required this.note, required this.absenceDays});

  @override
  Widget build(BuildContext context) {
    final isAbsent  = note.status == 'Absent';
    final statusClr = isAbsent
        ? const Color(0xFFC62828)
        : const Color(0xFFF57F17);
    final hasCalled =
        note.reason != null && note.reason!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Top row: avatar, name, status badge ─────────────────────────────
        Row(children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: statusClr.withOpacity(0.1),
            child: Text(
              note.name.isNotEmpty ? note.name[0].toUpperCase() : '?',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: statusClr),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(note.name,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              Text('Roll ${note.roll}',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade500)),
            ]),
          ),
          // Status badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusClr.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(note.status,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: statusClr)),
          ),
        ]),

        const SizedBox(height: 8),

        // ── Bottom row: called status + absence count ─────────────────────
        Row(children: [
          const SizedBox(width: 46), // align under name
          if (hasCalled) ...[
            Icon(Icons.check_circle,
                color: Colors.green.shade600, size: 13),
            const SizedBox(width: 4),
            Text('Called',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.green.shade600,
                    fontWeight: FontWeight.w500)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                note.reason!,
                style: TextStyle(
                    fontSize: 11, color: Colors.grey.shade600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ] else ...[
            Icon(Icons.phone_missed,
                color: Colors.grey.shade400, size: 13),
            const SizedBox(width: 4),
            Expanded(
              child: Text('Not called yet',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade400)),
            ),
            // Call button (if phone available)
            if (note.phone.isNotEmpty)
              GestureDetector(
                onTap: () async {
                  final uri =
                      Uri(scheme: 'tel', path: note.phone);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.call,
                            color: Colors.white, size: 12),
                        SizedBox(width: 3),
                        Text('Call',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.w600)),
                      ]),
                ),
              ),
          ],

          // Absence streak badge
          if (absenceDays > 1) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: Colors.orange.shade200),
              ),
              child: Text(
                '${absenceDays}d / 2wk',
                style: TextStyle(
                    fontSize: 10,
                    color: Colors.orange.shade800,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ]),
      ]),
    );
  }
}

// ── Stat pill ─────────────────────────────────────────────────────────────────

class _StatPill extends StatelessWidget {
  final int    count;
  final String label;
  final Color  color;
  const _StatPill(this.count, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(children: [
        Text('$count',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
                height: 1.1)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

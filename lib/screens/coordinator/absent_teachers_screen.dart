import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../models/substitution_record.dart';
import '../../models/teacher.dart';
import '../../models/timetable_entry.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../../services/substitution_history_service.dart';
import '../../services/timetable_service.dart';
import '../../theme.dart';

class AbsentTeachersScreen extends StatefulWidget {
  const AbsentTeachersScreen({super.key});

  @override
  State<AbsentTeachersScreen> createState() => _AbsentTeachersScreenState();
}

class _AbsentTeachersScreenState extends State<AbsentTeachersScreen> {
  bool _loading = true;
  List<Teacher> _allTeachers = [];
  Map<String, Teacher> _teacherMap = {};
  Map<String, Map<String, Map<int, TimetableEntry>>> _timetable = {};
  Set<String> _absentFromLeave = {};
  Map<String, String> _leaveReasons = {};
  Set<String> _absentFromManual = {};
  Map<String, String> _manualReasons = {};
  String _coordEmail = '';

  late final String _todayName;
  late final String _todayKey;

  static const _dayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
  ];
  static const _months = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _todayName = _dayNames[(now.weekday - 1).clamp(0, 5)];
    _todayKey  = '${now.year}-${now.month}-${now.day}';
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final session = await AuthService().getSession();
    if (!mounted) return;
    _coordEmail = (session?['email'] as String?) ?? '';

    final svc = TimetableService();
    final results = await Future.wait([
      svc.getTeachers(),
      svc.getTimetable(),
      svc.getLeaveApplications(),
      _loadManualAbsences(),
    ]);

    final teachers  = results[0] as List<Teacher>;
    final timetable = results[1] as Map<String, Map<String, Map<int, TimetableEntry>>>;
    final leaves    = results[2] as List<Map<String, dynamic>>;
    final manualDoc = results[3] as Map<String, dynamic>;

    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Approved leaves that cover today
    final absentFromLeave = <String>{};
    final leaveReasons    = <String, String>{};
    for (final leave in leaves) {
      if (leave['status'] != 'approved') continue;
      final startStr = leave['startDate'] as String?;
      if (startStr == null) continue;
      try {
        final parts = startStr.split('-');
        final start = DateTime(
            int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
        final days = (leave['numberOfDays'] as int?) ?? 1;
        final end  = start.add(Duration(days: days - 1));
        if (!today.isBefore(start) && !today.isAfter(end)) {
          final tid = leave['teacherId'] as String? ?? '';
          if (tid.isNotEmpty) {
            absentFromLeave.add(tid);
            leaveReasons[tid] = (leave['reason'] as String?) ?? '';
          }
        }
      } catch (_) {}
    }

    // Manually marked absences for today
    final absentFromManual = <String>{};
    final manualReasons    = <String, String>{};
    final teachersMap = manualDoc['teachers'];
    if (teachersMap is Map) {
      teachersMap.forEach((tid, v) {
        if (v is Map) {
          final status = v['status'] as String? ?? '';
          if (status == 'Absent') {
            absentFromManual.add(tid as String);
            manualReasons[tid] = (v['reason'] as String?) ?? '';
          }
        }
      });
    }

    if (!mounted) return;
    setState(() {
      _allTeachers      = teachers;
      _teacherMap       = {for (final t in teachers) t.id: t};
      _timetable        = timetable;
      _absentFromLeave  = absentFromLeave;
      _leaveReasons     = leaveReasons;
      _absentFromManual = absentFromManual;
      _manualReasons    = manualReasons;
      _loading          = false;
    });
  }

  Future<Map<String, dynamic>> _loadManualAbsences() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('teacher_attendance')
          .doc(_todayKey)
          .get();
      if (!doc.exists || doc.data() == null) return {};
      return Map<String, dynamic>.from(doc.data()!);
    } catch (_) {
      return {};
    }
  }

  Set<String> get _allAbsentIds => {..._absentFromLeave, ..._absentFromManual};

  List<_PeriodData> _getTeacherPeriods(String teacherId) {
    final periods = <_PeriodData>[];
    _timetable.forEach((className, dayMap) {
      final bellMap = dayMap[_todayName];
      if (bellMap == null) return;
      bellMap.forEach((bell, entry) {
        if (entry.teacherId == teacherId) {
          final subj = entry.subject?.isNotEmpty == true
              ? entry.subject!
              : (_teacherMap[teacherId]?.subject ?? '');
          periods.add(_PeriodData(bell, className, subj));
        }
      });
    });
    periods.sort((a, b) => a.bell.compareTo(b.bell));
    return periods;
  }

  List<Teacher> _freeTeachersAt(int bell, Map<String, String> subs) {
    final busy = <String>{..._allAbsentIds};
    _timetable.forEach((cls, dayMap) {
      final entry = dayMap[_todayName]?[bell];
      if (entry?.teacherId != null) busy.add(entry!.teacherId!);
    });
    subs.forEach((key, subId) {
      final lastUs = key.lastIndexOf('_');
      if (lastUs > 0) {
        final b = int.tryParse(key.substring(lastUs + 1));
        if (b == bell && subId.isNotEmpty) busy.add(subId);
      }
    });
    return _allTeachers.where((t) => !busy.contains(t.id)).toList();
  }

  Future<void> _assignSubstitute({
    required Teacher absent,
    required Teacher substitute,
    required String className,
    required int bell,
    required String subject,
  }) async {
    await TimetableService().setSubstitution(className, bell, substitute.id);

    final now = DateTime.now();
    await SubstitutionHistoryService().logSubstitution(SubstitutionRecord(
      id:                    '',
      dateKey:               _todayKey,
      date:                  now,
      className:             className,
      bell:                  bell,
      substituteTeacherId:   substitute.id,
      substituteTeacherName: substitute.name,
      originalTeacherId:     absent.id,
      originalTeacherName:   absent.name,
      subject:               subject,
      createdAt:             now,
    ));

    await NotificationService().addSubstitutionAssigned(
      teacherId: substitute.id,
      className: className,
      bell:      bell,
      subject:   subject,
      date:      now,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${substitute.name} assigned for Bell $bell'),
      backgroundColor: AppTheme.success,
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _removeSubstitute(String className, int bell) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Substitute'),
        content: Text('Remove substitute for Bell $bell in $className?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove',
                style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await TimetableService().setSubstitution(className, bell, null);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Substitute removed'),
      duration: Duration(seconds: 2),
    ));
  }

  Future<void> _showAssignSheet({
    required Teacher absent,
    required int bell,
    required String className,
    required String subject,
    required Map<String, String> subs,
  }) async {
    final free = _freeTeachersAt(bell, subs);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sheet header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.06),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('Bell $bell',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '$className${subject.isNotEmpty ? ' · $subject' : ''}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text('Covering for ${absent.name}',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),

            if (free.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'No free teachers available at Bell $bell',
                  style: TextStyle(
                      color: Colors.grey.shade600, fontSize: 14),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight:
                        MediaQuery.of(context).size.height * 0.5),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1),
                  itemCount: free.length,
                  itemBuilder: (_, i) {
                    final t = free[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            AppTheme.primary.withOpacity(0.12),
                        child: Text(
                          t.name[0].toUpperCase(),
                          style: const TextStyle(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(t.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600)),
                      subtitle: Text(t.subject),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.success.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppTheme.success.withOpacity(0.3)),
                        ),
                        child: Text('Free B$bell',
                            style: const TextStyle(
                                color: AppTheme.success,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ),
                      onTap: () async {
                        Navigator.pop(context);
                        await _assignSubstitute(
                          absent:    absent,
                          substitute: t,
                          className: className,
                          bell:      bell,
                          subject:   subject,
                        );
                      },
                    );
                  },
                ),
              ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _showMarkAbsentSheet() async {
    Teacher? selected;
    final reasonCtrl = TextEditingController();
    final remaining  = _allTeachers
        .where((t) => !_allAbsentIds.contains(t.id))
        .toList();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Mark Teacher Absent',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),

                DropdownButtonFormField<Teacher>(
                  value: selected,
                  decoration: InputDecoration(
                    labelText: 'Select Teacher',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    prefixIcon: const Icon(Icons.person_outlined),
                  ),
                  items: remaining
                      .map((t) => DropdownMenuItem(
                          value: t, child: Text(t.name)))
                      .toList(),
                  onChanged: (v) => setLocal(() => selected = v),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: reasonCtrl,
                  decoration: InputDecoration(
                    labelText: 'Reason (optional)',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    prefixIcon: const Icon(Icons.notes_outlined),
                  ),
                ),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: selected == null
                        ? null
                        : () async {
                            final t      = selected!;
                            final reason = reasonCtrl.text.trim();
                            Navigator.pop(ctx);
                            await FirebaseFirestore.instance
                                .collection('teacher_attendance')
                                .doc(_todayKey)
                                .set(
                              {
                                'teachers': {
                                  t.id: {
                                    'status':      'Absent',
                                    'reason':      reason,
                                    'teacherName': t.name,
                                    'markedBy':    _coordEmail,
                                    'markedAt':    FieldValue.serverTimestamp(),
                                  }
                                }
                              },
                              SetOptions(merge: true),
                            );
                            _load();
                          },
                    icon: const Icon(Icons.person_off_outlined),
                    label: const Text('Mark Absent'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.danger,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _exportPdf() async {
    final now     = DateTime.now();
    final dateStr = '${now.day} ${_months[now.month]} ${now.year}';
    final subs    = await TimetableService().getTodaySubstitutions();

    final pdf = pw.Document();

    final rows = <List<String>>[];
    for (final tid in _allAbsentIds) {
      final teacher = _teacherMap[tid];
      if (teacher == null) continue;
      final periods = _getTeacherPeriods(tid);
      for (final p in periods) {
        final subId   = subs[p.key];
        final subName = subId != null
            ? (_teacherMap[subId]?.name ?? subId)
            : '—';
        rows.add([
          '${p.bell}',
          p.className,
          p.subject,
          teacher.name,
          subName,
        ]);
      }
    }

    if (rows.isEmpty) {
      rows.add(['—', '—', '—', '—', '—']);
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => [
          pw.Text('Substitution Plan — $dateStr',
              style: pw.TextStyle(
                  fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text('Generated by $_coordEmail',
              style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: [
              'Bell', 'Class', 'Subject', 'Absent Teacher', 'Substitute'
            ],
            data: rows,
            headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.purple900),
            oddRowDecoration:
                const pw.BoxDecoration(color: PdfColors.grey200),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 8, vertical: 6),
          ),
        ],
      ),
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: Uint8List.fromList(bytes),
      filename: 'substitutions_$_todayKey.pdf',
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final now     = DateTime.now();
    final dateStr = '${now.day} ${_months[now.month]} ${now.year}';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Absent Teachers — $dateStr',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const Text('Substitution management',
                style: TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Export PDF',
            onPressed: _loading ? null : _exportPdf,
          ),
          IconButton(
            icon: const Icon(Icons.person_off_outlined),
            tooltip: 'Mark Teacher Absent',
            onPressed: _loading ? null : _showMarkAbsentSheet,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              color: AppTheme.primary,
              child: StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('substitutions')
                    .doc(_todayKey)
                    .snapshots(),
                builder: (context, snap) {
                  final subs = <String, String>{};
                  if (snap.hasData && snap.data!.exists) {
                    (snap.data!.data() as Map<String, dynamic>)
                        .forEach((k, v) {
                      if (v is String && v.isNotEmpty) subs[k] = v;
                    });
                  }
                  return _buildContent(subs);
                },
              ),
            ),
    );
  }

  Widget _buildContent(Map<String, String> subs) {
    final absentIds = _allAbsentIds;

    if (absentIds.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline,
                    size: 64, color: Colors.green.shade400),
                const SizedBox(height: 16),
                const Text('All teachers present today',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text('No absences recorded',
                    style: TextStyle(color: Colors.grey.shade500)),
              ],
            ),
          ),
        ],
      );
    }

    // Summary stats
    var uncovered = 0;
    var assigned  = 0;
    for (final tid in absentIds) {
      for (final p in _getTeacherPeriods(tid)) {
        if (subs.containsKey(p.key)) {
          assigned++;
        } else {
          uncovered++;
        }
      }
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        _buildSummaryBar(absentIds.length, uncovered, assigned),
        const SizedBox(height: 12),
        for (final tid in absentIds)
          if (_teacherMap.containsKey(tid))
            _buildTeacherCard(_teacherMap[tid]!, subs),
      ],
    );
  }

  Widget _buildSummaryBar(int absent, int uncovered, int assigned) {
    return Row(children: [
      _chip('$absent Absent', AppTheme.danger),
      const SizedBox(width: 8),
      _chip('$uncovered Uncovered', AppTheme.warning),
      const SizedBox(width: 8),
      _chip('$assigned Assigned', AppTheme.success),
    ]);
  }

  Widget _chip(String label, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: color),
          ),
        ),
      );

  Widget _buildTeacherCard(Teacher teacher, Map<String, String> subs) {
    final isOnLeave   = _absentFromLeave.contains(teacher.id);
    final leaveReason  = _leaveReasons[teacher.id]  ?? '';
    final manualReason = _manualReasons[teacher.id] ?? '';
    final periods      = _getTeacherPeriods(teacher.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: Color(0xFFFFEBEE),
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppTheme.primary.withOpacity(0.12),
                child: Text(
                  teacher.name[0].toUpperCase(),
                  style: const TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 18),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(teacher.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(teacher.subject,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade700)),
                  if (teacher.classTeacherOf != null)
                    Text('Class teacher of ${teacher.classTeacherOf}',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500)),
                  if (isOnLeave && leaveReason.isNotEmpty)
                    Row(children: [
                      const Icon(Icons.event_busy_outlined,
                          size: 12, color: AppTheme.danger),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text('Leave: $leaveReason',
                            style: const TextStyle(
                                fontSize: 11, color: AppTheme.danger),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ])
                  else if (!isOnLeave && manualReason.isNotEmpty)
                    Row(children: [
                      const Icon(Icons.info_outline,
                          size: 12, color: AppTheme.warning),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text('Reason: $manualReason',
                            style: const TextStyle(
                                fontSize: 11, color: AppTheme.warning),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ]),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: AppTheme.danger.withOpacity(0.3)),
                ),
                child: Text(
                  isOnLeave ? 'On Leave' : 'Absent',
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.danger),
                ),
              ),
            ]),
          ),

          // Periods
          if (periods.isEmpty)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text('No periods assigned today',
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey.shade500)),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: Text('UNCOVERED PERIODS TODAY',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade500,
                      letterSpacing: 0.5)),
            ),
            for (int i = 0; i < periods.length; i++) ...[
              if (i > 0)
                const Divider(height: 1, indent: 14, endIndent: 14),
              _buildPeriodRow(teacher, periods[i], subs),
            ],
          ],

          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildPeriodRow(
      Teacher absent, _PeriodData period, Map<String, String> subs) {
    final subId     = subs[period.key];
    final isCovered = subId != null && subId.isNotEmpty;
    final subName   = isCovered
        ? (_teacherMap[subId]?.name ?? subId)
        : null;

    return GestureDetector(
      onLongPress: isCovered
          ? () => _removeSubstitute(period.className, period.bell)
          : null,
      child: Container(
        color: isCovered
            ? const Color(0xFFE8F5E9)
            : const Color(0xFFFFF8E1),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          // Bell pill
          Container(
            width: 38, height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isCovered ? AppTheme.success : AppTheme.warning,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
              Text('${period.bell}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      height: 1.0)),
              const Text('bell',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 8,
                      height: 1.0)),
            ]),
          ),
          const SizedBox(width: 10),

          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(period.className,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              if (period.subject.isNotEmpty)
                Text(period.subject,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade600)),
            ]),
          ),

          if (isCovered)
            Row(children: [
              Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                Text(subName!,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.success)),
                const Text('Long press to remove',
                    style: TextStyle(fontSize: 9, color: Colors.grey)),
              ]),
              const SizedBox(width: 6),
              const Icon(Icons.check_circle,
                  color: AppTheme.success, size: 18),
            ])
          else
            TextButton.icon(
              onPressed: () => _showAssignSheet(
                absent:    absent,
                bell:      period.bell,
                className: period.className,
                subject:   period.subject,
                subs:      subs,
              ),
              icon: const Icon(Icons.person_add_outlined, size: 16),
              label: const Text('Assign',
                  style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.warning,
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
              ),
            ),
        ]),
      ),
    );
  }
}

// ── Data classes ──────────────────────────────────────────────────────────────

class _PeriodData {
  final int    bell;
  final String className;
  final String subject;

  const _PeriodData(this.bell, this.className, this.subject);

  String get key => '${className}_$bell';
}

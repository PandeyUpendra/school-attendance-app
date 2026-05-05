import 'package:flutter/material.dart';
import '../models/substitution_record.dart';
import '../models/teacher.dart';
import '../services/notification_service.dart';
import '../services/substitution_history_service.dart';
import '../services/substitution_suggester_service.dart';
import '../services/timetable_service.dart';
import '../theme.dart';

/// One-screen plan for covering an absent teacher's bells across their leave.
///
/// Shown after a leave is approved. Each affected bell gets a top-ranked
/// suggested substitute (free + same subject + low sub-load + not on duty).
/// Coordinator can tap any row to pick a different teacher, then "Assign All"
/// commits everything in one go and notifies each substitute.
class SubstitutionPlanScreen extends StatefulWidget {
  final String   teacherId;
  final String   teacherName;
  final DateTime startDate;
  final int      numberOfDays;

  const SubstitutionPlanScreen({
    super.key,
    required this.teacherId,
    required this.teacherName,
    required this.startDate,
    required this.numberOfDays,
  });

  @override
  State<SubstitutionPlanScreen> createState() => _SubstitutionPlanScreenState();
}

class _SubstitutionPlanScreenState extends State<SubstitutionPlanScreen> {
  bool _loading  = true;
  bool _saving   = false;
  List<SuggestedSlot> _slots = [];

  /// slot.key → selected teacherId  (null = skip this slot)
  final Map<String, String?> _selections = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final slots = await SubstitutionSuggesterService().buildPlan(
      absentTeacherId: widget.teacherId,
      startDate:       widget.startDate,
      numberOfDays:    widget.numberOfDays,
    );
    if (!mounted) return;
    setState(() {
      _slots = slots;
      _selections
        ..clear()
        ..addEntries(slots.map((s) => MapEntry(s.key, s.topPick?.teacher.id)));
      _loading = false;
    });
  }

  int get _assignableCount =>
      _selections.values.where((v) => v != null && v.isNotEmpty).length;

  Future<void> _assignAll() async {
    if (_assignableCount == 0) return;
    setState(() => _saving = true);

    final svc        = TimetableService();
    final histSvc    = SubstitutionHistoryService();
    final notifSvc   = NotificationService();
    final teacherMap = {for (final t in await svc.getTeachers()) t.id: t};

    int saved = 0;
    for (final slot in _slots) {
      final tid = _selections[slot.key];
      if (tid == null || tid.isEmpty) continue;
      final sub = teacherMap[tid];
      if (sub == null) continue;

      await svc.setSubstitutionForDate(
          slot.date, slot.className, slot.bell, tid);

      final now = DateTime.now();
      await histSvc.logSubstitution(SubstitutionRecord(
        id:                    '',
        dateKey:               '${slot.date.year}-${slot.date.month}-${slot.date.day}',
        date:                  slot.date,
        className:             slot.className,
        bell:                  slot.bell,
        substituteTeacherId:   tid,
        substituteTeacherName: sub.name,
        originalTeacherId:     slot.originalTeacherId,
        originalTeacherName:   slot.originalTeacherName,
        subject:               slot.subject,
        createdAt:             now,
      ));

      await notifSvc.addSubstitutionAssigned(
        teacherId: tid,
        className: slot.className,
        bell:      slot.bell,
        subject:   slot.subject,
        date:      slot.date,
      );

      saved++;
    }

    if (!mounted) return;
    setState(() => _saving = false);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Assigned $saved substitution${saved == 1 ? '' : 's'}'
          ' and notified teachers.'),
      backgroundColor: Colors.green.shade700,
      duration: const Duration(seconds: 3),
    ));
    Navigator.pop(context);
  }

  Future<void> _pickAlternate(SuggestedSlot slot) async {
    final currentSel = _selections[slot.key];
    final picked = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _CandidatePickerSheet(slot: slot, currentSelection: currentSel);
      },
    );
    if (picked == null) return; // sheet dismissed without action
    setState(() {
      _selections[slot.key] = picked.isEmpty ? null : picked;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Substitution Plan',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text(widget.teacherName,
                style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recompute suggestions',
            onPressed: _loading || _saving ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _slots.isEmpty
              ? _emptyState()
              : Column(children: [
                  _buildSummary(),
                  Expanded(child: _buildList()),
                ]),
      bottomNavigationBar: _slots.isEmpty || _loading ? null : _buildBottomBar(),
    );
  }

  Widget _emptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.event_available_outlined,
                    size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                const Text('No bells need covering',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(
                  'Either the timetable has no entries for ${widget.teacherName} '
                  'during the leave window, or all affected bells already have a '
                  'substitute assigned.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ]),
        ),
      );

  Widget _buildSummary() {
    final total       = _slots.length;
    final picked      = _assignableCount;
    final noCandidate = _slots.where((s) => s.candidates.isEmpty).length;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primary.withOpacity(0.15)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.auto_awesome, color: AppTheme.primary, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text('Smart Substitution Plan',
                style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          '$total bell${total == 1 ? '' : 's'} need${total == 1 ? 's' : ''} cover • '
          '$picked ready to assign'
          '${noCandidate > 0 ? ' • $noCandidate without free teachers' : ''}',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 4, children: [
          _legendChip('Free that bell', Colors.green),
          _legendChip('Same subject', AppTheme.primary),
          _legendChip('Low sub-load', Colors.blue),
          _legendChip('Not on duty', Colors.teal),
        ]),
      ]),
    );
  }

  Widget _legendChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _buildList() {
    // Group by date.
    final groups = <String, List<SuggestedSlot>>{};
    for (final s in _slots) {
      final k = '${s.date.year}-${s.date.month}-${s.date.day}';
      groups.putIfAbsent(k, () => []).add(s);
    }
    final dateKeys = groups.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
      itemCount: dateKeys.length,
      itemBuilder: (_, i) {
        final slots = groups[dateKeys[i]]!;
        final first = slots.first;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.06),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Text(
                '${first.dayName}, ${_fmtDate(first.date)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryDark,
                ),
              ),
            ),
            for (int j = 0; j < slots.length; j++) ...[
              if (j > 0) const Divider(height: 1, indent: 14, endIndent: 14),
              _buildSlotRow(slots[j]),
            ],
          ]),
        );
      },
    );
  }

  Widget _buildSlotRow(SuggestedSlot slot) {
    final selId = _selections[slot.key];
    final selected = slot.candidates
        .where((c) => c.teacher.id == selId)
        .firstOrNull
        ?.teacher;
    final reasons = slot.candidates
        .where((c) => c.teacher.id == selId)
        .firstOrNull
        ?.reasons ?? const <String>[];

    final hasNoCandidate = slot.candidates.isEmpty;

    return InkWell(
      onTap: hasNoCandidate ? null : () => _pickAlternate(slot),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          // Bell pill
          Container(
            width: 38, height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('${slot.bell}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      height: 1.0)),
              const Text('bell',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 8, height: 1.0)),
            ]),
          ),
          const SizedBox(width: 12),
          // Class + subject + selected sub
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(slot.className,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                    if (slot.subject.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text('· ${slot.subject}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ]),
                  const SizedBox(height: 4),
                  if (hasNoCandidate)
                    Row(children: [
                      Icon(Icons.error_outline,
                          color: Colors.orange.shade700, size: 14),
                      const SizedBox(width: 4),
                      Text('No free teachers for this bell',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.orange.shade800,
                              fontWeight: FontWeight.w600)),
                    ])
                  else if (selected == null)
                    Row(children: [
                      Icon(Icons.remove_circle_outline,
                          color: Colors.grey.shade500, size: 14),
                      const SizedBox(width: 4),
                      Text('Skipped — tap to assign',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600)),
                    ])
                  else
                    Row(children: [
                      const Icon(Icons.person, color: AppTheme.primary, size: 14),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(selected.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                      if (reasons.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text('• ${reasons.first}',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 10, color: Colors.grey.shade500)),
                        ),
                      ],
                    ]),
                ]),
          ),
          if (!hasNoCandidate)
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
        ]),
      ),
    );
  }

  Widget _buildBottomBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('Later'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: _saving || _assignableCount == 0 ? null : _assignAll,
              icon: _saving
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check, size: 16),
              label: Text(_saving
                  ? 'Assigning…'
                  : 'Assign All ($_assignableCount)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  String _fmtDate(DateTime d) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month]}';
  }
}

// ── Candidate picker bottom sheet ────────────────────────────────────────────

class _CandidatePickerSheet extends StatefulWidget {
  final SuggestedSlot slot;
  final String?       currentSelection;

  const _CandidatePickerSheet({
    required this.slot,
    required this.currentSelection,
  });

  @override
  State<_CandidatePickerSheet> createState() => _CandidatePickerSheetState();
}

class _CandidatePickerSheetState extends State<_CandidatePickerSheet> {
  late String? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.currentSelection;
  }

  @override
  Widget build(BuildContext context) {
    final slot = widget.slot;
    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.78),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          width: 36, height: 4,
          decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Pick Substitute',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                Text(
                    '${slot.className} · Bell ${slot.bell} · ${slot.dayName}'
                    '${slot.subject.isEmpty ? '' : ' · ${slot.subject}'}',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600)),
              ]),
        ),
        const Divider(height: 1),
        if (slot.candidates.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No free teachers for this bell.',
                style: TextStyle(color: Colors.grey)),
          )
        else
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: slot.candidates.length,
              itemBuilder: (_, i) {
                final c   = slot.candidates[i];
                final t   = c.teacher;
                final sel = t.id == _selectedId;
                final isTopPick = i == 0;
                return _CandidateTile(
                  teacher:    t,
                  reasons:    c.reasons,
                  selected:   sel,
                  isTopPick:  isTopPick,
                  score:      c.score,
                  onTap: () =>
                      setState(() => _selectedId = sel ? null : t.id),
                );
              },
            ),
          ),
        Container(
          padding: EdgeInsets.fromLTRB(
              20, 10, 20, MediaQuery.of(context).padding.bottom + 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(children: [
            if (widget.currentSelection != null)
              TextButton.icon(
                onPressed: () => Navigator.pop(context, ''),
                icon: const Icon(Icons.clear, color: Colors.red, size: 16),
                label: const Text('Skip this bell',
                    style: TextStyle(color: Colors.red)),
              ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: _selectedId == null
                  ? null
                  : () => Navigator.pop(context, _selectedId),
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Use this teacher'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade200,
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _CandidateTile extends StatelessWidget {
  final Teacher      teacher;
  final List<String> reasons;
  final bool         selected;
  final bool         isTopPick;
  final int          score;
  final VoidCallback onTap;

  const _CandidateTile({
    required this.teacher,
    required this.reasons,
    required this.selected,
    required this.isTopPick,
    required this.score,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final initial = teacher.name.isEmpty
        ? '?'
        : teacher.name[0].toUpperCase();
    return ListTile(
      leading: Stack(clipBehavior: Clip.none, children: [
        CircleAvatar(
          backgroundColor: selected
              ? AppTheme.primary
              : AppTheme.primary.withOpacity(0.12),
          child: Text(initial,
              style: TextStyle(
                  color: selected ? Colors.white : AppTheme.primary,
                  fontWeight: FontWeight.bold)),
        ),
        if (isTopPick)
          Positioned(
            right: -4, top: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: AppTheme.accent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('TOP',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold)),
            ),
          ),
      ]),
      title: Text(teacher.name,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(teacher.subject,
                style: TextStyle(
                    fontSize: 11, color: Colors.grey.shade600)),
            if (reasons.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 3,
                children: reasons.map(_reasonChip).toList(),
              ),
            ],
          ]),
      trailing: selected
          ? const Icon(Icons.check_circle, color: AppTheme.primary)
          : null,
      selected: selected,
      selectedTileColor: AppTheme.primary.withOpacity(0.05),
      onTap: onTap,
    );
  }

  Widget _reasonChip(String label) {
    Color color;
    if (label.toLowerCase().contains('same subject')) {
      color = AppTheme.primary;
    } else if (label.toLowerCase().contains('on duty')) {
      color = Colors.orange;
    } else if (label.toLowerCase().contains('no subs')) {
      color = Colors.green;
    } else {
      color = Colors.blueGrey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 9, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

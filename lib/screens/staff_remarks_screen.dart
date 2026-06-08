import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../theme.dart';
import '../models/staff_remark.dart';
import '../models/teacher.dart';
import '../services/auth_service.dart';
import '../services/staff_remark_service.dart';
import '../services/timetable_service.dart';
import '../services/notification_service.dart';

/// Remark / feedback hub for staff.
///
/// Behaviour by [role]:
///   • teacher / subjectTeacher → "Received" only (read remarks given to them)
///   • coordinator              → "Received" + "Given" (give remarks to teachers)
///   • principal / owner        → "Given" (give remarks to teachers & coordinators)
class StaffRemarksScreen extends StatefulWidget {
  final String role;
  final String userEmail;
  final String userName;

  /// Required when [role] is a teacher — the teacher's id (recipient key).
  final String? teacherId;

  const StaffRemarksScreen({
    super.key,
    required this.role,
    required this.userEmail,
    required this.userName,
    this.teacherId,
  });

  @override
  State<StaffRemarksScreen> createState() => _StaffRemarksScreenState();
}

class _StaffRemarksScreenState extends State<StaffRemarksScreen> {
  final _service = StaffRemarkService();

  /// Normalised to match how emails are stored (lowercase doc ids) and the
  /// lowercased auth-token email the Firestore create rule checks against.
  String get _myEmail => widget.userEmail.trim().toLowerCase();

  bool get _isTeacher =>
      widget.role == 'teacher' || widget.role == 'subjectTeacher';
  bool get _isCoordinator => widget.role == 'coordinator';

  /// May this role give remarks at all? (coordinator, principal, owner, …)
  bool get _canGive => !_isTeacher;

  /// May this role receive remarks? (teachers, coordinators)
  bool get _canReceive => _isTeacher || _isCoordinator;

  @override
  Widget build(BuildContext context) {
    final tabs = <Tab>[];
    final views = <Widget>[];

    if (_canReceive) {
      tabs.add(Tab(text: context.tr('receivedTab')));
      views.add(_buildReceived());
    }
    if (_canGive) {
      tabs.add(Tab(text: context.tr('givenTab')));
      views.add(_buildGiven());
    }

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: AppTheme.primaryDark,
          foregroundColor: Colors.white,
          title: Text(context.tr('remarksTitle')),
          bottom: tabs.length > 1
              ? TabBar(
                  indicatorColor: Colors.white,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  tabs: tabs,
                )
              : null,
        ),
        floatingActionButton: _canGive
            ? FloatingActionButton.extended(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.rate_review_outlined),
                label: Text(context.tr('giveRemark')),
                onPressed: _openGiveRemark,
              )
            : null,
        body: tabs.length > 1
            ? TabBarView(children: views)
            : views.first,
      ),
    );
  }

  // ── Received tab ──────────────────────────────────────────────────────────

  Widget _buildReceived() {
    final Stream<List<StaffRemark>> stream = _isTeacher
        ? _service.streamForTeacher(widget.teacherId ?? '')
        : _service.streamForCoordinator(_myEmail);

    return StreamBuilder<List<StaffRemark>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppTheme.primary));
        }
        final items = snap.data ?? [];
        if (items.isEmpty) {
          return _emptyState(
            Icons.inbox_outlined,
            context.tr('noRemarksYet'),
            context.tr('remarksAppearHere'),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _RemarkCard(
            remark: items[i],
            showFrom: true,
          ),
        );
      },
    );
  }

  // ── Given tab ─────────────────────────────────────────────────────────────

  Widget _buildGiven() {
    return StreamBuilder<List<StaffRemark>>(
      stream: _service.streamGivenBy(_myEmail),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppTheme.primary));
        }
        final items = snap.data ?? [];
        if (items.isEmpty) {
          return _emptyState(
            Icons.rate_review_outlined,
            context.tr('noRemarksGivenYet'),
            context.tr('tapGiveRemarkHint'),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _RemarkCard(
            remark: items[i],
            showFrom: false,
            onDelete: () => _confirmDelete(items[i]),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(StaffRemark remark) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.tr('deleteRemarkQ')),
        content: Text('${context.tr('removeRemarkSentToPrefix')} ${remark.toName}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr('cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
              child: Text(context.tr('delete'))),
        ],
      ),
    );
    if (ok == true) {
      await _service.deleteRemark(remark.id);
    }
  }

  // ── Give remark flow ──────────────────────────────────────────────────────

  Future<void> _openGiveRemark() async {
    // Principal may target teachers OR coordinators; coordinator only teachers.
    final canTargetCoordinators = !_isCoordinator;

    final recipient = await showModalBottomSheet<_Recipient>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RecipientPicker(
        allowCoordinators: canTargetCoordinators,
      ),
    );
    if (recipient == null || !mounted) return;

    final text = await showDialog<String>(
      context: context,
      builder: (_) => _RemarkComposer(recipientName: recipient.name),
    );
    if (text == null || text.trim().isEmpty || !mounted) return;

    final remark = StaffRemark(
      id: '',
      schoolId: AuthService.currentSchoolId,
      fromEmail: _myEmail,
      fromName: widget.userName,
      fromRole: widget.role,
      toEmail: recipient.email.trim().toLowerCase(),
      toName: recipient.name,
      toRole: recipient.role,
      toTeacherId: recipient.teacherId,
      remark: text.trim(),
      timestamp: DateTime.now(),
    );

    try {
      await _service.addRemark(remark);
      // Best-effort in-app notification to the recipient.
      final audience = recipient.role == 'coordinator'
          ? 'coordinator'
          : 'teacher:${recipient.teacherId}';
      await NotificationService().addStaffTaskNotice(
        taskTitle: 'New remark from ${widget.userName}',
        assignedTeacherId: recipient.teacherId ?? '',
        assignedByName: widget.userName,
        audience: audience,
      );
    } catch (_) {
      // Notification failure must not block the remark write.
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${context.tr('remarkSentToPrefix')} ${recipient.name}')),
      );
    }
  }

  // ── Shared ─────────────────────────────────────────────────────────────────

  Widget _emptyState(IconData icon, String title, String subtitle) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
            ],
          ),
        ),
      );
}

// ── Remark card ───────────────────────────────────────────────────────────────

class _RemarkCard extends StatelessWidget {
  final StaffRemark remark;
  final bool showFrom; // true on Received (show giver); false on Given (show recipient)
  final VoidCallback? onDelete;

  const _RemarkCard({
    required this.remark,
    required this.showFrom,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final person = showFrom ? remark.fromName : remark.toName;
    final personRole = showFrom ? remark.fromRole : remark.toRole;
    final label = showFrom ? context.tr('fromLabel') : context.tr('toLabel');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
              child: Text(
                person.isNotEmpty ? person[0].toUpperCase() : '?',
                style: const TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$label: $person',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  Text(_prettyRole(context, personRole),
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade500)),
                ],
              ),
            ),
            Text(_fmtDate(remark.timestamp),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
            if (onDelete != null)
              InkWell(
                onTap: onDelete,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(Icons.delete_outline,
                      size: 18, color: Colors.grey.shade400),
                ),
              ),
          ]),
          const SizedBox(height: 10),
          Text(remark.remark,
              style: const TextStyle(fontSize: 14, height: 1.35)),
        ],
      ),
    );
  }

  static String _prettyRole(BuildContext context, String role) {
    switch (role) {
      case 'teacher':
      case 'subjectTeacher':
        return context.trRole('teacher');
      case 'coordinator':
        return context.trRole('coordinator');
      case 'principal':
        return context.trRole('principal');
      case 'owner':
      case 'ownerPrincipal':
        return context.trRole('owner');
      default:
        return role;
    }
  }

  static String _fmtDate(DateTime d) {
    const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${mo[d.month - 1]}';
  }
}

// ── Recipient model + picker ────────────────────────────────────────────────────

class _Recipient {
  final String email;
  final String name;
  final String role;       // 'teacher' | 'coordinator'
  final String? teacherId; // non-null for teachers
  const _Recipient({
    required this.email,
    required this.name,
    required this.role,
    this.teacherId,
  });
}

class _RecipientPicker extends StatefulWidget {
  final bool allowCoordinators;
  const _RecipientPicker({required this.allowCoordinators});

  @override
  State<_RecipientPicker> createState() => _RecipientPickerState();
}

class _RecipientPickerState extends State<_RecipientPicker> {
  bool _loading = true;
  String _search = '';
  bool _showCoordinators = false; // when true, list coordinators instead of teachers
  List<Teacher> _teachers = [];
  List<Map<String, dynamic>> _coordinators = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ts = TimetableService();
    final sid = AuthService.currentSchoolId;
    try {
      final teachers = await ts.getTeachers();
      List<Map<String, dynamic>> coords = [];
      if (widget.allowCoordinators) {
        coords = await ts.getCoordinators(sid);
      }
      if (!mounted) return;
      setState(() {
        _teachers = teachers;
        _coordinators = coords;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(context.tr('selectRecipient'),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              if (widget.allowCoordinators)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(value: false, label: Text(context.tr('teachersTab'))),
                      ButtonSegment(value: true, label: Text(context.tr('coordinatorsTab'))),
                    ],
                    selected: {_showCoordinators},
                    onSelectionChanged: (s) =>
                        setState(() => _showCoordinators = s.first),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: context.tr('searchByName'),
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (v) => setState(() => _search = v.toLowerCase()),
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(
                        child:
                            CircularProgressIndicator(color: AppTheme.primary))
                    : _buildList(scrollController),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildList(ScrollController controller) {
    final List<_Recipient> recipients;
    if (_showCoordinators) {
      recipients = _coordinators.map((c) {
        final email = (c['email'] as String?) ?? '';
        final name = (c['name'] as String?) ??
            (c['displayName'] as String?) ??
            email;
        return _Recipient(email: email, name: name, role: 'coordinator');
      }).toList();
    } else {
      recipients = _teachers
          .map((t) => _Recipient(
                email: t.email,
                name: t.name,
                role: 'teacher',
                teacherId: t.id,
              ))
          .toList();
    }

    final filtered = _search.isEmpty
        ? recipients
        : recipients
            .where((r) => r.name.toLowerCase().contains(_search))
            .toList();

    if (filtered.isEmpty) {
      return Center(
        child: Text(
          _showCoordinators ? context.tr('noCoordinatorsFound') : context.tr('noTeachersFound'),
          style: TextStyle(color: Colors.grey.shade500),
        ),
      );
    }

    return ListView.separated(
      controller: controller,
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 64),
      itemBuilder: (_, i) {
        final r = filtered[i];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
            child: Text(
              r.name.isNotEmpty ? r.name[0].toUpperCase() : '?',
              style: const TextStyle(
                  color: AppTheme.primary, fontWeight: FontWeight.bold),
            ),
          ),
          title: Text(r.name),
          subtitle: Text(r.role == 'coordinator' ? context.trRole('coordinator') : context.trRole('teacher')),
          onTap: () => Navigator.pop(context, r),
        );
      },
    );
  }
}

// ── Remark composer ─────────────────────────────────────────────────────────────

class _RemarkComposer extends StatefulWidget {
  final String recipientName;
  const _RemarkComposer({required this.recipientName});

  @override
  State<_RemarkComposer> createState() => _RemarkComposerState();
}

class _RemarkComposerState extends State<_RemarkComposer> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${context.tr('remarkForPrefix')} ${widget.recipientName}'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 5,
        minLines: 3,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          hintText: context.tr('writeFeedbackHint'),
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('cancel'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(context.tr('sendAction')),
        ),
      ],
    );
  }
}

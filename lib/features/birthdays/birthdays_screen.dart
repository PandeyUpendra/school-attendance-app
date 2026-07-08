import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../l10n/app_strings.dart';
import '../../services/birthday_service.dart';
import '../../theme.dart';
import '../../shared/utils/phone_utils.dart';

/// Localised label for a birthday filter index (display only; logic uses the
/// integer index, so stored/compared values are unaffected).
String _bdayFilterLabel(BuildContext context, int i) => switch (i) {
      0 => context.tr('filterToday'),
      1 => context.tr('filterThisWeek'),
      2 => context.tr('filterThisMonth'),
      _ => context.tr('filterAll'),
    };

class BirthdaysScreen extends StatefulWidget {
  final String role;
  final String? className;
  final String? section;
  final List<String>? assignedClasses;
  final String schoolName;

  const BirthdaysScreen({
    super.key,
    required this.role,
    this.className,
    this.section,
    this.assignedClasses,
    this.schoolName = 'Our School',
  });

  @override
  State<BirthdaysScreen> createState() => _BirthdaysScreenState();
}

class _BirthdaysScreenState extends State<BirthdaysScreen> {
  final _svc = BirthdayService();

  int _filter = 0;
  bool _loading = true;
  List<Map<String, dynamic>> _staffList = [];
  List<Map<String, dynamic>> _studentList = [];

  static const _filters = ['Today', 'This Week', 'This Month', 'All'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await _reload();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _updateFilter(int i) async {
    if (_filter == i) return;
    setState(() {
      _filter = i;
      _loading = true;
    });
    await _reload();
    if (mounted) setState(() => _loading = false);
  }

  void _onHorizontalDragEnd(DragEndDetails d) {
    final dx = d.primaryVelocity ?? 0;
    if (dx < -200 && _filter < _filters.length - 1) {
      // Swipe left → next tab
      _updateFilter(_filter + 1);
    } else if (dx > 200 && _filter > 0) {
      // Swipe right → previous tab
      _updateFilter(_filter - 1);
    }
  }

  Future<void> _reload() async {
    final cn = widget.className;
    final sec = widget.section;
    final ac = widget.assignedClasses;

    List<Map<String, dynamic>> staff;
    List<Map<String, dynamic>> students;

    switch (_filter) {
      case 0:
        staff = await _svc.getTodayStaffBirthdays();
        students = await _svc.getTodayStudentBirthdays(
            className: cn, section: sec, classNames: ac);
        break;
      case 1:
        staff = await _svc.getUpcomingStaffBirthdays(7);
        students = await _svc.getUpcomingStudentBirthdays(7,
            className: cn, section: sec, classNames: ac);
        break;
      case 2:
        final currentMonth = DateTime.now().month;
        staff = await _svc.getMonthlyStaffBirthdays(currentMonth);
        students = await _svc.getMonthlyStudentBirthdays(currentMonth,
            className: cn, section: sec, classNames: ac);
        break;
      default:
        staff = await _svc.getAllStaffBirthdays();
        students = await _svc.getAllStudentBirthdays(
            className: cn, section: sec, classNames: ac);
    }

    if (ac != null && ac.isNotEmpty) {
      students = students.where((s) => ac.contains(s['className'])).toList();
    }

    if (mounted) {
      setState(() {
        _staffList = staff;
        _studentList = students;
      });
    }
  }

  Future<void> _refresh() async => _reload();

  String? _phone(Map<String, dynamic> entry) {
    if (entry['type'] == 'staff') return entry['phone'] as String?;
    final p = entry['phone'] as String?;
    return (p?.isNotEmpty == true) ? p : entry['parentPhone'] as String?;
  }

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _openWhatsApp(Map<String, dynamic> entry, String message) async {
    final phone = _phone(entry);
    if (phone == null || phone.isEmpty) return;
    final uri = PhoneUtils.whatsAppUri(phone, text: message);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _defaultMessage(Map<String, dynamic> entry) {
    final name = entry['name'] as String? ?? '';
    if (entry['type'] == 'staff') {
      return '🎂 Happy Birthday $name! 🎉\nWishing you a wonderful day filled with joy and happiness.\nBest wishes from ${widget.schoolName} family! 🌟';
    }
    final gender = entry['gender'] as String? ?? '';
    final himHer = gender.toLowerCase() == 'female' ? 'her' : 'him';
    final heShe = gender.toLowerCase() == 'female' ? 'she' : 'he';
    return '🎂 Dear Parent,\nToday is $name\'s birthday! 🎉\nThe entire ${widget.schoolName} family wishes $himHer a very Happy Birthday! 🌟\nMay $heShe have a bright and successful future ahead! 🎈';
  }

  bool get _showStudents =>
      widget.role == 'class_teacher' ||
      widget.role == 'subject_teacher' ||
      widget.role == 'coordinator' ||
      widget.role == 'principal';

  int get _totalCount =>
      _staffList.length + (_showStudents ? _studentList.length : 0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          _buildHeader(),
          _buildFilterBar(),
          Expanded(
            child: GestureDetector(
              key: const Key('birthday-swipe-detector'),
              onHorizontalDragEnd: _onHorizontalDragEnd,
              behavior: HitTestBehavior.translucent,
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary))
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      color: AppTheme.primary,
                      child: _buildBody(),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.primaryDark,
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 16, 16),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Birthdays',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      widget.schoolName,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Text('🎂', style: TextStyle(fontSize: 22)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Filter bar ─────────────────────────────────────────────────────────────

  Widget _buildFilterBar() {
    return Container(
      color: AppTheme.primaryDark,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(24),
        ),
        padding: const EdgeInsets.all(3),
        child: Row(
          children: List.generate(_filters.length, (i) {
            final sel = _filter == i;
            return Expanded(
              child: GestureDetector(
                onTap: () => _updateFilter(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: sel ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Text(
                    _bdayFilterLabel(context, i),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: sel ? AppTheme.primary : Colors.white,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  // ── Body ───────────────────────────────────────────────────────────────────

  Widget _buildBody() {
    final hasAny = _totalCount > 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        if (hasAny) _buildSummaryCard(),
        if (hasAny) const SizedBox(height: 20),

        _SectionHeader(
          label: 'Staff',
          icon: Icons.person_outline,
          count: _staffList.length,
          color: AppTheme.primary,
        ),
        const SizedBox(height: 10),
        if (_staffList.isEmpty)
          _EmptyBlock(filterLabel: _bdayFilterLabel(context, _filter), isToday: _filter == 0, type: 'staff')
        else
          ..._staffList.map((e) => _BirthdayCard(
                entry: e,
                schoolName: widget.schoolName,
                defaultMessage: _defaultMessage(e),
                onCall: () {
                  final p = _phone(e);
                  if (p != null) _call(p);
                },
                onWhatsApp: (msg) => _openWhatsApp(e, msg),
                svc: _svc,
              )),

        if (_showStudents) ...[
          const SizedBox(height: 24),
          _SectionHeader(
            label: 'Students',
            icon: Icons.school_outlined,
            count: _studentList.length,
            color: AppTheme.accent,
          ),
          const SizedBox(height: 10),
          if (_studentList.isEmpty)
            _EmptyBlock(filterLabel: _bdayFilterLabel(context, _filter), isToday: _filter == 0, type: 'student')
          else
            ..._studentList.map((e) => _BirthdayCard(
                  entry: e,
                  schoolName: widget.schoolName,
                  defaultMessage: _defaultMessage(e),
                  onCall: () {
                    final p = _phone(e);
                    if (p != null) _call(p);
                  },
                  onWhatsApp: (msg) => _openWhatsApp(e, msg),
                  svc: _svc,
                )),
        ],

        if (widget.role == 'principal' && _filter == 3)
          _MonthlyStats(svc: _svc),
      ],
    );
  }

  // ── Summary card ───────────────────────────────────────────────────────────

  Widget _buildSummaryCard() {
    final isToday = _filter == 0;
    final todayCount =
        _staffList.where((e) => (e['daysLeft'] as int) == 0).length +
            (_showStudents
                ? _studentList.where((e) => (e['daysLeft'] as int) == 0).length
                : 0);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isToday ? AppTheme.primaryMid : AppTheme.primaryDark,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isToday && todayCount > 0
                      ? '🎉 $_totalCount ${_totalCount > 1 ? context.tr('birthdaysWord') : context.tr('birthdayWord')} ${context.tr('birthdaysTodayExcl')}'
                      : '🎂 $_totalCount ${_totalCount > 1 ? context.tr('birthdaysWord') : context.tr('birthdayWord')} — ${_bdayFilterLabel(context, _filter)}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isToday && todayCount > 0
                      ? 'Don\'t forget to send your wishes!'
                      : 'Tap a card to send birthday wishes',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$_totalCount',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  final int count;
  final Color color;

  const _SectionHeader({
    required this.label,
    required this.icon,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 8),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Divider(color: color.withValues(alpha: 0.2), thickness: 1)),
      ],
    );
  }
}

// ── Empty block ───────────────────────────────────────────────────────────────

class _EmptyBlock extends StatelessWidget {
  final String filterLabel;
  final bool isToday;
  final String type;
  const _EmptyBlock({required this.filterLabel, required this.isToday, required this.type});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.07),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text('🎂', style: TextStyle(fontSize: 26)),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            type == 'staff' ? context.tr('noStaffBirthdays') : context.tr('noStudentBirthdays'),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isToday
                ? (type == 'staff' ? context.tr('noStaffBirthdaysToday') : context.tr('noStudentBirthdaysToday'))
                : '${context.tr('noneFoundFor')} "$filterLabel"',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

// ── Birthday card ─────────────────────────────────────────────────────────────

class _BirthdayCard extends StatelessWidget {
  final Map<String, dynamic> entry;
  final String schoolName;
  final String defaultMessage;
  final VoidCallback onCall;
  final void Function(String) onWhatsApp;
  final BirthdayService svc;

  const _BirthdayCard({
    required this.entry,
    required this.schoolName,
    required this.defaultMessage,
    required this.onCall,
    required this.onWhatsApp,
    required this.svc,
  });

  bool get _isToday => (entry['daysLeft'] as int) == 0;
  bool get _isTomorrow => (entry['daysLeft'] as int) == 1;
  String get _name => entry['name'] as String? ?? '';
  String get _initial => _name.isNotEmpty ? _name[0].toUpperCase() : '?';

  String get _subtitle {
    if (entry['type'] == 'staff') {
      return entry['subject'] as String? ?? entry['role'] as String? ?? '';
    }
    return '${entry['className'] ?? ''} · Roll ${entry['roll'] ?? ''}';
  }

  String get _dobFormatted => svc.formatDOB(entry['dateOfBirth'] as Timestamp);

  bool get _hasPhone =>
      (entry['phone'] as String?)?.isNotEmpty == true ||
      (entry['parentPhone'] as String?)?.isNotEmpty == true;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: _isToday
            ? Border.all(color: AppTheme.accent.withValues(alpha: 0.4), width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          if (_isToday)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: const BoxDecoration(
                color: AppTheme.accent,
                borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Row(
                children: [
                  const Text('🎉', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Text(
                    'Birthday Today — $_dobFormatted',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    // Avatar
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: _isToday
                            ? AppTheme.accent.withValues(alpha: 0.12)
                            : AppTheme.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: _isToday
                            ? const Text('🎂', style: TextStyle(fontSize: 24))
                            : Text(
                                _initial,
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: _isTomorrow
                                      ? AppTheme.accent
                                      : AppTheme.primary,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Name + info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          if (_subtitle.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              _subtitle,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Days badge
                    if (!_isToday)
                      _DaysBadge(
                        daysLeft: entry['daysLeft'] as int,
                        dob: _dobFormatted,
                      ),
                  ],
                ),

                const SizedBox(height: 14),
                const Divider(height: 1, thickness: 1),
                const SizedBox(height: 12),

                // Action row
                Row(
                  children: [
                    _ActionBtn(
                      icon: Icons.chat,
                      label: 'WhatsApp',
                      color: AppTheme.whatsapp,
                      enabled: _hasPhone,
                      onTap: _hasPhone
                          ? () => _showMessageSheet(context)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    _ActionBtn(
                      icon: Icons.phone_outlined,
                      label: 'Call',
                      color: AppTheme.primary,
                      enabled: _hasPhone,
                      onTap: _hasPhone ? onCall : null,
                    ),
                    const SizedBox(width: 8),
                    _ActionBtn(
                      icon: Icons.edit_note_outlined,
                      label: 'Custom',
                      color: AppTheme.primary,
                      enabled: _hasPhone,
                      onTap: _hasPhone
                          ? () => _showMessageSheet(context)
                          : null,
                    ),
                    if (!_hasPhone) ...[
                      const Spacer(),
                      Row(
                        children: [
                          Icon(Icons.phone_disabled_outlined,
                              size: 13, color: Colors.grey.shade400),
                          const SizedBox(width: 4),
                          Text(context.tr('noPhone'),
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade400)),
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showMessageSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CustomMessageSheet(
        name: _name,
        schoolName: schoolName,
        defaultMessage: defaultMessage,
        onSend: onWhatsApp,
      ),
    );
  }
}

// ── Days badge ────────────────────────────────────────────────────────────────

class _DaysBadge extends StatelessWidget {
  final int daysLeft;
  final String dob;
  const _DaysBadge({required this.daysLeft, required this.dob});

  @override
  Widget build(BuildContext context) {
    final isTomorrow = daysLeft == 1;
    final color = isTomorrow ? AppTheme.accent : AppTheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Text(
            isTomorrow ? 'Tomorrow' : 'in $daysLeft days',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          dob,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        ),
      ],
    );
  }
}

// ── Action button ─────────────────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback? onTap;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: enabled ? color.withValues(alpha: 0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: enabled ? color.withValues(alpha: 0.3) : Colors.grey.shade200,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              size: 14,
              color: enabled ? color : Colors.grey.shade400),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: enabled ? color : Colors.grey.shade400,
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Custom Message Sheet ──────────────────────────────────────────────────────

class _CustomMessageSheet extends StatefulWidget {
  final String name;
  final String schoolName;
  final String defaultMessage;
  final void Function(String) onSend;

  const _CustomMessageSheet({
    required this.name,
    required this.schoolName,
    required this.defaultMessage,
    required this.onSend,
  });

  @override
  State<_CustomMessageSheet> createState() => _CustomMessageSheetState();
}

class _CustomMessageSheetState extends State<_CustomMessageSheet> {
  late TextEditingController _ctrl;
  int _selectedTemplate = 0;

  static const _templateNames = ['Formal', 'Warm', 'Funny', 'Hindi', 'Custom'];
  late List<String> _templates;

  @override
  void initState() {
    super.initState();
    _templates = [
      'Dear ${widget.name}, wishing you a very Happy Birthday. May this special day bring you joy and success. Best regards, ${widget.schoolName}',
      '🎉 Happy Birthday ${widget.name}! 🎂\nHope your day is as wonderful as you are!\nLots of love from ${widget.schoolName} family! 💜',
      '🎂 Another year older, another year wiser!\nHappy Birthday ${widget.name}!\nMay your day be as awesome as you are! 😄',
      '🎂 ${widget.name} जी को जन्मदिन की हार्दिक शुभकामनाएं! 🎉\nईश्वर आपको दीर्घायु और सफलता प्रदान करें।\n${widget.schoolName} परिवार की ओर से। 💜',
      widget.defaultMessage,
    ];
    _ctrl = TextEditingController(text: _templates[0]);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _selectTemplate(int i) {
    setState(() {
      _selectedTemplate = i;
      if (i < 4) _ctrl.text = _templates[i];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Text('🎂', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.tr('sendBirthdayWish'),
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold)),
              Text('${context.tr('toColon')} ${widget.name}',
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey.shade600)),
            ]),
          ]),
          const SizedBox(height: 16),

          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(_templateNames.length, (i) {
                final sel = _selectedTemplate == i;
                return GestureDetector(
                  onTap: () => _selectTemplate(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: sel ? AppTheme.primary : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: sel
                            ? AppTheme.primary
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: Text(
                      _templateNames[i],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: sel ? Colors.white : Colors.grey.shade700,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _ctrl,
            maxLines: 5,
            onChanged: (_) {
              if (_selectedTemplate != 4) setState(() => _selectedTemplate = 4);
            },
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: AppTheme.primary, width: 1.5),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _ctrl,
              builder: (_, v, __) => Text(
                '${v.text.length} ${context.tr('charsWord')}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
              ),
            ),
          ),
          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                widget.onSend(_ctrl.text);
              },
              icon: const Icon(Icons.send_rounded),
              label: Text(context.tr('sendViaWhatsapp')),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.whatsapp,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Monthly stats (principal only) ────────────────────────────────────────────

class _MonthlyStats extends StatefulWidget {
  final BirthdayService svc;
  const _MonthlyStats({required this.svc});

  @override
  State<_MonthlyStats> createState() => _MonthlyStatsState();
}

class _MonthlyStatsState extends State<_MonthlyStats> {
  int _selectedMonth = DateTime.now().month;
  Map<int, List<Map<String, dynamic>>> _calData = {};
  bool _loading = true;
  int? _selectedDay;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  void initState() {
    super.initState();
    _loadMonth();
  }

  Future<void> _loadMonth() async {
    setState(() => _loading = true);
    final data = await widget.svc.getMonthlyBirthdays(_selectedMonth);
    if (mounted) {
      setState(() {
      _calData = data;
      _loading = false;
    });
    }
  }

  int _daysInMonth(int month) =>
      DateTime(DateTime.now().year, month + 1, 0).day;

  @override
  Widget build(BuildContext context) {
    final staffCount = _calData.values
        .expand((l) => l)
        .where((e) => e['type'] == 'staff')
        .length;
    final studentCount = _calData.values
        .expand((l) => l)
        .where((e) => e['type'] == 'student')
        .length;

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats row
          Row(children: [
            Expanded(
              child: _StatTile(
                label: 'Staff',
                value: staffCount,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatTile(
                label: 'Students',
                value: studentCount,
                color: AppTheme.accent,
              ),
            ),
          ]),
          const SizedBox(height: 14),

          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(12, (i) {
                final m = i + 1;
                final sel = m == _selectedMonth;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedMonth = m;
                      _selectedDay = null;
                    });
                    _loadMonth();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: sel ? AppTheme.primary : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color:
                            sel ? AppTheme.primary : Colors.grey.shade300,
                      ),
                    ),
                    child: Text(
                      _months[i],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: sel ? Colors.white : Colors.grey.shade700,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 14),

          if (_loading)
            const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          else
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)
                ],
              ),
              padding: const EdgeInsets.all(12),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                ),
                itemCount: _daysInMonth(_selectedMonth),
                itemBuilder: (_, i) {
                  final day = i + 1;
                  final hasBirthday = _calData.containsKey(day);
                  final isSelected = _selectedDay == day;
                  return GestureDetector(
                    onTap: hasBirthday
                        ? () => setState(() =>
                            _selectedDay = isSelected ? null : day)
                        : null,
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.primary
                            : hasBirthday
                                ? AppTheme.primaryLight.withValues(alpha: 0.2)
                                : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: hasBirthday
                            ? Border.all(
                                color: isSelected
                                    ? AppTheme.primary
                                    : AppTheme.primary.withValues(alpha: 0.3),
                                width: 1.5)
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$day',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? Colors.white
                                  : hasBirthday
                                      ? AppTheme.primary
                                      : Colors.grey.shade500,
                            ),
                          ),
                          if (hasBirthday)
                            Text('🎂',
                                style: TextStyle(
                                    fontSize: isSelected ? 10 : 9)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

          if (_selectedDay != null && _calData.containsKey(_selectedDay)) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primaryLight.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Birthdays on ${_months[_selectedMonth - 1]} $_selectedDay',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppTheme.primary),
                  ),
                  const SizedBox(height: 8),
                  ..._calData[_selectedDay]!.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(children: [
                          Text(
                            e['type'] == 'staff' ? '👨‍🏫 ' : '🎒 ',
                            style: const TextStyle(fontSize: 14),
                          ),
                          Text(
                            e['name'] as String? ?? '',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              e['type'] == 'staff'
                                  ? (e['subject'] as String? ?? '')
                                  : '${e['className'] ?? ''} · Roll ${e['roll'] ?? ''}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ]),
                      )),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _StatTile(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          '$label: $value',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ]),
    );
  }
}

// ── Birthday reminder banner (reusable) ───────────────────────────────────────

class BirthdayBanner extends StatefulWidget {
  final String role;
  final String? className;
  final String? section;
  final List<String>? assignedClasses;
  final String schoolName;
  final VoidCallback onTap;

  const BirthdayBanner({
    super.key,
    required this.role,
    required this.onTap,
    this.className,
    this.section,
    this.assignedClasses,
    this.schoolName = 'Our School',
  });

  @override
  State<BirthdayBanner> createState() => _BirthdayBannerState();
}

class _BirthdayBannerState extends State<BirthdayBanner> {
  final _svc = BirthdayService();
  List<Map<String, dynamic>> _todayBirthdays = [];
  List<Map<String, dynamic>> _tomorrowBirthdays = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final today = await _svc.getTodayAllBirthdays(
      className: widget.className,
      section: widget.section,
      classNames: widget.assignedClasses,
    );
    final tomorrow = await _svc.getTomorrowAllBirthdays(
      className: widget.className,
      section: widget.section,
      classNames: widget.assignedClasses,
    );
    if (!mounted) return;
    setState(() {
      _todayBirthdays = today;
      _tomorrowBirthdays = tomorrow;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || (_todayBirthdays.isEmpty && _tomorrowBirthdays.isEmpty)) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        if (_todayBirthdays.isNotEmpty)
          GestureDetector(
            onTap: widget.onTap,
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.warningLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.warning),
              ),
              child: Row(children: [
                const Text('🎂', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_todayBirthdays.length} Birthday${_todayBirthdays.length > 1 ? 's' : ''} Today!',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppTheme.warning,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _todayBirthdays
                            .take(3)
                            .map((e) => e['name'] as String? ?? '')
                            .join(', '),
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.warning,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text(
                    'Send Wishes',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            ),
          ),
        if (_tomorrowBirthdays.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(children: [
              const Text('🗓', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_tomorrowBirthdays.length} Birthday${_tomorrowBirthdays.length > 1 ? 's' : ''} Tomorrow — Be ready to wish them!',
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ),
            ]),
          ),
      ],
    );
  }
}

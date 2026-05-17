import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/birthday_service.dart';
import '../../theme.dart';

// ── Entry point ────────────────────────────────────────────────────────────

/// Role values: 'principal', 'coordinator', 'class_teacher', 'subject_teacher'
class BirthdaysScreen extends StatefulWidget {
  final String role;
  final String? className;  // class teacher's class
  final String? section;    // class teacher's section
  final List<String>? assignedClasses; // subject teacher's classes
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

  // 0=Today, 1=This Week, 2=This Month, 3=All
  int _filter = 0;

  bool _loading = true;
  List<Map<String, dynamic>> _staffList   = [];
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

  Future<void> _reload() async {
    final String? cn = widget.className;
    final String? sec = widget.section;
    final List<String>? ac = widget.assignedClasses;

    List<Map<String, dynamic>> staff;
    List<Map<String, dynamic>> students;

    switch (_filter) {
      case 0: // Today
        staff    = await _svc.getTodayStaffBirthdays();
        students = await _svc.getTodayStudentBirthdays(
          className: cn, section: sec, classNames: ac);
        break;
      case 1: // This Week
        staff    = await _svc.getUpcomingStaffBirthdays(7);
        students = await _svc.getUpcomingStudentBirthdays(7,
          className: cn, section: sec, classNames: ac);
        break;
      case 2: // This Month
        staff    = (await _svc.getAllStaffBirthdays())
            .where((m) => _svc.isBirthdayThisMonth(m['dateOfBirth'] as Timestamp))
            .toList();
        students = (await _svc.getAllStudentBirthdays(
            className: cn, section: sec, classNames: ac))
            .where((m) => _svc.isBirthdayThisMonth(m['dateOfBirth'] as Timestamp))
            .toList();
        break;
      default: // All
        staff    = await _svc.getAllStaffBirthdays();
        students = await _svc.getAllStudentBirthdays(
          className: cn, section: sec, classNames: ac);
    }

    // For subject teacher, filter students to assigned classes client-side
    if (ac != null && ac.isNotEmpty) {
      students = students.where((s) => ac.contains(s['className'])).toList();
    }

    if (mounted) {
      setState(() {
        _staffList   = staff;
        _studentList = students;
      });
    }
  }

  Future<void> _refresh() async {
    await _reload();
  }

  // ── Phone helpers ──────────────────────────────────────────────────────────

  String? _phone(Map<String, dynamic> entry) {
    if (entry['type'] == 'staff') {
      return entry['phone'] as String?;
    } else {
      // For student: use guardian's phone
      return (entry['phone'] as String?)?.isNotEmpty == true
          ? entry['phone'] as String
          : entry['parentPhone'] as String?;
    }
  }

  Future<void> _call(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _openWhatsApp(
      Map<String, dynamic> entry, String message) async {
    final phone = _phone(entry);
    if (phone == null || phone.isEmpty) return;
    final encoded = Uri.encodeComponent(message);
    final uri = Uri.parse('https://wa.me/91$phone?text=$encoded');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _defaultMessage(Map<String, dynamic> entry) {
    final name = entry['name'] as String? ?? '';
    if (entry['type'] == 'staff') {
      return '🎂 Happy Birthday $name! 🎉\nWishing you a wonderful day filled with joy and happiness.\nBest wishes from ${widget.schoolName} family! 🌟';
    } else {
      final gender = entry['gender'] as String? ?? '';
      final himHer = gender.toLowerCase() == 'female' ? 'her' : 'him';
      final heShe  = gender.toLowerCase() == 'female' ? 'she' : 'he';
      return '🎂 Dear Parent,\nToday is $name\'s birthday! 🎉\nThe entire ${widget.schoolName} family wishes $himHer a very Happy Birthday! 🌟\nMay $heShe have a bright and successful future ahead! 🎈';
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final showStudents = widget.role == 'class_teacher' ||
        widget.role == 'subject_teacher' ||
        widget.role == 'coordinator' ||
        widget.role == 'principal';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Birthdays 🎂'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Filter chips
          Container(
            color: AppTheme.primary,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(_filters.length, (i) {
                  final sel = _filter == i;
                  return GestureDetector(
                    onTap: () async {
                      setState(() { _filter = i; _loading = true; });
                      await _reload();
                      if (mounted) setState(() => _loading = false);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 7),
                      decoration: BoxDecoration(
                        color: sel
                            ? Colors.white
                            : Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _filters[i],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: sel ? AppTheme.primary : Colors.white,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),

          // Body
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
                      children: [
                        // ── Staff section ──────────────────────────────────
                        _SectionLabel('Staff Birthdays',
                            count: _staffList.length),
                        if (_staffList.isEmpty)
                          _emptyState()
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

                        // ── Student section ────────────────────────────────
                        if (showStudents) ...[
                          const SizedBox(height: 8),
                          _SectionLabel('Student Birthdays',
                              count: _studentList.length),
                          if (_studentList.isEmpty)
                            _emptyState()
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

                        // ── Principal analytics ────────────────────────────
                        if (widget.role == 'principal' && _filter == 3)
                          _MonthlyStats(svc: _svc),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(children: [
          Icon(Icons.cake_outlined, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 10),
          Text(
            'No birthdays in this period',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ]),
      );
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String title;
  final int count;
  const _SectionLabel(this.title, {required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade500,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AppTheme.primary,
            ),
          ),
        ),
      ]),
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
  String get _name => entry['name'] as String? ?? '';
  String? get _sub => entry['type'] == 'staff'
      ? entry['subject'] as String?
      : '${entry['className'] ?? ''} · Roll ${entry['roll'] ?? ''}';

  @override
  Widget build(BuildContext context) {
    final dob = entry['dateOfBirth'] as Timestamp;
    final daysLeft = entry['daysLeft'] as int;
    final hasPhone = (entry['phone'] as String?)?.isNotEmpty == true ||
        (entry['parentPhone'] as String?)?.isNotEmpty == true;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      decoration: BoxDecoration(
        gradient: _isToday
            ? const LinearGradient(
                colors: [Color(0xFFFFF8E1), Color(0xFFFFF3E0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: _isToday ? null : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(
            color: _isToday ? AppTheme.accent : AppTheme.primary,
            width: _isToday ? 4 : 2,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              // Avatar
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _isToday
                      ? const Color(0xFFD81B60).withOpacity(0.12)
                      : AppTheme.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: _isToday
                      ? Border.all(color: AppTheme.accent, width: 2)
                      : null,
                ),
                child: Center(
                  child: _isToday
                      ? const Text('🎂',
                          style: TextStyle(fontSize: 22))
                      : Text(
                          _name.isNotEmpty ? _name[0].toUpperCase() : '?',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary,
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
                      ),
                    ),
                    if (_sub != null && _sub!.isNotEmpty)
                      Text(
                        _sub!,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600),
                      ),
                    const SizedBox(height: 4),
                    if (_isToday)
                      Row(children: const [
                        Text('🎉 ', style: TextStyle(fontSize: 13)),
                        Text(
                          'Birthday Today!',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.accent,
                          ),
                        ),
                      ])
                    else
                      Row(children: [
                        Icon(Icons.calendar_today_outlined,
                            size: 13, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text(
                          daysLeft == 1
                              ? 'Tomorrow · ${svc.formatDOB(dob)}'
                              : 'In $daysLeft days · ${svc.formatDOB(dob)}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ]),
                  ],
                ),
              ),
            ]),

            const SizedBox(height: 12),

            // Action buttons
            Row(children: [
              // WhatsApp
              _ActionBtn(
                icon: Icons.message,
                label: 'WhatsApp',
                color: const Color(0xFF25D366),
                enabled: hasPhone,
                onTap: hasPhone
                    ? () => _showCustomMessageSheet(context)
                    : null,
              ),
              const SizedBox(width: 8),
              // Call
              _ActionBtn(
                icon: Icons.phone,
                label: 'Call',
                color: const Color(0xFF1565C0),
                enabled: hasPhone,
                onTap: hasPhone ? onCall : null,
              ),
              const SizedBox(width: 8),
              // Custom message
              _ActionBtn(
                icon: Icons.edit_outlined,
                label: 'Custom',
                color: AppTheme.primary,
                enabled: hasPhone,
                onTap: hasPhone
                    ? () => _showCustomMessageSheet(context)
                    : null,
              ),
              if (!hasPhone) ...[
                const SizedBox(width: 8),
                Text(
                  'No phone',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade400),
                ),
              ],
            ]),
          ],
        ),
      ),
    );
  }

  void _showCustomMessageSheet(BuildContext context) {
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: enabled ? color : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              size: 14,
              color: enabled ? Colors.white : Colors.grey.shade400),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: enabled ? Colors.white : Colors.grey.shade400,
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Custom Message Bottom Sheet ───────────────────────────────────────────────

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
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
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
          const SizedBox(height: 14),

          const Text(
            'Send Birthday Wish',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          Text(
            'To: ${widget.name}',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 14),

          // Template selector
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

          // Editable message
          TextField(
            controller: _ctrl,
            maxLines: 5,
            onChanged: (_) {
              if (_selectedTemplate != 4) {
                setState(() => _selectedTemplate = 4);
              }
            },
            decoration: InputDecoration(
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _ctrl,
              builder: (_, v, __) => Text(
                '${v.text.length} chars',
                style: TextStyle(
                    fontSize: 11, color: Colors.grey.shade400),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Send button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                widget.onSend(_ctrl.text);
              },
              icon: const Icon(Icons.send),
              label: const Text('Send via WhatsApp'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
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
    if (mounted) setState(() { _calData = data; _loading = false; });
  }

  int _daysInMonth(int month) {
    return DateTime(DateTime.now().year, month + 1, 0).day;
  }

  @override
  Widget build(BuildContext context) {
    final staffCount = _calData.values.expand((l) => l)
        .where((e) => e['type'] == 'staff').length;
    final studentCount = _calData.values.expand((l) => l)
        .where((e) => e['type'] == 'student').length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats row
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 6)],
            ),
            child: Row(children: [
              _StatChip(label: 'Staff', value: staffCount,
                  color: AppTheme.primary),
              const SizedBox(width: 12),
              _StatChip(label: 'Students', value: studentCount,
                  color: AppTheme.accent),
            ]),
          ),
          const SizedBox(height: 12),

          // Month selector
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(12, (i) {
                final m = i + 1;
                final sel = m == _selectedMonth;
                return GestureDetector(
                  onTap: () {
                    setState(() { _selectedMonth = m; _selectedDay = null; });
                    _loadMonth();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: sel ? AppTheme.primary : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: sel ? AppTheme.primary : Colors.grey.shade300),
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
          const SizedBox(height: 12),

          // Calendar grid
          _loading
              ? const Center(child: CircularProgressIndicator())
              : Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 6)],
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
                                    ? const Color(0xFFFFF8E1)
                                    : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: hasBirthday
                                ? Border.all(
                                    color: isSelected
                                        ? AppTheme.primary
                                        : const Color(0xFFF57F17),
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
                                          ? AppTheme.primaryDark
                                          : Colors.grey.shade500,
                                ),
                              ),
                              if (hasBirthday)
                                Text(
                                  '🎂',
                                  style: TextStyle(
                                      fontSize: isSelected ? 10 : 9),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

          // Selected day detail
          if (_selectedDay != null &&
              _calData.containsKey(_selectedDay)) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF57F17)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Birthdays on ${_months[_selectedMonth - 1]} $_selectedDay',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
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
                          Text(
                            e['type'] == 'staff'
                                ? (e['subject'] as String? ?? '')
                                : '${e['className'] ?? ''} · Roll ${e['roll'] ?? ''}',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600),
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

class _StatChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _StatChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 10, height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(
        '$label: $value',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ]);
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
      _todayBirthdays    = today;
      _tomorrowBirthdays = tomorrow;
      _loaded            = true;
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
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFF8E1), Color(0xFFFFF3E0)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFF57F17)),
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
                          color: Color(0xFFF57F17),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _todayBirthdays
                            .take(3)
                            .map((e) => e['name'] as String? ?? '')
                            .join(', '),
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF57F17),
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
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
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
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade700),
                ),
              ),
            ]),
          ),
      ],
    );
  }
}

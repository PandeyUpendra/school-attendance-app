import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/student.dart';
import '../models/fee.dart';
import '../models/homework.dart';
import '../services/auth_service.dart';
import '../services/student_service.dart';
import '../services/fee_service.dart';
import '../services/homework_service.dart';
import '../services/notification_service.dart';
import 'role_selection_screen.dart';
import 'announcements_screen.dart';
import 'notifications_screen.dart';
import 'attendance_certificate_screen.dart';

/// The Guardian Portal — shows a single student's attendance to their parent.
/// Guardian is linked to {studentClass, studentRoll} in allowed_users.
class GuardianDashboard extends StatefulWidget {
  final String studentClass;
  final int    studentRoll;

  const GuardianDashboard({
    super.key,
    required this.studentClass,
    required this.studentRoll,
  });

  @override
  State<GuardianDashboard> createState() => _GuardianDashboardState();
}

class _GuardianDashboardState extends State<GuardianDashboard> {
  final _service    = StudentService();
  final _feeService = FeeService();
  final _hwService  = HomeworkService();

  bool _loading = true;
  Student? _student;

  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Map<int, Map<int, String>> _monthData = {};
  String? _todayStatus;

  // Fee
  FeeStructure? _feeStructure;
  double        _totalPaid = 0;

  // Homework
  List<Homework> _homeworkList = [];

  // Notifications
  int _unreadNotifCount = 0;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    // Fire reads in parallel
    final results = await Future.wait([
      _service.getStudentByRoll(widget.studentClass, widget.studentRoll),
      _service.loadMonthAttendance(
          widget.studentClass, _month.year, _month.month),
      _service.loadTodayAttendance(widget.studentClass),
      _feeService.getFeeStructure(widget.studentClass),
      _feeService.getTotalPaid(widget.studentClass, widget.studentRoll),
      NotificationService().unreadCount(
        role:         'guardian',
        studentClass: widget.studentClass,
        studentRoll:  widget.studentRoll,
      ),
      _hwService.getHomeworkForClass(widget.studentClass),
    ]);
    if (!mounted) return;

    final student      = results[0] as Student?;
    final monthData    = results[1] as Map<int, Map<int, String>>;
    final todayByRoll  = results[2] as Map<int, String>;
    final feeStructure = results[3] as FeeStructure;
    final totalPaid    = results[4] as double;
    final notifCount   = results[5] as int;
    final hwList       = results[6] as List<Homework>;

    setState(() {
      _student          = student;
      _monthData        = monthData;
      _todayStatus      = todayByRoll[widget.studentRoll];
      _feeStructure     = feeStructure;
      _totalPaid        = totalPaid;
      _unreadNotifCount = notifCount;
      _homeworkList     = hwList;
      _loading          = false;
    });
  }

  Future<void> _changeMonth(DateTime newMonth) async {
    setState(() { _month = newMonth; _loading = true; });
    final data = await _service.loadMonthAttendance(
        widget.studentClass, newMonth.year, newMonth.month);
    if (!mounted) return;
    setState(() { _monthData = data; _loading = false; });
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  int get _workingDays => _monthData.keys.length;
  int get _present => _monthData.values
      .where((d) => d[widget.studentRoll] == 'Present').length;
  int get _absent => _monthData.values
      .where((d) => d[widget.studentRoll] == 'Absent').length;
  int get _leave => _monthData.values
      .where((d) => d[widget.studentRoll] == 'Leave').length;

  double get _pct =>
      _workingDays == 0 ? 0 : _present / _workingDays * 100;

  bool get _isLow => _workingDays > 0 && _pct < 75;

  String _monthLabel(DateTime dt) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[dt.month - 1]} ${dt.year}';
  }

  Color _statusColor(String? s) {
    switch (s) {
      case 'Present': return Colors.green;
      case 'Absent':  return Colors.red;
      case 'Leave':   return const Color(0xFFF57F17);
      default:        return Colors.grey;
    }
  }

  Future<void> _callSchool() async {
    if (_student == null || _student!.phone.isEmpty) return;
    // Calls school number saved on student — usually the class teacher contact.
    final uri = Uri.parse('tel:${_student!.phone}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _logout() async {
    await AuthService().clearSession();
    if (!mounted) return;
    Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => const RoleSelectionScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Guardian Portal',
                style:
                    TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text("Your child's school activity",
                style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                tooltip: 'Notifications',
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NotificationsScreen(
                        role:         'guardian',
                        studentClass: widget.studentClass,
                        studentRoll:  widget.studentRoll,
                      ),
                    ),
                  );
                  _loadAll();
                },
              ),
              if (_unreadNotifCount > 0)
                Positioned(
                  right: 8, top: 8,
                  child: Container(
                    width: 14, height: 14,
                    decoration: const BoxDecoration(
                      color: Colors.red, shape: BoxShape.circle),
                    child: Center(
                      child: Text(
                        _unreadNotifCount > 9 ? '9+' : '$_unreadNotifCount',
                        style: const TextStyle(
                            fontSize: 8,
                            color: Colors.white,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _logout,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        color: Colors.purple,
        child: _loading
            ? ListView(children: const [
                SizedBox(height: 120),
                Center(child: CircularProgressIndicator(color: Colors.purple)),
              ])
            : _student == null
                ? ListView(children: [
                    const SizedBox(height: 80),
                    Icon(Icons.person_off_outlined,
                        size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          'No student found for Roll ${widget.studentRoll} '
                          'in ${widget.studentClass}. Please contact the school '
                          'administrator to verify your account link.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 14, color: Colors.grey.shade600),
                        ),
                      ),
                    ),
                  ])
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      // ── Child identity card ──────────────────────────
                      _StudentCard(
                        student: _student!,
                        todayStatus: _todayStatus,
                      ),
                      const SizedBox(height: 16),

                      // ── Today's status banner ────────────────────────
                      _TodayBanner(status: _todayStatus),
                      const SizedBox(height: 16),

                      // ── This month summary card ──────────────────────
                      _MonthSummaryCard(
                        monthLabel: _monthLabel(_month),
                        workingDays: _workingDays,
                        present: _present,
                        absent: _absent,
                        leave: _leave,
                        pct: _pct,
                        isLow: _isLow,
                        isCurrentMonth: _isCurrentMonth,
                        onPrev: () => _changeMonth(
                            DateTime(_month.year, _month.month - 1)),
                        onNext: _isCurrentMonth
                            ? null
                            : () => _changeMonth(
                                DateTime(_month.year, _month.month + 1)),
                      ),
                      const SizedBox(height: 16),

                      // ── Low attendance banner ────────────────────────
                      if (_isLow) ...[
                        _LowAttendanceBanner(pct: _pct),
                        const SizedBox(height: 16),
                      ],

                      // ── Calendar view ────────────────────────────────
                      _CalendarCard(
                        month: _month,
                        monthData: _monthData,
                        roll: widget.studentRoll,
                        statusColor: _statusColor,
                      ),
                      const SizedBox(height: 16),

                      // ── Legend ───────────────────────────────────────
                      _LegendRow(),
                      const SizedBox(height: 20),

                      // ── Fee Status ───────────────────────────────────
                      if (_feeStructure != null &&
                          _feeStructure!.totalAnnualFee > 0) ...[
                        _FeeStatusCard(
                          structure: _feeStructure!,
                          totalPaid: _totalPaid,
                        ),
                        const SizedBox(height: 16),
                      ],

                      // ── Homework ──────────────────────────────────────
                      if (_homeworkList.isNotEmpty) ...[
                        _HomeworkSection(homeworkList: _homeworkList),
                        const SizedBox(height: 16),
                      ],

                      // ── Attendance Certificate ────────────────────────
                      if (_student != null)
                        OutlinedButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AttendanceCertificateScreen(
                                  student: _student!),
                            ),
                          ),
                          icon: const Icon(
                              Icons.workspace_premium_outlined),
                          label: const Text('Attendance Certificate'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.indigo,
                            side: const BorderSide(color: Colors.indigo),
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      const SizedBox(height: 12),

                      // ── Announcements ─────────────────────────────────
                      OutlinedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AnnouncementsScreen(
                                viewerRole: 'guardian'),
                          ),
                        ),
                        icon: const Icon(Icons.campaign_outlined),
                        label: const Text('School Announcements'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.deepOrange,
                          side: const BorderSide(color: Colors.deepOrange),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── Contact school ───────────────────────────────
                      OutlinedButton.icon(
                        onPressed: _callSchool,
                        icon: const Icon(Icons.call_outlined),
                        label: const Text('Contact School'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.purple,
                          side: const BorderSide(color: Colors.purple),
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
      ),
    );
  }
}

// ─── Student identity card ───────────────────────────────────────────────────

class _StudentCard extends StatelessWidget {
  final Student student;
  final String? todayStatus;
  const _StudentCard({required this.student, required this.todayStatus});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: Colors.purple.withOpacity(0.12),
          child: Text(
            student.name.isNotEmpty ? student.name[0].toUpperCase() : '?',
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.purple),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(student.name,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 3),
              Text(
                'Roll ${student.roll}  •  ${student.className}',
                style:
                    TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              if (student.fatherName.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text('Father: ${student.fatherName}',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500)),
              ],
            ],
          ),
        ),
      ]),
    );
  }
}

// ─── Today's status banner ───────────────────────────────────────────────────

class _TodayBanner extends StatelessWidget {
  final String? status;
  const _TodayBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;
    String title;
    String sub;

    switch (status) {
      case 'Present':
        color = Colors.green;
        icon  = Icons.check_circle_outline;
        title = 'Present Today';
        sub   = 'Your child attended school today.';
        break;
      case 'Absent':
        color = Colors.red;
        icon  = Icons.cancel_outlined;
        title = 'Absent Today';
        sub   = 'Your child was marked absent today.';
        break;
      case 'Leave':
        color = const Color(0xFFF57F17);
        icon  = Icons.event_busy_outlined;
        title = 'On Leave Today';
        sub   = 'Your child is on approved leave today.';
        break;
      default:
        color = Colors.grey;
        icon  = Icons.schedule_outlined;
        title = 'Attendance Not Marked';
        sub   = "The class teacher hasn't taken attendance yet today.";
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: color)),
              const SizedBox(height: 2),
              Text(sub,
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            ],
          ),
        ),
      ]),
    );
  }
}

// ─── Month summary card ──────────────────────────────────────────────────────

class _MonthSummaryCard extends StatelessWidget {
  final String monthLabel;
  final int    workingDays, present, absent, leave;
  final double pct;
  final bool   isLow, isCurrentMonth;
  final VoidCallback  onPrev;
  final VoidCallback? onNext;

  const _MonthSummaryCard({
    required this.monthLabel,
    required this.workingDays,
    required this.present,
    required this.absent,
    required this.leave,
    required this.pct,
    required this.isLow,
    required this.isCurrentMonth,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final pctColor = isLow
        ? Colors.red
        : pct >= 85
            ? Colors.green
            : const Color(0xFFF57F17);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: Icon(Icons.chevron_left, color: Colors.grey.shade700),
              onPressed: onPrev,
            ),
            Text(monthLabel,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            IconButton(
              icon: Icon(Icons.chevron_right,
                  color: onNext == null
                      ? Colors.grey.shade300
                      : Colors.grey.shade700),
              onPressed: onNext,
            ),
          ],
        ),
        const Divider(height: 14),
        if (workingDays == 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text('No school days recorded in this month',
                style: TextStyle(color: Colors.grey.shade500)),
          )
        else ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _StatCell(value: '$workingDays', label: 'Days',
                  color: Colors.indigo),
              _StatCell(value: '$present', label: 'Present',
                  color: Colors.green),
              _StatCell(value: '$absent', label: 'Absent',
                  color: Colors.red),
              _StatCell(value: '$leave', label: 'Leave',
                  color: const Color(0xFFF57F17)),
            ],
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (pct / 100).clamp(0.0, 1.0),
                  minHeight: 10,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(pctColor),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text('${pct.toStringAsFixed(1)}%',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: pctColor)),
          ]),
        ],
      ]),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String value, label;
  final Color  color;
  const _StatCell(
      {required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value,
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      ]);
}

// ─── Low attendance banner ───────────────────────────────────────────────────

class _LowAttendanceBanner extends StatelessWidget {
  final double pct;
  const _LowAttendanceBanner({required this.pct});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded,
            color: Colors.red, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Low Attendance (${pct.toStringAsFixed(1)}%)',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade800),
              ),
              const SizedBox(height: 2),
              Text(
                'Your child is below the 75% attendance requirement. '
                'Please ensure regular school attendance to avoid '
                'shortage action.',
                style: TextStyle(
                    fontSize: 12, color: Colors.red.shade700),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

// ─── Calendar card ───────────────────────────────────────────────────────────

class _CalendarCard extends StatelessWidget {
  final DateTime               month;
  final Map<int, Map<int, String>> monthData;
  final int                    roll;
  final Color Function(String?) statusColor;

  const _CalendarCard({
    required this.month,
    required this.monthData,
    required this.roll,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    final daysInMonth  = DateTime(month.year, month.month + 1, 0).day;
    final firstWeekday = DateTime(month.year, month.month, 1).weekday;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(children: [
        // Day-of-week headers
        Row(
          children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
              .map((d) => Expanded(
                    child: Center(
                      child: Text(d,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: d == 'Sun'
                                  ? Colors.red.shade300
                                  : Colors.grey.shade500)),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: 1,
            mainAxisSpacing: 5,
            crossAxisSpacing: 4,
          ),
          itemCount: (firstWeekday - 1) + daysInMonth,
          itemBuilder: (_, idx) {
            if (idx < firstWeekday - 1) return const SizedBox();
            final day    = idx - (firstWeekday - 1) + 1;
            final date   = DateTime(month.year, month.month, day);
            final status = monthData[day]?[roll];
            final isSun  = date.weekday == DateTime.sunday;
            final isFut  = date.isAfter(DateTime.now());

            final bg = isFut
                ? Colors.transparent
                : status != null
                    ? statusColor(status).withOpacity(0.15)
                    : isSun
                        ? Colors.red.shade50
                        : Colors.grey.shade50;
            final bd = status != null
                ? statusColor(status).withOpacity(0.45)
                : Colors.grey.shade200;
            final tc = isFut
                ? Colors.grey.shade300
                : status != null
                    ? statusColor(status)
                    : isSun
                        ? Colors.red.shade200
                        : Colors.grey.shade400;

            return Container(
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                    color: bd, width: status != null ? 1.5 : 0.8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('$day',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: status != null
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: tc)),
                  if (status != null)
                    Text(status[0],
                        style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: statusColor(status))),
                ],
              ),
            );
          },
        ),
      ]),
    );
  }
}

// ─── Fee status card for guardian ────────────────────────────────────────────

class _FeeStatusCard extends StatelessWidget {
  final FeeStructure structure;
  final double       totalPaid;

  const _FeeStatusCard({required this.structure, required this.totalPaid});

  @override
  Widget build(BuildContext context) {
    final total = structure.totalAnnualFee;
    final due   = (total - totalPaid).clamp(0, double.infinity);
    final pct   = total > 0 ? (totalPaid / total).clamp(0.0, 1.0) : 0.0;
    final isFullyPaid = due < 1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(Icons.account_balance_wallet_outlined,
                  color: Colors.green.shade700, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Fee Status',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isFullyPaid
                    ? Colors.green.shade50
                    : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isFullyPaid ? 'Fully Paid' : 'Pending',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isFullyPaid
                      ? Colors.green.shade700
                      : Colors.orange.shade700,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                isFullyPaid ? Colors.green : Colors.orange,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Paid: ₹${totalPaid.toStringAsFixed(0)}',
                  style: TextStyle(
                      fontSize: 12, color: Colors.green.shade700)),
              Text('Due: ₹${due.toStringAsFixed(0)}',
                  style: TextStyle(
                      fontSize: 12,
                      color: due > 0
                          ? Colors.orange.shade700
                          : Colors.grey.shade500)),
              Text('Total: ₹${total.toStringAsFixed(0)}',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Homework section for guardian ───────────────────────────────────────────

class _HomeworkSection extends StatelessWidget {
  final List<Homework> homeworkList;
  const _HomeworkSection({required this.homeworkList});

  Color _statusColor(Homework hw) {
    if (hw.isReviewed) return Colors.green;
    if (hw.isOverdue)  return Colors.red;
    return Colors.orange;
  }

  String _statusLabel(Homework hw) {
    if (hw.isReviewed) return 'Reviewed';
    if (hw.isOverdue)  return 'Overdue';
    final d = hw.daysUntilDue;
    if (d == 0) return 'Due Today';
    if (d == 1) return 'Tomorrow';
    return 'Due in $d days';
  }

  @override
  Widget build(BuildContext context) {
    // Show latest 5
    final list = homeworkList.take(5).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.assignment_outlined,
                    color: Colors.teal, size: 18),
              ),
              const SizedBox(width: 10),
              const Text('Homework',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('${homeworkList.length} total',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade500)),
            ]),
          ),
          const Divider(height: 1),
          ...list.asMap().entries.map((entry) {
            final i  = entry.key;
            final hw = entry.value;
            final due =
                '${hw.dueDate.day}/${hw.dueDate.month}/${hw.dueDate.year}';
            final sc = _statusColor(hw);
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(hw.title,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(
                              '${hw.subject}  •  Due: $due',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500),
                            ),
                            const SizedBox(height: 4),
                            Text(hw.description,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: sc.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(_statusLabel(hw),
                            style: TextStyle(
                                fontSize: 10,
                                color: sc,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
                if (i < list.length - 1)
                  const Divider(height: 1, indent: 16),
              ],
            );
          }),
          if (homeworkList.length > 5)
            Padding(
              padding: const EdgeInsets.only(
                  left: 16, right: 16, bottom: 10, top: 4),
              child: Text(
                '+ ${homeworkList.length - 5} more assignments',
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade500),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Legend ──────────────────────────────────────────────────────────────────

class _LegendRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Widget dot(Color c, String lbl) => Row(children: [
          Container(
              width: 10, height: 10,
              decoration: BoxDecoration(
                  color: c, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(lbl,
              style:
                  TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ]);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 16,
      runSpacing: 6,
      children: [
        dot(Colors.green, 'Present'),
        dot(Colors.red, 'Absent'),
        dot(const Color(0xFFF57F17), 'Leave'),
        dot(Colors.grey.shade300, 'No School'),
      ],
    );
  }
}

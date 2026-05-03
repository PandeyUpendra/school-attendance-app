import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/student_data.dart';
import '../models/app_user.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../services/firestore_service.dart';
import 'class_management_screen.dart';
import 'admin_screen.dart';

// ── Data carrier ──────────────────────────────────────────────────────────────

class _ClassCardData {
  final String className;
  final int totalStudents;
  final double todayAttendancePct; // -1 = no data
  final double lastTestAvgPct;     // -1 = no data

  const _ClassCardData({
    required this.className,
    required this.totalStudents,
    this.todayAttendancePct = -1,
    this.lastTestAvgPct = -1,
  });
}

// ── Screen ────────────────────────────────────────────────────────────────────

class TeacherDashboardScreen extends StatefulWidget {
  const TeacherDashboardScreen({super.key});

  @override
  State<TeacherDashboardScreen> createState() =>
      _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState extends State<TeacherDashboardScreen> {
  List<_ClassCardData> _cards = [];
  bool _loading = true;
  String _schoolId = '';
  List<String> _classes = [];

  static const _cardColors = [
    Color(0xFF1565C0),
    Color(0xFF00897B),
    Color(0xFF6A1B9A),
    Color(0xFFE65100),
    Color(0xFF283593),
    Color(0xFF00838F),
    Color(0xFFAD1457),
    Color(0xFF2E7D32),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<AuthProvider>().user;
      _schoolId = user?.schoolId ?? '';
      final all = classStudents.keys.toList();
      _classes = (user == null ||
              user.role == UserRole.coordinator ||
              user.role == UserRole.principal)
          ? all
          : all.where((c) => user.classIds.contains(c)).toList();
      _loadDashboard();
    });
  }

  String _todayKey() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadDashboard() async {
    setState(() => _loading = true);

    final futures = _classes.map((cls) async {
      // Student count
      int count = classStudents[cls]?.length ?? 0;
      if (_schoolId.isNotEmpty) {
        final cloud = await FirestoreService.loadStudents(
            schoolId: _schoolId, classId: cls);
        if (cloud != null) count = cloud.length;
      }

      // Today's attendance %
      double attPct = -1;
      if (_schoolId.isNotEmpty) {
        final att = await FirestoreService.loadAttendance(
            schoolId: _schoolId, classId: cls, date: _todayKey());
        if (att != null && att.isNotEmpty) {
          final present = att.values.where((v) => v.isPresent).length;
          attPct = present / att.length;
        }
      }

      // Last test average
      double testAvg = -1;
      if (_schoolId.isNotEmpty) {
        final tests = await FirestoreService.getTests(
            schoolId: _schoolId, classId: cls);
        if (tests.isNotEmpty) {
          final latest = tests.first;
          final marks =
              (latest['marks'] as Map<String, dynamic>?) ?? {};
          final total = (latest['totalMarks'] as num?)?.toInt() ?? 100;
          if (marks.isNotEmpty && total > 0) {
            final avg = marks.values
                    .map((v) => (v as num).toDouble())
                    .reduce((a, b) => a + b) /
                marks.length;
            testAvg = avg / total;
          }
        }
      }

      return _ClassCardData(
        className: cls,
        totalStudents: count,
        todayAttendancePct: attPct,
        lastTestAvgPct: testAvg,
      );
    }).toList();

    final results = await Future.wait(futures);
    if (mounted) setState(() { _cards = results; _loading = false; });
  }

  // ── Quick Actions FAB ─────────────────────────────────────────────────────

  void _showQuickActions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 36, height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 14),
            const Text('Quick Actions',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 6),
            const Divider(),
            _QuickAction(
              icon: Icons.fact_check_outlined,
              color: const Color(0xFF1565C0),
              label: 'Take Attendance',
              subtitle: 'Mark today\'s attendance',
              onTap: () {
                Navigator.pop(context);
                _pickClass(
                  title: 'Select Class for Attendance',
                  onSelected: (cls) => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ClassManagementScreen(
                              className: cls,
                              schoolId: _schoolId),
                    ),
                  ).then((_) => _loadDashboard()),
                );
              },
            ),
            _QuickAction(
              icon: Icons.quiz_outlined,
              color: const Color(0xFF6A1B9A),
              label: 'Create Test',
              subtitle: 'Add a new test & enter marks',
              onTap: () {
                Navigator.pop(context);
                _pickClass(
                  title: 'Select Class for Test',
                  onSelected: (cls) => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ClassManagementScreen(
                              className: cls,
                              schoolId: _schoolId),
                    ),
                  ).then((_) => _loadDashboard()),
                );
              },
            ),
            _QuickAction(
              icon: Icons.event_outlined,
              color: const Color(0xFF00897B),
              label: 'Schedule PTM',
              subtitle: 'Set up a parent-teacher meeting',
              onTap: () {
                Navigator.pop(context);
                _pickClass(
                  title: 'Select Class for PTM',
                  onSelected: (cls) => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ClassManagementScreen(
                              className: cls,
                              schoolId: _schoolId),
                    ),
                  ).then((_) => _loadDashboard()),
                );
              },
            ),
            _QuickAction(
              icon: Icons.dark_mode_outlined,
              color: Colors.grey.shade700,
              label: 'Toggle Dark Mode',
              subtitle: 'Switch light / dark theme',
              onTap: () {
                Navigator.pop(context);
                context.read<ThemeProvider>().toggle();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _pickClass({
    required String title,
    required ValueChanged<String> onSelected,
  }) {
    if (_classes.length == 1) {
      onSelected(_classes.first);
      return;
    }
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _classes
              .map((c) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.class_,
                        color: Color(0xFF1565C0)),
                    title: Text(c),
                    onTap: () {
                      Navigator.pop(context);
                      onSelected(c);
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final today = DateTime.now();
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday'
    ];
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final isAdmin = user?.role == UserRole.coordinator ||
        user?.role == UserRole.principal;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadDashboard,
        child: CustomScrollView(
          slivers: [
            // ── Header ───────────────────────────────────────────────────
            SliverAppBar(
              expandedHeight: 190,
              pinned: true,
              backgroundColor: const Color(0xFF1565C0),
              actions: [
                if (isAdmin)
                  IconButton(
                    icon: const Icon(Icons.admin_panel_settings,
                        color: Colors.white),
                    tooltip: 'Admin Panel',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AdminScreen()),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.logout, color: Colors.white),
                  tooltip: 'Sign Out',
                  onPressed: () => _confirmSignOut(context, auth),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1565C0), Color(0xFF1E88E5)],
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Icon(Icons.school,
                                color: Colors.white70, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              _greeting(),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 13),
                            ),
                          ]),
                          const SizedBox(height: 8),
                          Text(
                            user?.name ?? 'Teacher',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${weekdays[today.weekday - 1]}, ${today.day} ${months[today.month - 1]}',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13),
                          ),
                          const SizedBox(height: 10),
                          Row(children: [
                            _HeaderChip(
                                '${_classes.length} classes',
                                Icons.class_outlined),
                            const SizedBox(width: 8),
                            _HeaderChip(
                                _roleLabel(user?.role),
                                Icons.badge_outlined),
                          ]),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Grid ─────────────────────────────────────────────────────
            if (_loading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_classes.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.class_outlined,
                          size: 72, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text(
                        'No classes assigned',
                        style: TextStyle(
                            color: Colors.grey.shade500, fontSize: 16),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Ask your admin to assign classes to you.',
                        style: TextStyle(
                            color: Colors.grey.shade400, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding:
                    const EdgeInsets.fromLTRB(16, 16, 16, 100),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 0.95,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final card = _cards[i];
                      final color =
                          _cardColors[i % _cardColors.length];
                      return _ClassCard(
                        data: card,
                        color: color,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ClassManagementScreen(
                              className: card.className,
                              schoolId: _schoolId,
                            ),
                          ),
                        ).then((_) => _loadDashboard()),
                      );
                    },
                    childCount: _cards.length,
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showQuickActions,
        tooltip: 'Quick Actions',
        child: const Icon(Icons.bolt_rounded),
      ),
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _roleLabel(UserRole? role) {
    switch (role) {
      case UserRole.teacher:     return 'Teacher';
      case UserRole.coordinator: return 'Coordinator';
      case UserRole.principal:   return 'Principal';
      default:                   return 'Staff';
    }
  }

  void _confirmSignOut(BuildContext context, AuthProvider auth) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out?'),
        content:
            const Text('You will be returned to the login screen.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              auth.signOut();
            },
            child: const Text('Sign Out',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// ── Class card ────────────────────────────────────────────────────────────────

class _ClassCard extends StatelessWidget {
  final _ClassCardData data;
  final Color color;
  final VoidCallback onTap;

  const _ClassCard({
    required this.data,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color, color.withOpacity(0.75)],
            ),
            boxShadow: [
              BoxShadow(
                  color: color.withOpacity(0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.class_,
                        color: Colors.white, size: 18),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${data.totalStudents} students',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ]),

                const Spacer(),

                // Class name
                Text(
                  data.className,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),

                // Stats row
                Row(children: [
                  if (data.todayAttendancePct >= 0) ...[
                    _StatPill(
                      icon: Icons.people_outline,
                      value:
                          '${(data.todayAttendancePct * 100).toStringAsFixed(0)}%',
                      label: 'Today',
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (data.lastTestAvgPct >= 0)
                    _StatPill(
                      icon: Icons.quiz_outlined,
                      value:
                          '${(data.lastTestAvgPct * 100).toStringAsFixed(0)}%',
                      label: 'Test',
                    ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _StatPill(
      {required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: Colors.white70, size: 11),
        const SizedBox(width: 3),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold)),
        const SizedBox(width: 2),
        Text(label,
            style: const TextStyle(
                color: Colors.white60, fontSize: 10)),
      ]),
    );
  }
}

// ── Small helpers ─────────────────────────────────────────────────────────────

class _HeaderChip extends StatelessWidget {
  final String label;
  final IconData icon;
  const _HeaderChip(this.label, this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: Colors.white70, size: 13),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.color,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(label,
          style: const TextStyle(
              fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(subtitle,
          style: TextStyle(
              color: Colors.grey.shade500, fontSize: 12)),
      onTap: onTap,
    );
  }
}

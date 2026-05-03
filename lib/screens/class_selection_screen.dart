import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/student_data.dart';
import '../models/app_user.dart';
import '../providers/auth_provider.dart';
import 'attendance_screen.dart';
import 'admin_screen.dart';

class ClassSelectionScreen extends StatefulWidget {
  const ClassSelectionScreen({super.key});

  @override
  State<ClassSelectionScreen> createState() => _ClassSelectionScreenState();
}

class _ClassSelectionScreenState extends State<ClassSelectionScreen> {
  static const List<Color> _cardColors = [
    Color(0xFF1565C0),
    Color(0xFF00897B),
    Color(0xFF6A1B9A),
    Color(0xFFE65100),
    Color(0xFF283593),
  ];

  bool _isOffline = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _connectivitySub =
        Connectivity().onConnectivityChanged.listen((results) {
      final offline = results.isEmpty ||
          results.every((r) => r == ConnectivityResult.none);
      if (offline != _isOffline) setState(() => _isOffline = offline);
    });
    // Initial check
    Connectivity()
        .checkConnectivity()
        .then((results) => setState(() => _isOffline =
            results.isEmpty ||
            results.every((r) => r == ConnectivityResult.none)));
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    final allClasses = classStudents.keys.toList();
    final classes = (user == null ||
            user.role == UserRole.coordinator ||
            user.role == UserRole.principal)
        ? allClasses
        : allClasses.where((c) => user.classIds.contains(c)).toList();

    final today = DateTime.now();
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];

    final isAdmin = user?.role == UserRole.coordinator ||
        user?.role == UserRole.principal;

    return Scaffold(
      body: Column(
        children: [
          // Feature 6: Offline banner
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: _isOffline ? 36 : 0,
            color: Colors.orange.shade700,
            child: _isOffline
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.wifi_off, color: Colors.white, size: 15),
                      SizedBox(width: 8),
                      Text(
                        'Offline — showing cached data',
                        style:
                            TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ],
                  )
                : null,
          ),

          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: 180,
                  pinned: true,
                  backgroundColor: const Color(0xFF1565C0),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.logout, color: Colors.white),
                      tooltip: 'Sign out',
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
                          padding:
                              const EdgeInsets.fromLTRB(20, 12, 60, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.school,
                                      color: Colors.white70, size: 20),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'School Attendance',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${weekdays[today.weekday - 1]}, ${today.day} ${months[today.month - 1]}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              if (user != null) ...[
                                Row(
                                  children: [
                                    const Icon(Icons.person,
                                        color: Colors.white70, size: 14),
                                    const SizedBox(width: 4),
                                    Text(
                                      user.name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color:
                                            Colors.white.withOpacity(0.2),
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        _roleLabel(user.role),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 4),
                              Text(
                                classes.isEmpty
                                    ? 'No classes assigned'
                                    : 'Select a class to take attendance',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (classes.isEmpty)
                  const SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.class_outlined,
                              size: 72, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'No classes assigned to you yet.\nContact your school admin.',
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(color: Colors.grey, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: 1.15,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final className = classes[index];
                          final studentCount =
                              classStudents[className]?.length ?? 0;
                          final color =
                              _cardColors[index % _cardColors.length];
                          return _ClassCard(
                            className: className,
                            studentCount: studentCount,
                            color: color,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AttendanceScreen(
                                    className: className),
                              ),
                            ),
                          );
                        },
                        childCount: classes.length,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),

      // Feature 2: Admin panel FAB for coordinators/principals
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              heroTag: 'admin_fab',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminScreen()),
              ),
              icon: const Icon(Icons.admin_panel_settings),
              label: const Text('Admin'),
            )
          : null,
    );
  }

  String _roleLabel(UserRole role) {
    switch (role) {
      case UserRole.teacher:
        return 'Teacher';
      case UserRole.guardian:
        return 'Guardian';
      case UserRole.coordinator:
        return 'Coordinator';
      case UserRole.principal:
        return 'Principal';
      case UserRole.subjectTeacher:
        return 'Subject Teacher';
    }
  }

  void _confirmSignOut(BuildContext context, AuthProvider auth) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out?'),
        content: const Text('You will be returned to the login screen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
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

class _ClassCard extends StatelessWidget {
  final String className;
  final int studentCount;
  final Color color;
  final VoidCallback onTap;

  const _ClassCard({
    required this.className,
    required this.studentCount,
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
                color: color.withOpacity(0.35),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.class_,
                      color: Colors.white, size: 22),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      className,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$studentCount students',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

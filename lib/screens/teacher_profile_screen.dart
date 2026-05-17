import 'package:flutter/material.dart';
import '../models/teacher.dart';
import '../services/timetable_service.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';
import '../theme.dart';

/// Shown when a user picks "Teacher" from the role selector.
/// They must select their own profile from the list added by the coordinator.
class TeacherProfileScreen extends StatefulWidget {
  const TeacherProfileScreen({super.key});

  @override
  State<TeacherProfileScreen> createState() => _TeacherProfileScreenState();
}

class _TeacherProfileScreenState extends State<TeacherProfileScreen> {
  List<Teacher> _teachers = [];
  bool _loading = true;

  static const _colors = [
    AppTheme.primary, AppTheme.primaryDark, AppTheme.primaryMid, AppTheme.primaryLight,
    AppTheme.accent, AppTheme.primary, AppTheme.primaryMid, AppTheme.primaryDark,
    AppTheme.primaryLight, AppTheme.accent,
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = await AuthService().getSession();
    final currentEmail =
        (session?['email'] as String? ?? '').toLowerCase().trim();
    final list = await TimetableService().getTeachers();
    if (!mounted) return;

    final matched = list
        .where((t) => t.email.toLowerCase().trim() == currentEmail)
        .toList();

    if (matched.length == 1) {
      await _select(matched.first);
      return;
    }

    if (matched.isEmpty) {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'No teacher profile found for this email. Contact your coordinator to register your email.'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 5),
      ));
      await AuthService().clearSession();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }

    setState(() {
      _teachers = matched;
      _loading = false;
    });
  }

  Future<void> _select(Teacher teacher) async {
    // Persist teacher selection so app stays logged in on next launch
    final session = await AuthService().getSession();
    if (session != null) {
      await AuthService().saveSession(
        email: (session['email'] as String?) ?? '',
        role: 'teacher',
        teacherId: teacher.id,
      );
    }
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => HomeScreen(teacher: teacher)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Select Your Profile',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text('Teacher login',
                style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _teachers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline,
                          size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('No teachers added yet',
                          style: TextStyle(
                              fontSize: 16, color: Colors.grey.shade400)),
                      const SizedBox(height: 6),
                      Text('Ask the coordinator to add teacher profiles',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade400)),
                    ],
                  ),
                )
              : Column(children: [
                  Container(
                    color: AppTheme.primary,
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: const Text(
                        'Tap your name to continue',
                        style:
                            TextStyle(color: Colors.white70, fontSize: 13)),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _teachers.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 72),
                      itemBuilder: (_, i) {
                        final t = _teachers[i];
                        final color = _colors[i % _colors.length];
                        return InkWell(
                          onTap: () => _select(t),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            child: Row(children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: color,
                                child: Text(t.name[0].toUpperCase(),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18)),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(t.name,
                                          style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 2),
                                      Text(
                                          [
                                            t.subject,
                                            if (t.section.isNotEmpty)
                                              'Section ${t.section}',
                                            if (t.isClassTeacher &&
                                                t.classTeacherOf != null)
                                              t.classTeacherOf!,
                                          ].join('  •  '),
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade500)),
                                      if (t.email.isNotEmpty)
                                        Text(t.email,
                                            style: TextStyle(
                                                fontSize: 11,
                                                color:
                                                    Colors.grey.shade400)),
                                    ]),
                              ),
                              if (t.isClassTeacher)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                        color: AppTheme.primary.withOpacity(0.30)),
                                  ),
                                  child: const Text('Class Teacher',
                                      style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.primaryDark)),
                                ),
                              const SizedBox(width: 4),
                              Icon(Icons.chevron_right,
                                  color: Colors.grey.shade400),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
                ]),
    );
  }
}

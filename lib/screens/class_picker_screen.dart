import 'package:flutter/material.dart';
import '../services/timetable_service.dart';
import '../theme.dart';

enum ClassPickerMode { attendance, studentList, reports }

class ClassPickerScreen extends StatefulWidget {
  final ClassPickerMode mode;
  const ClassPickerScreen({super.key, required this.mode});

  @override
  State<ClassPickerScreen> createState() => _ClassPickerScreenState();
}

class _ClassPickerScreenState extends State<ClassPickerScreen> {
  List<String> _classes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await TimetableService().getSettings();
    setState(() {
      _classes = List<String>.from(settings['classes'] as List);
      _loading = false;
    });
  }

  String get _title => 'Select Class';

  String get _subtitle {
    switch (widget.mode) {
      case ClassPickerMode.attendance: return 'Choose a class to take attendance';
      case ClassPickerMode.reports:    return 'Choose a class to view attendance history';
      default:                         return 'Choose a class to view students';
    }
  }

  Color get _color => AppTheme.primary;

  IconData get _icon {
    switch (widget.mode) {
      case ClassPickerMode.attendance: return Icons.fact_check_outlined;
      case ClassPickerMode.reports:    return Icons.bar_chart_outlined;
      default:                         return Icons.people_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(_title),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _classes.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.class_outlined,
                          size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('No classes configured',
                          style: TextStyle(
                              fontSize: 16, color: Colors.grey.shade400)),
                      const SizedBox(height: 6),
                      Text('Ask the coordinator to add classes',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade400)),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Container(
                      color: _color,
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: Text(_subtitle,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13)),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _classes.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 70),
                        itemBuilder: (_, i) {
                          final cls = _classes[i];
                          return InkWell(
                            onTap: () => Navigator.pop(context, cls),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                              child: Row(children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: _color.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(_icon, color: _color, size: 22),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(cls,
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600)),
                                ),
                                Icon(Icons.chevron_right,
                                    color: Colors.grey.shade400),
                              ]),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}

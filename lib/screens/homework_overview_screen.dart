import 'package:flutter/material.dart';
import '../models/homework.dart';
import '../services/homework_service.dart';
import '../services/timetable_service.dart';
import '../theme.dart';

/// Coordinator screen — view all homework across classes.
class HomeworkOverviewScreen extends StatefulWidget {
  const HomeworkOverviewScreen({super.key});

  @override
  State<HomeworkOverviewScreen> createState() =>
      _HomeworkOverviewScreenState();
}

class _HomeworkOverviewScreenState extends State<HomeworkOverviewScreen> {
  final _service = HomeworkService();

  bool           _loading = true;
  List<String>   _classes = [];
  String?        _selectedClass;
  List<Homework> _all     = [];
  List<Homework> _filtered = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final settings = await TimetableService().getSettings();
    final classes  = List<String>.from(settings['classes'] as List? ?? []);
    final all      = await _service.getAllHomework();
    if (!mounted) return;
    setState(() {
      _classes       = classes;
      _all           = all;
      _selectedClass = null;
      _filtered      = all;
      _loading       = false;
    });
  }

  void _filterClass(String? cls) {
    setState(() {
      _selectedClass = cls;
      _filtered = cls == null
          ? _all
          : _all.where((h) => h.className == cls).toList();
    });
  }

  Future<void> _delete(Homework hw) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Homework?'),
        content: Text('Delete "${hw.title}" posted by ${hw.teacherName}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      await _service.deleteHomework(hw.id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Homework Overview',
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold)),
            Text('All assignments across classes',
                style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Class filter chips
                if (_classes.isNotEmpty)
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: const Text('All'),
                              selected: _selectedClass == null,
                              selectedColor: AppTheme.primary,
                              labelStyle: TextStyle(
                                color: _selectedClass == null
                                    ? Colors.white
                                    : null,
                                fontWeight: _selectedClass == null
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                              onSelected: (_) => _filterClass(null),
                            ),
                          ),
                          ..._classes.map((cls) {
                            final sel = cls == _selectedClass;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(cls),
                                selected: sel,
                                selectedColor: AppTheme.primary,
                                labelStyle: TextStyle(
                                  color: sel ? Colors.white : null,
                                  fontWeight: sel
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                                onSelected: (_) => _filterClass(cls),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                const Divider(height: 1),

                // Summary bar
                if (_filtered.isNotEmpty)
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        _StatBadge(
                          label: 'Total',
                          count: _filtered.length,
                          color: AppTheme.primary,
                        ),
                        const SizedBox(width: 8),
                        _StatBadge(
                          label: 'Reviewed',
                          count: _filtered
                              .where((h) => h.isReviewed)
                              .length,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 8),
                        _StatBadge(
                          label: 'Pending',
                          count: _filtered
                              .where((h) => !h.isReviewed)
                              .length,
                          color: Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        _StatBadge(
                          label: 'Overdue',
                          count: _filtered
                              .where((h) => h.isOverdue)
                              .length,
                          color: Colors.red,
                        ),
                      ],
                    ),
                  ),

                Expanded(
                  child: _filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.assignment_outlined,
                                  size: 56,
                                  color: Colors.grey.shade300),
                              const SizedBox(height: 12),
                              Text(
                                'No homework found.',
                                style: TextStyle(
                                    color: Colors.grey.shade500),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: AppTheme.primary,
                          child: ListView.separated(
                            physics:
                                const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(12),
                            itemCount: _filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final hw = _filtered[i];
                              return _CoordHomeworkCard(
                                hw: hw,
                                onDelete: () => _delete(hw),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String label;
  final int    count;
  final Color  color;
  const _StatBadge(
      {required this.label,
      required this.count,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text('$count $label',
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.bold)),
    );
  }
}

class _CoordHomeworkCard extends StatelessWidget {
  final Homework     hw;
  final VoidCallback onDelete;
  const _CoordHomeworkCard(
      {required this.hw, required this.onDelete});

  Color get _statusColor {
    if (hw.isReviewed) return Colors.green;
    if (hw.isOverdue)  return Colors.red;
    return Colors.orange;
  }

  String get _statusLabel {
    if (hw.isReviewed) return 'Reviewed';
    if (hw.isOverdue)  return 'Overdue';
    final d = hw.daysUntilDue;
    if (d == 0) return 'Due Today';
    return 'Due in $d days';
  }

  @override
  Widget build(BuildContext context) {
    final due =
        '${hw.dueDate.day}/${hw.dueDate.month}/${hw.dueDate.year}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(hw.title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(_statusLabel,
                    style: TextStyle(
                        fontSize: 11,
                        color: _statusColor,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.class_outlined,
                  size: 13, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text(hw.className,
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(width: 10),
              Icon(Icons.book_outlined,
                  size: 13, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text(hw.subject,
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
          const SizedBox(height: 6),
          Text(hw.description,
              style: TextStyle(
                  fontSize: 13, color: Colors.grey.shade700),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.person_outline,
                  size: 13, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text('By ${hw.teacherName}',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade500)),
              const Spacer(),
              Icon(Icons.event_outlined,
                  size: 13, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text('Due: $due',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade500)),
              const SizedBox(width: 8),
              InkWell(
                onTap: onDelete,
                child: const Icon(Icons.delete_outline,
                    color: Colors.red, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

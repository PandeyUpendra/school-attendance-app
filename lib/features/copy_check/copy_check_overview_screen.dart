import 'package:flutter/material.dart';
import '../../l10n/app_strings.dart';
import '../../models/copy_check.dart';
import '../../models/student.dart';
import '../../services/copy_check_service.dart';
import '../../services/student_service.dart';
import '../../services/timetable_service.dart';
import '../../theme.dart';
import '../../shared/utils/app_logger.dart';
import '../../shared/widgets/refreshable_data.dart';
import '../../shared/utils/app_transitions.dart';

/// Coordinator screen — view copy-checking status across all classes.
class CopyCheckOverviewScreen extends StatefulWidget {
  const CopyCheckOverviewScreen({super.key});

  @override
  State<CopyCheckOverviewScreen> createState() =>
      _CopyCheckOverviewScreenState();
}

class _CopyCheckOverviewScreenState extends State<CopyCheckOverviewScreen> {
  bool _loading = true;
  List<String> _classes = [];
  String? _selectedClass;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadClasses();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadClasses() async {
    final settings = await TimetableService.instance.getSettings();
    final classes = List<String>.from(settings['classes'] as List? ?? []);
    if (!mounted) return;
    setState(() {
      _classes = classes;
      if (classes.isNotEmpty) {
        _selectedClass = classes.first;
      }
      _loading = false;
    });
  }

  void _onChipSelected(String cls) {
    final index = _classes.indexOf(cls);
    if (index != -1 && cls != _selectedClass) {
      setState(() {
        _selectedClass = cls;
      });
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _openDetail(CopyCheck check) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _CoordCheckDetailScreen(check: check),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('copyCheckingOverview'),
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold)),
            Text(context.tr('allSessionsAcrossClasses'),
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
      ),
      body: _loading
          ? const LoadingState()
          : _classes.isEmpty
              ? Center(
                  child: Text(context.tr('noClassesConfiguredShort'),
                      style: TextStyle(color: Colors.grey.shade500)))
              : Column(
                  children: [
                    // Class chips
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _classes.map((cls) {
                            final selected = cls == _selectedClass;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(cls),
                                selected: selected,
                                selectedColor: AppTheme.primary,
                                labelStyle: TextStyle(
                                  color: selected ? Colors.white : null,
                                  fontWeight: selected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                                onSelected: (_) => _onChipSelected(cls),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: _classes.length,
                        onPageChanged: (index) {
                          setState(() {
                            _selectedClass = _classes[index];
                          });
                        },
                        itemBuilder: (context, index) {
                          return _ClassSessionsList(
                            className: _classes[index],
                            onTapCheck: _openDetail,
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _ClassSessionsList extends StatefulWidget {
  final String className;
  final ValueChanged<CopyCheck> onTapCheck;

  const _ClassSessionsList({
    required this.className,
    required this.onTapCheck,
  });

  @override
  State<_ClassSessionsList> createState() => _ClassSessionsListState();
}

class _ClassSessionsListState extends State<_ClassSessionsList>
    with AutomaticKeepAliveClientMixin {
  final _service = CopyCheckService();
  bool _loading = true;
  List<CopyCheck> _checks = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final checks = await _service.getAllChecks(className: widget.className);
      if (!mounted) return;
      setState(() {
        _checks = checks;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const LoadingState();
    }
    if (_checks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined,
                size: 56,
                color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              context.tr('noCopyCheckSessions'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.primary,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: _checks.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final c = _checks[i];
          final date =
              '${c.checkDate.day}/${c.checkDate.month}/${c.checkDate.year}';
          return InkWell(
            onTap: () => widget.onTapCheck(c),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                      Icons.menu_book_outlined,
                      color: AppTheme.primary,
                      size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$date  •  ${c.subject}',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${context.tr('by')} ${c.teacherName}  •  ${c.className} ${c.section}',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    color: Colors.grey.shade400,
                    size: 20),
              ]),
            ),
          );
        },
      ),
    );
  }
}

// ─── Coordinator detail view for one session ──────────────────────────────────

class _CoordCheckDetailScreen extends StatefulWidget {
  final CopyCheck check;
  const _CoordCheckDetailScreen({required this.check});

  @override
  State<_CoordCheckDetailScreen> createState() =>
      _CoordCheckDetailScreenState();
}

class _CoordCheckDetailScreenState extends State<_CoordCheckDetailScreen>
    with SingleTickerProviderStateMixin {
  final _service        = CopyCheckService();
  final _studentService = StudentService.instance;
  late TabController _tab;
  bool _loading = true;
  List<CopyStatus> _all     = [];
  List<CopyStatus> _pending = [];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _studentService.getStudentsByClass(className: widget.check.className,
          section: widget.check.section),
      _service.getStatuses(widget.check.id),
    ]);
    final students = results[0] as List<Student>;
    final saved    = results[1] as List<CopyStatus>;

    assert(students.length == {for (final s in students) s.roll: s}.length,
        'Duplicate rolls detected in class ${widget.check.className}');
    AppLogger.d('StudentList', '[${widget.check.className}] count=${students.length}');

    // Build lookup from saved statuses; ignore any entry whose roll is not in students.
    final savedMap = {for (final s in saved) s.roll: s};

    // Iterate over authoritative student list — never over the sub-collection.
    final all = students.map((s) {
      final existing = savedMap[s.roll];
      return CopyStatus(
        roll:          s.roll,
        studentName:   s.name,    // always live from students/ collection
        guardianPhone: s.phone,   // always live from students/ collection
        status:        existing?.status ?? 'not_done',
        remarks:       existing?.remarks,
      );
    }).toList();

    final pending = all
        .where((s) => s.status == 'incomplete' || s.status == 'not_done')
        .toList();
    if (!mounted) return;
    setState(() {
      _all     = all;
      _pending = pending;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c    = widget.check;
    final date = '${c.checkDate.day}/${c.checkDate.month}/${c.checkDate.year}';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${c.subject} — $date',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold)),
            Text('${context.tr('by')} ${c.teacherName}  •  ${c.className} ${c.section}',
                style:
                    const TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: '${context.tr('allCount')} (${_all.length})'),
            Tab(text: '${context.tr('statusPending')} (${_pending.length})'),
          ],
        ),
      ),
      body: _loading
          ? const LoadingState()
          : PremiumTabBarView(
              controller: _tab,
              children: [
                _StatusList(statuses: _all, showAll: true),
                _StatusList(statuses: _pending, showAll: false),
              ],
            ),
    );
  }
}

class _StatusList extends StatelessWidget {
  final List<CopyStatus> statuses;
  final bool             showAll;
  const _StatusList(
      {required this.statuses, required this.showAll});

  Color _colorFor(String status) {
    switch (status) {
      case 'checked':    return AppTheme.success;
      case 'incomplete': return AppTheme.warning;
      default:           return AppTheme.danger;
    }
  }

  String _labelFor(BuildContext context, String status) {
    switch (status) {
      case 'checked':    return context.tr('copyChecked');
      case 'incomplete': return context.tr('copyIncomplete');
      default:           return context.tr('copyNotDone');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (statuses.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              showAll
                  ? Icons.people_outline
                  : Icons.check_circle_outline,
              size: 56,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 12),
            Text(
              showAll
                  ? context.tr('noStatusesRecorded')
                  : context.tr('allCopiesChecked'),
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: statuses.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final s     = statuses[i];
        final color = _colorFor(s.status);
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: color.withValues(alpha: 0.12),
              child: Text(
                s.studentName.isNotEmpty
                    ? s.studentName[0].toUpperCase()
                    : '?',
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.studentName,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  Text('${context.tr('roll')} ${s.roll}',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade500)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _labelFor(context, s.status),
                style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ]),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import '../models/copy_check.dart';
import '../services/copy_check_service.dart';
import '../services/timetable_service.dart';
import '../theme.dart';

/// Coordinator screen — view copy-checking status across all classes.
class CopyCheckOverviewScreen extends StatefulWidget {
  const CopyCheckOverviewScreen({super.key});

  @override
  State<CopyCheckOverviewScreen> createState() =>
      _CopyCheckOverviewScreenState();
}

class _CopyCheckOverviewScreenState extends State<CopyCheckOverviewScreen> {
  final _service = CopyCheckService();

  bool _loading = true;
  List<String>    _classes  = [];
  String?         _selectedClass;
  List<CopyCheck> _checks   = [];

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    final settings = await TimetableService().getSettings();
    final classes  = List<String>.from(settings['classes'] as List? ?? []);
    if (!mounted) return;
    setState(() { _classes = classes; });
    if (classes.isNotEmpty) {
      await _selectClass(classes.first);
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _selectClass(String cls) async {
    setState(() { _selectedClass = cls; _loading = true; });
    final checks = await _service.getAllChecks(className: cls);
    if (!mounted) return;
    setState(() { _checks = checks; _loading = false; });
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
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Copy Checking Overview',
                style:
                    TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text('All sessions across classes',
                style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _classes.isEmpty
              ? Center(
                  child: Text('No classes configured.',
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
                                selectedColor: Colors.indigo,
                                labelStyle: TextStyle(
                                  color: selected ? Colors.white : null,
                                  fontWeight: selected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                                onSelected: (_) => _selectClass(cls),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: _checks.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.menu_book_outlined,
                                      size: 56,
                                      color: Colors.grey.shade300),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No copy-checking sessions\nfor this class yet.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: Colors.grey.shade500),
                                  ),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: () =>
                                  _selectClass(_selectedClass!),
                              color: Colors.indigo,
                              child: ListView.separated(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.all(12),
                                itemCount: _checks.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (_, i) {
                                  final c = _checks[i];
                                  final date =
                                      '${c.checkDate.day}/${c.checkDate.month}/${c.checkDate.year}';
                                  return InkWell(
                                    onTap: () => _openDetail(c),
                                    child: Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        border: Border.all(
                                            color: Colors.grey.shade200),
                                      ),
                                      child: Row(children: [
                                        Container(
                                          width: 42, height: 42,
                                          decoration: BoxDecoration(
                                            color: Colors.indigo
                                                .withOpacity(0.1),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: const Icon(
                                              Icons.menu_book_outlined,
                                              color: Colors.indigo,
                                              size: 22),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '$date  •  ${c.subject}',
                                                style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight:
                                                        FontWeight.bold),
                                              ),
                                              Text(
                                                'By ${c.teacherName}',
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors
                                                        .grey.shade500),
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
                            ),
                    ),
                  ],
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
  final _service = CopyCheckService();
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
    final all     = await _service.getStatuses(widget.check.id);
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
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${c.subject} — $date',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold)),
            Text('By ${c.teacherName}  •  ${c.className}',
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
            Tab(text: 'All (${_all.length})'),
            Tab(text: 'Pending (${_pending.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
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
      case 'checked':    return Colors.green;
      case 'incomplete': return Colors.orange;
      default:           return Colors.red;
    }
  }

  String _labelFor(String status) {
    switch (status) {
      case 'checked':    return 'Checked';
      case 'incomplete': return 'Incomplete';
      default:           return 'Not Done';
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
                  ? 'No statuses recorded yet.'
                  : 'All copies checked!',
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
              backgroundColor: color.withOpacity(0.12),
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
                  Text('Roll ${s.roll}',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade500)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _labelFor(s.status),
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

import 'package:flutter/material.dart';
import '../theme.dart';
import '../models/fee.dart';
import '../services/fee_service.dart';
import '../services/timetable_service.dart';
import 'fee_collection_screen.dart';
import 'fee_structure_screen.dart';
import '../widgets/refreshable_data.dart';

/// Top-level fee screen shown to principal / owner / coordinator.
/// Displays school-wide collection stats and one card per class.
/// Tap a class card → FeeCollectionScreen pre-filtered to that class.
class FeeOverviewScreen extends StatefulWidget {
  /// Role passed through to hide/show edit actions (coordinator can edit structure).
  final String role; // 'principal' | 'owner' | 'coordinator'

  const FeeOverviewScreen({super.key, required this.role});

  @override
  State<FeeOverviewScreen> createState() => _FeeOverviewScreenState();
}

class _FeeOverviewScreenState extends State<FeeOverviewScreen> {
  final _feeService = FeeService();

  bool _loading = true;
  List<String>          _classes   = [];
  List<ClassFeeSummary> _summaries = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final settings = await TimetableService().getSettings();
      final classes  = List<String>.from(settings['classes'] as List? ?? []);
      final summaries = await _feeService.getClassSummaries(classes: classes);
      if (!mounted) return;
      setState(() {
        _classes   = classes;
        _summaries = summaries;
        _loading   = false;
      });
    } catch (_) {
      // Don't surface raw Firestore errors here — fall back to the calm empty
      // state below (the "No classes configured yet." view, with a Refresh).
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  // ── Aggregated school-wide numbers ────────────────────────────────────────

  double get _schoolTotalDue       => _summaries.fold(0, (s, c) => s + c.totalDue);
  double get _schoolTotalCollected => _summaries.fold(0, (s, c) => s + c.totalCollected);
  int    get _schoolStudents       => _summaries.fold(0, (s, c) => s + c.studentCount);
  int    get _schoolFullyPaid      => _summaries.fold(0, (s, c) => s + c.fullyPaid);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Fee Collection',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text('Class-wise collection overview',
                style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          // Coordinator can jump straight to fee structure config
          if (widget.role == 'coordinator')
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Fee Structure',
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FeeStructureScreen()),
                );
                _load(); // refresh after possible structure changes
              },
            ),
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const LoadingState()
          : _classes.isEmpty
              ? _emptyState()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppTheme.primary,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      // ── School-wide summary banner ────────────────────
                      _SchoolSummaryBanner(
                        totalDue:       _schoolTotalDue,
                        totalCollected: _schoolTotalCollected,
                        studentCount:   _schoolStudents,
                        fullyPaid:      _schoolFullyPaid,
                      ),

                      // ── Section header ────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                        child: Text(
                          'CLASSES  (${_classes.length})',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),

                      // ── Class cards ───────────────────────────────────
                      ...List.generate(_summaries.length, (i) {
                        return _ClassFeeCard(
                          summary: _summaries[i],
                          onTap: () => _openClass(_summaries[i].className),
                        );
                      }),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  void _openClass(String className) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FeeCollectionScreen(initialClass: className),
      ),
    ).then((_) => _load());
  }

  Widget _emptyState() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.school_outlined, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 14),
            Text(
              'No classes configured yet.',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 15),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _load,
              child: const Text('Refresh'),
            ),
          ],
        ),
      );
}

// ─── School-wide summary banner ───────────────────────────────────────────────

class _SchoolSummaryBanner extends StatelessWidget {
  final double totalDue;
  final double totalCollected;
  final int    studentCount;
  final int    fullyPaid;

  const _SchoolSummaryBanner({
    required this.totalDue,
    required this.totalCollected,
    required this.studentCount,
    required this.fullyPaid,
  });

  @override
  Widget build(BuildContext context) {
    final pct = totalDue > 0
        ? (totalCollected / totalDue * 100).clamp(0, 100)
        : 0.0;

    return Container(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 0),
      decoration: const BoxDecoration(
        color: AppTheme.primaryDark,
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('SCHOOL-WIDE COLLECTION',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1)),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _BannerStat(
                  '₹${_fmtK(totalCollected)}', 'Collected', Colors.white),
              _BannerStat('₹${_fmtK((totalDue - totalCollected).clamp(0, double.infinity))}',
                  'Pending', Colors.yellow.shade200),
              _BannerStat(
                  '$fullyPaid / $studentCount', 'Fully Paid', Colors.white),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: totalDue > 0
                  ? (totalCollected / totalDue).clamp(0.0, 1.0)
                  : 0,
              minHeight: 8,
              backgroundColor: Colors.white24,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            totalDue > 0
                ? '${pct.toStringAsFixed(1)}% of total fee collected'
                : 'No fee structures configured',
            style:
                const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  static String _fmtK(double v) {
    if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(1)}Cr';
    if (v >= 100000)   return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000)     return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

class _BannerStat extends StatelessWidget {
  final String value, label;
  final Color  color;
  const _BannerStat(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label,
              style:
                  TextStyle(color: color.withAlpha(178), fontSize: 10)),
        ],
      );
}

// ─── Per-class card ───────────────────────────────────────────────────────────

class _ClassFeeCard extends StatelessWidget {
  final ClassFeeSummary summary;
  final VoidCallback    onTap;
  const _ClassFeeCard({required this.summary, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s    = summary;
    final pct  = s.collectionPct;
    final hasFee = s.totalAnnualFee > 0;

    Color progressColor;
    if (!hasFee) {
      progressColor = Colors.grey;
    } else if (pct >= 0.9) {
      progressColor = Colors.green.shade600;
    } else if (pct >= 0.5) {
      progressColor = const Color(0xFFF57F17);
    } else {
      progressColor = Colors.red.shade400;
    }

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Class avatar
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withAlpha(26),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        s.className.replaceAll(' ', '').substring(
                            0,
                            s.className
                                .replaceAll(' ', '')
                                .length
                                .clamp(0, 3)
                                .toInt()),
                        style: const TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.className,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(
                          hasFee
                              ? '${s.fullyPaid}/${s.studentCount} fully paid'
                              : '${s.studentCount} students  •  no fee set',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                  // Right: collected + chevron
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        hasFee ? '₹${_fmtK(s.totalCollected)}' : '—',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: progressColor),
                      ),
                      Text(
                        hasFee
                            ? 'of ₹${_fmtK(s.totalDue)}'
                            : '',
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey.shade400),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right,
                      color: Colors.grey.shade300, size: 20),
                ],
              ),
              if (hasFee) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 5,
                    backgroundColor: Colors.grey.shade100,
                    valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${(pct * 100).toStringAsFixed(0)}% collected',
                      style: TextStyle(
                          fontSize: 11,
                          color: progressColor,
                          fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'Due ₹${_fmtK(s.pendingAmount)}',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _fmtK(double v) {
    if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(1)}Cr';
    if (v >= 100000)   return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000)     return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

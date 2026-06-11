import 'package:flutter/material.dart';
import '../../l10n/app_strings.dart';
import '../../theme.dart';
import '../../models/student.dart';
import '../../services/student_service.dart';
import '../../services/timetable_service.dart';
import '../../services/promotion_service.dart';
import '../../shared/utils/app_logger.dart';

/// Academic-year promotion / rollover (#70).
///
/// Lets a coordinator/principal promote a source class roster into the next
/// class. Source students keep their attendance/fee history (the old record is
/// archived, not deleted) and carry a stable admission id into the new class.
class PromotionScreen extends StatefulWidget {
  const PromotionScreen({super.key});

  @override
  State<PromotionScreen> createState() => _PromotionScreenState();
}

class _PromotionScreenState extends State<PromotionScreen> {
  final _studentSvc = StudentService.instance;

  List<String> _classes = [];
  bool _loadingClasses = true;

  String? _fromClass;
  String? _toClass;
  final _fromSection = TextEditingController();
  final _toSection = TextEditingController();

  List<Student> _loaded = [];
  bool _loadingStudents = false;
  bool _promoting = false;

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  @override
  void dispose() {
    _fromSection.dispose();
    _toSection.dispose();
    super.dispose();
  }

  Future<void> _loadClasses() async {
    try {
      final settings = await TimetableService.instance.getSettings();
      final classes =
          (settings['classes'] as List?)?.map((e) => e.toString()).toList() ??
              [];
      if (!mounted) return;
      setState(() {
        _classes = classes;
        _loadingClasses = false;
      });
    } catch (e, st) {
      AppLogger.e('PromotionScreen', 'Failed to load classes', e, st);
      if (!mounted) return;
      setState(() => _loadingClasses = false);
    }
  }

  Future<void> _loadStudents() async {
    final from = _fromClass;
    if (from == null) return;
    setState(() {
      _loadingStudents = true;
      _loaded = [];
    });
    final list = await _studentSvc.getStudentsByClass(
      className: from,
      section: _fromSection.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _loaded = list;
      _loadingStudents = false;
    });
  }

  Future<void> _promote() async {
    final to = _toClass;
    if (to == null || _loaded.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => PromotionDryRunDialog(
        students: _loaded,
        targetClass: to,
        targetSection: _toSection.text.trim(),
        fromClassSection:
            '$_fromClass${_fromSection.text.trim().isEmpty ? '' : ' ${_fromSection.text.trim()}'}',
        toClassSection:
            '$to${_toSection.text.trim().isEmpty ? '' : ' ${_toSection.text.trim()}'}',
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _promoting = true);
    PromotionResult result;
    try {
      result = await PromotionService().promoteStudents(
        students: _loaded,
        targetClass: to,
        targetSection: _toSection.text.trim(),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _promoting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${context.tr('promotionFailed')} $e')));
      return;
    }
    if (!mounted) return;
    setState(() {
      _promoting = false;
      _loaded = [];
    });
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.tr('promotionComplete')),
        content: SingleChildScrollView(
          child: Text(
            '${context.tr('promotedLabel')}: ${result.promoted}\n'
            '${context.tr('skippedLabel')}: ${result.skipped.length}'
            '${result.skipped.isEmpty ? '' : '\n\n${result.skipped.join('\n')}'}',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(_), child: Text(context.tr('ok'))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryDark,
        foregroundColor: Colors.white,
        title: Text(context.tr('promoteClass')),
      ),
      body: _loadingClasses
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _card(
                  context.tr('fromCurrentClass'),
                  _fromClass,
                  (v) => setState(() {
                    _fromClass = v;
                    _loaded = [];
                  }),
                  _fromSection,
                ),
                const SizedBox(height: 12),
                Center(
                  child: OutlinedButton.icon(
                    onPressed: _fromClass == null || _loadingStudents
                        ? null
                        : _loadStudents,
                    icon: const Icon(Icons.search),
                    label: Text(_loadingStudents
                        ? context.tr('loadingEllipsis')
                        : context.tr('loadStudents')),
                  ),
                ),
                if (_loaded.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('${_loaded.length} ${context.tr('studentsFoundSuffix')}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
                const SizedBox(height: 16),
                _card(
                  context.tr('toNextClass'),
                  _toClass,
                  (v) => setState(() => _toClass = v),
                  _toSection,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: (_loaded.isEmpty ||
                          _toClass == null ||
                          _toClass == _fromClass &&
                              _toSection.text.trim() ==
                                  _fromSection.text.trim() ||
                          _promoting)
                      ? null
                      : _promote,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: _promoting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.upgrade),
                  label: Text(_promoting ? context.tr('promotingEllipsis') : context.tr('promoteStudents')),
                ),
                const SizedBox(height: 12),
                Text(
                  context.tr('promotionFooterNote'),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
    );
  }

  Widget _card(String label, String? value, ValueChanged<String?> onChanged,
      TextEditingController sectionCtrl) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: AppTheme.primary)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: value,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: context.tr('classLabel'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              items: _classes
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: onChanged,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: sectionCtrl,
              decoration: InputDecoration(
                labelText: context.tr('sectionOptional'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PromotionDryRunDialog extends StatefulWidget {
  final List<Student> students;
  final String targetClass;
  final String targetSection;
  final String fromClassSection;
  final String toClassSection;

  const PromotionDryRunDialog({
    super.key,
    required this.students,
    required this.targetClass,
    required this.targetSection,
    required this.fromClassSection,
    required this.toClassSection,
  });

  @override
  State<PromotionDryRunDialog> createState() => _PromotionDryRunDialogState();
}

class _PromotionDryRunDialogState extends State<PromotionDryRunDialog> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  bool _analyzing = true;
  String? _error;
  late PromotionAnalysis _analysis;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _runAnalysis();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _runAnalysis() async {
    try {
      final res = await PromotionService().analyzePromotion(
        students: widget.students,
        targetClass: widget.targetClass,
        targetSection: widget.targetSection,
      );
      if (!mounted) return;
      setState(() {
        _analysis = res;
        _analyzing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _analyzing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_analyzing) {
      return AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppTheme.primary),
            const SizedBox(height: 16),
            Text(context.tr('loadingEllipsis')),
          ],
        ),
      );
    }

    if (_error != null) {
      return AlertDialog(
        title: const Text("Dry-run Failed"),
        content: Text("Error: $_error"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('ok')),
          ),
        ],
      );
    }

    final toPromote = _analysis.toPromoteNew;
    final skipped = _analysis.skipped;

    return AlertDialog(
      title: const Text("Promotion Dry-Run Preview"),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Promoting: ${widget.fromClassSection} ➔ ${widget.toClassSection}",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              "${toPromote.length} students ready to promote, ${skipped.length} skipped.",
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            TabBar(
              controller: _tabCtrl,
              labelColor: AppTheme.primary,
              unselectedLabelColor: Colors.grey,
              indicatorColor: AppTheme.primary,
              tabs: [
                Tab(text: "To Promote (${toPromote.length})"),
                Tab(text: "Skipped / Collisions (${skipped.length})"),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  toPromote.isEmpty
                      ? const Center(child: Text("No students to promote"))
                      : ListView.builder(
                          itemCount: toPromote.length,
                          itemBuilder: (context, idx) {
                            final s = toPromote[idx];
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.check_circle_outline, color: Colors.green),
                              title: Text(s.name),
                              subtitle: Text("Roll: ${s.roll} | Admission ID: ${s.admissionId}"),
                            );
                          },
                        ),
                  skipped.isEmpty
                      ? const Center(child: Text("No skipped/colliding records"))
                      : ListView.builder(
                          itemCount: skipped.length,
                          itemBuilder: (context, idx) {
                            final reason = skipped[idx];
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                              title: Text(reason),
                            );
                          },
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.tr('cancel')),
        ),
        ElevatedButton(
          onPressed: toPromote.isEmpty
              ? null
              : () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text("Proceed"),
        ),
      ],
    );
  }
}


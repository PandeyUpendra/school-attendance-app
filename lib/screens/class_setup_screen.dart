import 'package:flutter/material.dart';
import '../services/timetable_service.dart';
import '../theme.dart';

class ClassSetupScreen extends StatefulWidget {
  const ClassSetupScreen({super.key});

  @override
  State<ClassSetupScreen> createState() => _ClassSetupScreenState();
}

class _ClassSetupScreenState extends State<ClassSetupScreen> {
  final _service = TimetableService();
  bool _loading = true;

  static const _allBaseClasses = [
    'Nursery', 'LKG', 'UKG', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12'
  ];

  String _startClass = '1';
  String _endClass = '10';
  Map<String, List<String>> _sections = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await _service.getSettings();
    final classes = List<String>.from(settings['classes'] as List? ?? []);

    if (classes.isNotEmpty) {
      _parseExisting(classes);
    } else {
      _updateRange();
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  void _parseExisting(List<String> classes) {
    final reg = RegExp(r'^(Nursery|LKG|UKG|\d+)([A-Z]?.*)$');
    final parsedSections = <String, List<String>>{};
    final foundBases = <String>[];

    for (final c in classes) {
      final match = reg.firstMatch(c);
      if (match != null) {
        final bc = match.group(1)!;
        final sec = match.group(2)!.isEmpty ? 'A' : match.group(2)!;
        parsedSections.putIfAbsent(bc, () => []).add(sec);
        if (!foundBases.contains(bc) && _allBaseClasses.contains(bc)) {
          foundBases.add(bc);
        }
      } else {
        // Fallback for non-standard class names
        parsedSections.putIfAbsent(c, () => ['A']);
      }
    }

    if (foundBases.isNotEmpty) {
      foundBases.sort((a, b) => _allBaseClasses.indexOf(a).compareTo(_allBaseClasses.indexOf(b)));
      _sections = parsedSections;
      _startClass = foundBases.first;
      _endClass = foundBases.last;
    } else {
      _updateRange();
    }
  }

  void _updateRange() {
    final sIdx = _allBaseClasses.indexOf(_startClass);
    final eIdx = _allBaseClasses.indexOf(_endClass);
    if (sIdx == -1 || eIdx == -1 || sIdx > eIdx) return;

    final newSections = <String, List<String>>{};
    for (int i = sIdx; i <= eIdx; i++) {
      final bc = _allBaseClasses[i];
      newSections[bc] = _sections[bc] ?? ['A'];
    }
    setState(() => _sections = newSections);
  }

  void _addNextSection(String bc) {
    final currentSections = List<String>.from(_sections[bc] ?? ['A']);
    if (currentSections.length >= 10) return;

    for (int i = 0; i < 10; i++) {
      final letter = String.fromCharCode(65 + i);
      if (!currentSections.contains(letter)) {
        setState(() {
          currentSections.add(letter);
          currentSections.sort();
          _sections[bc] = currentSections;
        });
        return;
      }
    }
  }

  void _removeSection(String bc, String sec) {
    final currentSections = List<String>.from(_sections[bc] ?? ['A']);
    if (currentSections.length <= 1) return;

    setState(() {
      currentSections.remove(sec);
      _sections[bc] = currentSections;
    });
  }

  int _getNextIndex(List<String> secs) {
    for (int i = 0; i < 10; i++) {
      if (!secs.contains(String.fromCharCode(65 + i))) return i;
    }
    return secs.length;
  }

  Future<void> _save() async {
    final result = <String>[];
    for (final bc in _sections.keys) {
      for (final sec in _sections[bc]!) {
        result.add('$bc$sec');
      }
    }

    final settings = await _service.getSettings();
    settings['classes'] = result;
    await _service.saveSettings(settings);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Class & Section setup saved!'), backgroundColor: Colors.green),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Manage Classes & Sections'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildRangeSelector(),
                const Divider(height: 1),
                Expanded(child: _buildClassList()),
                _buildSaveButton(),
              ],
            ),
    );
  }

  Widget _buildRangeSelector() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('SET CLASS RANGE',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _startClass,
                  decoration: const InputDecoration(
                    labelText: 'From',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: _allBaseClasses
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _startClass = v);
                      _updateRange();
                    }
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _endClass,
                  decoration: const InputDecoration(
                    labelText: 'To',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: _allBaseClasses
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _endClass = v);
                      _updateRange();
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildClassList() {
    final keys = _sections.keys.toList();
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: keys.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final bc = keys[i];
        final secs = _sections[bc]!;
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            title: Text('Class $bc', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('Sections: ${secs.join(', ')}', style: TextStyle(color: AppTheme.primaryMid, fontSize: 13)),
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'ADD') {
                  _addNextSection(bc);
                } else if (value.startsWith('REMOVE_')) {
                  _removeSection(bc, value.substring(7));
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  enabled: false,
                  child: Text('MANAGE SECTIONS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                ),
                ...secs.map((s) => PopupMenuItem(
                  value: 'REMOVE_$s',
                  child: Row(
                    children: [
                      Text('Section $s'),
                      const Spacer(),
                      if (secs.length > 1) const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                    ],
                  ),
                )),
                if (secs.length < 10) ...[
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'ADD',
                    child: Row(
                      children: [
                        const Icon(Icons.add_circle_outline, color: Colors.green, size: 20),
                        const SizedBox(width: 8),
                        Text('Add Section ${String.fromCharCode(65 + _getNextIndex(secs))}',
                            style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${secs.length} Sections',
                        style: const TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                    const Icon(Icons.arrow_drop_down, color: AppTheme.primary, size: 18),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSaveButton() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, -2))],
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Save Configuration', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../services/timetable_service.dart';
import '../services/base_firestore_service.dart';
import '../theme.dart';

class BellSettingsScreen extends StatefulWidget {
  const BellSettingsScreen({super.key});

  @override
  State<BellSettingsScreen> createState() => _BellSettingsScreenState();
}

class _BellSettingsScreenState extends State<BellSettingsScreen> {
  final _service = TimetableService();
  final _classCtrl = TextEditingController();

  int _bellCount = 8;
  List<String> _classes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _classCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await _service.getSettings();
    if (!mounted) return;
    setState(() {
      _bellCount = settings['numberOfBells'] as int;
      _classes = List<String>.from(settings['classes'] as List);
      _loading = false;
    });
  }

  Future<void> _save() async {
    await _service.saveSettings(BaseFirestoreService.currentSchoolId ?? 'default_school', {'numberOfBells': _bellCount, 'classes': _classes});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Settings saved'), backgroundColor: Colors.green),
    );
  }

  void _addClass() {
    final name = _classCtrl.text.trim();
    if (name.isEmpty) return;
    if (_classes.contains(name)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Class already exists')));
      return;
    }
    setState(() => _classes.add(name));
    _classCtrl.clear();
  }

  void _removeClass(String cls) {
    setState(() => _classes.remove(cls));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bell & Class Settings'),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save, color: Colors.white),
            label: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Bells per day ───────────────────────────────────────────────
            _SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Bells per Day',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Bell 1 to Bell $_bellCount will appear in the timetable',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, size: 36),
                        color: AppTheme.primary,
                        onPressed:
                            _bellCount > 1 ? () => setState(() => _bellCount--) : null,
                      ),
                      const SizedBox(width: 20),
                      Text('$_bellCount',
                          style: const TextStyle(
                              fontSize: 44, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 20),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, size: 36),
                        color: AppTheme.primary,
                        onPressed:
                            _bellCount < 12 ? () => setState(() => _bellCount++) : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // ── Classes list ────────────────────────────────────────────────
            _SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Classes (${_classes.length})',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Drag to reorder', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _classCtrl,
                        decoration: const InputDecoration(
                          hintText: 'e.g. Class 6',
                          prefixIcon: Icon(Icons.class_),
                          border: OutlineInputBorder(),
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        textCapitalization: TextCapitalization.words,
                        onSubmitted: (_) => _addClass(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _addClass,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14)),
                      child: const Text('Add'),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  if (_classes.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('No classes added',
                            style: TextStyle(color: Colors.grey[400])),
                      ),
                    )
                  else
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _classes.length,
                      onReorder: (oldIdx, newIdx) {
                        if (newIdx > oldIdx) newIdx--;
                        setState(() {
                          final item = _classes.removeAt(oldIdx);
                          _classes.insert(newIdx, item);
                        });
                      },
                      itemBuilder: (_, i) {
                        final cls = _classes[i];
                        return ListTile(
                          key: ValueKey(cls),
                          leading: const Icon(Icons.drag_handle, color: Colors.grey),
                          title: Text(cls),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () => _removeClass(cls),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;
  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

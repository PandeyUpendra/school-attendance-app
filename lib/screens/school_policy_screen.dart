import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme.dart';
import '../services/school_service.dart';
import '../services/base_firestore_service.dart';

class SchoolPolicyScreen extends StatefulWidget {
  const SchoolPolicyScreen({super.key});

  @override
  State<SchoolPolicyScreen> createState() => _SchoolPolicyScreenState();
}

class _SchoolPolicyScreenState extends State<SchoolPolicyScreen> {
  final _service = SchoolService();
  final _picker = ImagePicker();
  final _ruleCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String _dressPhotoUrl = '';
  List<String> _rules = [];

  @override
  void initState() {
    super.initState();
    _loadPolicy();
  }

  @override
  void dispose() {
    _ruleCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPolicy() async {
    setState(() => _loading = true);
    try {
      final data = await _service.getSchoolPolicy(BaseFirestoreService.currentSchoolId ?? 'default_school');
      setState(() {
        _dressPhotoUrl = data['idealDressPhoto'] ?? '';
        _rules = List<String>.from(data['disciplineRules'] ?? []);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error loading policy: $e')));
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (picked == null) return;

    setState(() => _saving = true);
    try {
      final sId = BaseFirestoreService.currentSchoolId ?? 'default_school';
      final url = await _service.uploadDressPhoto(sId, File(picked.path));
      setState(() {
        _dressPhotoUrl = url;
        _saving = false;
      });
      await _service.updateSchoolPolicy(sId, {'idealDressPhoto': url});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error uploading image: $e')));
        setState(() => _saving = false);
      }
    }
  }

  void _addRule() {
    final rule = _ruleCtrl.text.trim();
    if (rule.isEmpty) return;
    setState(() {
      _rules.add(rule);
      _ruleCtrl.clear();
    });
  }

  void _removeRule(int index) {
    setState(() => _rules.removeAt(index));
  }

  Future<void> _savePolicy() async {
    setState(() => _saving = true);
    try {
      await _service.updateSchoolPolicy(BaseFirestoreService.currentSchoolId ?? 'default_school', {
        'idealDressPhoto': _dressPhotoUrl,
        'disciplineRules': _rules,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Policy saved successfully')));
        setState(() => _saving = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error saving policy: $e')));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Ideal Dress & Discipline'),
        actions: [
          if (!_loading)
            IconButton(
              onPressed: _saving ? null : _savePolicy,
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.save),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const SizedBox(height: 12),
                _buildPhotoCard(),
                const SizedBox(height: 32),
                const SizedBox(height: 12),
                _buildRulesSection(),
              ],
            ),
    );
  }

  Widget _buildPhotoCard() {
    return Container(
      width: double.infinity,
      height: 250,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          if (_dressPhotoUrl.isNotEmpty)
            Image.network(
              _dressPhotoUrl,
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
            )
          else
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.photo_outlined, size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  const Text('No photo uploaded',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          Positioned(
            right: 12,
            bottom: 12,
            child: Row(
              children: [
                if (_dressPhotoUrl.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FloatingActionButton.small(
                      onPressed: _saving
                          ? null
                          : () => setState(() => _dressPhotoUrl = ''),
                      backgroundColor: Colors.red,
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                  ),
                FloatingActionButton.small(
                  onPressed: _saving ? null : _pickImage,
                  backgroundColor: AppTheme.primary,
                  child: const Icon(Icons.edit, color: Colors.white),
                ),
              ],
            ),
          ),
          if (_saving)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildRulesSection() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ruleCtrl,
                decoration: InputDecoration(
                  hintText: 'Add a discipline rule...',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                onSubmitted: (_) => _addRule(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _addRule,
              icon: const Icon(Icons.add),
              style: IconButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.all(16),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_rules.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(
              children: [
                Icon(Icons.list_alt, size: 48, color: Colors.grey.shade300),
                const SizedBox(height: 8),
                const Text('No rules added yet',
                    style: TextStyle(color: Colors.grey)),
              ],
            ),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _rules.length,
            itemBuilder: (context, index) {
              return Card(
                key: ValueKey('rule_$index'),
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: const Icon(Icons.drag_handle, color: Colors.grey),
                  title: Text(_rules[index]),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _removeRule(index),
                  ),
                ),
              );
            },
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex -= 1;
                final rule = _rules.removeAt(oldIndex);
                _rules.insert(newIndex, rule);
              });
            },
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: AppTheme.primary,
      ),
    );
  }
}

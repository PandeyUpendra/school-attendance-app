import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/study_material.dart';
import '../../services/study_material_service.dart';
import '../../theme.dart';
import '../../l10n/app_strings.dart';
import '../../shared/utils/class_name_utils.dart';

class StudyMaterialListScreen extends StatefulWidget {
  final String className;
  final String section;

  const StudyMaterialListScreen({
    super.key,
    required this.className,
    required this.section,
  });

  @override
  State<StudyMaterialListScreen> createState() => _StudyMaterialListScreenState();
}

class _StudyMaterialListScreenState extends State<StudyMaterialListScreen> {
  final _service = StudyMaterialService();
  bool _loading = true;
  List<StudyMaterial> _allMaterials = [];
  String _selectedSubject = 'All';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadMaterials();
  }

  Future<void> _loadMaterials() async {
    setState(() => _loading = true);
    try {
      final list = await _service.getMaterials(widget.className);
      if (mounted) {
        setState(() {
          _allMaterials = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> get _subjectsList {
    final list = {'All'};
    for (final m in _allMaterials) {
      list.add(m.subject);
    }
    return list.toList()..sort();
  }

  List<StudyMaterial> get _filteredMaterials {
    return _allMaterials.where((m) {
      final matchesSubject = _selectedSubject == 'All' || m.subject == _selectedSubject;
      final matchesSearch = _searchQuery.isEmpty ||
          m.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          m.description.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesSubject && matchesSearch;
    }).toList();
  }

  Future<void> _openFile(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw 'Could not launch $url';
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('cannotOpenFile').replaceAll('{error}', e.toString())), backgroundColor: AppTheme.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(context.tr('studyMaterialsTitle').replaceAll('{class}', ClassName.format(widget.className, widget.section))),
        backgroundColor: AppTheme.primaryDark,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMaterials,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildSubjectFilterBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredMaterials.isEmpty
                    ? _buildEmptyState()
                    : _buildMaterialsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        decoration: InputDecoration(
          hintText: context.tr('searchStudyResources'),
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
          isDense: true,
        ),
        onChanged: (v) {
          setState(() {
            _searchQuery = v;
          });
        },
      ),
    );
  }

  Widget _buildSubjectFilterBar() {
    final list = _subjectsList;
    if (list.length <= 2) return const SizedBox(); // No need to filter if only one subject present

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: list.map((sub) {
            final isSelected = _selectedSubject == sub;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                selected: isSelected,
                onSelected: (val) {
                  if (val) {
                    setState(() {
                      _selectedSubject = sub;
                    });
                  }
                },
                label: Text(sub),
                labelStyle: TextStyle(
                  fontSize: 12,
                  color: isSelected ? Colors.white : AppTheme.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
                selectedColor: AppTheme.primary,
                backgroundColor: AppTheme.background,
                side: BorderSide(color: isSelected ? AppTheme.primary : AppTheme.border),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.library_books_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty ? context.tr('noStudyMaterialsPosted') : context.tr('noMatchingMaterialsFound'),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildMaterialsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredMaterials.length,
      itemBuilder: (context, index) {
        final mat = _filteredMaterials[index];
        final uploadDate = mat.uploadedAt ?? DateTime.now();
        final dateStr = '${uploadDate.day}/${uploadDate.month}/${uploadDate.year}';

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: AppTheme.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryLight.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        mat.subject.toUpperCase(),
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primary),
                      ),
                    ),
                    Text(
                      dateStr,
                      style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  mat.title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary),
                ),
                if (mat.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    mat.description,
                    style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                  ),
                ],
                const Divider(height: 24),
                Row(
                  children: [
                    const Icon(Icons.attachment_outlined, size: 16, color: AppTheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        mat.fileName,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _openFile(mat.fileUrl),
                      icon: const Icon(Icons.download, size: 14),
                      label: Text(context.tr('download')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

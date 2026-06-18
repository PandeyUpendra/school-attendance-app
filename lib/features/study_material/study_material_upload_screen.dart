import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/study_material.dart';
import '../../models/teacher.dart';
import '../../services/study_material_service.dart';
import '../../services/copy_check_service.dart';
import '../../theme.dart';
import '../../l10n/app_strings.dart';

class StudyMaterialUploadScreen extends StatefulWidget {
  final Teacher teacher;
  const StudyMaterialUploadScreen({super.key, required this.teacher});

  @override
  State<StudyMaterialUploadScreen> createState() => _StudyMaterialUploadScreenState();
}

class _StudyMaterialUploadScreenState extends State<StudyMaterialUploadScreen> {
  final _service = StudyMaterialService();
  bool _loadingClasses = true;
  bool _loadingHistory = false;
  bool _uploading = false;

  Map<String, String> _classSubjectMap = {}; // "Class Section" -> Subject
  String? _selectedClassKey;

  // Form fields
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();

  // File Picker State
  PlatformFile? _pickedFile;
  Uint8List? _fileBytes;

  List<StudyMaterial> _uploadHistory = [];

  @override
  void initState() {
    super.initState();
    _loadTeacherAssignments();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _loadTeacherAssignments() async {
    setState(() => _loadingClasses = true);
    try {
      final assignments = await CopyCheckService().getTeacherAssignments(widget.teacher.id);
      final map = <String, String>{};
      for (final a in assignments) {
        final key = a.section.isEmpty ? a.className : '${a.className} ${a.section}';
        map[key] = a.subject;
      }
      if (mounted) {
        setState(() {
          _classSubjectMap = map;
          _selectedClassKey = map.keys.isNotEmpty ? map.keys.first : null;
          _loadingClasses = false;
        });
        _loadUploadHistory();
      }
    } catch (e) {
      if (mounted) setState(() => _loadingClasses = false);
    }
  }

  Future<void> _loadUploadHistory() async {
    if (_selectedClassKey == null) return;
    setState(() => _loadingHistory = true);
    try {
      final list = await _service.getMaterials(_selectedClassKey!, subject: _classSubjectMap[_selectedClassKey!]);
      // Filter list to only show materials uploaded by this teacher
      final filtered = list.where((m) => m.uploadedBy == widget.teacher.email).toList();
      if (mounted) {
        setState(() {
          _uploadHistory = filtered;
          _loadingHistory = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _selectFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true, // Required for Web/macOS to read bytes easily
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.size > 10 * 1024 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.tr('fileSizeLimitError')), backgroundColor: AppTheme.danger),
            );
          }
          return;
        }
        setState(() {
          _pickedFile = file;
          _fileBytes = file.bytes;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('errorPickingFile').replaceAll('{error}', e.toString())), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  Future<void> _uploadAndPublish() async {
    if (!_formKey.currentState!.validate()) return;
    if (_pickedFile == null || _fileBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('attachFileError')), backgroundColor: AppTheme.danger),
      );
      return;
    }

    setState(() => _uploading = true);
    try {
      final subject = _classSubjectMap[_selectedClassKey!] ?? 'General';
      final fileName = _pickedFile!.name;
      final extension = fileName.split('.').last.toLowerCase();
      
      // Determine content type
      String contentType = 'application/octet-stream';
      if (extension == 'pdf') {
        contentType = 'application/pdf';
      } else if (['jpg', 'jpeg', 'png'].contains(extension)) {
        contentType = 'image/$extension';
      } else if (['doc', 'docx'].contains(extension)) {
        contentType = 'application/msword';
      }

      // 1. Upload file to Storage
      final downloadUrl = await _service.uploadMaterialFile(fileName, _fileBytes!, contentType);

      // 2. Save metadata in Firestore
      final material = StudyMaterial(
        id: '',
        title: _titleController.text.trim(),
        description: _descController.text.trim(),
        className: _selectedClassKey!,
        subject: subject,
        fileUrl: downloadUrl,
        fileName: fileName,
        uploadedBy: widget.teacher.email,
      );

      await _service.saveMaterial(material);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('studyMaterialUploadSuccess')), backgroundColor: AppTheme.success),
        );
        setState(() {
          _pickedFile = null;
          _fileBytes = null;
          _titleController.clear();
          _descController.clear();
        });
        _loadUploadHistory();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('uploadFailed').replaceAll('{error}', e.toString())), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _confirmDelete(StudyMaterial mat) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('deleteMaterialQuestion')),
        content: Text(context.tr('deleteMaterialConfirm').replaceAll('{title}', mat.title)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _loadingHistory = true);
      try {
        await _service.deleteMaterial(mat.id, mat.fileUrl);
        _loadUploadHistory();
      } catch (e) {
        if (mounted) setState(() => _loadingHistory = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(context.tr('publishStudyMaterials')),
        backgroundColor: AppTheme.primaryDark,
        elevation: 0,
      ),
      body: _loadingClasses
          ? const Center(child: CircularProgressIndicator())
          : _classSubjectMap.isEmpty
              ? _buildNoClassesState()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildUploadFormCard(),
                      const SizedBox(height: 24),
                      Text(
                        context.tr('myUploadHistory'),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.textSecondary, letterSpacing: 0.8),
                      ),
                      const SizedBox(height: 8),
                      _loadingHistory
                          ? const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
                          : _uploadHistory.isEmpty
                              ? _buildEmptyHistoryState()
                              : _buildHistoryList(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildNoClassesState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_upload_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              context.tr('noClassesAssignedToYou'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('studyMaterialNoClassesDesc'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadFormCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppTheme.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Upload New Resource',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primary),
              ),
              const Divider(height: 24),
              
              DropdownButtonFormField<String>(
                value: _selectedClassKey,
                decoration: InputDecoration(
                  labelText: context.tr('targetClassSubject'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                items: _classSubjectMap.entries.map((e) {
                  return DropdownMenuItem(
                    value: e.key,
                    child: Text('${e.key} (${e.value})'),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      _selectedClassKey = v;
                    });
                    _loadUploadHistory();
                  }
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: context.tr('titleTopicLabel'),
                  border: const OutlineInputBorder(),
                  hintText: context.tr('studyMaterialTitleHint'),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return context.tr('pleaseEnterTitle');
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _descController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: context.tr('descInstructionsLabel'),
                  border: const OutlineInputBorder(),
                  hintText: context.tr('studyMaterialDescHint'),
                ),
              ),
              const SizedBox(height: 16),

              // File Slot
              InkWell(
                onTap: _selectFile,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.attach_file, size: 28, color: AppTheme.primary),
                      const SizedBox(height: 8),
                      Text(
                        _pickedFile == null ? context.tr('attachFileLabel') : _pickedFile!.name,
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _pickedFile == null ? AppTheme.textSecondary : AppTheme.primary),
                      ),
                      if (_pickedFile != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            context.tr('fileSizeLabel').replaceAll('{size}', '${(_pickedFile!.size / 1024).toStringAsFixed(1)} KB'),
                            style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _uploading ? null : _uploadAndPublish,
                child: _uploading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Text(
                        context.tr('uploadPublish'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyHistoryState() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppTheme.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(context.tr('noUploadsFound'), style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        ),
      ),
    );
  }

  Widget _buildHistoryList() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _uploadHistory.length,
      itemBuilder: (context, index) {
        final mat = _uploadHistory[index];
        final uploadDate = mat.uploadedAt ?? DateTime.now();
        final dateStr = '${uploadDate.day}/${uploadDate.month}/${uploadDate.year}';
        
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: AppTheme.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.primaryLight.withValues(alpha: 0.15),
              foregroundColor: AppTheme.primary,
              child: const Icon(Icons.description_outlined),
            ),
            title: Text(mat.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text('${mat.fileName}\n${context.tr('publishedOn')} $dateStr', style: const TextStyle(fontSize: 11)),
            isThreeLine: true,
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
              onPressed: () => _confirmDelete(mat),
            ),
          ),
        );
      },
    );
  }
}

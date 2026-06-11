import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/study_material.dart';
import '../models/teacher.dart';
import '../services/study_material_service.dart';
import '../services/copy_check_service.dart';
import '../theme.dart';

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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('File size exceeds 10MB limit'), backgroundColor: AppTheme.danger),
          );
          return;
        }
        setState(() {
          _pickedFile = file;
          _fileBytes = file.bytes;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking file: $e'), backgroundColor: AppTheme.danger),
      );
    }
  }

  Future<void> _uploadAndPublish() async {
    if (!_formKey.currentState!.validate()) return;
    if (_pickedFile == null || _fileBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please attach a study material file'), backgroundColor: AppTheme.danger),
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
          const SnackBar(content: Text('Study material uploaded successfully!'), backgroundColor: AppTheme.success),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e'), backgroundColor: AppTheme.danger),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _confirmDelete(StudyMaterial mat) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Material?'),
        content: Text('Remove "${mat.title}" from the class repository? This also deletes the attached file.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
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
        title: const Text('Publish Study Materials'),
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
                      const Text(
                        'MY UPLOAD HISTORY',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.textSecondary, letterSpacing: 0.8),
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
            const Text(
              'No classes assigned',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            const Text(
              'You need timetable or copy-checking class assignments to upload study materials.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
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
                decoration: const InputDecoration(
                  labelText: 'Target Class & Subject',
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  isDense: true,
                  border: OutlineInputBorder(),
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
                decoration: const InputDecoration(
                  labelText: 'Title / Topic *',
                  border: OutlineInputBorder(),
                  hintText: 'e.g. Calculus Practice Questions',
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Please enter a title';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _descController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Description / Instructions',
                  border: OutlineInputBorder(),
                  hintText: 'e.g. Try to solve questions 1 to 5 before Friday.',
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
                        _pickedFile == null ? 'Attach File (Max 10MB)' : _pickedFile!.name,
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _pickedFile == null ? AppTheme.textSecondary : AppTheme.primary),
                      ),
                      if (_pickedFile != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Size: ${(_pickedFile!.size / 1024).toStringAsFixed(1)} KB',
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
                    : const Text(
                        'Upload & Publish',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
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
      child: const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text('No previous uploads found for this class.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
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
            subtitle: Text('${mat.fileName}\nPublished on $dateStr', style: const TextStyle(fontSize: 11)),
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

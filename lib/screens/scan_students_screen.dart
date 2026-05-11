import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/student.dart';

class ScanStudentsScreen extends StatefulWidget {
  const ScanStudentsScreen({super.key});

  @override
  State<ScanStudentsScreen> createState() => _ScanStudentsScreenState();
}

class _ScanStudentsScreenState extends State<ScanStudentsScreen> {
  File? _imageFile;
  bool _isProcessing = false;
  List<Student> _parsedStudents = [];
  String _rawText = '';

  Future<void> _pickImage(ImageSource source) async {
    final picked =
        await ImagePicker().pickImage(source: source, imageQuality: 90);
    if (picked == null) return;

    setState(() {
      _imageFile = File(picked.path);
      _isProcessing = true;
      _parsedStudents = [];
      _rawText = '';
    });

    await _recognize(File(picked.path));
  }

  Future<void> _recognize(File image) async {
    final recognizer =
        TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFile(image));
      setState(() {
        _rawText = result.text;
        _parsedStudents = _parse(result.text);
        _isProcessing = false;
      });
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Recognition error: $e')),
        );
      }
    } finally {
      recognizer.close();
    }
  }

  List<Student> _parse(String text) {
    final pattern = RegExp(r'^(\d+)[.\s):-]+\s*(.+)$');
    return text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .expand((line) {
          final m = pattern.firstMatch(line);
          if (m == null) return <Student>[];
          final roll = int.tryParse(m.group(1)!);
          final name = m.group(2)!.trim();
          if (roll == null || name.isEmpty) return <Student>[];
          return [Student(id: 'scanned_${roll}_${DateTime.now().millisecondsSinceEpoch}', roll: roll, name: name)];
        })
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Student List'),
        actions: [
          if (_rawText.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.text_snippet_outlined),
              tooltip: 'View raw text',
              onPressed: () => showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Recognized Text'),
                  content: SingleChildScrollView(child: Text(_rawText)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close')),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Picker buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: _PickerButton(
                    icon: Icons.camera_alt_outlined,
                    label: 'Camera',
                    onTap: () => _pickImage(ImageSource.camera),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PickerButton(
                    icon: Icons.photo_library_outlined,
                    label: 'Gallery',
                    onTap: () => _pickImage(ImageSource.gallery),
                  ),
                ),
              ],
            ),
          ),

          // Image preview
          if (_imageFile != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  _imageFile!,
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),

          const SizedBox(height: 8),

          // Content area
          Expanded(
            child: _isProcessing
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Recognizing text…',
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : _parsedStudents.isNotEmpty
                    ? Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                            child: Row(
                              children: [
                                Text(
                                  '${_parsedStudents.length} student(s) found',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14),
                                ),
                                const Spacer(),
                                TextButton.icon(
                                  onPressed: () => Navigator.pop(
                                      context, _parsedStudents),
                                  icon: const Icon(Icons.check_rounded),
                                  label: const Text('Use These'),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14),
                              itemCount: _parsedStudents.length,
                              itemBuilder: (_, i) {
                                final s = _parsedStudents[i];
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius:
                                        BorderRadius.circular(10),
                                    boxShadow: const [
                                      BoxShadow(
                                          color: Colors.black12,
                                          blurRadius: 3,
                                          offset: Offset(0, 1)),
                                    ],
                                  ),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: const Color(
                                              0xFF1565C0)
                                          .withOpacity(0.1),
                                      child: Text(
                                        s.roll.toString(),
                                        style: const TextStyle(
                                            color: Color(0xFF1565C0),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13),
                                      ),
                                    ),
                                    title: Text(s.name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600)),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      )
                    : Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.document_scanner_outlined,
                                  size: 72,
                                  color: Colors.grey.shade300),
                              const SizedBox(height: 16),
                              Text(
                                _imageFile != null
                                    ? 'No students found.\nEnsure lines are like:\n"1. Student Name"'
                                    : 'Take a photo of your attendance\nregister or student list',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 14,
                                    height: 1.5),
                              ),
                            ],
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _PickerButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PickerButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: const Color(0xFF1565C0), size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1565C0)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 90);
    if (picked == null) return;

    setState(() {
      _imageFile = File(picked.path);
      _isProcessing = true;
      _parsedStudents = [];
      _rawText = '';
    });

    await _recognizeText(File(picked.path));
  }

  Future<void> _recognizeText(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);

    try {
      final RecognizedText result = await recognizer.processImage(inputImage);
      final text = result.text;
      final students = _parseStudents(text);

      setState(() {
        _rawText = text;
        _parsedStudents = students;
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error recognizing text: $e')),
        );
      }
    } finally {
      recognizer.close();
    }
  }

  /// Attempts to parse lines like:
  ///   "1. Rohan Gupta"
  ///   "1 Rohan Gupta"
  ///   "Roll: 1, Name: Rohan Gupta"
  List<Student> _parseStudents(String text) {
    final lines = text.split('\n');
    final students = <Student>[];

    final pattern = RegExp(r'^(\d+)[.\s):-]+\s*(.+)$');

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final match = pattern.firstMatch(trimmed);
      if (match != null) {
        final roll = int.tryParse(match.group(1)!);
        final name = match.group(2)!.trim();
        if (roll != null && name.isNotEmpty) {
          students.add(Student(roll: roll, name: name));
        }
      }
    }

    return students;
  }

  void _showRawText() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Recognized Text'),
        content: SingleChildScrollView(child: Text(_rawText)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Student List'),
        actions: [
          if (_rawText.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.text_snippet),
              tooltip: 'View raw text',
              onPressed: _showRawText,
            ),
        ],
      ),
      body: Column(
        children: [
          // Image picker buttons
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Camera'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                  ),
                ),
              ],
            ),
          ),

          // Preview image
          if (_imageFile != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  _imageFile!,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),

          const SizedBox(height: 8),

          if (_isProcessing)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_parsedStudents.isEmpty && _imageFile != null)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.search_off, size: 48, color: Colors.grey),
                    const SizedBox(height: 8),
                    const Text(
                      'No students found.\nEnsure lines are formatted as:\n"1. Student Name"',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                    if (_rawText.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _showRawText,
                        child: const Text('View recognized text'),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else if (_parsedStudents.isNotEmpty)
            Expanded(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Text(
                          '${_parsedStudents.length} student(s) found',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () =>
                              Navigator.pop(context, _parsedStudents),
                          icon: const Icon(Icons.check),
                          label: const Text('Use These'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _parsedStudents.length,
                      itemBuilder: (_, i) {
                        final s = _parsedStudents[i];
                        return ListTile(
                          leading: CircleAvatar(
                            child: Text(s.roll.toString()),
                          ),
                          title: Text(s.name),
                        );
                      },
                    ),
                  ),
                ],
              ),
            )
          else
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.document_scanner,
                        size: 64, color: Colors.grey),
                    SizedBox(height: 12),
                    Text(
                      'Scan a student list from a photo or document.\nExpected format: "1. Student Name"',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

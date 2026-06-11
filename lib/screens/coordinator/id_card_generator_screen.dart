import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../../models/student.dart';
import '../../services/student_service.dart';
import '../../services/timetable_service.dart';
import '../../providers/school_settings_provider.dart';
import '../../theme.dart';
import '../../utils/pdf_theme.dart';

class IdCardGeneratorScreen extends StatefulWidget {
  const IdCardGeneratorScreen({super.key});

  @override
  State<IdCardGeneratorScreen> createState() => _IdCardGeneratorScreenState();
}

class _IdCardGeneratorScreenState extends State<IdCardGeneratorScreen> {
  final _studentService = StudentService();
  bool _loadingClasses = true;
  bool _generating = false;

  List<String> _classes = [];
  String? _selectedClass;

  final List<String> _sections = ['All', 'A', 'B', 'C', 'D', 'E'];
  String _selectedSection = 'All';

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    setState(() => _loadingClasses = true);
    try {
      final settings = await TimetableService.instance.getSettings();
      final cls = List<String>.from(settings['classes'] as List? ?? []);
      if (mounted) {
        setState(() {
          _classes = cls;
          _selectedClass = cls.isNotEmpty ? cls.first : null;
          _loadingClasses = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingClasses = false);
    }
  }

  Future<void> _generatePdf(String schoolName) async {
    if (_selectedClass == null) return;

    setState(() => _generating = true);
    try {
      final sectionFilter = _selectedSection == 'All' ? '' : _selectedSection;
      final students = await _studentService.getStudentsByClass(
        className: _selectedClass!,
        section: sectionFilter,
      );

      if (students.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No students found in the selected class/section.'),
              backgroundColor: AppTheme.warning,
            ),
          );
        }
        setState(() => _generating = false);
        return;
      }

      // Download student photos in parallel
      final Map<String, Uint8List> photoData = {};
      final client = http.Client();
      try {
        final futures = students.map((s) async {
          if (s.photoUrl != null && s.photoUrl!.isNotEmpty) {
            try {
              final res = await client
                  .get(Uri.parse(s.photoUrl!))
                  .timeout(const Duration(seconds: 4));
              if (res.statusCode == 200) {
                photoData[s.id] = res.bodyBytes;
              }
            } catch (_) {}
          }
        });
        await Future.wait(futures);
      } finally {
        client.close();
      }

      // Compile PDF Document
      final pdf = pw.Document();

      // Chunk students by 8 (2 columns x 4 rows per page)
      final List<List<Student>> chunks = [];
      for (var i = 0; i < students.length; i += 8) {
        chunks.add(students.sublist(
            i, i + 8 > students.length ? students.length : i + 8));
      }

      for (final chunk in chunks) {
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(20),
            build: (pw.Context context) {
              return pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.start,
                children: [
                  for (var row = 0; row < 4; row++) ...[
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        for (var col = 0; col < 2; col++) ...[
                          _buildCardWrapper(
                            row * 2 + col,
                            chunk,
                            photoData,
                            schoolName,
                          ),
                        ]
                      ],
                    ),
                    if (row < 3) pw.SizedBox(height: 10),
                  ]
                ],
              );
            },
          ),
        );
      }

      // Trigger print preview
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'ID_Cards_${_selectedClass!.replaceAll(' ', '_')}_$_selectedSection.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate ID Cards: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _generating = false);
      }
    }
  }

  pw.Widget _buildCardWrapper(
    int index,
    List<Student> chunk,
    Map<String, Uint8List> photoData,
    String schoolName,
  ) {
    if (index >= chunk.length) {
      // Invisible card placeholder to preserve grid structure
      return pw.Opacity(
        opacity: 0.0,
        child: pw.Container(width: 265, height: 180),
      );
    }

    final student = chunk[index];
    final bytes = photoData[student.id];
    final imageProvider = bytes != null ? pw.MemoryImage(bytes) : null;

    return pw.Container(
      width: 265,
      height: 180,
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(color: PdfTheme.primary, width: 1.2),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          pw.Container(
            height: 28,
            decoration: const pw.BoxDecoration(
              color: PdfTheme.primary,
              borderRadius: pw.BorderRadius.only(
                topLeft: pw.Radius.circular(7),
                topRight: pw.Radius.circular(7),
              ),
            ),
            padding: const pw.EdgeInsets.symmetric(horizontal: 6),
            alignment: pw.Alignment.center,
            child: pw.Text(
              schoolName.toUpperCase(),
              style: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                fontSize: 9.5,
              ),
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
            ),
          ),
          // Subheader
          pw.Container(
            height: 14,
            color: PdfTheme.primaryTint,
            alignment: pw.Alignment.center,
            child: pw.Text(
              'STUDENT IDENTITY CARD',
              style: pw.TextStyle(
                color: PdfTheme.primary,
                fontWeight: pw.FontWeight.bold,
                fontSize: 7.5,
                letterSpacing: 0.5,
              ),
            ),
          ),
          // Main Body
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Photo Box
                  pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.start,
                    children: [
                      pw.Container(
                        width: 58,
                        height: 70,
                        decoration: pw.BoxDecoration(
                          color: PdfTheme.grey50,
                          borderRadius:
                              const pw.BorderRadius.all(pw.Radius.circular(4)),
                          border: pw.Border.all(
                            color: PdfTheme.primaryLight,
                            width: 0.8,
                          ),
                        ),
                        child: imageProvider != null
                            ? pw.ClipRRect(
                                horizontalRadius: 3,
                                verticalRadius: 3,
                                child: pw.Image(
                                  imageProvider,
                                  fit: pw.BoxFit.cover,
                                ),
                              )
                            : pw.Center(
                                child: pw.Text(
                                  'PHOTO',
                                  style: const pw.TextStyle(
                                    fontSize: 8,
                                    color: PdfTheme.grey400,
                                  ),
                                ),
                              ),
                      ),
                      pw.SizedBox(height: 6),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1.5),
                        decoration: const pw.BoxDecoration(
                          color: PdfTheme.accent,
                          borderRadius:
                              pw.BorderRadius.all(pw.Radius.circular(4)),
                        ),
                        child: pw.Text(
                          'B.G: ${student.bloodGroup ?? "N/A"}',
                          style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 7,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(width: 8),
                  // Details Box
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          student.name.toUpperCase(),
                          style: pw.TextStyle(
                            fontSize: 10.5,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfTheme.primary,
                          ),
                          maxLines: 1,
                          overflow: pw.TextOverflow.clip,
                        ),
                        pw.SizedBox(height: 3),
                        _buildDetailRow(
                            'Class/Sec:', '${student.className} - ${student.section}'),
                        _buildDetailRow('Roll No:', '${student.roll}'),
                        _buildDetailRow(
                            'Adm No:', student.admissionId.isNotEmpty ? student.admissionId : 'N/A'),
                        _buildDetailRow('Father:', student.fatherName),
                        _buildDetailRow(
                            'Emergency:', student.emergencyContact ?? student.phone),
                        pw.Spacer(),
                        pw.Align(
                          alignment: pw.Alignment.bottomRight,
                          child: pw.Text(
                            'Auth. Signatory',
                            style: pw.TextStyle(
                              fontSize: 6.5,
                              color: PdfTheme.textLight,
                              fontStyle: pw.FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildDetailRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 52,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfTheme.textLight,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value.isNotEmpty ? value : 'N/A',
              style: const pw.TextStyle(
                fontSize: 7.5,
                color: PdfColors.black,
              ),
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SchoolSettingsProvider>(context);
    final schoolName = settings.schoolName;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Batch ID Card Generator'),
        backgroundColor: AppTheme.primaryDark,
        elevation: 0,
      ),
      body: _loadingClasses
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      side: const BorderSide(color: AppTheme.border),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Select Target Class & Section',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: AppTheme.primary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            value: _selectedClass,
                            decoration: const InputDecoration(
                              labelText: 'Class',
                              prefixIcon: Icon(Icons.class_),
                              border: OutlineInputBorder(),
                            ),
                            items: _classes.map((cls) {
                              return DropdownMenuItem(
                                  value: cls, child: Text(cls));
                            }).toList(),
                            onChanged: (v) {
                              setState(() {
                                _selectedClass = v;
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            value: _selectedSection,
                            decoration: const InputDecoration(
                              labelText: 'Section',
                              prefixIcon: Icon(Icons.grid_3x3),
                              border: OutlineInputBorder(),
                            ),
                            items: _sections.map((sec) {
                              return DropdownMenuItem(
                                  value: sec, child: Text(sec));
                            }).toList(),
                            onChanged: (v) {
                              if (v != null) {
                                setState(() {
                                  _selectedSection = v;
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.picture_as_pdf),
                    onPressed: _generating ? null : () => _generatePdf(schoolName),
                    label: _generating
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Generate PDF Batch',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                  const SizedBox(height: 20),
                  const Card(
                    color: AppTheme.primaryLight,
                    elevation: 0,
                    child: Padding(
                      padding: EdgeInsets.all(12.0),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: AppTheme.primary),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'This compiles and generates a print-ready A4 PDF layout containing student ID cards (2x4 grid, 8 cards per page). Student photos will be downloaded automatically if configured.',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppTheme.primaryDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';
import '../models/datesheet.dart';
import '../models/exam.dart';
import '../models/student.dart';
import '../services/datesheet_service.dart';
import '../services/exam_service.dart';
import '../providers/school_settings_provider.dart';
import '../theme.dart';
import '../utils/pdf_theme.dart';

class GuardianDatesheetScreen extends StatefulWidget {
  final Student student;

  const GuardianDatesheetScreen({
    super.key,
    required this.student,
  });

  @override
  State<GuardianDatesheetScreen> createState() => _GuardianDatesheetScreenState();
}

class _GuardianDatesheetScreenState extends State<GuardianDatesheetScreen> {
  final _examService = ExamService();
  final _datesheetService = DatesheetService();

  bool _loadingExams = true;
  bool _loadingDatesheet = false;

  List<Exam> _exams = [];
  Exam? _selectedExam;
  Datesheet? _datesheet;

  @override
  void initState() {
    super.initState();
    _loadExams();
  }

  Future<void> _loadExams() async {
    setState(() => _loadingExams = true);
    try {
      final list = await _examService.getExams(className: widget.student.className);
      // Only show published exams to guardians
      final published = list.where((e) => e.isPublished).toList();
      if (mounted) {
        setState(() {
          _exams = published;
          _selectedExam = published.isNotEmpty ? published.first : null;
          _loadingExams = false;
        });
        if (_selectedExam != null) {
          _loadDatesheet();
        }
      }
    } catch (e) {
      if (mounted) setState(() => _loadingExams = false);
    }
  }

  Future<void> _loadDatesheet() async {
    if (_selectedExam == null) return;
    setState(() => _loadingDatesheet = true);
    try {
      final datesheet = await _datesheetService.getDatesheet(widget.student.className, _selectedExam!.id);
      if (mounted) {
        setState(() {
          _datesheet = datesheet;
          _loadingDatesheet = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingDatesheet = false);
    }
  }

  pw.Document _buildAdmitCardPdf(String schoolName) {
    final pdf = pw.Document();
    final s = widget.student;
    final ex = _selectedExam!;
    final ds = _datesheet!;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header Block
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(schoolName.toUpperCase(), style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfTheme.primary)),
                    pw.SizedBox(height: 4),
                    pw.Text('EXAM ADMIT CARD / HALL TICKET', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
                    pw.Text('${ex.name} - Academic Term', style: pw.TextStyle(fontSize: 11, color: PdfTheme.textLight)),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),
              pw.Divider(thickness: 1, color: PdfTheme.primaryLight),
              pw.SizedBox(height: 12),

              // Student Details Grid
              pw.Text('Student Information', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfTheme.primary)),
              pw.SizedBox(height: 6),
              pw.Table(
                border: pw.TableBorder.all(color: PdfTheme.grey200, width: 0.5),
                children: [
                  pw.TableRow(
                    children: [
                      _buildInfoCell('Candidate Name:', s.name, isHeader: true),
                      _buildInfoCell('Roll Number:', '${s.roll}', isHeader: true),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      _buildInfoCell('Class & Section:', '${s.className} ${s.section}', isHeader: true),
                      _buildInfoCell('Admission Number:', s.admissionId ?? 'N/A', isHeader: true),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 20),

              // Exam Schedule Table
              pw.Text('Exam Schedule', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfTheme.primary)),
              pw.SizedBox(height: 8),
              pw.Table(
                border: pw.TableBorder.all(color: PdfTheme.grey400),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfTheme.primaryTint),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Subject', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Date', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Time / Duration', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                    ],
                  ),
                  ...ds.schedules.map((sched) {
                    return pw.TableRow(
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(sched.subject, style: const pw.TextStyle(fontSize: 9))),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(sched.dateStr, style: const pw.TextStyle(fontSize: 9))),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(sched.timeStr, style: const pw.TextStyle(fontSize: 9))),
                      ],
                    );
                  }),
                ],
              ),
              pw.SizedBox(height: 24),

              // Instructions
              pw.Text('Instructions to the Candidate:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              _buildInstructionBullet('1. Please carry a physical printout of this admit card to the examination hall.'),
              _buildInstructionBullet('2. Candidates must report at least 15 minutes before the scheduled start time.'),
              _buildInstructionBullet('3. Calculators, mobile phones, smartwatches, and study materials are strictly prohibited.'),
              _buildInstructionBullet('4. Cooperate with the invigilation staff for identity check verification.'),

              pw.Spacer(),
              
              // Signatures
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    children: [
                      pw.Container(width: 100, height: 1, color: PdfColors.black),
                      pw.SizedBox(height: 4),
                      pw.Text('Invigilator Signature', style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Container(width: 100, height: 1, color: PdfColors.black),
                      pw.SizedBox(height: 4),
                      pw.Text('Principal Signature', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
    return pdf;
  }

  pw.Widget _buildInfoCell(String label, String value, {bool isHeader = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Row(
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfTheme.textLight)),
          pw.SizedBox(width: 4),
          pw.Text(value, style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    );
  }

  pw.Widget _buildInstructionBullet(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Text(text, style: const pw.TextStyle(fontSize: 8, color: PdfTheme.textLight)),
    );
  }

  Future<void> _printAdmitCard(String schoolName) async {
    if (_datesheet == null || _datesheet!.schedules.isEmpty) return;
    try {
      final pdf = _buildAdmitCardPdf(schoolName);
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'AdmitCard_${widget.student.name.replaceAll(' ', '_')}.pdf',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to print admit card: $e'), backgroundColor: AppTheme.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SchoolSettingsProvider>(context);
    final schoolName = settings.schoolName;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Exam Datesheets & Admit Card'),
        backgroundColor: AppTheme.primaryDark,
        elevation: 0,
      ),
      body: _loadingExams
          ? const Center(child: CircularProgressIndicator())
          : _exams.isEmpty
              ? _buildEmptyState()
              : Column(
                  children: [
                    _buildExamSelector(),
                    Expanded(
                      child: _loadingDatesheet
                          ? const Center(child: CircularProgressIndicator())
                          : _datesheet == null || _datesheet!.schedules.isEmpty
                              ? _buildNoDatesheetState()
                              : _buildDatesheetView(schoolName),
                    ),
                  ],
                ),
    );
  }

  Widget _buildExamSelector() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: DropdownButtonFormField<Exam>(
        value: _selectedExam,
        decoration: const InputDecoration(
          labelText: 'Active Examination',
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          isDense: true,
          border: OutlineInputBorder(),
        ),
        items: _exams.map((ex) {
          return DropdownMenuItem(value: ex, child: Text(ex.name));
        }).toList(),
        onChanged: (v) {
          if (v != null) {
            setState(() {
              _selectedExam = v;
            });
            _loadDatesheet();
          }
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_outlined, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text(
              'No exams scheduled',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            const Text(
              'There are no active exam schedules posted for your class.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoDatesheetState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calendar_today, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text(
              'Schedule pending',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            const Text(
              'The exam has been created, but the coordinator has not yet published the datesheet schedule.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDatesheetView(String schoolName) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Admit Card Download Card
          Card(
            elevation: 0,
            color: AppTheme.primaryLight.withValues(alpha: 0.15),
            shape: RoundedRectangleBorder(
              side: const BorderSide(color: AppTheme.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.picture_as_pdf, size: 36, color: AppTheme.primary),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Exam Hall Ticket Ready',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.primary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Generate and print the official admit card for ${widget.student.name}.',
                          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _printAdmitCard(schoolName),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Print', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          const Text(
            'EXAMINATION TIMETABLE',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.textSecondary, letterSpacing: 0.8),
          ),
          const SizedBox(height: 8),

          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _datesheet!.schedules.length,
            itemBuilder: (context, index) {
              final sched = _datesheet!.schedules[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  side: const BorderSide(color: AppTheme.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primaryLight.withValues(alpha: 0.1),
                    child: const Icon(Icons.quiz_outlined, color: AppTheme.primary, size: 20),
                  ),
                  title: Text(sched.subject, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text('Date: ${sched.dateStr}\nTime: ${sched.timeStr}', style: const TextStyle(fontSize: 12)),
                  isThreeLine: true,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

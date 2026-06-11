import 'dart:io';
import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/student_service.dart';
import '../../theme.dart';

class GovernmentReportScreen extends StatefulWidget {
  const GovernmentReportScreen({super.key});

  @override
  State<GovernmentReportScreen> createState() => _GovernmentReportScreenState();
}

class _GovernmentReportScreenState extends State<GovernmentReportScreen> {
  final _studentService = StudentService();
  bool _exporting = false;

  Future<void> _exportUdiseReport() async {
    setState(() => _exporting = true);
    try {
      // Fetch all students in the school
      final students = await _studentService.watchStudents().first;

      if (students.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No student records found to export.'),
              backgroundColor: AppTheme.warning,
            ),
          );
        }
        setState(() => _exporting = false);
        return;
      }

      // Build CSV Data structure
      final List<List<dynamic>> rows = [];
      // Header row according to UDISE+ standard student profile variables
      rows.add([
        'Admission Number',
        'Student Name',
        'Class',
        'Section',
        'Roll Number',
        'Gender',
        'Date of Birth',
        'Father Name',
        'Mother Name',
        'Emergency Contact',
        'Phone',
        'Address',
        'Blood Group',
        'Allergies',
        'Transport Mode',
        'Previous School',
        'Social Category',
      ]);

      // Populate student records
      for (final s in students) {
        // Date of birth parsing/formatting
        String dobStr = '';
        if (s.dateOfBirth != null) {
          final dt = s.dateOfBirth!.toDate();
          dobStr =
              '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
        } else if (s.guardianDetails?.dob.isNotEmpty == true) {
          dobStr = s.guardianDetails!.dob;
        }

        rows.add([
          s.admissionId.isNotEmpty ? s.admissionId : s.id,
          s.name,
          s.className,
          s.section,
          s.roll,
          s.gender ?? s.guardianDetails?.gender ?? 'N/A',
          dobStr.isNotEmpty ? dobStr : 'N/A',
          s.fatherName,
          s.motherName ?? 'N/A',
          s.emergencyContact ?? s.guardianDetails?.emergencyContactPhone ?? 'N/A',
          s.phone,
          s.address ?? s.guardianDetails?.address ?? 'N/A',
          s.bloodGroup ?? s.guardianDetails?.bloodGroup ?? 'N/A',
          s.allergies ?? s.guardianDetails?.allergies ?? 'N/A',
          s.transportMode ?? s.guardianDetails?.transportMode ?? 'N/A',
          s.previousSchool ?? s.guardianDetails?.previousSchool ?? 'N/A',
          'General', // Fallback social category variable
        ]);
      }

      // Convert to CSV string format
      final csvData = const ListToCsvConverter().convert(rows);

      // Save to temp directory and open share dialog
      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/UDISE_Government_Report.csv';
      final file = File(path);
      await file.writeAsString(csvData);

      if (mounted) {
        await Share.shareXFiles(
          [XFile(path)],
          text: 'UDISE+ Student Demographic Report CSV',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate government report: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Government Reports (UDISE+)'),
        backgroundColor: AppTheme.primaryDark,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
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
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor:
                              AppTheme.primaryLight.withValues(alpha: 0.2),
                          child: const Icon(
                            Icons.description,
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Text(
                          'UDISE+ Student Profile CSV',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'UDISE+ (Unified District Information System for Education) requires periodic submission of student profile lists.',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'This exporter extracts details for all active student enrollments, compiles them into the standard government-mandated demographic structure, and formats them into a CSV file.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    const Text(
                      'Included variables:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _buildVariableChip('Admission ID'),
                        _buildVariableChip('Name'),
                        _buildVariableChip('Class & Sec'),
                        _buildVariableChip('Roll No'),
                        _buildVariableChip('Gender'),
                        _buildVariableChip('Date of Birth'),
                        _buildVariableChip('Parents'),
                        _buildVariableChip('Address'),
                        _buildVariableChip('Blood Group'),
                        _buildVariableChip('Transport'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.file_download),
              onPressed: _exporting ? null : _exportUdiseReport,
              label: _exporting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Export UDISE+ CSV',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVariableChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.primaryLight.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: AppTheme.primaryLight.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          color: AppTheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

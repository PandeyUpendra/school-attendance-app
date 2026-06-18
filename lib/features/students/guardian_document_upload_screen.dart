import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/student.dart';
import '../../theme.dart';
import '../../services/auth_service.dart';
import '../../l10n/app_strings.dart';

class GuardianDocumentUploadScreen extends StatefulWidget {
  final Student student;
  const GuardianDocumentUploadScreen({super.key, required this.student});

  @override
  State<GuardianDocumentUploadScreen> createState() => _GuardianDocumentUploadScreenState();
}

class _GuardianDocumentUploadScreenState extends State<GuardianDocumentUploadScreen> {
  final List<String> _docTypes = ['Aadhaar Card', 'Birth Certificate', 'Address Proof'];
  Map<String, Map<String, dynamic>> _docsStatus = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDocumentsStatus();
  }

  Future<void> _loadDocumentsStatus() async {
    final schoolId = AuthService.currentSchoolId;
    final db = FirebaseFirestore.instance;
    final docRef = db
        .collection('schools')
        .doc(schoolId)
        .collection('students')
        .doc(widget.student.id)
        .collection('documents');

    try {
      final snap = await docRef.get();
      final statusMap = <String, Map<String, dynamic>>{};
      for (final doc in snap.docs) {
        statusMap[doc.id] = doc.data();
      }
      setState(() {
        _docsStatus = statusMap;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _pickAndUploadDocument(String docType) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      setState(() => _loading = true);

      final schoolId = AuthService.currentSchoolId;
      final db = FirebaseFirestore.instance;
      
      // Simulate file upload metadata storage
      await db
          .collection('schools')
          .doc(schoolId)
          .collection('students')
          .doc(widget.student.id)
          .collection('documents')
          .doc(docType)
          .set({
            'fileName': file.name,
            'fileSize': file.size,
            'status': 'pending', // pending | approved | rejected
            'uploadedAt': FieldValue.serverTimestamp(),
            'uploadedBy': AuthService().currentFirebaseUser?.email ?? 'guardian',
          });

      await _loadDocumentsStatus();
      if (mounted) {
        final translatedDocType = context.tr(docType.toLowerCase().replaceAll(' ', '_'));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('uploadSuccessPendingReview').replaceAll('{docType}', translatedDocType)), backgroundColor: AppTheme.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('uploadFailed').replaceAll('{error}', e.toString())), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'approved':
        return AppTheme.success;
      case 'rejected':
        return AppTheme.danger;
      case 'pending':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(context.tr('uploadVerificationFiles')),
        backgroundColor: AppTheme.primaryDark,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _docTypes.length,
              itemBuilder: (ctx, i) {
                final docType = _docTypes[i];
                final statusData = _docsStatus[docType];
                final status = statusData?['status'] as String? ?? 'not_uploaded';
                final fileName = statusData?['fileName'] as String? ?? '';

                String statusLabel(String st) {
                  switch (st) {
                    case 'not_uploaded':
                      return context.tr('statusNotUploaded');
                    case 'pending':
                      return context.tr('statusPending');
                    case 'approved':
                      return context.tr('statusApproved');
                    case 'rejected':
                      return context.tr('statusRejected');
                    default:
                      return st.toUpperCase().replaceAll('_', ' ');
                  }
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              context.tr(docType.toLowerCase().replaceAll(' ', '_')),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: _getStatusColor(status).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: _getStatusColor(status).withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                statusLabel(status),
                                style: TextStyle(color: _getStatusColor(status), fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            )
                          ],
                        ),
                        if (fileName.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(context.tr('fileLabel').replaceAll('{fileName}', fileName), style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                        ],
                        const SizedBox(height: 16),
                        if (status == 'not_uploaded' || status == 'rejected')
                          SizedBox(
                            width: double.infinity,
                            height: 40,
                            child: ElevatedButton.icon(
                              onPressed: () => _pickAndUploadDocument(docType),
                              icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              label: Text(context.tr('selectAndUploadFile'), style: const TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          )
                        else
                          Text(
                            context.tr('verificationFilesLocked'),
                            style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

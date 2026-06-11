import 'package:cloud_firestore/cloud_firestore.dart';

class StudyMaterial {
  final String id;
  final String title;
  final String description;
  final String className;
  final String subject;
  final String fileUrl; // Firebase Storage download url or path
  final String fileName;
  final String uploadedBy;
  final DateTime? uploadedAt;

  StudyMaterial({
    required this.id,
    required this.title,
    required this.description,
    required this.className,
    required this.subject,
    required this.fileUrl,
    required this.fileName,
    required this.uploadedBy,
    this.uploadedAt,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'className': className,
        'subject': subject,
        'fileUrl': fileUrl,
        'fileName': fileName,
        'uploadedBy': uploadedBy,
        'uploadedAt': uploadedAt != null ? Timestamp.fromDate(uploadedAt!) : FieldValue.serverTimestamp(),
      };

  factory StudyMaterial.fromDoc(String id, Map<String, dynamic> data) {
    final ts = data['uploadedAt'];
    return StudyMaterial(
      id: id,
      title: (data['title'] as String?) ?? '',
      description: (data['description'] as String?) ?? '',
      className: (data['className'] as String?) ?? '',
      subject: (data['subject'] as String?) ?? '',
      fileUrl: (data['fileUrl'] as String?) ?? '',
      fileName: (data['fileName'] as String?) ?? '',
      uploadedBy: (data['uploadedBy'] as String?) ?? '',
      uploadedAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

class Lead {
  final String id;
  final String studentName;
  final String className;
  final String parentName;
  final String parentPhone;
  final String parentEmail;
  final String stage; // 'Inquiry' | 'Visit' | 'Docs Pending' | 'Approved' | 'Admitted'
  final String note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String schoolId;

  const Lead({
    required this.id,
    required this.studentName,
    required this.className,
    required this.parentName,
    required this.parentPhone,
    required this.parentEmail,
    required this.stage,
    this.note = '',
    required this.createdAt,
    required this.updatedAt,
    required this.schoolId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'studentName': studentName,
        'className': className,
        'parentName': parentName,
        'parentPhone': parentPhone,
        'parentEmail': parentEmail,
        'stage': stage,
        'note': note,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
        'schoolId': schoolId,
      };

  factory Lead.fromJson(Map<String, dynamic> json) => Lead(
        id: json['id']?.toString() ?? '',
        studentName: json['studentName']?.toString() ?? '',
        className: json['className']?.toString() ?? '',
        parentName: json['parentName']?.toString() ?? '',
        parentPhone: json['parentPhone']?.toString() ?? '',
        parentEmail: json['parentEmail']?.toString() ?? '',
        stage: json['stage']?.toString() ?? 'Inquiry',
        note: json['note']?.toString() ?? '',
        createdAt: (json['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        updatedAt: (json['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        schoolId: json['schoolId']?.toString() ?? '',
      );

  Lead copyWith({
    String? id,
    String? studentName,
    String? className,
    String? parentName,
    String? parentPhone,
    String? parentEmail,
    String? stage,
    String? note,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? schoolId,
  }) =>
      Lead(
        id: id ?? this.id,
        studentName: studentName ?? this.studentName,
        className: className ?? this.className,
        parentName: parentName ?? this.parentName,
        parentPhone: parentPhone ?? this.parentPhone,
        parentEmail: parentEmail ?? this.parentEmail,
        stage: stage ?? this.stage,
        note: note ?? this.note,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        schoolId: schoolId ?? this.schoolId,
      );
}

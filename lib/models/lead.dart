import 'package:cloud_firestore/cloud_firestore.dart';

class FollowUp {
  final String note;
  final DateTime date;
  final String byEmail;
  final String byName;
  final String byRole;

  const FollowUp({
    required this.note,
    required this.date,
    required this.byEmail,
    required this.byName,
    required this.byRole,
  });

  Map<String, dynamic> toJson() => {
        'note': note,
        'date': Timestamp.fromDate(date),
        'byEmail': byEmail,
        'byName': byName,
        'byRole': byRole,
      };

  factory FollowUp.fromJson(Map<String, dynamic> json) => FollowUp(
        note: json['note']?.toString() ?? '',
        date: (json['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
        byEmail: json['byEmail']?.toString() ?? '',
        byName: json['byName']?.toString() ?? '',
        byRole: json['byRole']?.toString() ?? '',
      );
}

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
  final String createdByEmail;
  final String createdByName;
  final String createdByRole;
  final List<FollowUp> followUps;
  final DateTime? nextFollowUpDate;

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
    this.createdByEmail = '',
    this.createdByName = '',
    this.createdByRole = '',
    this.followUps = const [],
    this.nextFollowUpDate,
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
        'createdByEmail': createdByEmail,
        'createdByName': createdByName,
        'createdByRole': createdByRole,
        'followUps': followUps.map((f) => f.toJson()).toList(),
        'nextFollowUpDate': nextFollowUpDate != null ? Timestamp.fromDate(nextFollowUpDate!) : null,
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
        createdByEmail: json['createdByEmail']?.toString() ?? '',
        createdByName: json['createdByName']?.toString() ?? '',
        createdByRole: json['createdByRole']?.toString() ?? '',
        followUps: (json['followUps'] as List?)
                ?.map((item) => FollowUp.fromJson(Map<String, dynamic>.from(item)))
                .toList() ??
            const [],
        nextFollowUpDate: (json['nextFollowUpDate'] as Timestamp?)?.toDate(),
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
    String? createdByEmail,
    String? createdByName,
    String? createdByRole,
    List<FollowUp>? followUps,
    DateTime? nextFollowUpDate,
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
        createdByEmail: createdByEmail ?? this.createdByEmail,
        createdByName: createdByName ?? this.createdByName,
        createdByRole: createdByRole ?? this.createdByRole,
        followUps: followUps ?? this.followUps,
        nextFollowUpDate: nextFollowUpDate ?? this.nextFollowUpDate,
      );
}

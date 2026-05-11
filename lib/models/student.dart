import 'guardian_student_details.dart';

class Student {
  final String id; // Unique Student ID (e.g. Admission Number or UUID)
  final int roll;
  final String name;
  final String className;
  final String section;
  final String fatherName;
  final String? motherName;
  final String phone;
  final String? parentPhone;
  final String? photoPath;
  final String? photoUrl;
  final String feeStatus; // 'Paid' | 'Pending' | 'Partial'
  /// ID of the class teacher who owns this student record.
  /// Null on legacy records created before this field was introduced.
  final String? teacherId;
  final GuardianStudentDetails? guardianDetails;

  const Student({
    required this.id,
    required this.roll,
    required this.name,
    this.className = '',
    this.section = '',
    this.fatherName = '',
    this.motherName,
    this.phone = '',
    this.parentPhone,
    this.photoPath,
    this.photoUrl,
    this.feeStatus = 'Pending',
    this.teacherId,
    this.guardianDetails,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'roll': roll,
        'name': name,
        'className': className,
        'section': section,
        'fatherName': fatherName,
        'motherName': motherName,
        'phone': phone,
        'parentPhone': parentPhone,
        'photoPath': photoPath,
        'photoUrl': photoUrl,
        'feeStatus': feeStatus,
        if (teacherId != null) 'teacherId': teacherId,
        if (guardianDetails != null) 'guardianDetails': guardianDetails!.toJson(),
      };

  factory Student.fromJson(Map<String, dynamic> json) => Student(
        id: json['id'] as String? ?? (json['roll'] != null ? '${json['className']}_${json['section']}_${json['roll']}'.replaceAll(' ', '_') : ''),
        roll: json['roll'] as int,
        name: json['name'] as String,
        className: json['className'] as String? ?? '',
        section: json['section'] as String? ?? '',
        fatherName: json['fatherName'] as String? ?? '',
        motherName: json['motherName'] as String?,
        phone: json['phone'] as String? ?? '',
        parentPhone: json['parentPhone'] as String?,
        photoPath: json['photoPath'] as String?,
        photoUrl: json['photoUrl'] as String?,
        feeStatus: json['feeStatus'] as String? ?? 'Pending',
        teacherId: json['teacherId'] as String?,
        guardianDetails: json['guardianDetails'] != null
            ? GuardianStudentDetails.fromJson(
                Map<String, dynamic>.from(json['guardianDetails']))
            : null,
      );

  Student copyWith({
    String? id,
    String? name,
    String? className,
    String? section,
    String? fatherName,
    String? motherName,
    String? phone,
    String? parentPhone,
    String? photoPath,
    String? photoUrl,
    String? feeStatus,
    String? teacherId,
    GuardianStudentDetails? guardianDetails,
  }) =>
      Student(
        id: id ?? this.id,
        roll: roll,
        name: name ?? this.name,
        className: className ?? this.className,
        section: section ?? this.section,
        fatherName: fatherName ?? this.fatherName,
        motherName: motherName ?? this.motherName,
        phone: phone ?? this.phone,
        parentPhone: parentPhone ?? this.parentPhone,
        photoPath: photoPath ?? this.photoPath,
        photoUrl: photoUrl ?? this.photoUrl,
        feeStatus: feeStatus ?? this.feeStatus,
        teacherId: teacherId ?? this.teacherId,
        guardianDetails: guardianDetails ?? this.guardianDetails,
      );
}

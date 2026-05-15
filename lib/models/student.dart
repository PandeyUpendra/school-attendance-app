import 'guardian_student_details.dart';

class Student {
  final String id; // Unique Student ID (e.g. Admission Number or UUID); may be empty for new records
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
  /// ISO date string "YYYY-MM-DD" for the fee due date.
  final String? feeDueDate;
  /// Fee amount in rupees.
  final double? feeAmount;
  /// ID of the class teacher who owns this student record.
  /// Null on legacy records created before this field was introduced.
  final String? teacherId;
  final GuardianStudentDetails? guardianDetails;
  /// Guardian's Gmail address used for Google Sign-In on the Guardian Portal.
  final String? guardianEmail;

  const Student({
    this.id = '',
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
    this.feeDueDate,
    this.feeAmount,
    this.teacherId,
    this.guardianDetails,
    this.guardianEmail,
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
        if (feeDueDate != null) 'feeDueDate': feeDueDate,
        if (feeAmount != null) 'feeAmount': feeAmount,
        if (teacherId != null) 'teacherId': teacherId,
        if (guardianDetails != null) 'guardianDetails': guardianDetails!.toJson(),
        if (guardianEmail != null) 'guardianEmail': guardianEmail,
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
        feeDueDate: json['feeDueDate'] as String?,
        feeAmount: (json['feeAmount'] as num?)?.toDouble(),
        teacherId: json['teacherId'] as String?,
        guardianDetails: json['guardianDetails'] != null
            ? GuardianStudentDetails.fromJson(
                Map<String, dynamic>.from(json['guardianDetails']))
            : null,
        guardianEmail: json['guardianEmail'] as String?,
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
    String? feeDueDate,
    double? feeAmount,
    String? teacherId,
    GuardianStudentDetails? guardianDetails,
    String? guardianEmail,
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
        feeDueDate: feeDueDate ?? this.feeDueDate,
        feeAmount: feeAmount ?? this.feeAmount,
        teacherId: teacherId ?? this.teacherId,
        guardianDetails: guardianDetails ?? this.guardianDetails,
        guardianEmail: guardianEmail ?? this.guardianEmail,
      );
}

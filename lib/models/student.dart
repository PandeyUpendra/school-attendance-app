class Student {
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

  const Student({
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
  });

  Map<String, dynamic> toJson() => {
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
      };

  factory Student.fromJson(Map<String, dynamic> json) => Student(
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
      );

  Student copyWith({
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
  }) =>
      Student(
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
      );
}

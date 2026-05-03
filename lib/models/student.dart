class Student {
  final int roll;
  final String name;
  final String className;
  final String section;
  final String fatherName;
  final String? motherName;
  final String phone;
  final String? photoPath;
  final String feeStatus; // 'Paid' | 'Pending' | 'Partial'
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
    this.photoPath,
    this.feeStatus = 'Pending',
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
        'photoPath': photoPath,
        'feeStatus': feeStatus,
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
        photoPath: json['photoPath'] as String?,
        feeStatus: json['feeStatus'] as String? ?? 'Pending',
        teacherId: json['teacherId'] as String?,
      );

  Student copyWith({
    String? name,
    String? className,
    String? section,
    String? fatherName,
    String? motherName,
    String? phone,
    String? photoPath,
    String? feeStatus,
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
        photoPath: photoPath ?? this.photoPath,
        feeStatus: feeStatus ?? this.feeStatus,
        teacherId: teacherId ?? this.teacherId,
      );
}

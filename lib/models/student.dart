class Student {
  final int roll;
  final String name;
  final String className;
  final String fatherName;
  final String? motherName;
  final String phone;
  final String? photoPath;
  final String feeStatus; // 'Paid' | 'Pending' | 'Partial'

  const Student({
    required this.roll,
    required this.name,
    this.className = '',
    this.fatherName = '',
    this.motherName,
    this.phone = '',
    this.photoPath,
    this.feeStatus = 'Pending',
  });

  Map<String, dynamic> toJson() => {
        'roll': roll,
        'name': name,
        'className': className,
        'fatherName': fatherName,
        'motherName': motherName,
        'phone': phone,
        'photoPath': photoPath,
        'feeStatus': feeStatus,
      };

  factory Student.fromJson(Map<String, dynamic> json) => Student(
        roll: json['roll'] as int,
        name: json['name'] as String,
        className: json['className'] as String? ?? '',
        fatherName: json['fatherName'] as String? ?? '',
        motherName: json['motherName'] as String?,
        phone: json['phone'] as String? ?? '',
        photoPath: json['photoPath'] as String?,
        feeStatus: json['feeStatus'] as String? ?? 'Pending',
      );

  Student copyWith({
    String? name,
    String? className,
    String? fatherName,
    String? motherName,
    String? phone,
    String? photoPath,
    String? feeStatus,
  }) =>
      Student(
        roll: roll,
        name: name ?? this.name,
        className: className ?? this.className,
        fatherName: fatherName ?? this.fatherName,
        motherName: motherName ?? this.motherName,
        phone: phone ?? this.phone,
        photoPath: photoPath ?? this.photoPath,
        feeStatus: feeStatus ?? this.feeStatus,
      );
}

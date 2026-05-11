class GuardianStudentDetails {
  final String dob;
  final String gender;
  final String address;
  final String bloodGroup;
  final String emergencyContactName;
  final String emergencyContactPhone;
  final String allergies;
  final String transportMode;
  final String previousSchool;
  final String? lastUpdated;

  const GuardianStudentDetails({
    this.dob = '',
    this.gender = '',
    this.address = '',
    this.bloodGroup = '',
    this.emergencyContactName = '',
    this.emergencyContactPhone = '',
    this.allergies = '',
    this.transportMode = '',
    this.previousSchool = '',
    this.lastUpdated,
  });

  Map<String, dynamic> toJson() => {
    'dob': dob,
    'gender': gender,
    'address': address,
    'bloodGroup': bloodGroup,
    'emergencyContactName': emergencyContactName,
    'emergencyContactPhone': emergencyContactPhone,
    'allergies': allergies,
    'transportMode': transportMode,
    'previousSchool': previousSchool,
    'lastUpdated': lastUpdated,
  };

  factory GuardianStudentDetails.fromJson(Map<String, dynamic> json) => GuardianStudentDetails(
    dob: json['dob'] as String? ?? '',
    gender: json['gender'] as String? ?? '',
    address: json['address'] as String? ?? '',
    bloodGroup: json['bloodGroup'] as String? ?? '',
    emergencyContactName: json['emergencyContactName'] as String? ?? '',
    emergencyContactPhone: json['emergencyContactPhone'] as String? ?? '',
    allergies: json['allergies'] as String? ?? '',
    transportMode: json['transportMode'] as String? ?? '',
    previousSchool: json['previousSchool'] as String? ?? '',
    lastUpdated: json['lastUpdated'] as String?,
  );
}

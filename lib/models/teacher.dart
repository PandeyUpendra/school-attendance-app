import 'package:cloud_firestore/cloud_firestore.dart';

class Teacher {
  final String id;
  final String name;
  final String subject;
  final String email;
  final String section;
  final bool isClassTeacher;
  final String? classTeacherOf; // the class this teacher is class teacher of
  final String schoolId;
  final List<String> assignedClasses; // classes a subject teacher is allowed to access
  final String? phone;
  final Timestamp? dateOfBirth;
  final String? photoUrl;          // profile photo (Firebase Storage download URL)
  final String? designation;       // e.g. Senior Teacher, HOD
  final Timestamp? joiningDate;    // date the teacher joined the school
  final String? qualification;     // e.g. M.Sc, B.Ed
  final String? address;
  final String? emergencyContact;  // emergency phone number

  const Teacher({
    required this.id,
    required this.name,
    required this.subject,
    required this.email,
    this.section = '',
    this.isClassTeacher = false,
    this.classTeacherOf,
    this.schoolId = 'default_school',
    this.assignedClasses = const [],
    this.phone,
    this.dateOfBirth,
    this.photoUrl,
    this.designation,
    this.joiningDate,
    this.qualification,
    this.address,
    this.emergencyContact,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'subject': subject,
        'email': email,
        'section': section,
        'isClassTeacher': isClassTeacher,
        'classTeacherOf': classTeacherOf,
        'schoolId': schoolId,
        'assignedClasses': assignedClasses,
        if (phone != null) 'phone': phone,
        if (dateOfBirth != null) 'dateOfBirth': dateOfBirth,
        if (photoUrl != null) 'photoUrl': photoUrl,
        if (designation != null) 'designation': designation,
        if (joiningDate != null) 'joiningDate': joiningDate,
        if (qualification != null) 'qualification': qualification,
        if (address != null) 'address': address,
        if (emergencyContact != null) 'emergencyContact': emergencyContact,
      };

  factory Teacher.fromJson(Map<String, dynamic> json) => Teacher(
        id: json['id'] as String,
        name: json['name'] as String,
        subject: json['subject'] as String,
        email: json['email'] as String? ?? '',
        section: json['section'] as String? ?? '',
        isClassTeacher: json['isClassTeacher'] as bool? ?? false,
        classTeacherOf: json['classTeacherOf'] as String?,
        schoolId: json['schoolId'] as String? ?? 'default_school',
        assignedClasses: (json['assignedClasses'] as List?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        phone: json['phone'] as String?,
        dateOfBirth: json['dateOfBirth'] as Timestamp?,
        photoUrl: json['photoUrl'] as String?,
        designation: json['designation'] as String?,
        joiningDate: json['joiningDate'] as Timestamp?,
        qualification: json['qualification'] as String?,
        address: json['address'] as String?,
        emergencyContact: json['emergencyContact'] as String?,
      );

  Teacher copyWith({
    String? name,
    String? subject,
    String? email,
    String? section,
    bool? isClassTeacher,
    String? classTeacherOf,
    String? schoolId,
    List<String>? assignedClasses,
    String? phone,
    Timestamp? dateOfBirth,
    String? photoUrl,
    String? designation,
    Timestamp? joiningDate,
    String? qualification,
    String? address,
    String? emergencyContact,
  }) =>
      Teacher(
        id: id,
        name: name ?? this.name,
        subject: subject ?? this.subject,
        email: email ?? this.email,
        section: section ?? this.section,
        isClassTeacher: isClassTeacher ?? this.isClassTeacher,
        classTeacherOf: classTeacherOf ?? this.classTeacherOf,
        schoolId: schoolId ?? this.schoolId,
        assignedClasses: assignedClasses ?? this.assignedClasses,
        phone: phone ?? this.phone,
        dateOfBirth: dateOfBirth ?? this.dateOfBirth,
        photoUrl: photoUrl ?? this.photoUrl,
        designation: designation ?? this.designation,
        joiningDate: joiningDate ?? this.joiningDate,
        qualification: qualification ?? this.qualification,
        address: address ?? this.address,
        emergencyContact: emergencyContact ?? this.emergencyContact,
      );
}

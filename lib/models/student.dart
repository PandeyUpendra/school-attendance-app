import 'package:cloud_firestore/cloud_firestore.dart';
import 'guardian_student_details.dart';

class Student {
  final String id; // Unique Student ID (e.g. Admission Number or UUID); may be empty for new records
  /// Stable cross-year identity that survives class promotion (#70). Unlike the
  /// Firestore doc id (class_section_roll, which changes when a student moves up
  /// a class), this never changes once assigned, so a student's history can be
  /// linked across academic years. Defaults to the current doc id for legacy
  /// records that predate the field.
  final String admissionId;
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
  /// Guardian's Gmail address used for Guardian Portal login.
  final String? guardianEmail;
  final Timestamp? dateOfBirth;
  final int? birthMonth;
  final int? birthDay;
  final String? gender;
  final String? address;
  final String? previousSchool;
  final String? emergencyContact;
  final String? bloodGroup;
  final String? allergies;
  final String? transportMode;
  /// True while a teacher-filed deletion request for this student is awaiting
  /// principal approval. The student is shown as deactivated (greyed out) and
  /// cannot be re-selected for deletion until the request is approved (record
  /// removed) or rejected (flag cleared).
  final bool deletionPending;

  /// True once the student has been promoted out of this class into the next
  /// academic year (#70). The old-class record is kept (so its attendance/fee
  /// history stays intact) but hidden from active rosters.
  final bool promoted;

  const Student({
    this.id = '',
    this.admissionId = '',
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
    this.dateOfBirth,
    this.birthMonth,
    this.birthDay,
    this.gender,
    this.address,
    this.previousSchool,
    this.emergencyContact,
    this.bloodGroup,
    this.allergies,
    this.transportMode,
    this.deletionPending = false,
    this.promoted = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'admissionId': admissionId,
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
        if (dateOfBirth != null) 'dateOfBirth': dateOfBirth,
        if (birthMonth != null) 'birthMonth': birthMonth,
        if (birthDay != null) 'birthDay': birthDay,
        if (gender != null) 'gender': gender,
        if (address != null) 'address': address,
        if (previousSchool != null) 'previousSchool': previousSchool,
        if (emergencyContact != null) 'emergencyContact': emergencyContact,
        if (bloodGroup != null) 'bloodGroup': bloodGroup,
        if (allergies != null) 'allergies': allergies,
        if (transportMode != null) 'transportMode': transportMode,
        if (deletionPending) 'deletionPending': true,
        if (promoted) 'promoted': true,
      };

  static String buildDocId(int roll, String className, String section) {
    final base = className.replaceAll(' ', '_');
    final sec = section.trim().replaceAll(' ', '_');
    return sec.isEmpty ? '${base}_$roll' : '${base}_${sec}_$roll';
  }

  factory Student.fromJson(Map<String, dynamic> json) => Student(
        id: json['id'] as String? ??
            (json['roll'] != null
                ? buildDocId(
                    json['roll'] as int,
                    json['className'] as String? ?? '',
                    json['section'] as String? ?? '')
                : ''),
        admissionId: (json['admissionId'] as String?)?.trim().isNotEmpty == true
            ? json['admissionId'] as String
            : (json['roll'] != null
                ? buildDocId(
                    json['roll'] as int,
                    json['className'] as String? ?? '',
                    json['section'] as String? ?? '')
                : ''),
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
        dateOfBirth: json['dateOfBirth'] as Timestamp?,
        birthMonth: json['birthMonth'] as int? ??
            (json['dateOfBirth'] as Timestamp?)?.toDate().month,
        birthDay: json['birthDay'] as int? ??
            (json['dateOfBirth'] as Timestamp?)?.toDate().day,
        gender: json['gender'] as String?,
        address: json['address'] as String?,
        previousSchool: json['previousSchool'] as String?,
        emergencyContact: json['emergencyContact'] as String?,
        bloodGroup: json['bloodGroup'] as String?,
        allergies: json['allergies'] as String?,
        transportMode: json['transportMode'] as String?,
        deletionPending: json['deletionPending'] as bool? ?? false,
        promoted: json['promoted'] as bool? ?? false,
      );

  Student copyWith({
    String? id,
    String? admissionId,
    int? roll,
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
    Timestamp? dateOfBirth,
    int? birthMonth,
    int? birthDay,
    String? gender,
    String? address,
    String? previousSchool,
    String? emergencyContact,
    String? bloodGroup,
    String? allergies,
    String? transportMode,
    bool? deletionPending,
    bool? promoted,
  }) =>
      Student(
        id: id ?? this.id,
        admissionId: admissionId ?? this.admissionId,
        roll: roll ?? this.roll,
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
        dateOfBirth: dateOfBirth ?? this.dateOfBirth,
        birthMonth: birthMonth ?? this.birthMonth,
        birthDay: birthDay ?? this.birthDay,
        gender: gender ?? this.gender,
        address: address ?? this.address,
        previousSchool: previousSchool ?? this.previousSchool,
        emergencyContact: emergencyContact ?? this.emergencyContact,
        bloodGroup: bloodGroup ?? this.bloodGroup,
        allergies: allergies ?? this.allergies,
        transportMode: transportMode ?? this.transportMode,
        deletionPending: deletionPending ?? this.deletionPending,
        promoted: promoted ?? this.promoted,
      );
}

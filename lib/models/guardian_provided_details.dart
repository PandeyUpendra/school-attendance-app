import 'package:cloud_firestore/cloud_firestore.dart';

class GuardianProvidedDetails {
  final String id;
  final String name;
  final String dob;
  final String gender;
  final String fatherName;
  final String motherName;
  final String phone;
  final String parentPhone;
  final String address;
  final String previousSchool;
  final String bloodGroup;
  final String emergencyContactName;
  final String emergencyContactPhone;
  final String allergies;
  final String transportMode;
  final Timestamp? timestamp;
  final String guardianUid;
  final String status; // 'pending' | 'accepted' | 'rejected' | 'clarification_requested'
  final String remarks;
  final String? photoBase64;

  const GuardianProvidedDetails({
    this.id = '',
    this.name = '',
    this.dob = '',
    this.gender = '',
    this.fatherName = '',
    this.motherName = '',
    this.phone = '',
    this.parentPhone = '',
    this.address = '',
    this.previousSchool = '',
    this.bloodGroup = '',
    this.emergencyContactName = '',
    this.emergencyContactPhone = '',
    this.allergies = '',
    this.transportMode = '',
    this.timestamp,
    this.guardianUid = '',
    this.status = 'pending',
    this.remarks = '',
    this.photoBase64,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'dob': dob,
        'gender': gender,
        'fatherName': fatherName,
        'motherName': motherName,
        'phone': phone,
        'parentPhone': parentPhone,
        'address': address,
        'previousSchool': previousSchool,
        'bloodGroup': bloodGroup,
        'emergencyContactName': emergencyContactName,
        'emergencyContactPhone': emergencyContactPhone,
        'allergies': allergies,
        'transportMode': transportMode,
        'timestamp': timestamp ?? FieldValue.serverTimestamp(),
        'guardianUid': guardianUid,
        'status': status,
        'remarks': remarks,
        'photoBase64': photoBase64,
      };

  factory GuardianProvidedDetails.fromJson(String docId, Map<String, dynamic> json) =>
      GuardianProvidedDetails(
        id: docId,
        name: json['name'] as String? ?? '',
        dob: json['dob'] as String? ?? '',
        gender: json['gender'] as String? ?? '',
        fatherName: json['fatherName'] as String? ?? '',
        motherName: json['motherName'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        parentPhone: json['parentPhone'] as String? ?? '',
        address: json['address'] as String? ?? '',
        previousSchool: json['previousSchool'] as String? ?? '',
        bloodGroup: json['bloodGroup'] as String? ?? '',
        emergencyContactName: json['emergencyContactName'] as String? ?? '',
        emergencyContactPhone: json['emergencyContactPhone'] as String? ?? '',
        allergies: json['allergies'] as String? ?? '',
        transportMode: json['transportMode'] as String? ?? '',
        timestamp: json['timestamp'] as Timestamp?,
        guardianUid: json['guardianUid'] as String? ?? '',
        status: json['status'] as String? ?? 'pending',
        remarks: json['remarks'] as String? ?? '',
        photoBase64: json['photoBase64'] as String?,
      );
}

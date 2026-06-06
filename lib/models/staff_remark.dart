import 'package:cloud_firestore/cloud_firestore.dart';

/// A remark / feedback note given by a member of management to a staff member.
///
/// Direction rules (enforced in the UI and Firestore rules):
///   • coordinator → teacher
///   • principal   → teacher | coordinator
///
/// Recipients are addressed by [toEmail] (always) and, for teachers, also by
/// [toTeacherId] so the teacher's session — which is keyed by teacherId — can
/// query the remarks given to them.
class StaffRemark {
  final String  id;
  final String  schoolId;
  final String  fromEmail;   // giver's email
  final String  fromName;
  final String  fromRole;    // 'coordinator' | 'principal' | 'owner' | 'ownerPrincipal'
  final String  toEmail;     // recipient's email
  final String  toName;
  final String  toRole;      // 'teacher' | 'coordinator'
  final String? toTeacherId; // teacherId when the recipient is a teacher
  final String  remark;
  final DateTime timestamp;

  const StaffRemark({
    required this.id,
    required this.schoolId,
    required this.fromEmail,
    required this.fromName,
    required this.fromRole,
    required this.toEmail,
    required this.toName,
    required this.toRole,
    this.toTeacherId,
    required this.remark,
    required this.timestamp,
  });

  factory StaffRemark.fromJson(String id, Map<String, dynamic> json) {
    final ts = json['timestamp'];
    final dt = ts is Timestamp ? ts.toDate() : DateTime.now();
    return StaffRemark(
      id:          id,
      schoolId:    json['schoolId']    as String? ?? '',
      fromEmail:   json['fromEmail']   as String? ?? '',
      fromName:    json['fromName']    as String? ?? '',
      fromRole:    json['fromRole']    as String? ?? '',
      toEmail:     json['toEmail']     as String? ?? '',
      toName:      json['toName']      as String? ?? '',
      toRole:      json['toRole']      as String? ?? 'teacher',
      toTeacherId: json['toTeacherId'] as String?,
      remark:      json['remark']      as String? ?? '',
      timestamp:   dt,
    );
  }

  Map<String, dynamic> toJson() => {
    'schoolId':  schoolId,
    'fromEmail': fromEmail,
    'fromName':  fromName,
    'fromRole':  fromRole,
    'toEmail':   toEmail,
    'toName':    toName,
    'toRole':    toRole,
    if (toTeacherId != null) 'toTeacherId': toTeacherId,
    'remark':    remark,
    'timestamp': Timestamp.fromDate(timestamp),
  };
}

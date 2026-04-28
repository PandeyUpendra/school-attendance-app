import 'package:cloud_firestore/cloud_firestore.dart';

/// A copy-checking session — one per teacher per class per date.
class CopyCheck {
  final String   id;
  final String   teacherId;
  final String   teacherName;
  final String   className;
  final String   subject;
  final DateTime checkDate;
  final DateTime createdAt;

  const CopyCheck({
    required this.id,
    required this.teacherId,
    required this.teacherName,
    required this.className,
    required this.subject,
    required this.checkDate,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'teacherId':   teacherId,
        'teacherName': teacherName,
        'className':   className,
        'subject':     subject,
        'checkDate':   Timestamp.fromDate(checkDate),
        'createdAt':   FieldValue.serverTimestamp(),
      };

  factory CopyCheck.fromDoc(String id, Map<String, dynamic> data) {
    final ts  = data['checkDate'];
    final cts = data['createdAt'];
    return CopyCheck(
      id:          id,
      teacherId:   (data['teacherId']   as String?) ?? '',
      teacherName: (data['teacherName'] as String?) ?? '',
      className:   (data['className']   as String?) ?? '',
      subject:     (data['subject']     as String?) ?? '',
      checkDate:   ts  is Timestamp ? ts.toDate()  : DateTime.now(),
      createdAt:   cts is Timestamp ? cts.toDate() : DateTime.now(),
    );
  }
}

/// Status of a single student's copy in one checking session.
class CopyStatus {
  final int     roll;
  final String  studentName;
  final String  guardianPhone;
  /// 'checked' | 'incomplete' | 'not_done'
  final String  status;
  final String? remarks;

  const CopyStatus({
    required this.roll,
    required this.studentName,
    required this.guardianPhone,
    required this.status,
    this.remarks,
  });

  Map<String, dynamic> toJson() => {
        'roll':          roll,
        'studentName':   studentName,
        'guardianPhone': guardianPhone,
        'status':        status,
        'remarks':       remarks,
      };

  factory CopyStatus.fromDoc(Map<String, dynamic> data) => CopyStatus(
        roll:          (data['roll']          as num?)?.toInt() ?? 0,
        studentName:   (data['studentName']   as String?) ?? '',
        guardianPhone: (data['guardianPhone'] as String?) ?? '',
        status:        (data['status']        as String?) ?? 'not_done',
        remarks:       data['remarks']        as String?,
      );

  CopyStatus copyWith({String? status, String? remarks}) => CopyStatus(
        roll:          roll,
        studentName:   studentName,
        guardianPhone: guardianPhone,
        status:        status ?? this.status,
        remarks:       remarks ?? this.remarks,
      );
}

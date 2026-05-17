import 'package:cloud_firestore/cloud_firestore.dart';

class StudentRemark {
  final String  id;
  final String  createdBy; // email
  final String  role;      // 'teacher' | 'coordinator' | 'principal' | 'guardian'
  final String  remark;
  final DateTime timestamp;
  final String? teacherId;
  /// 'positive' | 'negative' — null on legacy records (treated as 'negative')
  final String? type;
  final bool whatsappSent;

  const StudentRemark({
    required this.id,
    required this.createdBy,
    required this.role,
    required this.remark,
    required this.timestamp,
    this.teacherId,
    this.type,
    this.whatsappSent = false,
  });

  bool get isPositive => type == 'positive';

  factory StudentRemark.fromJson(String id, Map<String, dynamic> json) {
    final ts = json['timestamp'];
    final dt = ts is Timestamp ? ts.toDate() : DateTime.now();
    return StudentRemark(
      id:           id,
      createdBy:    json['createdBy']    as String? ?? '',
      role:         json['role']         as String? ?? 'teacher',
      remark:       json['remark']       as String? ?? '',
      timestamp:    dt,
      teacherId:    json['teacherId']    as String?,
      type:         json['type']         as String?,
      whatsappSent: json['whatsappSent'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'createdBy':    createdBy,
    'role':         role,
    'remark':       remark,
    'timestamp':    Timestamp.fromDate(timestamp),
    if (teacherId != null) 'teacherId': teacherId,
    if (type != null) 'type': type,
    'whatsappSent': whatsappSent,
  };
}

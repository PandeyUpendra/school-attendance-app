import 'package:cloud_firestore/cloud_firestore.dart';

/// One substitution event — logged every time a substitute is assigned.
class SubstitutionRecord {
  final String   id;
  final String   dateKey;              // 'YYYY-M-D' for querying
  final DateTime date;
  final String   className;
  final int      bell;
  final String   substituteTeacherId;
  final String   substituteTeacherName;
  final String   originalTeacherId;
  final String   originalTeacherName;
  final String   subject;
  final DateTime createdAt;

  const SubstitutionRecord({
    required this.id,
    required this.dateKey,
    required this.date,
    required this.className,
    required this.bell,
    required this.substituteTeacherId,
    required this.substituteTeacherName,
    required this.originalTeacherId,
    required this.originalTeacherName,
    required this.subject,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'dateKey':               dateKey,
        'date':                  Timestamp.fromDate(date),
        'className':             className,
        'bell':                  bell,
        'substituteTeacherId':   substituteTeacherId,
        'substituteTeacherName': substituteTeacherName,
        'originalTeacherId':     originalTeacherId,
        'originalTeacherName':   originalTeacherName,
        'subject':               subject,
        'createdAt':             FieldValue.serverTimestamp(),
      };

  factory SubstitutionRecord.fromDoc(
      String id, Map<String, dynamic> data) {
    final dateRaw    = data['date'];
    final createdRaw = data['createdAt'];
    return SubstitutionRecord(
      id:                    id,
      dateKey:               (data['dateKey']              as String?) ?? '',
      date:                  dateRaw is Timestamp ? dateRaw.toDate() : DateTime.now(),
      className:             (data['className']            as String?) ?? '',
      bell:                  (data['bell']                 as int?)    ?? 0,
      substituteTeacherId:   (data['substituteTeacherId']  as String?) ?? '',
      substituteTeacherName: (data['substituteTeacherName']as String?) ?? '',
      originalTeacherId:     (data['originalTeacherId']    as String?) ?? '',
      originalTeacherName:   (data['originalTeacherName']  as String?) ?? '',
      subject:               (data['subject']              as String?) ?? '',
      createdAt:             createdRaw is Timestamp
                                 ? createdRaw.toDate()
                                 : DateTime.now(),
    );
  }
}

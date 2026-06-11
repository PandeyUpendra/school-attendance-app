import 'package:cloud_firestore/cloud_firestore.dart';

class ClassDiaryEntry {
  final String id;
  final String className;
  final String dateKey; // YYYY-MM-DD
  final String subject;
  final String homeworkSummary;
  final String topicsTaught;
  final String recordedBy;
  final DateTime? timestamp;

  ClassDiaryEntry({
    required this.id,
    required this.className,
    required this.dateKey,
    required this.subject,
    required this.homeworkSummary,
    required this.topicsTaught,
    required this.recordedBy,
    this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'className': className,
        'dateKey': dateKey,
        'subject': subject,
        'homeworkSummary': homeworkSummary,
        'topicsTaught': topicsTaught,
        'recordedBy': recordedBy,
        'timestamp': timestamp != null ? Timestamp.fromDate(timestamp!) : FieldValue.serverTimestamp(),
      };

  factory ClassDiaryEntry.fromDoc(String id, Map<String, dynamic> data) {
    final ts = data['timestamp'];
    return ClassDiaryEntry(
      id: id,
      className: (data['className'] as String?) ?? '',
      dateKey: (data['dateKey'] as String?) ?? '',
      subject: (data['subject'] as String?) ?? '',
      homeworkSummary: (data['homeworkSummary'] as String?) ?? '',
      topicsTaught: (data['topicsTaught'] as String?) ?? '',
      recordedBy: (data['recordedBy'] as String?) ?? '',
      timestamp: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

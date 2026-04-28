import 'package:cloud_firestore/cloud_firestore.dart';

/// A homework assignment posted by a teacher.
class Homework {
  final String   id;
  final String   teacherId;
  final String   teacherName;
  final String   className;
  final String   subject;
  final String   title;
  final String   description;
  final DateTime dueDate;
  final DateTime postedAt;
  final bool     isReviewed; // teacher marks it reviewed after checking

  const Homework({
    required this.id,
    required this.teacherId,
    required this.teacherName,
    required this.className,
    required this.subject,
    required this.title,
    required this.description,
    required this.dueDate,
    required this.postedAt,
    this.isReviewed = false,
  });

  Map<String, dynamic> toJson() => {
        'teacherId':   teacherId,
        'teacherName': teacherName,
        'className':   className,
        'subject':     subject,
        'title':       title,
        'description': description,
        'dueDate':     Timestamp.fromDate(dueDate),
        'postedAt':    FieldValue.serverTimestamp(),
        'isReviewed':  isReviewed,
      };

  factory Homework.fromDoc(String id, Map<String, dynamic> data) {
    final due = data['dueDate'];
    final pos = data['postedAt'];
    return Homework(
      id:          id,
      teacherId:   (data['teacherId']   as String?) ?? '',
      teacherName: (data['teacherName'] as String?) ?? '',
      className:   (data['className']   as String?) ?? '',
      subject:     (data['subject']     as String?) ?? '',
      title:       (data['title']       as String?) ?? '',
      description: (data['description'] as String?) ?? '',
      dueDate:     due is Timestamp ? due.toDate() : DateTime.now(),
      postedAt:    pos is Timestamp ? pos.toDate() : DateTime.now(),
      isReviewed:  (data['isReviewed']  as bool?)  ?? false,
    );
  }

  bool get isOverdue =>
      !isReviewed && dueDate.isBefore(DateTime.now());

  int get daysUntilDue =>
      dueDate.difference(DateTime.now()).inDays;
}

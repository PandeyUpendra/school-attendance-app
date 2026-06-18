
class DatesheetSubjectSchedule {
  final String subject;
  final String dateStr; // YYYY-MM-DD
  final String timeStr; // e.g. "09:00 AM - 12:00 PM"

  DatesheetSubjectSchedule({
    required this.subject,
    required this.dateStr,
    required this.timeStr,
  });

  Map<String, dynamic> toJson() => {
        'subject': subject,
        'dateStr': dateStr,
        'timeStr': timeStr,
      };

  factory DatesheetSubjectSchedule.fromJson(Map<String, dynamic> json) {
    return DatesheetSubjectSchedule(
      subject: (json['subject'] as String?) ?? '',
      dateStr: (json['dateStr'] as String?) ?? '',
      timeStr: (json['timeStr'] as String?) ?? '',
    );
  }
}

class Datesheet {
  final String id;
  final String examId;
  final String className;
  final List<DatesheetSubjectSchedule> schedules;

  Datesheet({
    required this.id,
    required this.examId,
    required this.className,
    required this.schedules,
  });

  Map<String, dynamic> toJson() => {
        'examId': examId,
        'className': className,
        'schedules': schedules.map((s) => s.toJson()).toList(),
      };

  factory Datesheet.fromDoc(String id, Map<String, dynamic> data) {
    final list = data['schedules'] as List? ?? [];
    return Datesheet(
      id: id,
      examId: (data['examId'] as String?) ?? '',
      className: (data['className'] as String?) ?? '',
      schedules: list.map((s) => DatesheetSubjectSchedule.fromJson(Map<String, dynamic>.from(s as Map))).toList(),
    );
  }
}

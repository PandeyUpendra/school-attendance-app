/// One slot in the timetable: a teacher + an optional custom subject.
/// The custom subject overrides the teacher's default subject for that specific
/// class × day × bell combination.
class TimetableEntry {
  final String? teacherId;
  final String? subject; // null → use teacher's default subject

  const TimetableEntry({this.teacherId, this.subject});

  bool get isEmpty => teacherId == null;

  Map<String, dynamic> toJson() => {
        'teacherId': teacherId,
        'subject': subject,
      };

  factory TimetableEntry.fromJson(dynamic json) {
    if (json == null) return const TimetableEntry();
    // Backward compat: old format stored just a teacherId string
    if (json is String) {
      return TimetableEntry(teacherId: json.isEmpty ? null : json);
    }
    if (json is Map) {
      final m = Map<String, dynamic>.from(json);
      return TimetableEntry(
        teacherId: m['teacherId'] as String?,
        subject: m['subject'] as String?,
      );
    }
    return const TimetableEntry();
  }
}

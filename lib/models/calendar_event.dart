enum CalendarEventType { holiday, festival, vacation, exam, event }

class CalendarEvent {
  final String id;
  final String title;
  final DateTime date;
  final CalendarEventType type;
  final String? description;
  final bool isGlobal; // true if it's a national/state holiday by default
  final bool isObserved; // false if school remains open for classes
  final bool isModified; // true if a global holiday was edited

  CalendarEvent({
    required this.id,
    required this.title,
    required this.date,
    required this.type,
    this.description,
    this.isGlobal = false,
    this.isObserved = true,
    this.isModified = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'date': date.toIso8601String(),
      'type': type.name,
      'description': description,
      'isGlobal': isGlobal,
      'isObserved': isObserved,
      'isModified': isModified,
    };
  }

  factory CalendarEvent.fromMap(Map<String, dynamic> map, String id) {
    return CalendarEvent(
      id: id,
      title: map['title'] ?? '',
      date: DateTime.parse(map['date']),
      type: CalendarEventType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => CalendarEventType.event,
      ),
      description: map['description'],
      isGlobal: map['isGlobal'] ?? false,
      isObserved: map['isObserved'] ?? true,
      isModified: map['isModified'] ?? false,
    );
  }
}

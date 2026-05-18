import 'package:cloud_firestore/cloud_firestore.dart';

class TodoItem {
  final String id;
  final String userId;
  final String role;
  final String title;
  final bool isCustom;
  final DateTime? dueDate;
  final bool reminderEnabled;
  final bool isCompleted;
  final DateTime createdAt;

  const TodoItem({
    required this.id,
    required this.userId,
    required this.role,
    required this.title,
    required this.isCustom,
    this.dueDate,
    required this.reminderEnabled,
    required this.isCompleted,
    required this.createdAt,
  });

  TodoItem copyWith({
    String? id,
    String? userId,
    String? role,
    String? title,
    bool? isCustom,
    DateTime? dueDate,
    bool clearDueDate = false,
    bool? reminderEnabled,
    bool? isCompleted,
    DateTime? createdAt,
  }) {
    return TodoItem(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      role: role ?? this.role,
      title: title ?? this.title,
      isCustom: isCustom ?? this.isCustom,
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'role': role,
        'title': title,
        'isCustom': isCustom,
        'dueDate': dueDate != null ? Timestamp.fromDate(dueDate!) : null,
        'reminderEnabled': reminderEnabled,
        'isCompleted': isCompleted,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  static TodoItem fromJson(Map<String, dynamic> json, String id) {
    DateTime? dueDate;
    final rawDue = json['dueDate'];
    if (rawDue is Timestamp) dueDate = rawDue.toDate();

    return TodoItem(
      id: id,
      userId: json['userId'] as String? ?? '',
      role: json['role'] as String? ?? '',
      title: json['title'] as String? ?? '',
      isCustom: json['isCustom'] as bool? ?? false,
      dueDate: dueDate,
      reminderEnabled: json['reminderEnabled'] as bool? ?? false,
      isCompleted: json['isCompleted'] as bool? ?? false,
      createdAt: (json['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  bool get isDueToday {
    if (dueDate == null) return false;
    final now = DateTime.now();
    return dueDate!.year == now.year &&
        dueDate!.month == now.month &&
        dueDate!.day == now.day;
  }

  bool get isOverdue {
    if (dueDate == null || isCompleted) return false;
    final today = DateTime.now();
    final due = dueDate!;
    return DateTime(due.year, due.month, due.day)
        .isBefore(DateTime(today.year, today.month, today.day));
  }
}

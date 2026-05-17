import 'package:cloud_firestore/cloud_firestore.dart';

enum TaskStatus { pending, inProgress, completed }

enum TaskPriority { low, medium, high }

TaskStatus _parseStatus(String? s) {
  switch (s) {
    case 'inProgress': return TaskStatus.inProgress;
    case 'completed':  return TaskStatus.completed;
    case 'done':       return TaskStatus.completed; // legacy
    default:           return TaskStatus.pending;
  }
}

TaskPriority _parsePriority(String? s) {
  switch (s?.toLowerCase()) {
    case 'medium': return TaskPriority.medium;
    case 'high':   return TaskPriority.high;
    default:       return TaskPriority.low;
  }
}

extension TaskStatusLabel on TaskStatus {
  String get label {
    switch (this) {
      case TaskStatus.pending:    return 'Pending';
      case TaskStatus.inProgress: return 'In Progress';
      case TaskStatus.completed:  return 'Completed';
    }
  }
}

extension TaskPriorityLabel on TaskPriority {
  String get label {
    switch (this) {
      case TaskPriority.low:    return 'Low';
      case TaskPriority.medium: return 'Medium';
      case TaskPriority.high:   return 'High';
    }
  }
}

class StaffTask {
  final String       id;
  final String       title;
  final String       description;
  final String       assignedTo;       // teacher doc ID
  final String       assignedToName;   // denormalized teacher name
  final String       assignedBy;       // creator email/userId
  final String       assignedByRole;   // 'coordinator' | 'principal'
  final DateTime?    dueDate;
  final TaskStatus   status;
  final TaskPriority priority;
  final String       classId;          // optional class context
  final DateTime     createdAt;
  final bool         isGroupTask;
  final String       groupTaskId;

  const StaffTask({
    required this.id,
    required this.title,
    required this.description,
    required this.assignedTo,
    required this.assignedToName,
    required this.assignedBy,
    required this.assignedByRole,
    this.dueDate,
    required this.status,
    required this.priority,
    this.classId = '',
    required this.createdAt,
    this.isGroupTask = false,
    this.groupTaskId = '',
  });

  bool get isOverdue =>
      dueDate != null &&
      DateTime.now().isAfter(dueDate!) &&
      status != TaskStatus.completed;

  int get overdueDays =>
      isOverdue ? DateTime.now().difference(dueDate!).inDays : 0;

  factory StaffTask.fromJson(Map<String, dynamic> json, String docId) =>
      StaffTask(
        id:             docId,
        title:          json['title']          as String? ?? '',
        description:    json['description']    as String? ?? '',
        assignedTo:     json['assignedTo']     as String? ?? '',
        assignedToName: json['assignedToName'] as String? ?? '',
        // backward compat: old docs used 'createdBy'
        assignedBy:     (json['assignedBy']    as String?) ??
                        (json['createdBy']     as String?) ?? '',
        assignedByRole: json['assignedByRole'] as String? ?? 'principal',
        dueDate:        (json['dueDate'] as Timestamp?)?.toDate(),
        status:         _parseStatus(json['status'] as String?),
        priority:       _parsePriority(json['priority'] as String?),
        classId:        json['classId']        as String? ?? '',
        createdAt:      (json['createdAt'] as Timestamp?)?.toDate() ??
                        DateTime.now(),
        isGroupTask:    json['isGroupTask']    as bool?   ?? false,
        groupTaskId:    json['groupTaskId']    as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
    'title':          title,
    'description':    description,
    'assignedTo':     assignedTo,
    'assignedToName': assignedToName,
    'assignedBy':     assignedBy,
    'assignedByRole': assignedByRole,
    if (dueDate != null) 'dueDate': Timestamp.fromDate(dueDate!),
    'status':         status.name,
    'priority':       priority.name,
    'classId':        classId,
    'createdAt':      FieldValue.serverTimestamp(),
    'isGroupTask':    isGroupTask,
    if (groupTaskId.isNotEmpty) 'groupTaskId': groupTaskId,
  };

  StaffTask copyWith({TaskStatus? status}) => StaffTask(
    id:             id,
    title:          title,
    description:    description,
    assignedTo:     assignedTo,
    assignedToName: assignedToName,
    assignedBy:     assignedBy,
    assignedByRole: assignedByRole,
    dueDate:        dueDate,
    status:         status ?? this.status,
    priority:       priority,
    classId:        classId,
    createdAt:      createdAt,
    isGroupTask:    isGroupTask,
    groupTaskId:    groupTaskId,
  );
}

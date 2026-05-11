import 'package:cloud_firestore/cloud_firestore.dart';

enum TaskPriority { high, medium, low }

enum TaskStatus { pending, inProgress, completed, overdue }

class Checkpoint {
  final String title;
  final bool isCompleted;

  Checkpoint({required this.title, this.isCompleted = false});

  factory Checkpoint.fromJson(Map<String, dynamic> json) {
    return Checkpoint(
      title: json['title'] ?? '',
      isCompleted: json['isCompleted'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'isCompleted': isCompleted,
    };
  }
}

class StaffTask {
  final String id;
  final String title;
  final String description;
  final String? notes;
  final String createdBy; // ID or Email
  final String creatorRole; // 'principal' or 'coordinator'
  final String creatorName;
  final List<String> assignedToIds;
  final List<String> assignedToNames;
  final List<String> assignedToRoles;
  final List<String> targetRoles; // e.g. ["teacher", "coordinator"] for "All Teachers"
  final List<String> targetClasses; // e.g. ["10-A", "9-B"]
  final TaskPriority priority;
  final TaskStatus status;
  final DateTime createdAt;
  final DateTime dueDate;
  final bool isRecurring;
  final String? recurrencePattern;
  final List<Checkpoint> checkpoints;
  final String? completionNotes;
  final List<String> progressUpdates;

  StaffTask({
    required this.id,
    required this.title,
    required this.description,
    this.notes,
    required this.createdBy,
    required this.creatorRole,
    required this.creatorName,
    required this.assignedToIds,
    required this.assignedToNames,
    required this.assignedToRoles,
    this.targetRoles = const [],
    required this.targetClasses,
    required this.priority,
    required this.status,
    required this.createdAt,
    required this.dueDate,
    this.isRecurring = false,
    this.recurrencePattern,
    this.checkpoints = const [],
    this.completionNotes,
    this.progressUpdates = const [],
  });

  factory StaffTask.fromFirestore(Map<String, dynamic> json, String id) {
    return StaffTask(
      id: id,
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      notes: json['notes'],
      createdBy: json['createdBy'] ?? '',
      creatorRole: json['creatorRole'] ?? '',
      creatorName: json['creatorName'] ?? '',
      assignedToIds: List<String>.from(json['assignedToIds'] ?? []),
      assignedToNames: List<String>.from(json['assignedToNames'] ?? []),
      assignedToRoles: List<String>.from(json['assignedToRoles'] ?? []),
      targetRoles: List<String>.from(json['targetRoles'] ?? []),
      targetClasses: List<String>.from(json['targetClasses'] ?? []),
      priority: TaskPriority.values.firstWhere(
        (e) => e.name == (json['priority'] ?? 'medium'),
        orElse: () => TaskPriority.medium,
      ),
      status: TaskStatus.values.firstWhere(
        (e) => e.name == (json['status'] ?? 'pending'),
        orElse: () => TaskStatus.pending,
      ),
      createdAt: (json['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      dueDate: (json['dueDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isRecurring: json['isRecurring'] ?? false,
      recurrencePattern: json['recurrencePattern'],
      checkpoints: (json['checkpoints'] as List? ?? [])
          .map((e) => Checkpoint.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      completionNotes: json['completionNotes'],
      progressUpdates: List<String>.from(json['progressUpdates'] ?? []),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'description': description,
      'notes': notes,
      'createdBy': createdBy,
      'creatorRole': creatorRole,
      'creatorName': creatorName,
      'assignedToIds': assignedToIds,
      'assignedToNames': assignedToNames,
      'assignedToRoles': assignedToRoles,
      'targetRoles': targetRoles,
      'targetClasses': targetClasses,
      'priority': priority.name,
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'dueDate': Timestamp.fromDate(dueDate),
      'isRecurring': isRecurring,
      'recurrencePattern': recurrencePattern,
      'checkpoints': checkpoints.map((e) => e.toJson()).toList(),
      'completionNotes': completionNotes,
      'progressUpdates': progressUpdates,
    };
  }

  StaffTask copyWith({
    String? title,
    String? description,
    String? notes,
    List<String>? assignedToIds,
    List<String>? assignedToNames,
    List<String>? assignedToRoles,
    List<String>? targetRoles,
    List<String>? targetClasses,
    TaskPriority? priority,
    TaskStatus? status,
    DateTime? dueDate,
    bool? isRecurring,
    String? recurrencePattern,
    List<Checkpoint>? checkpoints,
    String? completionNotes,
    List<String>? progressUpdates,
  }) {
    return StaffTask(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      notes: notes ?? this.notes,
      createdBy: createdBy,
      creatorRole: creatorRole,
      creatorName: creatorName,
      assignedToIds: assignedToIds ?? this.assignedToIds,
      assignedToNames: assignedToNames ?? this.assignedToNames,
      assignedToRoles: assignedToRoles ?? this.assignedToRoles,
      targetRoles: targetRoles ?? this.targetRoles,
      targetClasses: targetClasses ?? this.targetClasses,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      createdAt: createdAt,
      dueDate: dueDate ?? this.dueDate,
      isRecurring: isRecurring ?? this.isRecurring,
      recurrencePattern: recurrencePattern ?? this.recurrencePattern,
      checkpoints: checkpoints ?? this.checkpoints,
      completionNotes: completionNotes ?? this.completionNotes,
      progressUpdates: progressUpdates ?? this.progressUpdates,
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

enum TaskStatus { pending, inProgress, completed, overdue }

enum TaskPriority { low, medium, high }

TaskStatus _parseStatus(String? s) {
  switch (s) {
    case 'inProgress': return TaskStatus.inProgress;
    case 'completed':  return TaskStatus.completed;
    case 'done':       return TaskStatus.completed; // legacy
    case 'overdue':    return TaskStatus.overdue;
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
      case TaskStatus.overdue:    return 'Overdue';
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

class Checkpoint {
  final String title;
  final bool isCompleted;
  const Checkpoint({required this.title, this.isCompleted = false});
  Checkpoint copyWith({bool? isCompleted}) =>
      Checkpoint(title: title, isCompleted: isCompleted ?? this.isCompleted);
  Map<String, dynamic> toJson() => {'title': title, 'isCompleted': isCompleted};
  factory Checkpoint.fromJson(Map<String, dynamic> j) =>
      Checkpoint(
        title: j['title'] as String? ?? '',
        isCompleted: j['isCompleted'] as bool? ?? false,
      );
}

class StaffTask {
  final String       id;
  final String       schoolId;
  final String       title;
  final String       description;
  final String?      notes;

  // Creator fields
  final String       createdBy;       // creator email (primary)
  final String       assignedBy;      // alias for createdBy (backward compat)
  final String       creatorRole;
  final String       creatorName;
  final String       assignedByRole;  // alias for creatorRole

  // Assignee fields (list-based)
  final List<String> assignedToIds;
  final List<String> assignedToNames;
  final List<String> assignedToRoles;
  final List<String> targetRoles;
  final List<String> targetClasses;

  // Legacy single-assignee fields (backward compat)
  final String       assignedTo;
  final String       assignedToName;

  final DateTime?    dueDate;
  final TaskStatus   status;
  final TaskPriority priority;
  final String       classId;
  final DateTime     createdAt;
  final bool         isGroupTask;
  final String       groupTaskId;

  // Rich task features
  final List<Checkpoint>            checkpoints;
  final List<Map<String, dynamic>>  progressUpdates;

  const StaffTask({
    required this.id,
    this.schoolId = '',
    required this.title,
    required this.description,
    this.notes,
    // creator
    String? createdBy,
    String? assignedBy,
    this.creatorRole = '',
    this.creatorName = '',
    String? assignedByRole,
    // assignees
    List<String>? assignedToIds,
    List<String>? assignedToNames,
    List<String>? assignedToRoles,
    List<String>? targetRoles,
    List<String>? targetClasses,
    // legacy
    this.assignedTo = '',
    this.assignedToName = '',
    this.dueDate,
    required this.status,
    required this.priority,
    this.classId = '',
    required this.createdAt,
    this.isGroupTask = false,
    this.groupTaskId = '',
    List<Checkpoint>? checkpoints,
    List<Map<String, dynamic>>? progressUpdates,
  })  : createdBy      = createdBy ?? assignedBy ?? '',
        assignedBy     = assignedBy ?? createdBy ?? '',
        assignedByRole = assignedByRole ?? creatorRole,
        assignedToIds   = assignedToIds ?? const [],
        assignedToNames = assignedToNames ?? const [],
        assignedToRoles = assignedToRoles ?? const [],
        targetRoles     = targetRoles ?? const [],
        targetClasses   = targetClasses ?? const [],
        checkpoints     = checkpoints ?? const [],
        progressUpdates = progressUpdates ?? const [];

  bool get isOverdue =>
      dueDate != null &&
      DateTime.now().isAfter(dueDate!) &&
      status != TaskStatus.completed;

  int get overdueDays =>
      isOverdue ? DateTime.now().difference(dueDate!).inDays : 0;

  factory StaffTask.fromJson(Map<String, dynamic> json, String docId) {
    final createdByVal   = (json['createdBy']      as String?) ??
                           (json['assignedBy']     as String?) ?? '';
    final creatorRoleVal = (json['creatorRole']    as String?) ??
                           (json['assignedByRole'] as String?) ?? '';
    final creatorNameVal = (json['creatorName']    as String?) ?? '';
    return StaffTask(
      id:             docId,
      schoolId:       json['schoolId']       as String? ?? '',
      title:          json['title']          as String? ?? '',
      description:    json['description']    as String? ?? '',
      notes:          json['notes']          as String?,
      createdBy:      createdByVal,
      assignedBy:     createdByVal,
      creatorRole:    creatorRoleVal,
      creatorName:    creatorNameVal,
      assignedByRole: creatorRoleVal,
      assignedToIds:   _parseStringList(json['assignedToIds']),
      assignedToNames: _parseStringList(json['assignedToNames']),
      assignedToRoles: _parseStringList(json['assignedToRoles']),
      targetRoles:     _parseStringList(json['targetRoles']),
      targetClasses:   _parseStringList(json['targetClasses']),
      assignedTo:     json['assignedTo']     as String? ?? '',
      assignedToName: json['assignedToName'] as String? ?? '',
      dueDate:        (json['dueDate'] as Timestamp?)?.toDate(),
      status:         _parseStatus(json['status'] as String?),
      priority:       _parsePriority(json['priority'] as String?),
      classId:        json['classId']        as String? ?? '',
      createdAt:      (json['createdAt'] as Timestamp?)?.toDate() ??
                      DateTime.now(),
      isGroupTask:    json['isGroupTask']    as bool?   ?? false,
      groupTaskId:    json['groupTaskId']    as String? ?? '',
      checkpoints:    _parseCheckpoints(json['checkpoints']),
      progressUpdates: _parseProgressUpdates(json['progressUpdates']),
    );
  }

  factory StaffTask.fromFirestore(Map<String, dynamic> data, String docId) =>
      StaffTask.fromJson(data, docId);

  static List<String> _parseStringList(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return [];
  }

  static List<Checkpoint> _parseCheckpoints(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) {
      return raw
          .whereType<Map<String, dynamic>>()
          .map((e) => Checkpoint.fromJson(e))
          .toList();
    }
    return [];
  }

  static List<Map<String, dynamic>> _parseProgressUpdates(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) {
      return raw.map((e) {
        if (e is Map<String, dynamic>) return e;
        if (e is String) return <String, dynamic>{'text': e};
        return <String, dynamic>{'text': e.toString()};
      }).toList();
    }
    return [];
  }

  Map<String, dynamic> toJson() => {
    'schoolId':       schoolId,
    'title':          title,
    'description':    description,
    if (notes != null && notes!.isNotEmpty) 'notes': notes,
    'createdBy':      createdBy,
    'assignedBy':     assignedBy,
    'creatorRole':    creatorRole,
    'creatorName':    creatorName,
    'assignedByRole': assignedByRole,
    'assignedToIds':   assignedToIds,
    'assignedToNames': assignedToNames,
    'assignedToRoles': assignedToRoles,
    'targetRoles':     targetRoles,
    'targetClasses':   targetClasses,
    'assignedTo':     assignedTo,
    'assignedToName': assignedToName,
    if (dueDate != null) 'dueDate': Timestamp.fromDate(dueDate!),
    'status':         status.name,
    'priority':       priority.name,
    'classId':        classId,
    'createdAt':      FieldValue.serverTimestamp(),
    'isGroupTask':    isGroupTask,
    if (groupTaskId.isNotEmpty) 'groupTaskId': groupTaskId,
    'checkpoints':    checkpoints.map((c) => c.toJson()).toList(),
    'progressUpdates': progressUpdates,
  };

  StaffTask copyWith({
    TaskStatus?                  status,
    List<Checkpoint>?            checkpoints,
    List<Map<String, dynamic>>?  progressUpdates,
  }) => StaffTask(
    id:             id,
    schoolId:       schoolId,
    title:          title,
    description:    description,
    notes:          notes,
    createdBy:      createdBy,
    assignedBy:     assignedBy,
    creatorRole:    creatorRole,
    creatorName:    creatorName,
    assignedByRole: assignedByRole,
    assignedToIds:   assignedToIds,
    assignedToNames: assignedToNames,
    assignedToRoles: assignedToRoles,
    targetRoles:     targetRoles,
    targetClasses:   targetClasses,
    assignedTo:     assignedTo,
    assignedToName: assignedToName,
    dueDate:        dueDate,
    status:         status ?? this.status,
    priority:       priority,
    classId:        classId,
    createdAt:      createdAt,
    isGroupTask:    isGroupTask,
    groupTaskId:    groupTaskId,
    checkpoints:    checkpoints ?? this.checkpoints,
    progressUpdates: progressUpdates ?? this.progressUpdates,
  );
}

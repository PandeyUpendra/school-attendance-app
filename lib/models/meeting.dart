import 'package:cloud_firestore/cloud_firestore.dart';

enum MeetingStatus { draft, active, completed }

MeetingStatus _parseStatus(String? s) {
  switch (s) {
    case 'Active':    return MeetingStatus.active;
    case 'Completed': return MeetingStatus.completed;
    default:          return MeetingStatus.draft;
  }
}

extension MeetingStatusLabel on MeetingStatus {
  String get label {
    switch (this) {
      case MeetingStatus.draft:     return 'Draft';
      case MeetingStatus.active:    return 'Active';
      case MeetingStatus.completed: return 'Completed';
    }
  }
}

class MeetingPoint {
  final String   id;
  final String   text;
  final bool     isChecked;
  final bool     convertedToTask;
  final String   taskId;   // meetingTask doc ID after conversion
  final String   addedBy;
  final DateTime addedAt;

  const MeetingPoint({
    required this.id,
    required this.text,
    this.isChecked       = false,
    this.convertedToTask = false,
    this.taskId          = '',
    required this.addedBy,
    required this.addedAt,
  });

  factory MeetingPoint.fromJson(Map<String, dynamic> json) => MeetingPoint(
        id:              json['id']              as String?   ?? '',
        text:            json['text']            as String?   ?? '',
        isChecked:       json['isChecked']       as bool?     ?? false,
        convertedToTask: json['convertedToTask'] as bool?     ?? false,
        taskId:          json['taskId']          as String?   ?? '',
        addedBy:         json['addedBy']         as String?   ?? '',
        addedAt:         (json['addedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id':              id,
        'text':            text,
        'isChecked':       isChecked,
        'convertedToTask': convertedToTask,
        'taskId':          taskId,
        'addedBy':         addedBy,
        'addedAt':         Timestamp.fromDate(addedAt),
      };

  MeetingPoint copyWith({
    bool?   isChecked,
    bool?   convertedToTask,
    String? taskId,
  }) =>
      MeetingPoint(
        id:              id,
        text:            text,
        isChecked:       isChecked       ?? this.isChecked,
        convertedToTask: convertedToTask ?? this.convertedToTask,
        taskId:          taskId          ?? this.taskId,
        addedBy:         addedBy,
        addedAt:         addedAt,
      );
}

class Meeting {
  final String            id;
  final String            title;
  final DateTime          date;
  final String            createdBy;
  final String            createdByName;
  final String            createdByRole;
  final List<MeetingPoint> points;
  final List<String>      assignedTeacherIds;
  final List<String>      assignedTeacherNames;
  final MeetingStatus     status;
  final DateTime?         completedAt;
  final String            pdfUrl;
  final DateTime          createdAt;
  final DateTime          updatedAt;

  const Meeting({
    required this.id,
    required this.title,
    required this.date,
    required this.createdBy,
    required this.createdByName,
    required this.createdByRole,
    required this.points,
    required this.assignedTeacherIds,
    required this.assignedTeacherNames,
    required this.status,
    this.completedAt,
    this.pdfUrl = '',
    required this.createdAt,
    required this.updatedAt,
  });

  int get discussedCount  => points.where((p) => p.isChecked).length;
  int get tasksCreated    => points.where((p) => p.convertedToTask).length;
  bool get isCompleted    => status == MeetingStatus.completed;
  bool get isReadOnly     => status == MeetingStatus.completed;

  factory Meeting.fromJson(Map<String, dynamic> json, String docId) => Meeting(
        id:                   docId,
        title:                json['title']          as String? ?? '',
        date:                 (json['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
        createdBy:            json['createdBy']      as String? ?? '',
        createdByName:        json['createdByName']  as String? ?? '',
        createdByRole:        json['createdByRole']  as String? ?? '',
        points:               (json['points'] as List?)
                                  ?.map((e) => MeetingPoint.fromJson(e as Map<String, dynamic>))
                                  .toList() ??
                              [],
        assignedTeacherIds:   List<String>.from(json['assignedTeacherIds']   as List? ?? []),
        assignedTeacherNames: List<String>.from(json['assignedTeacherNames'] as List? ?? []),
        status:               _parseStatus(json['status'] as String?),
        completedAt:          (json['completedAt'] as Timestamp?)?.toDate(),
        pdfUrl:               json['pdfUrl'] as String? ?? '',
        createdAt:            (json['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        updatedAt:            (json['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );

  Map<String, dynamic> toCreateJson() => {
        'title':                title,
        'date':                 Timestamp.fromDate(date),
        'createdBy':            createdBy,
        'createdByName':        createdByName,
        'createdByRole':        createdByRole,
        'points':               points.map((p) => p.toJson()).toList(),
        'assignedTeacherIds':   assignedTeacherIds,
        'assignedTeacherNames': assignedTeacherNames,
        'status':               status.label,
        'pdfUrl':               pdfUrl,
        'createdAt':            FieldValue.serverTimestamp(),
        'updatedAt':            FieldValue.serverTimestamp(),
      };
}

class MeetingTask {
  final String   id;
  final String   meetingId;
  final String   meetingTitle;
  final DateTime meetingDate;
  final String   pointText;
  final String   assignedTo;       // teacher doc ID
  final String   assignedToName;
  final String   assignedBy;       // creator email
  final String   staffTaskId;      // linked staff_tasks doc ID
  final String   status;           // 'Pending' | 'InProgress' | 'Completed'
  final DateTime createdAt;

  const MeetingTask({
    required this.id,
    required this.meetingId,
    required this.meetingTitle,
    required this.meetingDate,
    required this.pointText,
    required this.assignedTo,
    required this.assignedToName,
    required this.assignedBy,
    this.staffTaskId = '',
    required this.status,
    required this.createdAt,
  });

  bool get isCompleted => status == 'Completed';

  factory MeetingTask.fromJson(Map<String, dynamic> json, String docId) => MeetingTask(
        id:            docId,
        meetingId:     json['meetingId']     as String? ?? '',
        meetingTitle:  json['meetingTitle']  as String? ?? '',
        meetingDate:   (json['meetingDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
        pointText:     json['pointText']     as String? ?? '',
        assignedTo:    json['assignedTo']    as String? ?? '',
        assignedToName: json['assignedToName'] as String? ?? '',
        assignedBy:    json['assignedBy']    as String? ?? '',
        staffTaskId:   json['staffTaskId']   as String? ?? '',
        status:        json['status']        as String? ?? 'Pending',
        createdAt:     (json['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'meetingId':     meetingId,
        'meetingTitle':  meetingTitle,
        'meetingDate':   Timestamp.fromDate(meetingDate),
        'pointText':     pointText,
        'assignedTo':    assignedTo,
        'assignedToName': assignedToName,
        'assignedBy':    assignedBy,
        'staffTaskId':   staffTaskId,
        'status':        status,
        'createdAt':     FieldValue.serverTimestamp(),
      };
}

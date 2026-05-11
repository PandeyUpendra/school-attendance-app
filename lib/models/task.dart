import 'package:cloud_firestore/cloud_firestore.dart';

class Task {
  final String id;
  final String title;
  final String description;
  final String createdBy; // Email or ID of creator
  final String creatorRole; // 'coordinator' or 'principal'
  final List<String> assignedClasses;
  final DateTime createdAt;
  final DateTime? dueDate;
  // studentStatuses: Map<String, bool> where key is 'className_roll'
  final Map<String, bool> studentStatuses;

  Task({
    required this.id,
    required this.title,
    required this.description,
    required this.createdBy,
    required this.creatorRole,
    required this.assignedClasses,
    required this.createdAt,
    this.dueDate,
    this.studentStatuses = const {},
  });

  factory Task.fromJson(Map<String, dynamic> json, String id) {
    return Task(
      id: id,
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      createdBy: json['createdBy'] ?? '',
      creatorRole: json['creatorRole'] ?? '',
      assignedClasses: List<String>.from(json['assignedClasses'] ?? []),
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      dueDate: json['dueDate'] != null ? (json['dueDate'] as Timestamp).toDate() : null,
      studentStatuses: Map<String, bool>.from(json['studentStatuses'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'createdBy': createdBy,
      'creatorRole': creatorRole,
      'assignedClasses': assignedClasses,
      'createdAt': Timestamp.fromDate(createdAt),
      'dueDate': dueDate != null ? Timestamp.fromDate(dueDate!) : null,
      'studentStatuses': studentStatuses,
    };
  }
}

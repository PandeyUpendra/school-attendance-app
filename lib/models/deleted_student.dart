import 'package:cloud_firestore/cloud_firestore.dart';

/// Read-only tombstone written when a student is permanently removed
/// (principal-approved deletion). Surfaced in the "Deleted Students" history
/// on the class-teacher, coordinator, and principal dashboards.
///
/// Lives at `schools/{schoolId}/deleted_students/{autoId}`. Unlike the
/// `student_deletion_requests` collection (principal-only by Firestore rules),
/// these tombstones are readable by any staff member so all three roles can
/// view the history.
class DeletedStudent {
  final String id;
  final int roll;
  final String name;
  final String className;
  final String section;

  /// Class teacher who owned the student record — used to scope a class
  /// teacher's view to their own students. May be null on legacy records.
  final String? teacherId;

  /// When the student was permanently removed.
  final Timestamp? deletedAt;

  const DeletedStudent({
    this.id = '',
    required this.roll,
    required this.name,
    this.className = '',
    this.section = '',
    this.teacherId,
    this.deletedAt,
  });

  Map<String, dynamic> toJson() => {
        'roll': roll,
        'name': name,
        'className': className,
        'section': section,
        if (teacherId != null && teacherId!.isNotEmpty) 'teacherId': teacherId,
        'deletedAt': deletedAt ?? FieldValue.serverTimestamp(),
      };

  factory DeletedStudent.fromJson(String id, Map<String, dynamic> json) =>
      DeletedStudent(
        id: id,
        roll: (json['roll'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? 'Unknown',
        className: json['className'] as String? ?? '',
        section: json['section'] as String? ?? '',
        teacherId: json['teacherId'] as String?,
        deletedAt: json['deletedAt'] as Timestamp?,
      );
}

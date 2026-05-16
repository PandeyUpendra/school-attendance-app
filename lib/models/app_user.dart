enum UserRole { teacher, guardian, coordinator, principal, subjectTeacher, owner }

class AppUser {
  final String uid;
  final String name;
  final String email;
  final UserRole role;
  final String schoolId;

  /// Teacher   : class IDs they teach  (e.g. ["Class 9-A"])
  /// Guardian  : child's class ID      (e.g. ["Class 9-A"])
  /// Coordinator / Principal : empty
  final List<String> classIds;

  /// Guardian only: the IDs of their children
  final List<String> studentIds;

  const AppUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.schoolId,
    required this.classIds,
    this.studentIds = const [],
  });

  factory AppUser.fromFirestore(Map<String, dynamic> data, String uid) {
    return AppUser(
      uid: uid,
      name: data['name'] as String? ?? '',
      email: data['email'] as String? ?? '',
      role: _roleFromString(data['role'] as String? ?? ''),
      schoolId: data['schoolId'] as String? ?? '',
      classIds: List<String>.from(data['classIds'] as List? ?? []),
      studentIds: List<String>.from(data['studentIds'] as List? ?? (data['studentId'] != null ? [data['studentId']] : [])),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'email': email,
        'role': role.name,
        'schoolId': schoolId,
        'classIds': classIds,
        'studentIds': studentIds,
      };

  static UserRole _roleFromString(String value) {
    return UserRole.values.firstWhere(
      (r) => r.name == value,
      orElse: () => UserRole.teacher,
    );
  }
}

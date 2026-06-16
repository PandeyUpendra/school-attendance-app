import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:meta/meta.dart';
import '../models/todo_item.dart';

class TodoService {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get _col => _db.collection('personal_todos');

  static TodoService? _instance;
  TodoService._();
  factory TodoService() => _instance ??= TodoService._();

  @visibleForTesting
  static set mockInstance(TodoService? mock) => _instance = mock;

  String _normalizeUserId(String userId) {
    final trimmed = userId.trim();
    if (trimmed.contains('@')) {
      return trimmed.toLowerCase();
    }
    return trimmed;
  }

  Stream<List<TodoItem>> streamForUser(String userId) {
    // No orderBy — avoids the composite index requirement.
    // Sorting is done in-app after fetching.
    final normalized = _normalizeUserId(userId);
    return _col
        .where('userId', isEqualTo: normalized)
        .snapshots()
        .map((snap) {
          final items = snap.docs
              .map((d) => TodoItem.fromJson(d.data(), d.id))
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return items;
        });
  }

  Stream<List<TodoItem>> streamTodayReminders(String userId) {
    final today    = DateTime.now();
    final start    = DateTime(today.year, today.month, today.day);
    final end      = start.add(const Duration(days: 1));
    final normalized = _normalizeUserId(userId);

    return _col
        .where('userId', isEqualTo: normalized)
        .where('reminderEnabled', isEqualTo: true)
        .where('isCompleted', isEqualTo: false)
        .where('dueDate', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('dueDate', isLessThan: Timestamp.fromDate(end))
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => TodoItem.fromJson(d.data(), d.id))
            .toList());
  }

  Future<void> addTodo(TodoItem item) async {
    final doc = _col.doc();
    await doc.set(TodoItem(
      id: doc.id,
      userId: _normalizeUserId(item.userId),
      role: item.role,
      title: item.title,
      isCustom: item.isCustom,
      dueDate: item.dueDate,
      reminderEnabled: item.reminderEnabled,
      isCompleted: false,
      createdAt: DateTime.now(),
    ).toJson());
  }

  Future<void> toggleComplete(String id, bool isCompleted) async {
    await _col.doc(id).update({'isCompleted': isCompleted});
  }

  Future<void> updateReminder(String id, bool enabled) async {
    await _col.doc(id).update({'reminderEnabled': enabled});
  }

  Future<void> deleteTodo(String id) async {
    await _col.doc(id).delete();
  }

  Future<void> updateDueDate(String id, DateTime? date) async {
    await _col.doc(id).update({
      'dueDate': date != null ? Timestamp.fromDate(date) : null,
    });
  }
}

// Pre-defined todo templates per role
class TodoTemplates {
  static const Map<String, List<String>> _templates = {
    'teacher': [
      'Take class attendance',
      'Post homework assignment',
      'Grade student copies / notebooks',
      'Prepare lesson plan',
      'Update student remarks',
      'Apply for leave',
      'Record exam / test marks',
      'Call absent student guardians',
      'Prepare test paper',
      'Attend staff meeting',
      'Submit attendance report',
      'Review student performance',
      'Check notice board',
      'Complete copy checking',
      'Submit class register',
    ],
    'coordinator': [
      'Review teacher attendance',
      'Assign substitute duties',
      'Process pending leave requests',
      'Monitor homework submissions',
      'Coordinate exam scheduling',
      'Generate student attendance report',
      'Conduct class observations',
      'Parent communication follow-up',
      'Review copy checking reports',
      'Arrange staff meeting',
      'Resolve timetable conflicts',
      'Check student discipline records',
      'Review coordinator tasks',
      'Update notice board',
      'Audit class registers',
    ],
    'principal': [
      'Review daily attendance report',
      'Approve pending leave requests',
      'Check fee collection status',
      'Review exam results',
      'Conduct staff meeting',
      'Review homework submission status',
      'Plan school events',
      'Parent-teacher meeting',
      'Review school budget',
      'Inspect classrooms',
      'Post school announcement',
      'Review student discipline records',
      'Coordinate with department heads',
      'Sign documents / circulars',
      'Review copy checking progress',
    ],
    'ownerPrincipal': [
      'Review daily attendance report',
      'Approve pending leave requests',
      'Check fee collection status',
      'Review exam results',
      'Conduct staff meeting',
      'Review homework submission status',
      'Plan school events',
      'Parent-teacher meeting',
      'Review school budget',
      'Inspect classrooms',
      'Post school announcement',
      'Review student discipline records',
      'Coordinate with department heads',
      'Sign documents / circulars',
      'Review copy checking progress',
    ],
  };

  static List<String> forRole(String role) =>
      _templates[role] ?? _templates['teacher']!;
}

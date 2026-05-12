import 'package:cloud_firestore/cloud_firestore.dart';

/// Base class for all Firestore services to provide common functionality
/// and ensure consistent database access patterns.
abstract class BaseFirestoreService {
  final FirebaseFirestore db = FirebaseFirestore.instance;

  static String? currentSchoolId;

  /// Helper to get a collection reference
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      db.collection(path);

  /// Helper to get a document reference
  DocumentReference<Map<String, dynamic>> doc(String path) =>
      db.doc(path);

  /// Standardized helper for school-specific collections
  CollectionReference<Map<String, dynamic>> schoolCollection(String schoolId, String path) =>
      db.collection('schools').doc(schoolId).collection(path);

  /// Standardized helper for student IDs
  String sidFromParts(int roll, String className, String section) {
    final s = section.trim().isEmpty ? '' : ' ${section.trim()}';
    return '${className.replaceAll(' ', '_')}$s.roll_$roll';
  }

  String sid(dynamic student) {
    // Assuming student has roll, className, section properties or keys
    if (student is Map) {
      return sidFromParts(student['roll'] as int, student['className'] as String, student['section'] as String? ?? '');
    }
    // Fallback if it's a model (you might need to import the model or use dynamic)
    return sidFromParts(student.roll, student.className, student.section);
  }

  /// Standardized helper for today's attendance key
  String todayKey(String className) {
    final d = DateTime.now();
    return '${className.replaceAll(' ', '_')}_${d.year}-${d.month}-${d.day}';
  }

  /// Standardized error handling for Firestore operations
  void handleError(Object e, StackTrace stackTrace) {
    // Log error to console or crashlytics
    print('Firestore Error: $e');
    print(stackTrace);
    // You could throw a custom app exception here
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

/// Provides a shared school identifier and common Firestore helpers.
class BaseFirestoreService {
  static String? currentSchoolId;

  FirebaseFirestore get db => FirebaseFirestore.instance;

  /// Returns a top-level collection reference scoped to the given school.
  CollectionReference<Map<String, dynamic>> schoolCollection(
      String schoolId, String collectionName) =>
      db.collection('schools').doc(schoolId).collection(collectionName);

  void handleError(Object e, StackTrace stack) {
    // ignore: avoid_print
    print('Firestore error: $e\n$stack');
  }
}

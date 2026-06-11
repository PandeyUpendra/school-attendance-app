import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../shared/utils/app_logger.dart';

/// Provides a shared school identifier and common Firestore helpers.
class BaseFirestoreService {
  /// Active school id, exposed as a [ValueNotifier] so school-scoped state
  /// (e.g. SchoolSettingsProvider) can rebind its Firestore streams whenever
  /// the signed-in school changes (login, session restore, logout reset).
  static final ValueNotifier<String?> schoolIdNotifier =
      ValueNotifier<String?>(null);

  static String? get currentSchoolId => schoolIdNotifier.value;
  static set currentSchoolId(String? id) {
    if (schoolIdNotifier.value == id) return;
    schoolIdNotifier.value = id;
  }

  FirebaseFirestore get db => FirebaseFirestore.instance;

  /// Returns a top-level collection reference scoped to the given school.
  CollectionReference<Map<String, dynamic>> schoolCollection(
      String schoolId, String collectionName) =>
      db.collection('schools').doc(schoolId).collection(collectionName);

  void handleError(Object e, StackTrace stack) {
    AppLogger.e('Firestore', 'error: $e', e, stack);
  }
}

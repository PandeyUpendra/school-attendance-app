import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';
import 'base_firestore_service.dart';
import 'timetable_service.dart';

class SchoolSettingsService extends BaseFirestoreService {
  String get _sid => AuthService.currentSchoolId;

  CollectionReference<Map<String, dynamic>> get _settings =>
      schoolCollection(_sid, 'settings');

  Stream<Map<String, dynamic>> getSchoolSettings() =>
      _settings.doc('school').snapshots().map((s) => s.data() ?? {});

  Stream<Map<String, dynamic>> getAcademicSettings() =>
      _settings.doc('academic').snapshots().map((s) => s.data() ?? {});

  Stream<Map<String, dynamic>> getFeeSettings() =>
      _settings.doc('fees').snapshots().map((s) => s.data() ?? {});

  Stream<Map<String, dynamic>> getCommSettings() =>
      _settings.doc('communication').snapshots().map((s) => s.data() ?? {});

  Future<void> updateSchoolSettings(Map<String, dynamic> data) async {
    await _settings.doc('school').set(data, SetOptions(merge: true));
    // Sync school name to the shared school-scoped settings/main doc that
    // TimetableService.getSettings() (and every screen) reads.
    if (data['schoolName'] != null) {
      await _settings.doc('main')
          .set({'schoolName': data['schoolName']}, SetOptions(merge: true));
    }
  }

  Future<void> updateAcademicSettings(Map<String, dynamic> data) async {
    await _settings.doc('academic').set(data, SetOptions(merge: true));
    // Sync to the shared school-scoped settings/main so all screens (coordinator
    // class chips, principal, teacher mgmt, etc.) pick up the owner's changes.
    final syncData = <String, dynamic>{};
    if (data['classList'] != null) syncData['classes'] = data['classList'];
    if (data['periodsPerDay'] != null) syncData['periodsPerDay'] = data['periodsPerDay'];
    if (data['workingDays'] != null) syncData['workingDays'] = data['workingDays'];
    if (data['lunchAfterPeriod'] != null) syncData['lunchAfterPeriod'] = data['lunchAfterPeriod'];
    if (data['periodDuration'] != null) syncData['periodDuration'] = data['periodDuration'];
    if (syncData.isNotEmpty) {
      await _settings.doc('main').set(syncData, SetOptions(merge: true));
      // Drop TimetableService's cached settings so screens reading the class
      // list through getSettings() reflect this change in the same session.
      TimetableService.invalidateSettingsCache();
    }
  }

  Future<void> updateFeeSettings(Map<String, dynamic> data) =>
      _settings.doc('fees').set(data, SetOptions(merge: true));

  Future<void> updateCommSettings(Map<String, dynamic> data) =>
      _settings.doc('communication').set(data, SetOptions(merge: true));

  Future<void> logChange(String field, String oldVal, String newVal, String uid) {
    final verifiedUid = AuthService().currentFirebaseUser?.uid ?? uid;
    return _settings.doc('changeLog').collection('entries').add({
      'changedBy': verifiedUid,
      'changedAt': FieldValue.serverTimestamp(),
      'field': field,
      'oldValue': oldVal,
      'newValue': newVal,
    });
  }

  Stream<List<Map<String, dynamic>>> watchChangeLog() =>
      _settings.doc('changeLog').collection('entries')
          .orderBy('changedAt', descending: true)
          .limit(10)
          .snapshots()
          .map((s) => s.docs.map((d) => {...d.data(), 'id': d.id}).toList());

  Future<Map<String, dynamic>> getOnboardingStatus() async {
    final doc = await _settings.doc('onboarding').get();
    return doc.data() ?? {};
  }

  Future<void> saveOnboardingDraft(Map<String, dynamic> data) =>
      _settings.doc('onboarding').set(data, SetOptions(merge: true));

  Future<void> completeOnboarding(Map<String, dynamic> d) async {
    final batch = db.batch();

    batch.set(_settings.doc('school'), {
      'schoolName': d['schoolName'] ?? '',
      'logoUrl': d['logoUrl'] ?? '',
      'phone': d['phone'] ?? '',
      'email': d['email'] ?? '',
      'address': d['address'] ?? '',
      'city': d['city'] ?? '',
      'state': d['state'] ?? '',
      'pinCode': d['pinCode'] ?? '',
      'board': d['board'] ?? '',
      'schoolType': d['schoolType'] ?? '',
      'principalName': d['principalName'] ?? '',
      'tagline': d['schoolTagline'] ?? '',
      'website': d['website'] ?? '',
      'establishedYear': d['establishedYear'] ?? '',
      'facebookUrl': d['facebookUrl'] ?? '',
      'instagramUrl': d['instagramUrl'] ?? '',
      'twitterUrl': d['twitterUrl'] ?? '',
      'youtubeUrl': d['youtubeUrl'] ?? '',
      'linkedinUrl': d['linkedinUrl'] ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Build label fields from classList if not explicitly provided
    final classList = List<String>.from(d['classList'] as List? ?? []);
    if (classList.isEmpty) {
      throw ArgumentError('Class list cannot be empty.');
    }
    final fromInt = d['classesFrom'] as int? ?? 1;
    final toInt   = d['classesTo']   as int? ?? 10;
    String intToLabel(int n) => n <= 0 ? 'Nursery' : 'Class $n';
    batch.set(_settings.doc('academic'), {
      'classesFrom': fromInt,
      'classesTo':   toInt,
      'classesFromLabel': d['classesFromLabel'] ?? intToLabel(fromInt),
      'classesToLabel':   d['classesToLabel']   ?? intToLabel(toInt),
      'sections': d['sectionsPerClass'] ?? ['A'],
      'classList': classList,
      'academicYearStart': d['academicYearStart'] ?? 'April',
      'workingDays': d['workingDays'] ?? 'Mon-Sat',
      'periodsPerDay': d['periodsPerDay'] ?? 8,
      'periodDuration': d['periodDuration'] ?? 45,
      'lunchAfterPeriod': d['lunchAfterPeriod'] ?? 4,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    batch.set(_settings.doc('fees'), {
      'feeFrequency': d['feeFrequency'] ?? 'Monthly',
      'feeDueDate': d['feeDueDate'] ?? 10,
      'lateFeeEnabled': d['lateFeeEnabled'] ?? false,
      'lateFeePerDay': d['lateFeePerDay'] ?? 0,
      'reminderDaysBefore': d['reminderDaysBefore'] ?? 7,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    batch.set(_settings.doc('communication'), {
      'whatsappEnabled': d['whatsappEnabled'] ?? false,
      'schoolWhatsapp': d['schoolWhatsapp'] ?? '',
      'preferredLanguage': d['preferredLanguage'] ?? 'English',
      'busServiceAvailable': d['busServiceAvailable'] ?? false,
      'busRouteCount': d['busRouteCount'] ?? 0,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    batch.set(_settings.doc('onboarding'), {
      ...d,
      'isCompleted': true,
      'completedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();

    // Sync classList to the shared school-scoped settings/main so all screens
    // (coordinator class chips, principal, teacher mgmt, etc.) pick it up.
    await _settings.doc('main').set({
      'classes': classList,
      'schoolName': d['schoolName'] ?? '',
      'periodsPerDay': d['periodsPerDay'] ?? 8,
      'workingDays': d['workingDays'] ?? 'Mon-Sat',
      'lunchAfterPeriod': d['lunchAfterPeriod'] ?? 4,
      'periodDuration': d['periodDuration'] ?? 45,
    }, SetOptions(merge: true));
    TimetableService.invalidateSettingsCache();

    // Create class documents (each write is independent — run in parallel)
    try {
      await Future.wait(classList.map((classId) async {
        try {
          await createClassDocument(classId);
        } catch (e) {
          // Log or handle error gracefully
        }
      }));
    } catch (e) {
      // Log or handle error gracefully
    }
  }

  Future<void> createClassDocument(String classId) async {
    final docRef = schoolCollection(_sid, 'classes').doc(classId);
    final docSnap = await docRef.get();
    if (!docSnap.exists) {
      await docRef.set({
        'classId': classId,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }
}

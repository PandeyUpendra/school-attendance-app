import 'package:cloud_firestore/cloud_firestore.dart';

class SchoolSettingsService {
  static const String schoolId = 'school_1';
  static final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _settings =>
      _db.collection('schools').doc(schoolId).collection('settings');

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
    // Sync school name to legacy settings/main
    if (data['schoolName'] != null) {
      await _db.collection('settings').doc('main')
          .set({'schoolName': data['schoolName']}, SetOptions(merge: true));
    }
  }

  Future<void> updateAcademicSettings(Map<String, dynamic> data) async {
    await _settings.doc('academic').set(data, SetOptions(merge: true));
    // Sync to legacy settings/main so all existing screens pick up changes
    final syncData = <String, dynamic>{};
    if (data['classList'] != null) syncData['classes'] = data['classList'];
    if (data['periodsPerDay'] != null) syncData['periodsPerDay'] = data['periodsPerDay'];
    if (data['workingDays'] != null) syncData['workingDays'] = data['workingDays'];
    if (data['lunchAfterPeriod'] != null) syncData['lunchAfterPeriod'] = data['lunchAfterPeriod'];
    if (data['periodDuration'] != null) syncData['periodDuration'] = data['periodDuration'];
    if (syncData.isNotEmpty) {
      await _db.collection('settings').doc('main').set(syncData, SetOptions(merge: true));
    }
  }

  Future<void> updateFeeSettings(Map<String, dynamic> data) =>
      _settings.doc('fees').set(data, SetOptions(merge: true));

  Future<void> updateCommSettings(Map<String, dynamic> data) =>
      _settings.doc('communication').set(data, SetOptions(merge: true));

  Future<void> logChange(String field, String oldVal, String newVal, String uid) =>
      _settings.doc('changeLog').collection('entries').add({
        'changedBy': uid,
        'changedAt': FieldValue.serverTimestamp(),
        'field': field,
        'oldValue': oldVal,
        'newValue': newVal,
      });

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
    final batch = _db.batch();

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
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    batch.set(_settings.doc('academic'), {
      'classesFrom': d['classesFrom'] ?? 1,
      'classesTo': d['classesTo'] ?? 10,
      'sections': d['sectionsPerClass'] ?? ['A'],
      'classList': d['classList'] ?? [],
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

    // Sync classList to legacy settings/main so all existing screens pick it up
    final classList = List<String>.from(d['classList'] as List? ?? []);
    await _db.collection('settings').doc('main').set({
      'classes': classList,
      'schoolName': d['schoolName'] ?? '',
      'periodsPerDay': d['periodsPerDay'] ?? 8,
      'workingDays': d['workingDays'] ?? 'Mon-Sat',
      'lunchAfterPeriod': d['lunchAfterPeriod'] ?? 4,
      'periodDuration': d['periodDuration'] ?? 45,
    }, SetOptions(merge: true));

    // Create class documents
    for (final classId in classList) {
      await _db.collection('schools').doc(schoolId)
          .collection('classes').doc(classId).set({
        'classId': classId,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<void> createClassDocument(String classId) =>
      _db.collection('schools').doc(schoolId)
          .collection('classes').doc(classId).set({
        'classId': classId,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
}

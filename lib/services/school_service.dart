import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../utils/image_utils.dart';
import '../models/school.dart';
import 'base_firestore_service.dart';
import 'report_card_template_service.dart';
import 'timetable_service.dart';

class SchoolService extends BaseFirestoreService {
  static final SchoolService _instance = SchoolService._();
  SchoolService._();
  factory SchoolService() => _instance;

  static final _storage = FirebaseStorage.instance;
  CollectionReference<Map<String, dynamic>> get _schools => db.collection('schools');

  Future<void> registerSchool(School school, String adminEmail, String adminPassword, String adminName) async {
    // 1. Create School Document
    await _schools.doc(school.id).set(school.toJson());

    // 2. Initialize default settings
    await _schools.doc(school.id).collection('settings').doc('main').set({
      'numberOfBells': 8,
      'classes': ['Class 1', 'Class 2', 'Class 3', 'Class 4', 'Class 5', 'Class 6', 'Class 7', 'Class 8', 'Class 9', 'Class 10'],
      'bells': List.generate(8, (_) => {'duration': 40, 'isLunch': false}),
      'firstBellTime': '08:00',
    });

    // 3. Register Admin via the shared account-provisioning path. This:
    //      • writes allowed_users WITHOUT a password field (the old code stored
    //        the password in plaintext — readable by management — review #251);
    //      • creates a real Firebase Auth account with adminPassword, so the
    //        principal can actually sign in (the old code created no Auth user,
    //        so the freshly-registered principal could never log in — #252);
    //      • uses the same code path as every other account (#253).
    await TimetableService.instance.addAllowedUser(
      adminEmail.toLowerCase().trim(),
      adminPassword,
      'principal',
      name:     adminName,
      schoolId: school.id,
    );

    // 4. Seed the 3 default report card templates for this school.
    //    Uses school.effectiveBrandName so no institution name is hardcoded.
    await ReportCardTemplateService().seedDefaultTemplates(
      schoolId:  school.id,
      brandName: school.effectiveBrandName,
    );
  }

  Future<School?> getSchool(String schoolId) async {
    final doc = await _schools.doc(schoolId).get();
    if (!doc.exists || doc.data() == null) return null;
    return School.fromJson(doc.data()!, doc.id);
  }

  /// Returns the effective branding label for [schoolId].
  /// Reads schools/{schoolId}.brandName; falls back to .name.
  /// Used by report card generation to stamp PDFs with the correct brand.
  /// Never returns a hardcoded institution name.
  Future<String> getBrandName(String schoolId) async {
    final school = await getSchool(schoolId);
    return school?.effectiveBrandName ?? '';
  }

  Future<Map<String, dynamic>> getSchoolPolicy(String schoolId) async {
    final doc = await _schools.doc(schoolId).collection('settings').doc('policy').get();
    if (!doc.exists || doc.data() == null) {
      return {
        'idealDressPhoto': '',
        'disciplineRules': <String>[],
      };
    }
    final data = Map<String, dynamic>.from(doc.data()!);
    if (data['disciplineRules'] != null) {
      data['disciplineRules'] = List<String>.from(data['disciplineRules'] as List);
    } else {
      data['disciplineRules'] = <String>[];
    }
    return data;
  }

  Future<void> updateSchoolPolicy(String schoolId, Map<String, dynamic> data) async {
    await _schools.doc(schoolId).collection('settings').doc('policy').set(data, SetOptions(merge: true));
  }

  Future<String> uploadDressPhoto(String schoolId, File file) async {
    final compressedBytes = await ImageUtils.compressAndStripExif(file, quality: 70);

    final path = 'schools/$schoolId/policy/ideal_dress.jpg';
    final ref  = _storage.ref(path);
    final task = await ref.putData(
      compressedBytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return await task.ref.getDownloadURL();
  }
}

import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../models/school.dart';
import 'base_firestore_service.dart';

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

    // 3. Register Admin in allowed_users
    await db.collection('allowed_users').doc(adminEmail.toLowerCase().trim()).set({
      'email': adminEmail.toLowerCase().trim(),
      'name': adminName,
      'role': 'principal',
      'schoolId': school.id,
      'password': adminPassword,
    });
  }

  Future<School?> getSchool(String schoolId) async {
    final doc = await _schools.doc(schoolId).get();
    if (!doc.exists || doc.data() == null) return null;
    return School.fromJson(doc.data()!, doc.id);
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
    final origBytes = await file.readAsBytes();

    // Compress
    final compressedBytes = await FlutterImageCompress.compressWithList(
      origBytes,
      minWidth: 1080,
      minHeight: 1080,
      quality: 70,
    );

    final path = 'schools/$schoolId/policy/ideal_dress.jpg';
    final ref  = _storage.ref(path);
    final task = await ref.putData(
      Uint8List.fromList(compressedBytes!),
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return await task.ref.getDownloadURL();
  }
}

import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

class SchoolService {
  static final _db      = FirebaseFirestore.instance;
  static final _storage = FirebaseStorage.instance;
  static final _settings = _db.collection('settings');

  static final SchoolService _instance = SchoolService._();
  SchoolService._();
  factory SchoolService() => _instance;

  Future<Map<String, dynamic>> getSchoolPolicy() async {
    final doc = await _settings.doc('policy').get();
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

  Future<void> updateSchoolPolicy(Map<String, dynamic> data) async {
    await _settings.doc('policy').set(data, SetOptions(merge: true));
  }

  Future<String> uploadDressPhoto(File file) async {
    final origBytes = await file.readAsBytes();

    // Compress
    final compressedBytes = await FlutterImageCompress.compressWithList(
      origBytes,
      minWidth: 1080,
      minHeight: 1080,
      quality: 70,
    );

    final path = 'school/policy/ideal_dress.jpg';
    final ref  = _storage.ref(path);
    final task = await ref.putData(
      Uint8List.fromList(compressedBytes),
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return await task.ref.getDownloadURL();
  }
}

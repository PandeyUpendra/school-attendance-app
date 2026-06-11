import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/study_material.dart';
import 'auth_service.dart';
import 'base_firestore_service.dart';
import 'audit_log_service.dart';

class StudyMaterialService extends BaseFirestoreService {
  static final StudyMaterialService _instance = StudyMaterialService._();
  StudyMaterialService._();
  factory StudyMaterialService() => _instance;

  String get _sid => AuthService.currentSchoolId;
  static final _storage = FirebaseStorage.instance;

  CollectionReference<Map<String, dynamic>> get _materials =>
      schoolCollection(_sid, 'study_materials');

  Future<String> uploadMaterialFile(String fileName, Uint8List fileBytes, String contentType) async {
    final docId = FirebaseFirestore.instance.collection('temp').doc().id;
    final path = 'schools/$_sid/study_materials/${docId}_$fileName';
    final ref = _storage.ref(path);
    final task = await ref.putData(
      fileBytes,
      SettableMetadata(contentType: contentType),
    );
    return await task.ref.getDownloadURL();
  }

  Future<void> saveMaterial(StudyMaterial material) async {
    final docRef = material.id.isEmpty ? _materials.doc() : _materials.doc(material.id);
    final data = material.toJson();
    await docRef.set(data, SetOptions(merge: true));

    AuditService.emit(
      action: material.id.isEmpty ? 'create' : 'update',
      entity: 'study_material',
      entityId: docRef.id,
      after: data,
    );
  }

  Future<void> deleteMaterial(String id, String fileUrl) async {
    final prev = await _materials.doc(id).get();
    final before = prev.exists && prev.data() != null 
        ? Map<String, dynamic>.from(prev.data()!) 
        : null;
    await _materials.doc(id).delete();

    try {
      if (fileUrl.isNotEmpty) {
        final ref = _storage.refFromURL(fileUrl);
        await ref.delete();
      }
    } catch (e) {
      handleError(e, StackTrace.current);
    }

    AuditService.emit(
      action: 'delete',
      entity: 'study_material',
      entityId: id,
      before: before,
    );
  }

  Stream<List<StudyMaterial>> watchMaterials(String className) {
    return _materials
        .where('className', isEqualTo: className)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => StudyMaterial.fromDoc(d.id, Map<String, dynamic>.from(d.data() as Map)))
            .toList());
  }

  Future<List<StudyMaterial>> getMaterials(String className, {String? subject}) async {
    Query<Map<String, dynamic>> q = _materials.where('className', isEqualTo: className);
    if (subject != null && subject.isNotEmpty && subject != 'All') {
      q = q.where('subject', isEqualTo: subject);
    }
    final snap = await q.get();
    final list = snap.docs
        .map((d) => StudyMaterial.fromDoc(d.id, Map<String, dynamic>.from(d.data() as Map)))
        .toList();

    // Sort client-side to avoid composite index requirements in Firestore
    list.sort((a, b) {
      if (a.uploadedAt == null || b.uploadedAt == null) return 0;
      return b.uploadedAt!.compareTo(a.uploadedAt!);
    });
    return list;
  }
}

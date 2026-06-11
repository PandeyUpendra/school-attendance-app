import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/class_diary.dart';
import 'auth_service.dart';
import 'base_firestore_service.dart';
import 'audit_log_service.dart';

class ClassDiaryService extends BaseFirestoreService {
  static final ClassDiaryService _instance = ClassDiaryService._();
  ClassDiaryService._();
  factory ClassDiaryService() => _instance;

  String get _sid => AuthService.currentSchoolId;

  CollectionReference<Map<String, dynamic>> get _diary =>
      schoolCollection(_sid, 'class_diary');

  Future<void> saveDiaryEntry(ClassDiaryEntry entry) async {
    final docRef = entry.id.isEmpty ? _diary.doc() : _diary.doc(entry.id);
    final data = entry.toJson();
    await docRef.set(data, SetOptions(merge: true));

    AuditService.emit(
      action: entry.id.isEmpty ? 'create' : 'update',
      entity: 'class_diary',
      entityId: docRef.id,
      after: data,
    );
  }

  Future<void> deleteDiaryEntry(String id) async {
    final prev = await _diary.doc(id).get();
    final before = prev.exists && prev.data() != null 
        ? Map<String, dynamic>.from(prev.data()!) 
        : null;
    await _diary.doc(id).delete();

    AuditService.emit(
      action: 'delete',
      entity: 'class_diary',
      entityId: id,
      before: before,
    );
  }

  Stream<List<ClassDiaryEntry>> watchDiary(String className, String dateKey) {
    return _diary
        .where('className', isEqualTo: className)
        .where('dateKey', isEqualTo: dateKey)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => ClassDiaryEntry.fromDoc(d.id, Map<String, dynamic>.from(d.data() as Map)))
            .toList());
  }

  Future<List<ClassDiaryEntry>> getDiaryForDateRange(String className, String startDateKey, String endDateKey) async {
    final snap = await _diary
        .where('className', isEqualTo: className)
        .where('dateKey', isGreaterThanOrEqualTo: startDateKey)
        .where('dateKey', isLessThanOrEqualTo: endDateKey)
        .get();

    return snap.docs
        .map((d) => ClassDiaryEntry.fromDoc(d.id, Map<String, dynamic>.from(d.data() as Map)))
        .toList()
        ..sort((a, b) => b.dateKey.compareTo(a.dateKey)); // Newest first
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/homework.dart';

class HomeworkService {
  static final HomeworkService _instance = HomeworkService._internal();
  factory HomeworkService() => _instance;
  HomeworkService._internal();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  CollectionReference get _col => _db.collection('homework');

  // ── Teacher: post new homework ────────────────────────────────────────────
  Future<void> postHomework(String schoolId, Homework hw) async {
    if (hw.description.trim().length > 1000) {
      throw ArgumentError('Homework description cannot exceed 1000 characters.');
    }
    // Stamp schoolId so this cross-school root collection can be tenant-filtered
    // (Phase 1 of multi-tenancy: previously the param was ignored and no
    // schoolId was written, review #258/#259). Read-side filtering is added in a
    // later phase once existing docs have been backfilled with schoolId.
    await _col.add({...hw.toJson(), 'schoolId': schoolId});
  }

  // ── Teacher: get their own posts, newest first ────────────────────────────
  Future<List<Homework>> getHomeworkForTeacher(String schoolId, String teacherId) async {
    final snap = await _col
        .where('schoolId', isEqualTo: schoolId)
        .where('teacherId', isEqualTo: teacherId)
        .get();
    final list = snap.docs
        .map((d) => Homework.fromDoc(d.id, d.data() as Map<String, dynamic>))
        .toList();
    list.sort((a, b) => b.postedAt.compareTo(a.postedAt)); // newest first
    return list;
  }

  // ── Guardian / Student: get homework for a class, newest first ────────────
  Future<List<Homework>> getHomeworkForClass(String schoolId, String className) async {
    final snap = await _col
        .where('schoolId', isEqualTo: schoolId)
        .where('className', isEqualTo: className)
        .get();
    final list = snap.docs
        .map((d) => Homework.fromDoc(d.id, d.data() as Map<String, dynamic>))
        .toList();
    list.sort((a, b) => b.postedAt.compareTo(a.postedAt)); // newest first
    return list;
  }

  // ── Coordinator: all homework across all classes, newest first ────────────
  Future<List<Homework>> getAllHomework(String schoolId, {int limit = 100}) async {
    final snap = await _col.where('schoolId', isEqualTo: schoolId).get();
    final list = snap.docs
        .map((d) => Homework.fromDoc(d.id, d.data() as Map<String, dynamic>))
        .toList();
    list.sort((a, b) => b.postedAt.compareTo(a.postedAt)); // newest first
    if (list.length > limit) return list.sublist(0, limit);
    return list;
  }

  // ── Teacher: mark reviewed ────────────────────────────────────────────────
  Future<void> markReviewed(String schoolId, String id) async {
    await _col.doc(id).update({'isReviewed': true});
  }

  // ── Teacher / Coordinator: delete ─────────────────────────────────────────
  Future<void> deleteHomework(String schoolId, String id) async {
    await _col.doc(id).delete();
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/homework.dart';

class HomeworkService {
  static final HomeworkService _instance = HomeworkService._internal();
  factory HomeworkService() => _instance;
  HomeworkService._internal();

  final _db = FirebaseFirestore.instance;

  CollectionReference _col(String schoolId) =>
      _db.collection('schools').doc(schoolId).collection('homework');

  // ── Teacher: post new homework ────────────────────────────────────────────
  Future<void> postHomework(String schoolId, Homework hw) async {
    await _col(schoolId).add(hw.toJson());
  }

  // ── Teacher: get their own posts, newest first ────────────────────────────
  Future<List<Homework>> getHomeworkForTeacher(String schoolId, String teacherId) async {
    final snap = await _col(schoolId)
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
    final snap = await _col(schoolId)
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
    final snap = await _col(schoolId).get();
    final list = snap.docs
        .map((d) => Homework.fromDoc(d.id, d.data() as Map<String, dynamic>))
        .toList();
    list.sort((a, b) => b.postedAt.compareTo(a.postedAt)); // newest first
    if (list.length > limit) return list.sublist(0, limit);
    return list;
  }

  // ── Teacher: mark reviewed ────────────────────────────────────────────────
  Future<void> markReviewed(String schoolId, String id) async {
    await _col(schoolId).doc(id).update({'isReviewed': true});
  }

  // ── Teacher / Coordinator: delete ─────────────────────────────────────────
  Future<void> deleteHomework(String schoolId, String id) async {
    await _col(schoolId).doc(id).delete();
  }
}

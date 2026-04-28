import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/homework.dart';

class HomeworkService {
  static final HomeworkService _instance = HomeworkService._internal();
  factory HomeworkService() => _instance;
  HomeworkService._internal();

  final _db = FirebaseFirestore.instance;

  CollectionReference get _col => _db.collection('homework');

  // ── Teacher: post new homework ────────────────────────────────────────────
  Future<void> postHomework(Homework hw) async {
    await _col.add(hw.toJson());
  }

  // ── Teacher: get their own posts, newest first ────────────────────────────
  Future<List<Homework>> getHomeworkForTeacher(String teacherId) async {
    final snap = await _col
        .where('teacherId', isEqualTo: teacherId)
        .orderBy('postedAt', descending: true)
        .get();
    return snap.docs
        .map((d) => Homework.fromDoc(d.id, d.data() as Map<String, dynamic>))
        .toList();
  }

  // ── Guardian / Student: get homework for a class, newest first ────────────
  Future<List<Homework>> getHomeworkForClass(String className) async {
    final snap = await _col
        .where('className', isEqualTo: className)
        .orderBy('postedAt', descending: true)
        .get();
    return snap.docs
        .map((d) => Homework.fromDoc(d.id, d.data() as Map<String, dynamic>))
        .toList();
  }

  // ── Coordinator: all homework across all classes, newest first ────────────
  Future<List<Homework>> getAllHomework({int limit = 100}) async {
    final snap = await _col
        .orderBy('postedAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs
        .map((d) => Homework.fromDoc(d.id, d.data() as Map<String, dynamic>))
        .toList();
  }

  // ── Teacher: mark reviewed ────────────────────────────────────────────────
  Future<void> markReviewed(String id) async {
    await _col.doc(id).update({'isReviewed': true});
  }

  // ── Teacher / Coordinator: delete ─────────────────────────────────────────
  Future<void> deleteHomework(String id) async {
    await _col.doc(id).delete();
  }
}

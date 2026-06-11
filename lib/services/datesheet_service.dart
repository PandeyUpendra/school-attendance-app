import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/datesheet.dart';
import 'auth_service.dart';
import 'base_firestore_service.dart';
import 'audit_log_service.dart';

class DatesheetService extends BaseFirestoreService {
  static final DatesheetService _instance = DatesheetService._();
  DatesheetService._();
  factory DatesheetService() => _instance;

  String get _sid => AuthService.currentSchoolId;

  CollectionReference<Map<String, dynamic>> get _datesheets =>
      schoolCollection(_sid, 'datesheets');

  // Normalization helper for document ID
  String _docId(String className, String examId) {
    final cleanClass = className.replaceAll(' ', '_');
    final cleanExam = examId.replaceAll(' ', '_');
    return '${cleanClass}_$cleanExam';
  }

  Future<Datesheet> getDatesheet(String className, String examId) async {
    final id = _docId(className, examId);
    final doc = await _datesheets.doc(id).get();

    if (doc.exists && doc.data() != null) {
      return Datesheet.fromDoc(id, doc.data()!);
    }

    return Datesheet(
      id: id,
      examId: examId,
      className: className,
      schedules: [],
    );
  }

  Future<void> saveDatesheet(Datesheet datesheet) async {
    final id = _docId(datesheet.className, datesheet.examId);
    final data = datesheet.toJson();
    await _datesheets.doc(id).set(data);

    AuditService.emit(
      action: 'save_datesheet',
      entity: 'datesheet',
      entityId: id,
      after: data,
    );
  }

  Stream<Datesheet> watchDatesheet(String className, String examId) {
    final id = _docId(className, examId);
    return _datesheets.doc(id).snapshots().map((doc) {
      if (doc.exists && doc.data() != null) {
        return Datesheet.fromDoc(id, doc.data()!);
      }
      return Datesheet(
        id: id,
        className: className,
        examId: examId,
        schedules: [],
      );
    });
  }
}

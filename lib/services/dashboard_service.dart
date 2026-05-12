import 'package:cloud_firestore/cloud_firestore.dart';
import 'base_firestore_service.dart';

class DashboardSummary {
  final int teachersAbsentCount;
  final int unassignedBellsCount;
  final int totalStudents;
  final int presentToday;
  final int leaveToday;
  final int absentToday;
  final DateTime updatedAt;

  DashboardSummary({
    required this.teachersAbsentCount,
    required this.unassignedBellsCount,
    required this.totalStudents,
    required this.presentToday,
    required this.leaveToday,
    required this.absentToday,
    required this.updatedAt,
  });

  factory DashboardSummary.fromFirestore(Map<String, dynamic> json) {
    return DashboardSummary(
      teachersAbsentCount: json['teachersAbsentCount'] ?? 0,
      unassignedBellsCount: json['unassignedBellsCount'] ?? 0,
      totalStudents: json['totalStudents'] ?? 0,
      presentToday: json['presentToday'] ?? 0,
      leaveToday: json['leaveToday'] ?? 0,
      absentToday: json['absentToday'] ?? 0,
      updatedAt: (json['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'teachersAbsentCount': teachersAbsentCount,
    'unassignedBellsCount': unassignedBellsCount,
    'totalStudents': totalStudents,
    'presentToday': presentToday,
    'leaveToday': leaveToday,
    'absentToday': absentToday,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

class DashboardService extends BaseFirestoreService {
  static final DashboardService _instance = DashboardService._();
  DashboardService._();
  factory DashboardService() => _instance;

  DocumentReference<Map<String, dynamic>> _summaryDoc(String schoolId) =>
      db.collection('schools').doc(schoolId).collection('dashboard').doc('today');

  Future<DashboardSummary?> getSummary(String schoolId) async {
    final doc = await _summaryDoc(schoolId).get(const GetOptions(source: Source.serverAndCache));
    if (!doc.exists || doc.data() == null) return null;
    return DashboardSummary.fromFirestore(doc.data()!);
  }

  Stream<DashboardSummary?> watchSummary(String schoolId) {
    return _summaryDoc(schoolId).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return DashboardSummary.fromFirestore(doc.data()!);
    });
  }

  /// Recalculates school-wide stats using AggregateQueries (very cheap).
  Future<DashboardSummary> recalculateSummary(String schoolId) async {
    final totalStudentsQuery = db.collection('schools').doc(schoolId).collection('students').count();
    final totalTeachersQuery = db.collection('schools').doc(schoolId).collection('teachers').count();

    final totalStudents = (await totalStudentsQuery.get()).count ?? 0;

    // Note: Approved leaves and unassigned bells still require some logic,
    // but we can at least get the baseline student count cheaply.

    final summary = DashboardSummary(
      teachersAbsentCount: 0, // Needs leave logic
      unassignedBellsCount: 0, // Needs timetable logic
      totalStudents: totalStudents,
      presentToday: 0,
      leaveToday: 0,
      absentToday: 0,
      updatedAt: DateTime.now(),
    );

    await _summaryDoc(schoolId).set(summary.toJson());
    return summary;
  }
}

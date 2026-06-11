import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/expense.dart';
import 'auth_service.dart';
import 'base_firestore_service.dart';
import 'audit_log_service.dart';

class ExpenseService extends BaseFirestoreService {
  static final ExpenseService _instance = ExpenseService._();
  ExpenseService._();
  factory ExpenseService() => _instance;

  String get _sid => AuthService.currentSchoolId;

  CollectionReference<Map<String, dynamic>> get _expenses =>
      schoolCollection(_sid, 'expenses');

  Future<void> addExpense(Expense expense) async {
    final docRef = _expenses.doc();
    final data = expense.toJson();
    await docRef.set(data);
    
    AuditService.emit(
      action: 'create',
      entity: 'expense',
      entityId: docRef.id,
      after: data,
    );
  }

  Future<void> deleteExpense(String id) async {
    final prev = await _expenses.doc(id).get();
    final before = prev.exists && prev.data() != null 
        ? Map<String, dynamic>.from(prev.data()!) 
        : null;
    await _expenses.doc(id).delete();
    
    AuditService.emit(
      action: 'delete',
      entity: 'expense',
      entityId: id,
      before: before,
    );
  }

  Stream<List<Expense>> watchExpenses() {
    return _expenses
        .orderBy('expenseDate', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => Expense.fromDoc(d.id, Map<String, dynamic>.from(d.data() as Map)))
            .toList());
  }

  Future<List<Expense>> getExpenses({DateTime? start, DateTime? end}) async {
    Query<Map<String, dynamic>> q = _expenses;
    
    // We can do client side filtering or compound queries. To avoid composite index requirements, 
    // we fetch and filter if both start/end are provided, or do simple query if none.
    final snap = await q.orderBy('expenseDate', descending: true).get();
    
    var list = snap.docs
        .map((d) => Expense.fromDoc(d.id, Map<String, dynamic>.from(d.data() as Map)))
        .toList();

    if (start != null) {
      list = list.where((e) => !e.expenseDate.isBefore(start)).toList();
    }
    if (end != null) {
      list = list.where((e) => !e.expenseDate.isAfter(end)).toList();
    }
    
    return list;
  }
}

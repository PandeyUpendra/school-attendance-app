import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/lead.dart';
import 'auth_service.dart';
import 'base_firestore_service.dart';
import 'audit_log_service.dart';

class LeadService extends BaseFirestoreService {
  static final LeadService _instance = LeadService._();
  LeadService._();
  factory LeadService() => _instance;

  String get _sid => AuthService.currentSchoolId;

  CollectionReference<Map<String, dynamic>> get _leads =>
      schoolCollection(_sid, 'leads');

  Future<void> addLead(Lead lead) async {
    final docRef = _leads.doc();
    final data = lead.copyWith(
      id: docRef.id,
      schoolId: _sid,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ).toJson();

    await docRef.set(data);

    AuditService.emit(
      action: 'create',
      entity: 'lead',
      entityId: docRef.id,
      after: data,
    );
  }

  Future<void> updateLeadStage(String id, String stage) async {
    final prev = await _leads.doc(id).get();
    final before = prev.exists && prev.data() != null 
        ? Map<String, dynamic>.from(prev.data()!) 
        : null;

    final updateData = {
      'stage': stage,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await _leads.doc(id).update(updateData);

    AuditService.emit(
      action: 'update',
      entity: 'lead',
      entityId: id,
      before: before,
      after: {
        if (before != null) ...before,
        ...updateData,
      },
      reason: 'stage_change',
    );
  }

  Future<void> updateLeadNote(String id, String note) async {
    final prev = await _leads.doc(id).get();
    final before = prev.exists && prev.data() != null 
        ? Map<String, dynamic>.from(prev.data()!) 
        : null;

    final updateData = {
      'note': note,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await _leads.doc(id).update(updateData);

    AuditService.emit(
      action: 'update',
      entity: 'lead',
      entityId: id,
      before: before,
      after: {
        if (before != null) ...before,
        ...updateData,
      },
      reason: 'note_update',
    );
  }

  Future<void> deleteLead(String id) async {
    final prev = await _leads.doc(id).get();
    final before = prev.exists && prev.data() != null 
        ? Map<String, dynamic>.from(prev.data()!) 
        : null;

    await _leads.doc(id).delete();

    AuditService.emit(
      action: 'delete',
      entity: 'lead',
      entityId: id,
      before: before,
    );
  }

  Stream<List<Lead>> watchLeads() {
    return _leads
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => Lead.fromJson(Map<String, dynamic>.from(d.data())))
            .toList());
  }
}

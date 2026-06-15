import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/transport_route.dart';
import 'auth_service.dart';
import 'base_firestore_service.dart';
import 'audit_log_service.dart';

class TransportService extends BaseFirestoreService {
  static final TransportService _instance = TransportService._();
  TransportService._();
  factory TransportService() => _instance;

  static TransportService get instance => _instance;

  String get _sid => AuthService.currentSchoolId;

  CollectionReference<Map<String, dynamic>> get _routes =>
      schoolCollection(_sid, 'routes');

  Future<void> addRoute(TransportRoute route) async {
    final docRef = _routes.doc();
    final data = route.copyWith(
      id: docRef.id,
      schoolId: _sid,
      lastUpdated: DateTime.now(),
    ).toJson();

    await docRef.set(data);

    AuditService.emit(
      action: 'create',
      entity: 'transport_route',
      entityId: docRef.id,
      after: data,
    );
  }

  Future<void> updateRouteStatus(String routeId, {required bool isActive, required int currentStopIndex}) async {
    final prev = await _routes.doc(routeId).get();
    final before = prev.exists && prev.data() != null 
        ? Map<String, dynamic>.from(prev.data()!) 
        : null;

    final updateData = {
      'isActive': isActive,
      'currentStopIndex': currentStopIndex,
      'lastUpdated': FieldValue.serverTimestamp(),
    };

    await _routes.doc(routeId).update(updateData);

    AuditService.emit(
      action: 'update',
      entity: 'transport_route',
      entityId: routeId,
      before: before,
      after: {
        if (before != null) ...before,
        ...updateData,
      },
      reason: 'route_status_change',
    );
  }

  Future<void> updateRouteDetails(TransportRoute route) async {
    final prev = await _routes.doc(route.id).get();
    final before = prev.exists && prev.data() != null 
        ? Map<String, dynamic>.from(prev.data()!) 
        : null;

    final updateData = route.copyWith(
      lastUpdated: DateTime.now(),
    ).toJson();

    await _routes.doc(route.id).set(updateData);

    AuditService.emit(
      action: 'update',
      entity: 'transport_route',
      entityId: route.id,
      before: before,
      after: updateData,
    );
  }

  Future<void> deleteRoute(String routeId) async {
    final prev = await _routes.doc(routeId).get();
    final before = prev.exists && prev.data() != null 
        ? Map<String, dynamic>.from(prev.data()!) 
        : null;

    await _routes.doc(routeId).delete();

    AuditService.emit(
      action: 'delete',
      entity: 'transport_route',
      entityId: routeId,
      before: before,
    );
  }

  Stream<TransportRoute?> watchRoute(String routeId) {
    if (routeId.isEmpty) return Stream.value(null);
    return _routes.doc(routeId).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return TransportRoute.fromJson(Map<String, dynamic>.from(doc.data()!));
    });
  }

  Stream<List<TransportRoute>> watchAllRoutes() {
    return _routes.snapshots().map((snap) {
      return snap.docs
          .map((doc) => TransportRoute.fromJson(Map<String, dynamic>.from(doc.data())))
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    });
  }

  Future<List<TransportRoute>> getAllRoutes() async {
    final snap = await _routes.get();
    return snap.docs
        .map((doc) => TransportRoute.fromJson(Map<String, dynamic>.from(doc.data())))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }
}

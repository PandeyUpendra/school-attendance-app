import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:school_app/models/transport_route.dart';
import 'package:school_app/services/base_firestore_service.dart';
import 'package:school_app/services/transport_service.dart';

void main() {
  late FakeFirebaseFirestore fakeDb;
  late TransportService service;

  setUp(() {
    fakeDb = FakeFirebaseFirestore();
    BaseFirestoreService.mockDb = fakeDb;
    BaseFirestoreService.currentSchoolId = 'test_school';
    service = TransportService();
  });

  tearDown(() {
    BaseFirestoreService.mockDb = null;
    BaseFirestoreService.currentSchoolId = null;
  });

  group('TransportService Tests', () {
    test('addRoute and watchAllRoutes works correctly', () async {
      final route = TransportRoute(
        id: '',
        schoolId: 'test_school',
        name: 'Route 101',
        driverName: 'John Doe',
        driverPhone: '1234567890',
        isActive: false,
        currentStopIndex: -1,
        lastUpdated: DateTime.now(),
        stops: const [
          TransportStop(name: 'Stop A', expectedTime: '07:00 AM', sequence: 1),
          TransportStop(name: 'Stop B', expectedTime: '07:30 AM', sequence: 2),
        ],
      );

      await service.addRoute(route);

      final routes = await service.watchAllRoutes().first;
      expect(routes.length, 1);
      expect(routes.first.name, 'Route 101');
      expect(routes.first.stops.length, 2);
      expect(routes.first.stops.first.name, 'Stop A');
    });

    test('updateRouteStatus modifies transit progress', () async {
      final route = TransportRoute(
        id: 'route_id_1',
        schoolId: 'test_school',
        name: 'Route 102',
        driverName: 'Jane Smith',
        driverPhone: '9876543210',
        isActive: false,
        currentStopIndex: -1,
        lastUpdated: DateTime.now(),
        stops: const [
          TransportStop(name: 'Stop X', expectedTime: '08:00 AM', sequence: 1),
        ],
      );

      await fakeDb
          .collection('schools')
          .doc('test_school')
          .collection('routes')
          .doc('route_id_1')
          .set(route.toJson());

      await service.updateRouteStatus('route_id_1', isActive: true, currentStopIndex: 0);

      final updatedRoute = await service.watchRoute('route_id_1').first;
      expect(updatedRoute, isNotNull);
      expect(updatedRoute!.isActive, isTrue);
      expect(updatedRoute.currentStopIndex, 0);
    });

    test('deleteRoute removes it from database', () async {
      final route = TransportRoute(
        id: 'route_id_2',
        schoolId: 'test_school',
        name: 'Route 103',
        driverName: 'Alex Mercer',
        driverPhone: '5555555555',
        isActive: false,
        currentStopIndex: -1,
        lastUpdated: DateTime.now(),
        stops: const [],
      );

      await fakeDb
          .collection('schools')
          .doc('test_school')
          .collection('routes')
          .doc('route_id_2')
          .set(route.toJson());

      await service.deleteRoute('route_id_2');

      final routes = await service.watchAllRoutes().first;
      expect(routes, isEmpty);
    });
  });
}

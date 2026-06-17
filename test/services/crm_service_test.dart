import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:school_app/models/lead.dart';
import 'package:school_app/services/base_firestore_service.dart';
import 'package:school_app/services/lead_service.dart';

void main() {
  late FakeFirebaseFirestore fakeDb;
  late LeadService service;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    fakeDb = FakeFirebaseFirestore();
    BaseFirestoreService.mockDb = fakeDb;
    BaseFirestoreService.currentSchoolId = 'test_school';
    service = LeadService();
  });

  tearDown(() {
    BaseFirestoreService.mockDb = null;
    BaseFirestoreService.currentSchoolId = null;
  });

  group('LeadService CRM Tests', () {
    test('addLead and watchLeads works correctly', () async {
      final lead = Lead(
        id: '',
        studentName: 'Alice Johnson',
        className: 'Class 5',
        parentName: 'Robert Johnson',
        parentPhone: '1112223333',
        parentEmail: 'robert@example.com',
        stage: 'Inquiry',
        note: 'Interested in sports facilities',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        schoolId: '',
      );

      await service.addLead(lead);

      final leads = await service.watchLeads().first;
      expect(leads.length, 1);
      expect(leads.first.studentName, 'Alice Johnson');
      expect(leads.first.stage, 'Inquiry');
    });

    test('updateLeadStage moves lead through funnel', () async {
      final lead = Lead(
        id: 'lead_id_1',
        studentName: 'Bob Smith',
        className: 'Class 6',
        parentName: 'Sarah Smith',
        parentPhone: '4445556666',
        parentEmail: 'sarah@example.com',
        stage: 'Inquiry',
        note: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        schoolId: 'test_school',
      );

      await fakeDb
          .collection('schools')
          .doc('test_school')
          .collection('leads')
          .doc('lead_id_1')
          .set(lead.toJson());

      await service.updateLeadStage('lead_id_1', 'Visit');

      final leads = await service.watchLeads().first;
      expect(leads.first.stage, 'Visit');
    });

    test('deleteLead removes lead from pipeline', () async {
      final lead = Lead(
        id: 'lead_id_2',
        studentName: 'Charlie Brown',
        className: 'Class 4',
        parentName: 'Sally Brown',
        parentPhone: '7778889999',
        parentEmail: 'sally@example.com',
        stage: 'Visit',
        note: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        schoolId: 'test_school',
      );

      await fakeDb
          .collection('schools')
          .doc('test_school')
          .collection('leads')
          .doc('lead_id_2')
          .set(lead.toJson());

      await service.deleteLead('lead_id_2');

      final leads = await service.watchLeads().first;
      expect(leads, isEmpty);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:school_app/models/syllabus.dart';
import 'package:school_app/services/base_firestore_service.dart';
import 'package:school_app/services/syllabus_service.dart';

void main() {
  late FakeFirebaseFirestore fakeDb;
  late SyllabusService service;

  setUp(() {
    fakeDb = FakeFirebaseFirestore();
    BaseFirestoreService.mockDb = fakeDb;
    BaseFirestoreService.currentSchoolId = 'test_school';
    service = SyllabusService();
  });

  tearDown(() {
    BaseFirestoreService.mockDb = null;
    BaseFirestoreService.currentSchoolId = null;
  });

  group('SyllabusService Tests', () {
    test('getTemplate returns default template if none exists in DB', () async {
      final template = await service.getTemplate('Class 9-A', 'Mathematics');
      expect(template.className, 'Class 9-A');
      expect(template.subject, 'Mathematics');
      expect(template.chapters, isNotEmpty);
      expect(template.chapters.first.name, 'Real Numbers');
    });

    test('saveTemplate and getTemplate persist template details', () async {
      final template = SyllabusTemplate(
        id: 'Class_9-A_Math',
        className: 'Class 9-A',
        subject: 'Math',
        chapters: [
          SyllabusChapter(id: 'ch1', name: 'Intro', topics: ['Topic A']),
        ],
      );

      await service.saveTemplate(template);

      final fetched = await service.getTemplate('Class 9-A', 'Math');
      expect(fetched.className, 'Class 9-A');
      expect(fetched.subject, 'Math');
      expect(fetched.chapters.length, 1);
      expect(fetched.chapters.first.name, 'Intro');
    });

    test('getCoverage returns empty coverage if none exists', () async {
      final coverage = await service.getCoverage('Class 9-A', 'Science');
      expect(coverage.completedChapterIds, isEmpty);
      expect(coverage.className, 'Class 9-A');
      expect(coverage.subject, 'Science');
    });

    test('saveCoverage and getCoverage persist coverage details', () async {
      final coverage = SyllabusCoverage(
        id: 'Class_9-A_Science',
        className: 'Class 9-A',
        subject: 'Science',
        completedChapterIds: ['ch1', 'ch2'],
        lastUpdatedBy: 'teacher_1',
      );

      await service.saveCoverage(coverage);

      final fetched = await service.getCoverage('Class 9-A', 'Science');
      expect(fetched.completedChapterIds, containsAll(['ch1', 'ch2']));
      expect(fetched.lastUpdatedBy, 'teacher_1');
    });

    test('watchCoverage emits new coverage records', () async {
      final stream = service.watchCoverage('Class 9-A', 'English');
      
      expect(
        stream,
        emitsInOrder([
          isA<SyllabusCoverage>().having((c) => c.completedChapterIds, 'completedChapterIds', isEmpty),
          isA<SyllabusCoverage>().having((c) => c.completedChapterIds, 'completedChapterIds', ['ch1']),
        ]),
      );

      // Trigger second emission by saving coverage
      final coverage = SyllabusCoverage(
        id: 'Class_9-A_English',
        className: 'Class 9-A',
        subject: 'English',
        completedChapterIds: ['ch1'],
        lastUpdatedBy: 'teacher_1',
      );
      
      // We wait a tiny bit to let the stream listener register
      await Future.delayed(const Duration(milliseconds: 50));
      await service.saveCoverage(coverage);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:school_app/models/homework.dart';
import 'package:school_app/models/announcement.dart';
import 'package:school_app/services/homework_service.dart';
import 'package:school_app/services/announcement_service.dart';

void main() {
  group('Homework description validation', () {
    test('throws ArgumentError when description exceeds 1000 characters', () {
      final longDescription = 'A' * 1001;
      final hw = Homework(
        id: '1',
        teacherId: 'teacher@test.com',
        teacherName: 'Teacher',
        className: 'Class 6',
        subject: 'Math',
        title: 'Title',
        description: longDescription,
        dueDate: DateTime.now().add(const Duration(days: 1)),
        postedAt: DateTime.now(),
      );

      expect(
        () => HomeworkService().postHomework('school_1', hw),
        throwsArgumentError,
      );
    });

    test('does not throw ArgumentError when description is within limit (fails on Firebase)', () async {
      final hw = Homework(
        id: '1',
        teacherId: 'teacher@test.com',
        teacherName: 'Teacher',
        className: 'Class 6',
        subject: 'Math',
        title: 'Title',
        description: 'Under limit',
        dueDate: DateTime.now().add(const Duration(days: 1)),
        postedAt: DateTime.now(),
      );

      try {
        await HomeworkService().postHomework('school_1', hw);
      } catch (e) {
        // Firebase is not initialized, so it should throw a Firebase exception, not an ArgumentError
        expect(e, isNot(isA<ArgumentError>()));
      }
    });
  });

  group('Announcement body validation', () {
    test('throws ArgumentError when body exceeds 1000 characters', () {
      final longBody = 'A' * 1001;
      final ann = Announcement(
        id: '1',
        title: 'Title',
        body: longBody,
        postedBy: 'Teacher',
        postedByRole: 'teacher',
        audience: 'all',
        isPinned: false,
      );

      expect(
        () => AnnouncementService().postAnnouncement(ann),
        throwsArgumentError,
      );
    });

    test('does not throw ArgumentError when body is within limit (fails on Firebase)', () async {
      const ann = Announcement(
        id: '1',
        title: 'Title',
        body: 'Under limit',
        postedBy: 'Teacher',
        postedByRole: 'teacher',
        audience: 'all',
        isPinned: false,
      );

      try {
        await AnnouncementService().postAnnouncement(ann);
      } catch (e) {
        // Firebase is not initialized, so it should throw a Firebase exception, not an ArgumentError
        expect(e, isNot(isA<ArgumentError>()));
      }
    });
  });
}

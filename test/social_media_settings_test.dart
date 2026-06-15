import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:school_app/services/base_firestore_service.dart';
import 'package:school_app/services/school_settings_service.dart';
import 'package:school_app/shared/providers/school_settings_provider.dart';

void main() {
  late FakeFirebaseFirestore fakeDb;

  setUp(() {
    fakeDb = FakeFirebaseFirestore();
    BaseFirestoreService.mockDb = fakeDb;
    BaseFirestoreService.currentSchoolId = 'test_school';
  });

  tearDown(() {
    BaseFirestoreService.mockDb = null;
    BaseFirestoreService.currentSchoolId = null;
  });

  group('SchoolSettingsProvider Social Media Tests', () {
    test('retrieves social media links correctly when set', () async {
      await fakeDb
          .collection('schools')
          .doc('test_school')
          .collection('settings')
          .doc('school')
          .set({
            'schoolName': 'Test School',
            'facebookUrl': 'https://facebook.com/test',
            'instagramUrl': 'https://instagram.com/test',
            'twitterUrl': 'https://twitter.com/test',
            'youtubeUrl': 'https://youtube.com/test',
            'linkedinUrl': 'https://linkedin.com/test',
          });

      final provider = SchoolSettingsProvider();

      // Wait for stream updates to propagate
      await Future.delayed(const Duration(milliseconds: 100));

      expect(provider.facebookUrl, 'https://facebook.com/test');
      expect(provider.instagramUrl, 'https://instagram.com/test');
      expect(provider.twitterUrl, 'https://twitter.com/test');
      expect(provider.youtubeUrl, 'https://youtube.com/test');
      expect(provider.linkedinUrl, 'https://linkedin.com/test');
    });

    test('returns empty string when social media links are not set', () async {
      await fakeDb
          .collection('schools')
          .doc('test_school')
          .collection('settings')
          .doc('school')
          .set({
            'schoolName': 'Test School',
          });

      final provider = SchoolSettingsProvider();

      await Future.delayed(const Duration(milliseconds: 100));

      expect(provider.facebookUrl, '');
      expect(provider.instagramUrl, '');
      expect(provider.twitterUrl, '');
      expect(provider.youtubeUrl, '');
      expect(provider.linkedinUrl, '');
    });
  });
}

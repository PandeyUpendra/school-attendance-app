import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:school_app/models/copy_check.dart';

void main() {
  group('CopyCheck Model Serialization', () {
    final date = DateTime(2026, 6, 9);

    test('fromDoc handles missing pendingCount and totalCount (legacy compat)', () {
      final docData = {
        'teacherId': 't1',
        'teacherName': 'Mr. Smith',
        'className': 'Class 6',
        'section': 'A',
        'subject': 'Math',
        'checkDate': Timestamp.fromDate(date),
        'createdAt': Timestamp.fromDate(date),
      };

      final check = CopyCheck.fromDoc('doc123', docData);

      expect(check.id, 'doc123');
      expect(check.teacherId, 't1');
      expect(check.className, 'Class 6');
      expect(check.section, 'A');
      expect(check.pendingCount, isNull);
      expect(check.totalCount, isNull);
    });

    test('fromDoc parses pendingCount and totalCount when present', () {
      final docData = {
        'teacherId': 't1',
        'teacherName': 'Mr. Smith',
        'className': 'Class 6',
        'section': 'A',
        'subject': 'Math',
        'checkDate': Timestamp.fromDate(date),
        'createdAt': Timestamp.fromDate(date),
        'pendingCount': 5,
        'totalCount': 25,
      };

      final check = CopyCheck.fromDoc('doc123', docData);

      expect(check.id, 'doc123');
      expect(check.pendingCount, 5);
      expect(check.totalCount, 25);
    });

    test('toJson excludes pendingCount and totalCount when they are null', () {
      final check = CopyCheck(
        id: 'doc123',
        teacherId: 't1',
        teacherName: 'Mr. Smith',
        className: 'Class 6',
        section: 'A',
        subject: 'Math',
        checkDate: date,
        createdAt: date,
      );

      final json = check.toJson();

      expect(json.containsKey('pendingCount'), isFalse);
      expect(json.containsKey('totalCount'), isFalse);
      expect(json['className'], 'Class 6');
    });

    test('toJson includes pendingCount and totalCount when they are non-null', () {
      final check = CopyCheck(
        id: 'doc123',
        teacherId: 't1',
        teacherName: 'Mr. Smith',
        className: 'Class 6',
        section: 'A',
        subject: 'Math',
        checkDate: date,
        createdAt: date,
        pendingCount: 4,
        totalCount: 30,
      );

      final json = check.toJson();

      expect(json['pendingCount'], 4);
      expect(json['totalCount'], 30);
    });
  });

  group('CopyStatus Aggregation Logic', () {
    test('aggregates pending statuses correctly', () {
      final list = [
        const CopyStatus(roll: 1, studentName: 'Alice', guardianPhone: '123', status: 'checked'),
        const CopyStatus(roll: 2, studentName: 'Bob', guardianPhone: '456', status: 'incomplete'),
        const CopyStatus(roll: 3, studentName: 'Charlie', guardianPhone: '789', status: 'not_done'),
        const CopyStatus(roll: 4, studentName: 'Dave', guardianPhone: '012', status: 'checked'),
      ];

      final pendingCount = list
          .where((s) => s.status == 'incomplete' || s.status == 'not_done')
          .length;
      final totalCount = list.length;

      expect(pendingCount, 2);
      expect(totalCount, 4);
    });
  });
}

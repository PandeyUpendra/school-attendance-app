import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:school_app/services/offline_queue_service.dart';
import 'package:school_app/services/student_service.dart';
import 'package:school_app/services/base_firestore_service.dart';

class MockStudentService extends Mock implements StudentService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockStudentService mockStudentService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BaseFirestoreService.currentSchoolId = 'test_school';
    mockStudentService = MockStudentService();
    StudentService.mockInstance = mockStudentService;
  });

  tearDown(() {
    BaseFirestoreService.currentSchoolId = null;
    StudentService.mockInstance = null;
  });

  test('Attendance Load Test - 50 teachers marking 50 students', () async {
    final stopwatch = Stopwatch()..start();

    // 1. Stub the student service to resolve instantly
    when(() => mockStudentService.saveAttendanceForDate(
          className: any(named: 'className'),
          attendance: any(named: 'attendance'),
          date: any(named: 'date'),
        )).thenAnswer((_) async {});

    // 2. Simulate 50 concurrent teachers enqueuing attendance
    final enqueueFutures = List.generate(50, (teacherIndex) async {
      final className = 'Class 9-$teacherIndex';
      final attendance = <int, String>{};
      for (int roll = 1; roll <= 50; roll++) {
        attendance[roll] = roll % 10 == 0 ? 'Absent' : 'Present';
      }

      await OfflineQueueService().enqueue(
        className: className,
        attendance: attendance,
      );
    });

    await Future.wait(enqueueFutures);
    final enqueueTime = stopwatch.elapsedMilliseconds;
    print('Enqueue latency for 50 classes (2500 students total): ${enqueueTime}ms');

    // 3. Verify queue size is 50
    final count = await OfflineQueueService().pendingCount();
    expect(count, 50);

    // 4. Measure sync time
    stopwatch.reset();
    stopwatch.start();

    final syncedCount = await OfflineQueueService().syncAll();

    stopwatch.stop();
    final syncTime = stopwatch.elapsedMilliseconds;
    print('Sync latency for 50 classes (2500 students total): ${syncTime}ms');

    expect(syncedCount, 50);

    // Verify queue is now empty
    final newCount = await OfflineQueueService().pendingCount();
    expect(newCount, 0);

    // Assert that the sync completion is fast (e.g. less than 500ms)
    expect(syncTime, lessThan(500));
  });
}

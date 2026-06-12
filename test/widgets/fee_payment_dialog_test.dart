import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:school_app/features/fees/fee_collection_screen.dart';
import 'package:school_app/models/student.dart';
import 'package:school_app/models/fee.dart';
import 'package:school_app/services/student_service.dart';
import 'package:school_app/services/timetable_service.dart';
import 'package:school_app/services/fee_service.dart';
import 'package:school_app/services/base_firestore_service.dart';
import 'package:school_app/shared/providers/locale_provider.dart';

// ── Mocks ────────────────────────────────────────────────────────────────────

class MockStudentService extends Mock implements StudentService {}
class MockTimetableService extends Mock implements TimetableService {}
class MockFeeService extends Mock implements FeeService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockStudentService mockStudentService;
  late MockTimetableService mockTimetableService;
  late MockFeeService mockFeeService;

  setUpAll(() {
    registerFallbackValue(DateTime.now());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BaseFirestoreService.currentSchoolId = 'test_school';
    mockStudentService = MockStudentService();
    mockTimetableService = MockTimetableService();
    mockFeeService = MockFeeService();

    StudentService.mockInstance = mockStudentService;
    TimetableService.mockInstance = mockTimetableService;
    FeeService.mockInstance = mockFeeService;
  });

  tearDown(() {
    BaseFirestoreService.currentSchoolId = null;
    StudentService.mockInstance = null;
    TimetableService.mockInstance = null;
    FeeService.mockInstance = null;
  });

  Widget createScreen() {
    return ChangeNotifierProvider(
      create: (_) => LocaleProvider('en'),
      child: const MaterialApp(
        home: FeeCollectionScreen(initialClass: 'Class 9-A'),
      ),
    );
  }

  group('FeeCollectionScreen & Payment BottomSheet Tests', () {
    final student = Student(
      roll: 1,
      name: 'Alice',
      className: 'Class 9-A',
      section: 'A',
      guardianEmail: 'alice@guardian.com',
    );

    final structure = FeeStructure(
      className: 'Class 9-A',
      totalAnnualFee: 5000.0,
      components: [],
      installments: [
        FeeInstallment(name: 'Term 1', amount: 2000.0, dueDate: DateTime(2026, 4, 1)),
        FeeInstallment(name: 'Term 2', amount: 3000.0, dueDate: DateTime(2026, 8, 1)),
      ],
    );

    testWidgets('Loads fee overview and opens record payment sheet', (WidgetTester tester) async {
      // 1. Stub settings, students, structures, and overview
      when(() => mockTimetableService.getSettings())
          .thenAnswer((_) async => {'classes': ['Class 9-A']});

      when(() => mockStudentService.getStudentsByClass(className: 'Class 9-A'))
          .thenAnswer((_) async => [student]);

      when(() => mockFeeService.getFeeStructure(className: 'Class 9-A'))
          .thenAnswer((_) async => structure);

      when(() => mockFeeService.getClassFeeOverview(className: 'Class 9-A', rolls: [1]))
          .thenAnswer((_) async => {1: 1500.0}); // Paid 1500 out of 5000

      when(() => mockFeeService.getPayments(
            className: any(named: 'className'),
            roll: any(named: 'roll'),
            includeReversed: any(named: 'includeReversed'),
          )).thenAnswer((_) async => [
                Payment(
                  id: 'p1',
                  amount: 1500.0,
                  paidOn: DateTime.now(),
                  mode: 'Cash',
                  receiptNo: 'REC-001',
                  reversed: false,
                )
              ]);

      when(() => mockFeeService.getInstallmentPaidAmounts(
            className: any(named: 'className'),
            roll: any(named: 'roll'),
          )).thenAnswer((_) async => <String, double>{});

      // Pump Screen
      await tester.pumpWidget(createScreen());
      await tester.pumpAndSettle();

      // Verify page title and list contains student
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Roll 1  •  Paid ₹1,500  •  Due ₹3,500'), findsOneWidget);

      // Tap student to open Student Fee Detail Screen
      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();

      expect(find.text('₹3,500'), findsWidgets);

      // Tap "Record Payment" button to open BottomSheet
      await tester.tap(find.text('Record Payment'));
      await tester.pumpAndSettle();

      // Verify the bottom sheet opened
      expect(find.text('Record Payment — Alice'), findsOneWidget);
      expect(find.text('Outstanding Due: ₹3,500'), findsOneWidget);

      // Verify invalid amount validation
      await tester.enterText(find.byType(TextFormField).first, '4000'); // > 3500 due
      await tester.pump();

      await tester.tap(find.text('Save Payment'));
      await tester.pumpAndSettle();

      expect(find.text('Cannot exceed outstanding due of ₹3,500'), findsOneWidget);
    });
  });
}

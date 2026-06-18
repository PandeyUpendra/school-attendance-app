import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:school_app/features/copy_check/copy_check_overview_screen.dart';
import 'package:school_app/models/copy_check.dart';
import 'package:school_app/services/timetable_service.dart';
import 'package:school_app/services/copy_check_service.dart';
import 'package:school_app/shared/providers/locale_provider.dart';

class MockTimetableService extends Mock implements TimetableService {}
class MockCopyCheckService extends Mock implements CopyCheckService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockTimetableService mockTimetableService;
  late MockCopyCheckService mockCopyCheckService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockTimetableService = MockTimetableService();
    mockCopyCheckService = MockCopyCheckService();

    TimetableService.mockInstance = mockTimetableService;
    CopyCheckService.mockInstance = mockCopyCheckService;
  });

  tearDown(() {
    TimetableService.mockInstance = null;
    CopyCheckService.mockInstance = null;
  });

  Widget createWidget() {
    return ChangeNotifierProvider(
      create: (_) => LocaleProvider('en'),
      child: const MaterialApp(
        home: CopyCheckOverviewScreen(),
      ),
    );
  }

  testWidgets('CopyCheckOverviewScreen displays class chips and allows swiping', (WidgetTester tester) async {
    // Stub timetable settings to return 3 classes
    when(() => mockTimetableService.getSettings()).thenAnswer((_) async => {
          'classes': ['Pre-Nursery-A', 'Nursery-A', 'LKG-A'],
        });

    // Stub copy checks retrieval for each class
    when(() => mockCopyCheckService.getAllChecks(className: 'Pre-Nursery-A'))
        .thenAnswer((_) async => []);
    when(() => mockCopyCheckService.getAllChecks(className: 'Nursery-A'))
        .thenAnswer((_) async => [
              CopyCheck(
                id: 'chk_1',
                teacherId: 't1',
                teacherName: 'Teacher A',
                className: 'Nursery-A',
                section: 'A',
                subject: 'English',
                checkDate: DateTime.now(),
                createdAt: DateTime.now(),
              )
            ]);
    when(() => mockCopyCheckService.getAllChecks(className: 'LKG-A'))
        .thenAnswer((_) async => []);

    // Build the widget tree
    await tester.pumpWidget(createWidget());

    // Allow initial load to finish
    await tester.pumpAndSettle();

    // Verify chips are displayed
    expect(find.text('Pre-Nursery-A'), findsOneWidget);
    expect(find.text('Nursery-A'), findsOneWidget);
    expect(find.text('LKG-A'), findsOneWidget);

    // Initial selected class chip should be Pre-Nursery-A
    // Since there are no checks for Pre-Nursery-A, it should show 'No copy-checking sessions for this class yet.'
    expect(find.text('No copy-checking sessions\nfor this class yet.'), findsOneWidget);

    // Swipe left (to the next page: Nursery-A)
    // Fling with a larger offset to ensure the page transition threshold is crossed
    await tester.fling(find.byType(PageView), const Offset(-600, 0), 3000);
    await tester.pumpAndSettle();
    await tester.pump();

    // Verify Nursery-A session details are now visible
    expect(find.textContaining('English'), findsOneWidget);
    expect(find.textContaining('Teacher A'), findsOneWidget);

    // Verify ChoiceChip for Nursery-A is selected
    final ChoiceChip nurseryChip = tester.widget(
      find.ancestor(
        of: find.text('Nursery-A'),
        matching: find.byType(ChoiceChip),
      ),
    );
    expect(nurseryChip.selected, isTrue);

    // Tap on LKG-A chip
    await tester.tap(find.text('LKG-A'));
    await tester.pumpAndSettle();

    // Verify ChoiceChip for LKG-A is selected
    final ChoiceChip lkgChip = tester.widget(
      find.ancestor(
        of: find.text('LKG-A'),
        matching: find.byType(ChoiceChip),
      ),
    );
    expect(lkgChip.selected, isTrue);
  });
}

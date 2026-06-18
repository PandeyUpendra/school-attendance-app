import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:school_app/shared/utils/csv_export.dart';
import 'package:school_app/shared/utils/pdf_branding_helper.dart';

void main() {
  const MethodChannel pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  const MethodChannel shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
  const MethodChannel shareChannelOld = MethodChannel('plugins.flutter.io/share');

  // A valid 1x1 PNG byte array to prevent image decoder exceptions
  final tinyPngBytes = Uint8List.fromList([
    137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82,
    0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137,
    0, 0, 0, 10, 73, 68, 65, 84, 120, 156, 99, 0, 1, 0, 0,
    5, 0, 1, 13, 10, 45, 180, 0, 0, 0, 0, 73, 69, 78, 68,
    174, 66, 96, 130
  ]);

  TestWidgetsFlutterBinding.ensureInitialized();

  String? sharedFilePath;
  final List<MethodCall> shareCalls = [];

  setUp(() {
    sharedFilePath = null;
    shareCalls.clear();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (MethodCall methodCall) async {
      if (methodCall.method == 'getTemporaryDirectory') {
        return Directory.systemTemp.path;
      }
      return null;
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, (MethodCall methodCall) async {
      shareCalls.add(methodCall);
      if (methodCall.arguments is Map) {
        final args = methodCall.arguments as Map;
        final paths = args['paths'] ?? args['tokens'] ?? args['paths'] ?? args['files'];
        if (paths is List && paths.isNotEmpty) {
          sharedFilePath = paths.first.toString();
        }
      } else if (methodCall.arguments is List) {
        final args = methodCall.arguments as List;
        if (args.isNotEmpty) {
          sharedFilePath = args.first.toString();
        }
      }
      return null;
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannelOld, (MethodCall methodCall) async {
      shareCalls.add(methodCall);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannelOld, null);
  });

  group('PdfBrandingHelper Tests', () {
    test('PdfBrandingData structures parameters correctly', () {
      final dummyLogo = pw.MemoryImage(tinyPngBytes);
      final data = PdfBrandingData(
        schoolName: 'Branded Academy',
        schoolLogo: dummyLogo,
        appLogo: dummyLogo,
      );

      expect(data.schoolName, 'Branded Academy');
      expect(data.appName, 'Klassivo');
      expect(data.schoolLogo, dummyLogo);
      expect(data.appLogo, dummyLogo);
    });

    test('buildHeader builds widget tree without crashing and includes correct layout', () {
      final dummyLogo = pw.MemoryImage(tinyPngBytes);
      final data = PdfBrandingData(
        schoolName: 'Test School',
        schoolLogo: dummyLogo,
        appLogo: dummyLogo,
      );

      final widget = PdfBrandingHelper.buildHeader(data);
      expect(widget, isNotNull);
      expect(widget, isA<pw.Container>());

      final container = widget as pw.Container;
      expect(container.child, isA<pw.Column>());

      final column = container.child as pw.Column;
      // Should have: Row (header line), SizedBox, Container (divider line)
      expect(column.children.length, 3);
    });
  });

  group('CsvExport Branding Tests', () {
    test('share prepends app and school branding rows correctly', () async {
      final rows = [
        ['Roll', 'Name', 'Class'],
        [1, 'Alice', 'Class 6'],
        [2, 'Bob', 'Class 6'],
      ];

      final success = await CsvExport.share(
        filename: 'student_list',
        rows: rows,
        schoolName: 'Greenwood High',
        schoolLogo: 'https://logo.url/school.png',
      );

      expect(success, isTrue);
      expect(sharedFilePath, isNotNull);

      final file = File(sharedFilePath!);
      expect(await file.exists(), isTrue);

      final content = await file.readAsString();
      final lines = content.split('\n').map((l) => l.trim()).toList();

      // Verify branding headers
      expect(lines[0], contains('App Name,Klassivo,App Logo,assets/images/logo.png'));
      expect(lines[1], contains('School Name,Greenwood High,School Logo,https://logo.url/school.png'));
      expect(lines[2], isEmpty); // blank row separator
      expect(lines[3], contains('Roll,Name,Class'));
      expect(lines[4], contains('1,Alice,Class 6'));
    });

    test('shareRaw prepends app and school branding headers to content correctly', () async {
      const rawContent = 'Roll,Name,Class\n1,Alice,Class 6\n2,Bob,Class 6';

      final success = await CsvExport.shareRaw(
        filename: 'student_list_raw',
        content: rawContent,
        schoolName: 'Skyline Academy',
        schoolLogo: '',
      );

      expect(success, isTrue);
      expect(sharedFilePath, isNotNull);

      final file = File(sharedFilePath!);
      expect(await file.exists(), isTrue);

      final content = await file.readAsString();
      final lines = content.split('\n').map((l) => l.trim()).toList();

      // Verify branding headers
      expect(lines[0], contains('App Name,Klassivo,App Logo,assets/images/logo.png'));
      expect(lines[1], contains('School Name,"Skyline Academy",School Logo,N/A'));
      expect(lines[2], isEmpty); // blank row separator
      expect(lines[3], contains('Roll,Name,Class'));
      expect(lines[4], contains('1,Alice,Class 6'));
    });
  });
}

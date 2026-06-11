import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';

import '../../theme.dart';
import '../../l10n/app_strings.dart';
import '../../services/student_service.dart';
import '../../services/timetable_service.dart';
import '../../models/student.dart';
import '../../shared/utils/app_logger.dart';

class BulkStudentImportScreen extends StatefulWidget {
  const BulkStudentImportScreen({super.key});

  @override
  State<BulkStudentImportScreen> createState() => _BulkStudentImportScreenState();
}

class _ParsedRow {
  final int rowIndex;
  final Student? student;
  final String? error;
  final String rawName;
  final String rawClass;
  final String rawSection;
  final String rawRoll;

  _ParsedRow({
    required this.rowIndex,
    this.student,
    this.error,
    required this.rawName,
    required this.rawClass,
    required this.rawSection,
    required this.rawRoll,
  });

  bool get isValid => error == null && student != null;
}

class _BulkStudentImportScreenState extends State<BulkStudentImportScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  bool _loading = false;
  bool _validating = false;
  String? _fileName;
  List<_ParsedRow> _parsedRows = [];
  bool _assertConsent = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _pickAndParseFile() async {
    setState(() {
      _validating = true;
      _parsedRows = [];
      _fileName = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt'],
      );
      if (result == null || result.files.isEmpty) {
        setState(() => _validating = false);
        return;
      }

      final file = result.files.first;
      final path = file.path;
      if (path == null) {
        setState(() => _validating = false);
        return;
      }

      final content = await File(path).readAsString();
      List<List<dynamic>> csvRows;
      try {
        csvRows = const CsvToListConverter(eol: '\n').convert(content);
      } catch (_) {
        csvRows = const CsvToListConverter(eol: '\r\n').convert(content);
      }

      if (csvRows.isEmpty) {
        setState(() {
          _validating = false;
          _parsedRows = [
            _ParsedRow(
              rowIndex: 1,
              error: 'File is empty.',
              rawName: '', rawClass: '', rawSection: '', rawRoll: '',
            )
          ];
        });
        return;
      }

      // 1. Detect headers or use default column indices
      int dataStart = 0;
      Map<String, int> colMap = {};
      final firstRow = csvRows[0].map((e) => e.toString().trim().toLowerCase()).toList();
      bool hasHeader = firstRow.any((c) => ['roll', 'name', 'class', 'section'].any((k) => c.contains(k)));
      
      if (hasHeader) {
        dataStart = 1;
        final headers = ['class', 'section', 'roll', 'name', 'father', 'mother', 'phone', 'email', 'fee'];
        for (final h in headers) {
          final idx = firstRow.indexWhere((c) => c.contains(h));
          if (idx >= 0) colMap[h] = idx;
        }
      } else {
        // Default mapping if no header is found
        colMap['class'] = 0;
        colMap['section'] = 1;
        colMap['roll'] = 2;
        colMap['name'] = 3;
        colMap['father'] = 4;
        colMap['mother'] = 5;
        colMap['phone'] = 6;
        colMap['email'] = 7;
        colMap['fee'] = 8;
      }

      // 2. Fetch timetable settings to validate school classes
      final settings = await TimetableService.instance.getSettings();
      final List<String> schoolClasses = List<String>.from(settings['classes'] ?? [])
          .map((c) => c.trim().toLowerCase())
          .toList();

      // Helper function to extract columns from a row safely
      String get(List<dynamic> row, String key) {
        final idx = colMap[key];
        if (idx == null || idx >= row.length) return '';
        return row[idx].toString().trim();
      }

      final List<_ParsedRow> parsedList = [];
      final Set<String> csvSeenKeys = {}; // 'class_section_roll' to detect duplicates in CSV
      final List<Student> potentiallyValidStudents = [];

      // 3. Structural & CSV Duplicate check
      for (int i = dataStart; i < csvRows.length; i++) {
        final row = csvRows[i];
        if (row.isEmpty || (row.length == 1 && row[0].toString().trim().isEmpty)) {
          continue; // Skip blank lines
        }

        final rawClassName = get(row, 'class');
        final rawSection = get(row, 'section');
        final rawRoll = get(row, 'roll');
        final rawName = get(row, 'name');
        final rawFather = get(row, 'father');
        final rawMother = get(row, 'mother');
        final rawPhone = get(row, 'phone');
        final rawEmail = get(row, 'email');
        final rawFee = get(row, 'fee');

        final rowIndex = i + 1;

        if (rawClassName.isEmpty) {
          parsedList.add(_ParsedRow(
            rowIndex: rowIndex,
            error: 'Missing Class Name',
            rawName: rawName, rawClass: rawClassName, rawSection: rawSection, rawRoll: rawRoll,
          ));
          continue;
        }

        if (rawName.isEmpty) {
          parsedList.add(_ParsedRow(
            rowIndex: rowIndex,
            error: 'Missing student Name',
            rawName: rawName, rawClass: rawClassName, rawSection: rawSection, rawRoll: rawRoll,
          ));
          continue;
        }

        final roll = int.tryParse(rawRoll);
        if (roll == null || roll <= 0) {
          parsedList.add(_ParsedRow(
            rowIndex: rowIndex,
            error: 'Missing or invalid Roll number (must be a positive number)',
            rawName: rawName, rawClass: rawClassName, rawSection: rawSection, rawRoll: rawRoll,
          ));
          continue;
        }

        // Title-case normalization to match service layer formatting
        String toTitleCase(String text) {
          if (text.trim().isEmpty) return text;
          return text.trim().split(RegExp(r'\s+')).map((word) {
            if (word.isEmpty) return '';
            return word[0].toUpperCase() + word.substring(1).toLowerCase();
          }).join(' ');
        }

        final cleanClass = toTitleCase(rawClassName);
        final cleanSection = rawSection.trim().isEmpty ? 'A' : rawSection.trim().toUpperCase();

        // Warning/Error if class name does not exist in timetable settings
        if (schoolClasses.isNotEmpty && !schoolClasses.contains(cleanClass.toLowerCase())) {
          parsedList.add(_ParsedRow(
            rowIndex: rowIndex,
            error: 'Class "$cleanClass" does not exist in school settings.',
            rawName: rawName, rawClass: rawClassName, rawSection: rawSection, rawRoll: rawRoll,
          ));
          continue;
        }

        final csvKey = '${cleanClass}_${cleanSection}_$roll';
        if (csvSeenKeys.contains(csvKey)) {
          parsedList.add(_ParsedRow(
            rowIndex: rowIndex,
            error: 'Duplicate Roll number within this CSV file.',
            rawName: rawName, rawClass: rawClassName, rawSection: rawSection, rawRoll: rawRoll,
          ));
          continue;
        }
        csvSeenKeys.add(csvKey);

        final s = Student(
          id: '', // Generated in service
          roll: roll,
          name: rawName,
          className: cleanClass,
          section: cleanSection,
          fatherName: rawFather,
          motherName: rawMother.isNotEmpty ? rawMother : null,
          phone: rawPhone,
          guardianEmail: rawEmail.isNotEmpty ? rawEmail.toLowerCase().trim() : null,
          feeStatus: rawFee.isNotEmpty ? toTitleCase(rawFee) : 'Pending',
        );

        potentiallyValidStudents.add(s);
        // Temporarily store with null error; database check will run next
        parsedList.add(_ParsedRow(
          rowIndex: rowIndex,
          student: s,
          rawName: rawName, rawClass: rawClassName, rawSection: rawSection, rawRoll: rawRoll,
        ));
      }

      // 4. Database Duplication Check (in parallel across target class-sections)
      if (potentiallyValidStudents.isNotEmpty) {
        final targetClassSections = potentiallyValidStudents.map((s) => (s.className, s.section)).toSet();
        final Map<String, Set<int>> dbExistingRolls = {}; // 'class_section' -> rolls

        await Future.wait(targetClassSections.map((cs) async {
          final key = '${cs.$1}_${cs.$2}';
          try {
            final list = await StudentService.instance.getStudentsByClass(className: cs.$1, section: cs.$2);
            dbExistingRolls[key] = list.map((s) => s.roll).toSet();
          } catch (e) {
            AppLogger.e('BulkImport', 'Error checking rolls for $key: $e', e);
            dbExistingRolls[key] = {};
          }
        }));

        // Update parsedList rows with database collision errors
        for (int i = 0; i < parsedList.length; i++) {
          final row = parsedList[i];
          if (row.isValid) {
            final s = row.student!;
            final key = '${s.className}_${s.section}';
            final existing = dbExistingRolls[key];
            if (existing != null && existing.contains(s.roll)) {
              parsedList[i] = _ParsedRow(
                rowIndex: row.rowIndex,
                error: 'Roll number ${s.roll} already exists in database for ${s.className} Section ${s.section}.',
                rawName: row.rawName, rawClass: row.rawClass, rawSection: row.rawSection, rawRoll: row.rawRoll,
              );
            }
          }
        }
      }

      setState(() {
        _parsedRows = parsedList;
        _fileName = file.name;
        _validating = false;
        // Switch to the first tab (Valid) if there are valid items, else the second
        final validCount = _parsedRows.where((r) => r.isValid).length;
        _tabController.index = validCount > 0 ? 0 : 1;
      });

    } catch (e) {
      AppLogger.e('BulkImport', 'Parsing failed: $e', e);
      setState(() {
        _validating = false;
        _parsedRows = [
          _ParsedRow(
            rowIndex: 1,
            error: 'Failed to read file: $e',
            rawName: '', rawClass: '', rawSection: '', rawRoll: '',
          )
        ];
      });
    }
  }

  Future<void> _executeImport() async {
    final validStudents = _parsedRows.where((r) => r.isValid).map((r) => r.student!).toList();
    if (validStudents.isEmpty) return;

    setState(() => _loading = true);

    try {
      final results = await StudentService.instance.addStudentsBulk(
        students: validStudents,
        assertConsent: _assertConsent,
      );

      if (!mounted) return;
      setState(() => _loading = false);

      // Show summary alert dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.green, size: 28),
              const SizedBox(width: 10),
              Text(context.tr('done')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Successfully imported ${results['addedCount']} students.',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 12),
              if (results['skippedDbDuplicate'] > 0)
                Text('• Skipped ${results['skippedDbDuplicate']} rolls already in database.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              if (results['skippedCsvDuplicate'] > 0)
                Text('• Skipped ${results['skippedCsvDuplicate']} duplicate rows in file.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              if (results['skippedInvalid'] > 0)
                Text('• Skipped ${results['skippedInvalid']} invalid rows.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(_); // close dialog
                Navigator.pop(context); // go back to dashboard
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              child: const Text('Go to Dashboard', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    } catch (e) {
      AppLogger.e('BulkImport', 'Import failed: $e', e);
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $e'), backgroundColor: AppTheme.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final validRows = _parsedRows.where((r) => r.isValid).toList();
    final invalidRows = _parsedRows.where((r) => !r.isValid).toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Bulk Student CSV Import', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            if (_fileName != null)
              Text(_fileName!, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        bottom: _parsedRows.isNotEmpty
            ? TabBar(
                controller: _tabController,
                indicatorColor: Colors.white,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                tabs: [
                  Tab(text: 'Valid (${validRows.length})'),
                  Tab(text: 'Errors (${invalidRows.length})'),
                ],
              )
            : null,
      ),
      body: _loading || _validating
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: AppTheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    _validating ? 'Validating CSV roster…' : 'Writing records to database…',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
                  ),
                ],
              ),
            )
          : _parsedRows.isEmpty
              ? _buildFileSelector()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildValidTab(validRows),
                    _buildErrorsTab(invalidRows),
                  ],
                ),
      bottomNavigationBar: _parsedRows.isNotEmpty && validRows.isNotEmpty && !_loading && !_validating
          ? _buildBottomBar(validRows.length)
          : null,
    );
  }

  Widget _buildFileSelector() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.upload_file, size: 84, color: AppTheme.primary.withValues(alpha: 0.15)),
          const SizedBox(height: 24),
          const Text(
            'Upload Student Roster',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Upload a CSV file containing columns for Class, Section, Roll, and Name to import them into the school database.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, height: 1.4),
          ),
          const SizedBox(height: 36),
          // Sample Format Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'REQUIRED CSV FORMAT HEADER EXAMPLE:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.primaryDark, letterSpacing: 0.5),
                ),
                const SizedBox(height: 10),
                const SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text(
                    'Class, Section, Roll, Name, Father Name, Phone, Guardian Email\nClass 9, A, 1, Amit Sharma, Raj Sharma, 9876543210, amit@mail.com\nClass 9, A, 2, Pooja Verma, Vijay Verma, 9876500000, pooja@mail.com',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.5, color: Colors.blueGrey),
                  ),
                ),
                const Divider(height: 20),
                Text(
                  '• Class, Roll, and Name columns are strictly required.\n• Section defaults to "A" if empty.\n• Unique admission ID is generated for each student.\n• Guardian accounts are created automatically for email entries.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 48),
          ElevatedButton.icon(
            onPressed: _pickAndParseFile,
            icon: const Icon(Icons.file_open, color: Colors.white),
            label: const Text('Select CSV File', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValidTab(List<_ParsedRow> validRows) {
    if (validRows.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Text(
              'No valid student records found.',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: validRows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, idx) {
        final student = validRows[idx].student!;
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 3)),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              radius: 20,
              backgroundColor: AppTheme.primary.withValues(alpha: 0.08),
              child: Text(
                '${student.roll}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary),
              ),
            ),
            title: Text(student.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${student.className} — Sec ${student.section}',
                        style: const TextStyle(fontSize: 10, color: Colors.blueAccent, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (student.guardianEmail != null && student.guardianEmail!.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Email Link',
                          style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
                if (student.fatherName.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Father: ${student.fatherName}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ],
            ),
            trailing: Text(
              student.feeStatus,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: student.feeStatus.toLowerCase() == 'paid' ? Colors.green : Colors.red,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildErrorsTab(List<_ParsedRow> invalidRows) {
    if (invalidRows.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
            SizedBox(height: 12),
            Text(
              'Zero Validation Errors! Roster is clean.',
              style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: invalidRows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, idx) {
        final row = invalidRows[idx];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.red.shade50.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.shade100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Row ${row.rowIndex}',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      row.error ?? 'Unknown error',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _rawTextItem('Name', row.rawName),
                  _rawTextItem('Class', row.rawClass),
                  _rawTextItem('Sec', row.rawSection),
                  _rawTextItem('Roll', row.rawRoll),
                ],
              )
            ],
          ),
        );
      },
    );
  }

  Widget _rawTextItem(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: TextStyle(fontSize: 9, color: Colors.grey.shade500, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(
            value.isEmpty ? '—' : value,
            style: const TextStyle(fontSize: 12, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(int validCount) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckboxListTile(
            title: const Text(
              'Assert physical parental consent is on record',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            subtitle: const Text(
              'I confirm that signed physical parental consent forms are collected in compliance with DPDP.',
              style: TextStyle(fontSize: 10),
            ),
            value: _assertConsent,
            onChanged: (val) {
              setState(() {
                _assertConsent = val ?? false;
              });
            },
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _parsedRows = [];
                      _fileName = null;
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppTheme.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Reset', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _assertConsent ? _executeImport : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    disabledBackgroundColor: Colors.grey.shade300,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    'Import $validCount Student${validCount == 1 ? '' : 's'}',
                    style: TextStyle(
                      color: _assertConsent ? Colors.white : Colors.grey.shade500,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

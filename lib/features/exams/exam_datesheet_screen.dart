import '../../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import '../../models/datesheet.dart';
import '../../models/exam.dart';
import '../../services/datesheet_service.dart';
import '../../services/exam_service.dart';
import '../../services/timetable_service.dart';
import '../../theme.dart';

class ExamDatesheetScreen extends StatefulWidget {
  const ExamDatesheetScreen({super.key});

  @override
  State<ExamDatesheetScreen> createState() => _ExamDatesheetScreenState();
}

class _ExamDatesheetScreenState extends State<ExamDatesheetScreen> {
  final _examService = ExamService();
  final _datesheetService = DatesheetService();

  bool _loadingClasses = true;
  bool _loadingExams = false;
  bool _loadingDatesheet = false;
  bool _saving = false;

  List<String> _classes = [];
  String? _selectedClass;

  List<Exam> _exams = [];
  Exam? _selectedExam;

  // Controllers/Values for the active schedule entries
  final Map<String, TextEditingController> _dateControllers = {}; // subject -> controller
  final Map<String, String> _timeSelections = {}; // subject -> selected time slot

  static const List<String> _timeSlots = [
    '08:30 AM - 11:30 AM',
    '09:00 AM - 12:00 PM',
    '09:30 AM - 12:30 PM',
    '01:00 PM - 04:00 PM',
    '01:30 PM - 04:30 PM',
    'Custom...',
  ];

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  @override
  void dispose() {
    for (final c in _dateControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadClasses() async {
    setState(() => _loadingClasses = true);
    try {
      final settings = await TimetableService.instance.getSettings();
      final cls = List<String>.from(settings['classes'] as List? ?? []);
      if (mounted) {
        setState(() {
          _classes = cls;
          _selectedClass = cls.isNotEmpty ? cls.first : null;
          _loadingClasses = false;
        });
        if (_selectedClass != null) {
          _loadExams();
        }
      }
    } catch (e) {
      if (mounted) setState(() => _loadingClasses = false);
    }
  }

  Future<void> _loadExams() async {
    if (_selectedClass == null) return;
    setState(() {
      _loadingExams = true;
      _exams = [];
      _selectedExam = null;
      _dateControllers.clear();
      _timeSelections.clear();
    });

    try {
      final list = await _examService.getExams(className: _selectedClass);
      if (mounted) {
        setState(() {
          _exams = list;
          _selectedExam = list.isNotEmpty ? list.first : null;
          _loadingExams = false;
        });
        if (_selectedExam != null) {
          _loadDatesheet();
        }
      }
    } catch (e) {
      if (mounted) setState(() => _loadingExams = false);
    }
  }

  Future<void> _loadDatesheet() async {
    if (_selectedClass == null || _selectedExam == null) return;
    setState(() {
      _loadingDatesheet = true;
      _dateControllers.clear();
      _timeSelections.clear();
    });

    try {
      final datesheet = await _datesheetService.getDatesheet(_selectedClass!, _selectedExam!.id);
      
      // Initialize forms with existing data
      for (final sub in _selectedExam!.subjects) {
        final existing = datesheet.schedules.firstWhere(
          (s) => s.subject == sub,
          orElse: () => DatesheetSubjectSchedule(subject: sub, dateStr: '', timeStr: _timeSlots[1]),
        );

        _dateControllers[sub] = TextEditingController(text: existing.dateStr);
        _timeSelections[sub] = _timeSlots.contains(existing.timeStr) ? existing.timeStr : 'Custom...';
        
        // If it was custom, we could handle it. Let's make sure it's stored.
        if (!_timeSlots.contains(existing.timeStr) && existing.timeStr.isNotEmpty) {
          _timeSelections[sub] = 'Custom...';
          _dateControllers['${sub}_custom_time'] = TextEditingController(text: existing.timeStr);
        }
      }

      if (mounted) {
        setState(() {
          _loadingDatesheet = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingDatesheet = false);
    }
  }

  Future<void> _selectDateForSubject(String subject) async {
    final controller = _dateControllers[subject];
    if (controller == null) return;

    DateTime initialDate = DateTime.now();
    if (controller.text.isNotEmpty) {
      try {
        initialDate = DateTime.parse(controller.text);
      } catch (_) {}
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 180)),
      builder: (context, child) {
        return Theme(
          data: AppTheme.light.copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primary,
              onPrimary: Colors.white,
              onSurface: AppTheme.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final formatted = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      setState(() {
        controller.text = formatted;
      });
    }
  }

  Future<void> _save() async {
    if (_selectedClass == null || _selectedExam == null) return;
    
    // Validate that all dates are filled
    for (final sub in _selectedExam!.subjects) {
      final dt = _dateControllers[sub]?.text.trim() ?? '';
      if (dt.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please select an exam date for $sub'), backgroundColor: AppTheme.danger),
        );
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final List<DatesheetSubjectSchedule> schedules = [];
      for (final sub in _selectedExam!.subjects) {
        final dateStr = _dateControllers[sub]!.text.trim();
        
        String timeStr = _timeSelections[sub] ?? '09:00 AM - 12:00 PM';
        if (timeStr == 'Custom...') {
          final customController = _dateControllers['${sub}_custom_time'];
          timeStr = customController?.text.trim() ?? '09:00 AM - 12:00 PM';
        }

        schedules.add(DatesheetSubjectSchedule(
          subject: sub,
          dateStr: dateStr,
          timeStr: timeStr,
        ));
      }

      final datesheet = Datesheet(
        id: '',
        examId: _selectedExam!.id,
        className: _selectedClass!,
        schedules: schedules,
      );

      await _datesheetService.saveDatesheet(datesheet);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Datesheet saved successfully!'), backgroundColor: AppTheme.success),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save datesheet: $e'), backgroundColor: AppTheme.danger),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(context.tr('examDatesheets')),
        backgroundColor: AppTheme.primaryDark,
        elevation: 0,
      ),
      body: _loadingClasses
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildSelectors(),
                Expanded(
                  child: _loadingExams || _loadingDatesheet
                      ? const Center(child: CircularProgressIndicator())
                      : _selectedExam == null
                          ? _buildNoExamsState()
                          : _buildScheduleForm(),
                ),
              ],
            ),
    );
  }

  Widget _buildSelectors() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            value: _selectedClass,
            decoration: const InputDecoration(
              labelText: 'Class',
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: _classes.map((cls) {
              return DropdownMenuItem(value: cls, child: Text(cls));
            }).toList(),
            onChanged: (v) {
              if (v != null) {
                setState(() {
                  _selectedClass = v;
                });
                _loadExams();
              }
            },
          ),
          const SizedBox(height: 12),
          if (_exams.isNotEmpty)
            DropdownButtonFormField<Exam>(
              value: _selectedExam,
              decoration: InputDecoration(
                labelText: context.tr('activeExam'),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: _exams.map((ex) {
                return DropdownMenuItem(value: ex, child: Text(ex.name));
              }).toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _selectedExam = v;
                  });
                  _loadDatesheet();
                }
              },
            ),
        ],
      ),
    );
  }

  Widget _buildNoExamsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(context.tr('noExamsCreated'), style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Create an exam under Coordinator Dashboard → Exams first.', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildScheduleForm() {
    final subjects = _selectedExam!.subjects;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'SUBJECT DATES & TIMINGS',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.textSecondary, letterSpacing: 0.8),
          ),
          const SizedBox(height: 12),

          ...subjects.map((sub) {
            final isCustomTime = _timeSelections[sub] == 'Custom...';
            
            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              elevation: 0,
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: AppTheme.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sub.toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.primary),
                    ),
                    const SizedBox(height: 16),

                    // Date Picker Input
                    TextFormField(
                      controller: _dateControllers[sub],
                      readOnly: true,
                      onTap: () => _selectDateForSubject(sub),
                      decoration: const InputDecoration(
                        labelText: 'Exam Date *',
                        prefixIcon: Icon(Icons.calendar_today, size: 18),
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Time Slot Picker
                    DropdownButtonFormField<String>(
                      value: _timeSelections[sub],
                      decoration: InputDecoration(
                        labelText: context.tr('timeSlotRequired'),
                        prefixIcon: Icon(Icons.access_time, size: 18),
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: _timeSlots.map((slot) {
                        return DropdownMenuItem(value: slot, child: Text(slot));
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() {
                            _timeSelections[sub] = v;
                          });
                        }
                      },
                    ),
                    
                    if (isCustomTime) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _dateControllers['${sub}_custom_time'] ??= TextEditingController(),
                        decoration: InputDecoration(
                          labelText: context.tr('customTimeRequired'),
                          hintText: context.tr('timeSlotHint'),
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),

          const SizedBox(height: 24),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Text(
                    'Save Datesheet',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
          ),
          const SizedBox(height: 60),
        ],
      ),
    );
  }
}

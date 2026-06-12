import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/calendar_event.dart';
import '../../shared/providers/school_settings_provider.dart';
import '../../theme.dart';
import '../../services/calendar_service.dart';
import '../../l10n/app_strings.dart';

class GuardianHolidayCalendarScreen extends StatefulWidget {
  const GuardianHolidayCalendarScreen({super.key});

  @override
  State<GuardianHolidayCalendarScreen> createState() => _GuardianHolidayCalendarScreenState();
}

class _GuardianHolidayCalendarScreenState extends State<GuardianHolidayCalendarScreen> {
  final CalendarService _calendarService = CalendarService();
  StreamSubscription? _eventsSub;
  List<CalendarEvent> _customEvents = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _eventsSub = _calendarService.getCustomEvents().listen((events) {
      if (mounted) {
        setState(() {
          _customEvents = events;
          _loading = false;
        });
      }
    }, onError: (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    });
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    super.dispose();
  }

  // Combine national, state, and custom school events for the current year
  List<Map<String, dynamic>> _buildAllHolidays(String state, int year) {
    final list = <Map<String, dynamic>>[];

    // 1. National Holidays
    final national = CalendarService.getNationalHolidays(year);
    for (final h in national['National'] ?? []) {
      list.add({
        'title': h['title'],
        'date': DateTime(year, h['month'], h['day']),
        'category': 'National Holiday',
        'isSchoolClosed': true,
      });
    }

    // 2. State Holidays
    if (state.isNotEmpty) {
      final stateHolidays = CalendarService.getStateHolidays(state, year);
      for (final h in stateHolidays[state] ?? []) {
        list.add({
          'title': h['title'],
          'date': DateTime(year, h['month'], h['day']),
          'category': '$state Holiday',
          'isSchoolClosed': true,
        });
      }
    }

    // 3. Custom School Events
    for (final e in _customEvents) {
      // Show events matching the active year
      if (e.date.year == year) {
        String category = 'School Event';
        if (e.type == CalendarEventType.holiday) {
          category = 'School Holiday';
        } else if (e.type == CalendarEventType.vacation) {
          category = 'Vacation';
        } else if (e.type == CalendarEventType.exam) {
          category = 'Exams';
        }

        list.add({
          'title': e.title,
          'date': e.date,
          'category': category,
          'isSchoolClosed': e.isObserved,
          'description': e.description,
        });
      }
    }

    // Deduplicate holidays on the same day (e.g. if a school event overlaps with a national holiday)
    final seenDates = <String, Map<String, dynamic>>{};
    for (final item in list) {
      final dt = item['date'] as DateTime;
      final dateKey = '${dt.year}-${dt.month}-${dt.day}';
      final existing = seenDates[dateKey];
      if (existing == null) {
        seenDates[dateKey] = item;
      } else {
        // Prefer national/state holidays or events marked as closing the school
        if (item['category'].toString().contains('National') || 
            (item['isSchoolClosed'] == true && existing['isSchoolClosed'] != true)) {
          seenDates[dateKey] = item;
        }
      }
    }

    final sortedList = seenDates.values.toList()
      ..sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));

    return sortedList;
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SchoolSettingsProvider>(context);
    final state = settings.schoolState;
    final year = DateTime.now().year;

    final allHolidays = _buildAllHolidays(state, year);

    // Group holidays by month
    final Map<int, List<Map<String, dynamic>>> grouped = {};
    for (final h in allHolidays) {
      final month = (h['date'] as DateTime).month;
      grouped.putIfAbsent(month, () => []).add(h);
    }

    final sortedMonths = grouped.keys.toList()..sort();
    const monthNames = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(context.tr('schoolCalendarHolidays')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : allHolidays.isEmpty
              ? Center(
                  child: Text(context.tr('noHolidaysScheduled')),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: sortedMonths.length,
                  itemBuilder: (ctx, index) {
                    final monthIndex = sortedMonths[index];
                    final monthHolidays = grouped[monthIndex]!;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 4, top: 12, bottom: 8),
                          child: Text(
                            monthNames[monthIndex].toUpperCase(),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primary,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          margin: const EdgeInsets.only(bottom: 16),
                          elevation: 0,
                          child: ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: monthHolidays.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (ctx, hIndex) {
                              final h = monthHolidays[hIndex];
                              final date = h['date'] as DateTime;
                              final category = h['category'] as String;
                              final isClosed = h['isSchoolClosed'] as bool;
                              final desc = h['description'] as String?;

                              Color tagBg;
                              Color tagFg;
                              if (category.contains('National')) {
                                tagBg = AppTheme.dangerLight;
                                tagFg = AppTheme.danger;
                              } else if (category.contains('State')) {
                                tagBg = AppTheme.warningLight;
                                tagFg = AppTheme.warning;
                              } else if (category.contains('Event')) {
                                tagBg = AppTheme.successLight;
                                tagFg = AppTheme.success;
                              } else {
                                tagBg = AppTheme.primaryLight;
                                tagFg = AppTheme.primary;
                              }

                              return Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Date Badge
                                    Container(
                                      width: 46,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: AppTheme.background,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            '${date.day}',
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: AppTheme.textPrimary,
                                            ),
                                          ),
                                          Text(
                                            _weekdayShort(date.weekday),
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: AppTheme.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    // Details
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            h['title'],
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: AppTheme.textPrimary,
                                            ),
                                          ),
                                          if (desc != null && desc.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              desc,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: AppTheme.textSecondary,
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 3,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: tagBg,
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  category,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: tagFg,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 3,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: isClosed 
                                                      ? AppTheme.dangerLight 
                                                      : AppTheme.successLight,
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  isClosed ? 'School Closed' : 'School Open',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: isClosed 
                                                        ? AppTheme.danger 
                                                        : AppTheme.success,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
    );
  }

  String _weekdayShort(int weekday) {
    const days = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[weekday];
  }
}

import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../models/calendar_event.dart';
import '../services/calendar_service.dart';
import '../theme.dart';
import 'package:intl/intl.dart';

class CalendarScreen extends StatefulWidget {
  final String userRole; // 'principal', 'coordinator', 'teacher', 'guardian'

  const CalendarScreen({super.key, required this.userRole});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final CalendarService _calendarService = CalendarService();
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  String? _selectedState;
  Map<String, dynamic> _overrides = {};

  List<CalendarEvent> _customEvents = [];

  final List<String> _indianStates = [
    'Andhra Pradesh', 'Arunachal Pradesh', 'Assam', 'Bihar', 'Chhattisgarh',
    'Goa', 'Gujarat', 'Haryana', 'Himachal Pradesh', 'Jharkhand', 'Karnataka',
    'Kerala', 'Madhya Pradesh', 'Maharashtra', 'Manipur', 'Meghalaya', 'Mizoram',
    'Nagaland', 'Odisha', 'Punjab', 'Rajasthan', 'Sikkim', 'Tamil Nadu',
    'Telangana', 'Tripura', 'Uttar Pradesh', 'Uttarakhand', 'West Bengal',
    'Delhi', 'Jammu and Kashmir', 'Ladakh', 'Puducherry'
  ];

  bool get _canEdit => widget.userRole == 'principal' || widget.userRole == 'coordinator';
  bool get _isPrincipal => widget.userRole == 'principal';

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
  }

  List<CalendarEvent> _getEventsForDay(DateTime day) {
    // Standardize the day to midnight for comparison
    final dateKey = DateTime(day.year, day.month, day.day);
    final dateStr = DateFormat('yyyy-MM-dd').format(dateKey);

    List<CalendarEvent> dayEvents = [];
    
    // 1. Add custom school events
    dayEvents.addAll(_customEvents.where((e) => 
      e.date.year == day.year && e.date.month == day.month && e.date.day == day.day));

    // 2. Add National Holidays
    final national = CalendarService.getNationalHolidays(day.year);
    for (var h in national['National']!) {
      if (h['month'] == day.month && h['day'] == day.day) {
        final holidayId = 'nat_${h['title']}_$dateStr';
        final override = _overrides[holidayId];

        if (override != null && override['deleted'] == true) continue;

        dayEvents.add(CalendarEvent(
          id: holidayId,
          title: override?['title'] ?? h['title'],
          date: dateKey,
          type: CalendarEventType.holiday,
          isGlobal: true,
          isObserved: override?['isObserved'] ?? true,
          isModified: override != null,
        ));
      }
    }

    // 3. Add State Holidays
    if (_selectedState != null) {
      final stateHolidays = CalendarService.getStateHolidays(_selectedState!, day.year);
      for (var h in stateHolidays[_selectedState!]!) {
        if (h['month'] == day.month && h['day'] == day.day) {
          final holidayId = 'state_${h['title']}_$dateStr';
          final override = _overrides[holidayId];

          if (override != null && override['deleted'] == true) continue;

          dayEvents.add(CalendarEvent(
            id: holidayId,
            title: override?['title'] ?? h['title'],
            date: dateKey,
            type: CalendarEventType.holiday,
            isGlobal: true,
            isObserved: override?['isObserved'] ?? true,
            isModified: override != null,
          ));
        }
      }
    }

    return dayEvents;
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    if (!isSameDay(_selectedDay, selectedDay)) {
      setState(() {
        _selectedDay = selectedDay;
        _focusedDay = focusedDay;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('School Calendar'),
        actions: [
          if (_isPrincipal)
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: _showStateSelectionDialog,
              tooltip: 'Select State',
            ),
        ],
      ),
      body: StreamBuilder<Map<String, dynamic>>(
        stream: _calendarService.getCalendarSettings(),
        builder: (context, settingsSnapshot) {
          if (settingsSnapshot.hasData) {
            _selectedState = settingsSnapshot.data!['selectedState'];
            _overrides = Map<String, dynamic>.from(settingsSnapshot.data!['overrides'] ?? {});
          }

          return StreamBuilder<List<CalendarEvent>>(
            stream: _calendarService.getCustomEvents(),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                _customEvents = snapshot.data!;
              }

              return Column(
                children: [
                  if (_selectedState != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                      color: AppTheme.primary.withOpacity(0.1),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on, size: 16, color: AppTheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            'School State: $_selectedState',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary),
                          ),
                          const Spacer(),
                          if (_isPrincipal)
                            TextButton(
                              onPressed: _showStateSelectionDialog,
                              child: const Text('Change'),
                            ),
                        ],
                      ),
                    ),
                  TableCalendar(
                    firstDay: DateTime.utc(2020, 1, 1),
                    lastDay: DateTime.utc(2030, 12, 31),
                    focusedDay: _focusedDay,
                    calendarFormat: _calendarFormat,
                    availableCalendarFormats: const {
                      CalendarFormat.month: 'Month',
                    },
                    selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                    onDaySelected: _onDaySelected,
                    onPageChanged: (focusedDay) {
                      setState(() {
                        _focusedDay = focusedDay;
                      });
                    },
                    eventLoader: _getEventsForDay,
                    calendarBuilders: CalendarBuilders(
                      markerBuilder: (context, date, events) {
                        if (events.isEmpty) return null;
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: events.take(4).map((event) {
                            final calEvent = event as CalendarEvent;
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 1.0),
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _getColorForType(calEvent),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                    calendarStyle: const CalendarStyle(
                      todayDecoration: BoxDecoration(
                        color: AppTheme.primaryLight,
                        shape: BoxShape.circle,
                      ),
                      selectedDecoration: BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                      ),
                      markerDecoration: BoxDecoration(
                        color: AppTheme.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    headerStyle: const HeaderStyle(
                      formatButtonVisible: true,
                      titleCentered: true,
                    ),
                  ),
                  const SizedBox(height: 8.0),
                  _buildLegend(),
                  const Divider(),
                  Expanded(
                    child: _buildEventList(),
                  ),
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: _canEdit
          ? FloatingActionButton(
              onPressed: () => _showAddEventDialog(),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          _legendItem(Colors.red, 'Govt Holiday'),
          _legendItem(Colors.grey, 'Govt Holiday (Open)'),
          _legendItem(AppTheme.primary, 'School Holiday'),
          _legendItem(Colors.green, 'Event'),
          _legendItem(Colors.orange, 'Festival'),
          _legendItem(Colors.blue, 'Exam'),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
  }

  Widget _buildEventList() {
    // Show all events for the currently focused month
    List<CalendarEvent> monthEvents = [];

    // Iterate through all days of the focused month
    final lastDay = DateTime(_focusedDay.year, _focusedDay.month + 1, 0).day;
    for (int i = 1; i <= lastDay; i++) {
      final day = DateTime(_focusedDay.year, _focusedDay.month, i);
      monthEvents.addAll(_getEventsForDay(day));
    }

    // Remove duplicates if any (e.g. from overlapping logic)
    final seenIds = <String>{};
    monthEvents = monthEvents.where((e) => seenIds.add(e.id)).toList();

    // Sort by date
    monthEvents.sort((a, b) => a.date.compareTo(b.date));

    if (monthEvents.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Text('No events for ${DateFormat('MMMM yyyy').format(_focusedDay)}'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Holidays & Events: ${DateFormat('MMMM yyyy').format(_focusedDay)}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: monthEvents.length,
            itemBuilder: (context, index) {
              final event = monthEvents[index];
              final isGlobal = event.id.startsWith('nat_') || event.id.startsWith('state_');

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: ListTile(
                  leading: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(DateFormat('dd').format(event.date), style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(DateFormat('E').format(event.date), style: const TextStyle(fontSize: 10)),
                    ],
                  ),
                  title: Text(
                    event.title,
                    style: TextStyle(
                      decoration: event.isObserved ? null : TextDecoration.lineThrough,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (event.description != null && event.description!.isNotEmpty) Text(event.description!),
                      if (isGlobal)
                        Text(
                          event.isObserved ? 'School Closed' : 'Classes Held (School Open)',
                          style: TextStyle(
                            fontSize: 12,
                            color: event.isObserved ? Colors.red : Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                  trailing: _canEdit
                      ? PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'edit') {
                              _showAddEventDialog(event: event);
                            } else if (value == 'delete') {
                              _confirmDelete(event);
                            } else if (value == 'toggle') {
                              _toggleObserved(event);
                            }
                          },
                          itemBuilder: (context) => [
                            if (!isGlobal || event.isModified)
                              const PopupMenuItem(value: 'edit', child: Text('Edit')),
                            if (isGlobal)
                              PopupMenuItem(
                                value: 'toggle',
                                child: Text(event.isObserved ? 'Set as Working Day' : 'Set as Holiday'),
                              ),
                            const PopupMenuItem(value: 'delete', child: Text('Remove/Delete')),
                          ],
                        )
                      : (isGlobal ? const Chip(label: Text('Govt', style: TextStyle(fontSize: 10))) : null),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  IconData _getIconForType(CalendarEvent event) {
    if (event.isGlobal) return Icons.account_balance;
    switch (event.type) {
      case CalendarEventType.holiday: return Icons.celebration;
      case CalendarEventType.festival: return Icons.festival;
      case CalendarEventType.vacation: return Icons.beach_access;
      case CalendarEventType.exam: return Icons.assignment;
      case CalendarEventType.event: return Icons.event;
    }
  }

  Color _getColorForType(CalendarEvent event) {
    if (event.isGlobal) {
      return event.isObserved ? Colors.red : Colors.grey;
    }
    switch (event.type) {
      case CalendarEventType.holiday: return AppTheme.primary;
      case CalendarEventType.festival: return Colors.orange;
      case CalendarEventType.vacation: return Colors.teal;
      case CalendarEventType.exam: return Colors.blue;
      case CalendarEventType.event: return Colors.green;
    }
  }

  void _toggleObserved(CalendarEvent event) async {
    final isGlobal = event.id.startsWith('nat_') || event.id.startsWith('state_');
    if (isGlobal) {
      await _calendarService.updateOverride(event.id, {
        'isObserved': !event.isObserved,
        'title': event.title, // Keep original title or updated if modified
      });
    } else {
      // For custom events, just update the event
      final updated = CalendarEvent(
        id: event.id,
        title: event.title,
        date: event.date,
        type: event.type,
        description: event.description,
        isObserved: !event.isObserved,
      );
      await _calendarService.updateEvent(updated);
    }
  }

  void _showStateSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select School State'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _indianStates.length,
            itemBuilder: (context, index) {
              final state = _indianStates[index];
              return ListTile(
                title: Text(state),
                onTap: () async {
                  await _calendarService.setSelectedState(state);
                  setState(() {
                    _selectedState = state;
                  });
                  Navigator.pop(context);
                },
                selected: _selectedState == state,
              );
            },
          ),
        ),
      ),
    );
  }

  void _showAddEventDialog({CalendarEvent? event}) {
    final isGlobal = event?.id.startsWith('nat_') == true || event?.id.startsWith('state_') == true;
    final titleController = TextEditingController(text: event?.title);
    final descController = TextEditingController(text: event?.description);
    CalendarEventType selectedType = event?.type ?? CalendarEventType.holiday;
    DateTime selectedDate = event?.date ?? _selectedDay!;
    bool isObserved = event?.isObserved ?? true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(event == null ? 'Add Event' : (isGlobal ? 'Edit Government Holiday' : 'Edit Event')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                if (!isGlobal) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: descController,
                    decoration: const InputDecoration(labelText: 'Description (Optional)'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<CalendarEventType>(
                    value: selectedType,
                    items: CalendarEventType.values.map((type) {
                      return DropdownMenuItem(
                        value: type,
                        child: Text(type.name.toUpperCase()),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedType = val);
                    },
                    decoration: const InputDecoration(labelText: 'Type'),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Date: ${DateFormat('yyyy-MM-dd').format(selectedDate)}'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) {
                        setDialogState(() => selectedDate = picked);
                      }
                    },
                  ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Observe as Holiday'),
                  subtitle: Text(isObserved ? 'School will be closed' : 'Classes will be held'),
                  value: isObserved,
                  onChanged: (val) {
                    setDialogState(() => isObserved = val);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (titleController.text.isEmpty) return;

                if (isGlobal) {
                  await _calendarService.updateOverride(event!.id, {
                    'title': titleController.text,
                    'isObserved': isObserved,
                    'isModified': true,
                  });
                } else {
                  final newEvent = CalendarEvent(
                    id: event?.id ?? '',
                    title: titleController.text,
                    description: descController.text,
                    date: DateTime(selectedDate.year, selectedDate.month, selectedDate.day),
                    type: selectedType,
                    isObserved: isObserved,
                  );

                  if (event == null) {
                    await _calendarService.addEvent(newEvent);
                  } else {
                    await _calendarService.updateEvent(newEvent);
                  }
                }
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(CalendarEvent event) {
    final isGlobal = event.id.startsWith('nat_') || event.id.startsWith('state_');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isGlobal ? 'Remove Holiday' : 'Delete Event'),
        content: Text('Are you sure you want to ${isGlobal ? 'remove' : 'delete'} "${event.title}" from the school calendar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              if (isGlobal) {
                await _calendarService.updateOverride(event.id, {'deleted': true});
              } else {
                await _calendarService.deleteEvent(event.id);
              }
              Navigator.pop(context);
            },
            child: Text(isGlobal ? 'Remove' : 'Delete', style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

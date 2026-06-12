import '../../models/timetable_entry.dart';
import '../../models/teacher.dart';

class TimetableConflict {
  final String type; // 'clash' | 'overload' | 'consecutive' | 'empty'
  final String day;
  final int bell;
  final String className;
  final String teacherId;
  final String teacherName;
  final String details;

  TimetableConflict({
    required this.type,
    required this.day,
    required this.bell,
    required this.className,
    required this.teacherId,
    required this.teacherName,
    required this.details,
  });
}

class TimetableConflictDetector {
  /// Scans the timetable structure and returns a list of conflicts.
  static List<TimetableConflict> detectConflicts({
    required Map<String, Map<String, Map<int, TimetableEntry>>> timetable,
    required List<Teacher> teachers,
    required List<String> classes,
    required List<String> days,
    required int bellsCount,
    required List<int> lunchBells, // 1-indexed lunch bell indices
  }) {
    final List<TimetableConflict> conflicts = [];
    final Map<String, Teacher> teacherMap = {for (final t in teachers) t.id: t};

    // Helper: get teacher name
    String getTeacherName(String? id) {
      if (id == null) return 'Unknown';
      return teacherMap[id]?.name ?? 'Unknown Teacher';
    }

    // 1. Detect Teacher Double Booking (Clashes)
    // Structure: Day -> Bell -> TeacherId -> List of Classes
    final Map<String, Map<int, Map<String, List<String>>>> schedule = {};

    for (final cls in classes) {
      final clsDays = timetable[cls] ?? {};
      for (final day in days) {
        final dayBells = clsDays[day] ?? {};
        for (int bell = 1; bell <= bellsCount; bell++) {
          final entry = dayBells[bell];
          if (entry != null && !entry.isEmpty && entry.teacherId != null) {
            final tId = entry.teacherId!;
            schedule.putIfAbsent(day, () => {});
            schedule[day]!.putIfAbsent(bell, () => {});
            schedule[day]![bell]!.putIfAbsent(tId, () => []);
            schedule[day]![bell]![tId]!.add(cls);
          }
        }
      }
    }

    // Now check for duplicate assignments
    schedule.forEach((day, bellMap) {
      bellMap.forEach((bell, teacherMapForBell) {
        teacherMapForBell.forEach((teacherId, assignedClasses) {
          if (assignedClasses.length > 1) {
            for (final cls in assignedClasses) {
              conflicts.add(
                TimetableConflict(
                  type: 'clash',
                  day: day,
                  bell: bell,
                  className: cls,
                  teacherId: teacherId,
                  teacherName: getTeacherName(teacherId),
                  details: '${getTeacherName(teacherId)} is double-booked on $day at Bell $bell in classes: ${assignedClasses.join(" & ")}',
                ),
              );
            }
          }
        });
      });
    });

    // 2. Detect Teacher Overload (>5 classes per day) and Consecutive Slots (>3 in a row)
    // Structure: Day -> TeacherId -> Sorted list of busy bells
    for (final day in days) {
      final Map<String, List<int>> teacherDayBells = {};
      
      for (final cls in classes) {
        final dayBells = timetable[cls]?[day] ?? {};
        for (int bell = 1; bell <= bellsCount; bell++) {
          final entry = dayBells[bell];
          if (entry != null && !entry.isEmpty && entry.teacherId != null) {
            final tId = entry.teacherId!;
            teacherDayBells.putIfAbsent(tId, () => []);
            if (!teacherDayBells[tId]!.contains(bell)) {
              teacherDayBells[tId]!.add(bell);
            }
          }
        }
      }

      teacherDayBells.forEach((teacherId, bells) {
        bells.sort();

        // 2a. Overload Check
        if (bells.length > 5) {
          conflicts.add(
            TimetableConflict(
              type: 'overload',
              day: day,
              bell: bells.first,
              className: '',
              teacherId: teacherId,
              teacherName: getTeacherName(teacherId),
              details: '${getTeacherName(teacherId)} is scheduled for ${bells.length} periods on $day (exceeds recommended limit of 5)',
            ),
          );
        }

        // 2b. Consecutive Slots Check (>3 consecutive bells)
        int consecutive = 1;
        for (int i = 0; i < bells.length - 1; i++) {
          if (bells[i + 1] == bells[i] + 1) {
            consecutive++;
            if (consecutive > 3) {
              conflicts.add(
                TimetableConflict(
                  type: 'consecutive',
                  day: day,
                  bell: bells[i + 1],
                  className: '',
                  teacherId: teacherId,
                  teacherName: getTeacherName(teacherId),
                  details: '${getTeacherName(teacherId)} has 4 or more consecutive periods on $day (Bells ${bells.sublist(i - 2, i + 2).join(", ")}) without a break',
                ),
              );
              break; // only report once per teacher per day
            }
          } else {
            consecutive = 1;
          }
        }
      });
    }

    // 3. Detect Unassigned Regular Classes (excluding Lunch periods)
    for (final cls in classes) {
      for (final day in days) {
        for (int bell = 1; bell <= bellsCount; bell++) {
          if (lunchBells.contains(bell)) continue; // ignore lunch

          final entry = timetable[cls]?[day]?[bell];
          if (entry == null || entry.isEmpty) {
            // Unassigned period
            conflicts.add(
              TimetableConflict(
                type: 'empty',
                day: day,
                bell: bell,
                className: cls,
                teacherId: '',
                teacherName: '',
                details: 'Class $cls has an unassigned period at Bell $bell on $day',
              ),
            );
          }
        }
      }
    }

    return conflicts;
  }
}

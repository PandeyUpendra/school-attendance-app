import '../models/teacher.dart';
import '../models/timetable_entry.dart';
import 'substitution_history_service.dart';
import 'timetable_service.dart';

/// One bell that needs covering, with ranked substitute candidates.
class SuggestedSlot {
  final DateTime date;
  final String   dayName;
  final String   className;
  final int      bell;
  final String   subject;
  final String   originalTeacherId;
  final String   originalTeacherName;
  final List<RankedCandidate> candidates;

  SuggestedSlot({
    required this.date,
    required this.dayName,
    required this.className,
    required this.bell,
    required this.subject,
    required this.originalTeacherId,
    required this.originalTeacherName,
    required this.candidates,
  });

  RankedCandidate? get topPick =>
      candidates.isEmpty ? null : candidates.first;

  /// Stable key for tracking selections in UI state.
  String get key =>
      '${date.year}-${date.month}-${date.day}_${className}_$bell';
}

class RankedCandidate {
  final Teacher      teacher;
  final int          score;
  final List<String> reasons;

  const RankedCandidate({
    required this.teacher,
    required this.score,
    required this.reasons,
  });
}

/// Builds an ordered "substitution plan" for an absent teacher's leave.
///
/// Ranking per bell:
///   • Free that bell on that date  — hard requirement (else excluded)
///   • Same subject as the absent class  — +100
///   • Lowest substitution count this week  — −10 per existing sub
///   • Not on a duty assignment today  — −50 if on duty
class SubstitutionSuggesterService {
  static final SubstitutionSuggesterService _instance =
      SubstitutionSuggesterService._();
  SubstitutionSuggesterService._();
  factory SubstitutionSuggesterService() => _instance;

  static const _dayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
  ];

  Future<List<SuggestedSlot>> buildPlan({
    required String   absentTeacherId,
    required DateTime startDate,
    required int      numberOfDays,
  }) async {
    final svc = TimetableService();

    final timetable  = await svc.getTimetable();
    final teachers   = await svc.getTeachers();
    final weekCounts = await SubstitutionHistoryService().getSubstituteCounts(days: 7);
    final dutyIds    = (await svc.getTodayDuties()).keys.toSet();

    final absentTeacher =
        teachers.where((t) => t.id == absentTeacherId).firstOrNull;
    if (absentTeacher == null) return [];

    final today = DateTime.now();
    final slots = <SuggestedSlot>[];

    for (int d = 0; d < numberOfDays; d++) {
      final date = DateTime(
          startDate.year, startDate.month, startDate.day + d);
      if (date.weekday == DateTime.sunday) continue;
      final dayName = _dayNames[(date.weekday - 1).clamp(0, 5)];

      final existingSubs = await svc.getSubstitutionsForDate(date);

      timetable.forEach((cls, dayMap) {
        final Map<int, TimetableEntry> bellMap = dayMap[dayName] ?? {};
        bellMap.forEach((bell, entry) {
          if (entry.teacherId != absentTeacherId) return;
          // Skip if a substitute is already assigned for this slot.
          if (existingSubs['${cls}_$bell'] != null) return;

          final entrySubject = (entry.subject?.isNotEmpty == true)
              ? entry.subject!
              : absentTeacher.subject;

          // Busy set: every teacher scheduled or already substituting for
          // this same bell across all classes on this day.
          final busy = <String>{absentTeacherId};
          timetable.forEach((c2, dm2) {
            final e2 = dm2[dayName]?[bell];
            if (e2?.teacherId?.isNotEmpty == true) busy.add(e2!.teacherId!);
            final s2 = existingSubs['${c2}_$bell'];
            if (s2 != null && s2.isNotEmpty) busy.add(s2);
          });

          final ranked = <RankedCandidate>[];
          for (final t in teachers) {
            if (busy.contains(t.id)) continue;
            int score = 0;
            final reasons = <String>[];

            if (entrySubject.isNotEmpty &&
                t.subject.toLowerCase() == entrySubject.toLowerCase()) {
              score += 100;
              reasons.add('Same subject');
            }
            final load = weekCounts[t.id] ?? 0;
            score -= load * 10;
            reasons.add(load == 0
                ? 'No subs this week'
                : '$load sub${load == 1 ? '' : 's'} this week');

            if (_sameDay(date, today) && dutyIds.contains(t.id)) {
              score -= 50;
              reasons.add('On duty today');
            }

            ranked.add(RankedCandidate(
                teacher: t, score: score, reasons: reasons));
          }
          ranked.sort((a, b) => b.score.compareTo(a.score));

          slots.add(SuggestedSlot(
            date:                date,
            dayName:             dayName,
            className:           cls,
            bell:                bell,
            subject:             entrySubject,
            originalTeacherId:   absentTeacherId,
            originalTeacherName: absentTeacher.name,
            candidates:          ranked,
          ));
        });
      });
    }

    slots.sort((a, b) {
      final c = a.date.compareTo(b.date);
      if (c != 0) return c;
      final c2 = a.bell.compareTo(b.bell);
      if (c2 != 0) return c2;
      return a.className.compareTo(b.className);
    });
    return slots;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

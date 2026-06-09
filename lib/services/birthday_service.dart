import 'package:cloud_firestore/cloud_firestore.dart';
import 'base_firestore_service.dart';
import 'auth_service.dart';

class BirthdayService extends BaseFirestoreService {
  static final BirthdayService _instance = BirthdayService._();
  BirthdayService._();
  factory BirthdayService() => _instance;

  CollectionReference<Map<String, dynamic>> get _teachers =>
      schoolCollection(AuthService.currentSchoolId, 'teachers');

  CollectionReference<Map<String, dynamic>> get _students =>
      schoolCollection(AuthService.currentSchoolId, 'students');

  // ── Date helpers ───────────────────────────────────────────────────────────

  /// The birthday's occurrence in [year], with the day clamped to the month's
  /// length so a 29-Feb birthday lands on 28 Feb in non-leap years instead of
  /// silently rolling over to 1 March (DateTime normalises overflow) — #237.
  DateTime _birthdayInYear(int year, DateTime birth) {
    final lastDayOfMonth = DateTime(year, birth.month + 1, 0).day;
    final day = birth.day > lastDayOfMonth ? lastDayOfMonth : birth.day;
    return DateTime(year, birth.month, day);
  }

  bool isBirthdayToday(Timestamp dob) {
    final now = DateTime.now();
    final celebrated = _birthdayInYear(now.year, dob.toDate());
    return celebrated.day == now.day && celebrated.month == now.month;
  }

  bool isBirthdayThisWeek(Timestamp dob) {
    final days = daysUntilBirthday(dob);
    return days >= 0 && days <= 7;
  }

  bool isBirthdayThisMonth(Timestamp dob) {
    final now = DateTime.now();
    final birth = dob.toDate();
    return birth.month == now.month;
  }

  int daysUntilBirthday(Timestamp dob) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final birth = dob.toDate();
    var next = _birthdayInYear(now.year, birth);
    if (next.isBefore(today)) {
      next = _birthdayInYear(now.year + 1, birth);
    }
    return next.difference(today).inDays;
  }

  String formatDOB(Timestamp dob) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final d = dob.toDate();
    return '${d.day} ${months[d.month - 1]}';
  }

  // ── Staff (teachers) ───────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getTodayStaffBirthdays() async {
    final now = DateTime.now();
    try {
      final snap = await _teachers
          .where('birthMonth', isEqualTo: now.month)
          .where('birthDay', isEqualTo: now.day)
          .get();
      return snap.docs
          .map((d) => {...d.data(), 'id': d.id, 'daysLeft': 0, 'type': 'staff'})
          .toList();
    } catch (e, stack) {
      handleError(e, stack);
      final snap = await _teachers.get();
      return snap.docs
          .where((d) =>
              d.data()['dateOfBirth'] != null &&
              isBirthdayToday(d.data()['dateOfBirth'] as Timestamp))
          .map((d) => {...d.data(), 'id': d.id, 'daysLeft': 0, 'type': 'staff'})
          .toList();
    }
  }

  Future<List<Map<String, dynamic>>> getTomorrowStaffBirthdays() async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    try {
      final snap = await _teachers
          .where('birthMonth', isEqualTo: tomorrow.month)
          .where('birthDay', isEqualTo: tomorrow.day)
          .get();
      return snap.docs
          .map((d) => {...d.data(), 'id': d.id, 'daysLeft': 1, 'type': 'staff'})
          .toList();
    } catch (e, stack) {
      handleError(e, stack);
      final snap = await _teachers.get();
      return snap.docs
          .where((d) =>
              d.data()['dateOfBirth'] != null &&
              daysUntilBirthday(d.data()['dateOfBirth'] as Timestamp) == 1)
          .map((d) => {...d.data(), 'id': d.id, 'daysLeft': 1, 'type': 'staff'})
          .toList();
    }
  }

  Future<List<Map<String, dynamic>>> getUpcomingStaffBirthdays(int days) async {
    final now = DateTime.now();
    try {
      final targetMonths = <int>{now.month};
      for (int i = 1; i <= days; i++) {
        targetMonths.add(now.add(Duration(days: i)).month);
      }
      final allMatches = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final month in targetMonths) {
        final snap = await _teachers.where('birthMonth', isEqualTo: month).get();
        allMatches.addAll(snap.docs);
      }
      final list = allMatches
          .map((d) {
            final data = d.data();
            final dob = data['dateOfBirth'];
            if (dob == null) return null;
            final daysLeft = daysUntilBirthday(dob as Timestamp);
            return {...data, 'id': d.id, 'daysLeft': daysLeft, 'type': 'staff'};
          })
          .whereType<Map<String, dynamic>>()
          .where((m) => (m['daysLeft'] as int) <= days)
          .toList()
        ..sort((a, b) => (a['daysLeft'] as int).compareTo(b['daysLeft'] as int));
      return list;
    } catch (e, stack) {
      handleError(e, stack);
      final snap = await _teachers.get();
      final list = snap.docs
          .where((d) => d.data()['dateOfBirth'] != null)
          .map((d) {
            final daysLeft = daysUntilBirthday(d.data()['dateOfBirth'] as Timestamp);
            return {...d.data(), 'id': d.id, 'daysLeft': daysLeft, 'type': 'staff'};
          })
          .where((m) => (m['daysLeft'] as int) <= days)
          .toList()
        ..sort((a, b) => (a['daysLeft'] as int).compareTo(b['daysLeft'] as int));
      return list;
    }
  }

  Future<List<Map<String, dynamic>>> getAllStaffBirthdays() async {
    final snap = await _teachers.get();
    final list = snap.docs
        .where((d) => d.data()['dateOfBirth'] != null)
        .map((d) {
          final daysLeft = daysUntilBirthday(d.data()['dateOfBirth'] as Timestamp);
          return {...d.data(), 'id': d.id, 'daysLeft': daysLeft, 'type': 'staff'};
        })
        .toList()
      ..sort((a, b) => (a['daysLeft'] as int).compareTo(b['daysLeft'] as int));
    return list;
  }

  // ── Students ───────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getTodayStudentBirthdays({
    String? className,
    String? section,
    List<String>? classNames,
  }) async {
    final now = DateTime.now();
    try {
      final snap = await _buildStudentQuery(
        className: className,
        section: section,
        classNames: classNames,
      )
      .where('birthMonth', isEqualTo: now.month)
      .where('birthDay', isEqualTo: now.day)
      .get();
      return snap.docs
          .map((d) => {...d.data(), 'id': d.id, 'daysLeft': 0, 'type': 'student'})
          .toList();
    } catch (e, stack) {
      handleError(e, stack);
      final snap = await _buildStudentQuery(
        className: className,
        section: section,
        classNames: classNames,
      ).get();
      return snap.docs
          .where((d) =>
              d.data()['dateOfBirth'] != null &&
              isBirthdayToday(d.data()['dateOfBirth'] as Timestamp))
          .map((d) => {...d.data(), 'id': d.id, 'daysLeft': 0, 'type': 'student'})
          .toList();
    }
  }

  Future<List<Map<String, dynamic>>> getTomorrowStudentBirthdays({
    String? className,
    String? section,
    List<String>? classNames,
  }) async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    try {
      final snap = await _buildStudentQuery(
        className: className,
        section: section,
        classNames: classNames,
      )
      .where('birthMonth', isEqualTo: tomorrow.month)
      .where('birthDay', isEqualTo: tomorrow.day)
      .get();
      return snap.docs
          .map((d) => {...d.data(), 'id': d.id, 'daysLeft': 1, 'type': 'student'})
          .toList();
    } catch (e, stack) {
      handleError(e, stack);
      final snap = await _buildStudentQuery(
        className: className,
        section: section,
        classNames: classNames,
      ).get();
      return snap.docs
          .where((d) =>
              d.data()['dateOfBirth'] != null &&
              daysUntilBirthday(d.data()['dateOfBirth'] as Timestamp) == 1)
          .map((d) => {...d.data(), 'id': d.id, 'daysLeft': 1, 'type': 'student'})
          .toList();
    }
  }

  Future<List<Map<String, dynamic>>> getUpcomingStudentBirthdays(
    int days, {
    String? className,
    String? section,
    List<String>? classNames,
  }) async {
    final now = DateTime.now();
    try {
      final targetMonths = <int>{now.month};
      for (int i = 1; i <= days; i++) {
        targetMonths.add(now.add(Duration(days: i)).month);
      }
      final allMatches = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final month in targetMonths) {
        final snap = await _buildStudentQuery(
          className: className,
          section: section,
          classNames: classNames,
        )
        .where('birthMonth', isEqualTo: month)
        .get();
        allMatches.addAll(snap.docs);
      }
      final list = allMatches
          .map((d) {
            final data = d.data();
            final dob = data['dateOfBirth'];
            if (dob == null) return null;
            final daysLeft = daysUntilBirthday(dob as Timestamp);
            return {...data, 'id': d.id, 'daysLeft': daysLeft, 'type': 'student'};
          })
          .whereType<Map<String, dynamic>>()
          .where((m) => (m['daysLeft'] as int) <= days)
          .toList()
        ..sort((a, b) => (a['daysLeft'] as int).compareTo(b['daysLeft'] as int));
      return list;
    } catch (e, stack) {
      handleError(e, stack);
      final snap = await _buildStudentQuery(
        className: className,
        section: section,
        classNames: classNames,
      ).get();
      final list = snap.docs
          .where((d) => d.data()['dateOfBirth'] != null)
          .map((d) {
            final daysLeft = daysUntilBirthday(d.data()['dateOfBirth'] as Timestamp);
            return {...d.data(), 'id': d.id, 'daysLeft': daysLeft, 'type': 'student'};
          })
          .where((m) => (m['daysLeft'] as int) <= days)
          .toList()
        ..sort((a, b) => (a['daysLeft'] as int).compareTo(b['daysLeft'] as int));
      return list;
    }
  }

  Future<List<Map<String, dynamic>>> getAllStudentBirthdays({
    String? className,
    String? section,
    List<String>? classNames,
  }) async {
    final snap = await _buildStudentQuery(
      className: className,
      section: section,
      classNames: classNames,
    ).get();
    final list = snap.docs
        .where((d) => d.data()['dateOfBirth'] != null)
        .map((d) {
          final daysLeft = daysUntilBirthday(d.data()['dateOfBirth'] as Timestamp);
          return {...d.data(), 'id': d.id, 'daysLeft': daysLeft, 'type': 'student'};
        })
        .toList()
      ..sort((a, b) => (a['daysLeft'] as int).compareTo(b['daysLeft'] as int));
    return list;
  }

  // ── Combined (for home-screen banners) ────────────────────────────────────

  Future<List<Map<String, dynamic>>> getTodayAllBirthdays({
    String? className,
    String? section,
    List<String>? classNames,
  }) async {
    final staff = await getTodayStaffBirthdays();
    final students = await getTodayStudentBirthdays(
      className: className,
      section: section,
      classNames: classNames,
    );
    return [...staff, ...students];
  }

  Future<List<Map<String, dynamic>>> getTomorrowAllBirthdays({
    String? className,
    String? section,
    List<String>? classNames,
  }) async {
    final staff = await getTomorrowStaffBirthdays();
    final students = await getTomorrowStudentBirthdays(
      className: className,
      section: section,
      classNames: classNames,
    );
    return [...staff, ...students];
  }

  // ── Monthly Queries (for calendar view) ───────────────────────────────────

  Future<List<Map<String, dynamic>>> getMonthlyStaffBirthdays(int month) async {
    try {
      final snap = await _teachers
          .where('birthMonth', isEqualTo: month)
          .get();
      final list = snap.docs
          .map((d) {
            final daysLeft = daysUntilBirthday(d.data()['dateOfBirth'] as Timestamp);
            return {...d.data(), 'id': d.id, 'daysLeft': daysLeft, 'type': 'staff'};
          })
          .toList()
        ..sort((a, b) => (a['daysLeft'] as int).compareTo(b['daysLeft'] as int));
      return list;
    } catch (e, stack) {
      handleError(e, stack);
      final snap = await _teachers.get();
      final list = snap.docs
          .where((d) =>
              d.data()['dateOfBirth'] != null &&
              (d.data()['dateOfBirth'] as Timestamp).toDate().month == month)
          .map((d) {
            final daysLeft = daysUntilBirthday(d.data()['dateOfBirth'] as Timestamp);
            return {...d.data(), 'id': d.id, 'daysLeft': daysLeft, 'type': 'staff'};
          })
          .toList()
        ..sort((a, b) => (a['daysLeft'] as int).compareTo(b['daysLeft'] as int));
      return list;
    }
  }

  Future<List<Map<String, dynamic>>> getMonthlyStudentBirthdays(
    int month, {
    String? className,
    String? section,
    List<String>? classNames,
  }) async {
    try {
      final snap = await _buildStudentQuery(
        className: className,
        section: section,
        classNames: classNames,
      )
      .where('birthMonth', isEqualTo: month)
      .get();
      final list = snap.docs
          .map((d) {
            final daysLeft = daysUntilBirthday(d.data()['dateOfBirth'] as Timestamp);
            return {...d.data(), 'id': d.id, 'daysLeft': daysLeft, 'type': 'student'};
          })
          .toList()
        ..sort((a, b) => (a['daysLeft'] as int).compareTo(b['daysLeft'] as int));
      return list;
    } catch (e, stack) {
      handleError(e, stack);
      final snap = await _buildStudentQuery(
        className: className,
        section: section,
        classNames: classNames,
      ).get();
      final list = snap.docs
          .where((d) =>
              d.data()['dateOfBirth'] != null &&
              (d.data()['dateOfBirth'] as Timestamp).toDate().month == month)
          .map((d) {
            final daysLeft = daysUntilBirthday(d.data()['dateOfBirth'] as Timestamp);
            return {...d.data(), 'id': d.id, 'daysLeft': daysLeft, 'type': 'student'};
          })
          .toList()
        ..sort((a, b) => (a['daysLeft'] as int).compareTo(b['daysLeft'] as int));
      return list;
    }
  }

  // ── Calendar (for principal analytics) ────────────────────────────────────

  /// Returns a map of day-of-month → list of birthday entries for a given month.
  Future<Map<int, List<Map<String, dynamic>>>> getMonthlyBirthdays(
      int month) async {
    final allStaff = await getMonthlyStaffBirthdays(month);
    final allStudents = await getMonthlyStudentBirthdays(month);
    final all = [...allStaff, ...allStudents];

    final result = <int, List<Map<String, dynamic>>>{};
    for (final entry in all) {
      final dob = entry['dateOfBirth'] as Timestamp;
      final birth = dob.toDate();
      result.putIfAbsent(birth.day, () => []).add(entry);
    }
    return result;
  }

  // ── Legacy migration helper ───────────────────────────────────────────────

  Future<void> migrateLegacyBirthdays() async {
    try {
      // Migrate teachers
      final tSnap = await _teachers.get();
      for (final doc in tSnap.docs) {
        final data = doc.data();
        if (data['dateOfBirth'] != null && (data['birthMonth'] == null || data['birthDay'] == null)) {
          final dob = data['dateOfBirth'] as Timestamp;
          final date = dob.toDate();
          await doc.reference.update({
            'birthMonth': date.month,
            'birthDay': date.day,
          });
        }
      }

      // Migrate students
      final sSnap = await _students.get();
      for (final doc in sSnap.docs) {
        final data = doc.data();
        if (data['dateOfBirth'] != null && (data['birthMonth'] == null || data['birthDay'] == null)) {
          final dob = data['dateOfBirth'] as Timestamp;
          final date = dob.toDate();
          await doc.reference.update({
            'birthMonth': date.month,
            'birthDay': date.day,
          });
        }
      }
    } catch (e, stack) {
      handleError(e, stack);
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Query<Map<String, dynamic>> _buildStudentQuery({
    String? className,
    String? section,
    List<String>? classNames,
  }) {
    // If classNames list provided (subject teacher), filter server-side using whereIn
    // if size <= 30 (Firestore limit). Otherwise fallback to client-side.
    if (classNames != null && classNames.isNotEmpty) {
      if (classNames.length <= 30) {
        return _students.where('className', whereIn: classNames);
      }
      return _students;
    }
    Query<Map<String, dynamic>> q = _students;
    if (className != null && className.isNotEmpty) {
      q = q.where('className', isEqualTo: className);
    }
    if (section != null && section.isNotEmpty) {
      q = q.where('section', isEqualTo: section);
    }
    return q;
  }
}

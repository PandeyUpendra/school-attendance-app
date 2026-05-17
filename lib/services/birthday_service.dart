import 'package:cloud_firestore/cloud_firestore.dart';

class BirthdayService {
  static final _db = FirebaseFirestore.instance;
  static final _teachers = _db.collection('teachers');
  static final _students = _db.collection('students');

  static final BirthdayService _instance = BirthdayService._();
  BirthdayService._();
  factory BirthdayService() => _instance;

  // ── Date helpers ───────────────────────────────────────────────────────────

  bool isBirthdayToday(Timestamp dob) {
    final now = DateTime.now();
    final birth = dob.toDate();
    return birth.day == now.day && birth.month == now.month;
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
    var next = DateTime(now.year, birth.month, birth.day);
    if (next.isBefore(today)) {
      next = DateTime(now.year + 1, birth.month, birth.day);
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
    final snap = await _teachers.get();
    return snap.docs
        .where((d) =>
            d.data()['dateOfBirth'] != null &&
            isBirthdayToday(d.data()['dateOfBirth'] as Timestamp))
        .map((d) => {...d.data(), 'id': d.id, 'daysLeft': 0, 'type': 'staff'})
        .toList();
  }

  Future<List<Map<String, dynamic>>> getTomorrowStaffBirthdays() async {
    final snap = await _teachers.get();
    return snap.docs
        .where((d) =>
            d.data()['dateOfBirth'] != null &&
            daysUntilBirthday(d.data()['dateOfBirth'] as Timestamp) == 1)
        .map((d) => {...d.data(), 'id': d.id, 'daysLeft': 1, 'type': 'staff'})
        .toList();
  }

  Future<List<Map<String, dynamic>>> getUpcomingStaffBirthdays(int days) async {
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

  Future<List<Map<String, dynamic>>> getTomorrowStudentBirthdays({
    String? className,
    String? section,
    List<String>? classNames,
  }) async {
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

  Future<List<Map<String, dynamic>>> getUpcomingStudentBirthdays(
    int days, {
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
        .where((m) => (m['daysLeft'] as int) <= days)
        .toList()
      ..sort((a, b) => (a['daysLeft'] as int).compareTo(b['daysLeft'] as int));
    return list;
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

  // ── Calendar (for principal analytics) ────────────────────────────────────

  /// Returns a map of day-of-month → list of birthday entries for a given month.
  Future<Map<int, List<Map<String, dynamic>>>> getMonthlyBirthdays(
      int month) async {
    final allStaff = await getAllStaffBirthdays();
    final allStudents = await getAllStudentBirthdays();
    final all = [...allStaff, ...allStudents];

    final result = <int, List<Map<String, dynamic>>>{};
    for (final entry in all) {
      final dob = entry['dateOfBirth'] as Timestamp;
      final birth = dob.toDate();
      if (birth.month == month) {
        result.putIfAbsent(birth.day, () => []).add(entry);
      }
    }
    return result;
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Query<Map<String, dynamic>> _buildStudentQuery({
    String? className,
    String? section,
    List<String>? classNames,
  }) {
    // If classNames list provided (subject teacher), fetch all students and
    // filter client-side (Firestore doesn't support OR queries on same field).
    if (classNames != null && classNames.isNotEmpty) {
      return _students; // filter client-side below
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

  // Override for classNames case — used in getAllStudentBirthdays etc.
  // The methods above already handle this by passing null className when
  // classNames is set, so docs are fetched and filtered client-side.
}

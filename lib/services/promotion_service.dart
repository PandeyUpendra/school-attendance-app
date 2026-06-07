import '../models/student.dart';
import '../models/teacher.dart';
import 'student_service.dart';
import 'timetable_service.dart';

/// Outcome of a class-promotion run.
class PromotionResult {
  final int promoted;
  final List<String> skipped; // human-readable "name (roll): reason"
  const PromotionResult(this.promoted, this.skipped);
}

/// Academic-year promotion / rollover (#70).
///
/// Promotes a source class roster into the next class for the new year. For each
/// student a NEW record is created in the target class via the regular add path
/// — which dup-guards the roll AND re-provisions the guardian login to the new
/// class/roll — while the **stable admissionId is carried forward** so the
/// student keeps one identity across years. The source record is then marked
/// `promoted`, which hides it from active rosters but KEEPS its prior-year
/// attendance/fee history intact under the old class. Fee status resets to
/// Pending for the new year, and the new record is owned by the target class
/// teacher so it appears on their (teacherId-filtered) roster.
///
/// This is intentionally additive: it does NOT re-key existing documents or
/// move history. Following a student's full history across years is keyed by
/// [Student.admissionId] (the stable id), which a later reporting layer can use.
class PromotionService {
  static final PromotionService _instance = PromotionService._();
  PromotionService._();
  factory PromotionService() => _instance;

  final StudentService _students = StudentService();
  final TimetableService _timetable = TimetableService();

  Future<PromotionResult> promoteStudents({
    required List<Student> students,
    required String targetClass,
    required String targetSection,
  }) async {
    // Resolve the target class teacher so promoted records are owned by whoever
    // will view that class roster (the roster query filters by teacherId).
    String? targetTeacherId;
    try {
      final teachers = await _timetable.getTeachers();
      final tSec = targetSection.trim();
      Teacher? match;
      for (final t in teachers) {
        if (!t.isClassTeacher) continue;
        if ((t.classTeacherOf ?? '') != targetClass) continue;
        if (tSec.isNotEmpty &&
            t.section.trim().isNotEmpty &&
            t.section.trim() != tSec) {
          continue;
        }
        match = t;
        break;
      }
      targetTeacherId = match?.id;
    } catch (_) {/* best-effort — fall back to carrying the old teacherId */}

    var promoted = 0;
    final skipped = <String>[];
    for (final s in students) {
      if (s.promoted) continue;
      if (s.className == targetClass && s.section == targetSection) {
        skipped.add('${s.name} (roll ${s.roll}): already in $targetClass');
        continue;
      }
      final next = Student(
        id: '', // new doc id derived from target class/roll
        admissionId: s.admissionId, // stable identity carried across years
        roll: s.roll,
        name: s.name,
        className: targetClass,
        section: targetSection,
        fatherName: s.fatherName,
        motherName: s.motherName,
        phone: s.phone,
        parentPhone: s.parentPhone,
        photoPath: s.photoPath,
        photoUrl: s.photoUrl,
        feeStatus: 'Pending', // new academic year — dues recomputed by structure
        teacherId: targetTeacherId ?? s.teacherId,
        guardianDetails: s.guardianDetails,
        guardianEmail: s.guardianEmail,
        dateOfBirth: s.dateOfBirth,
        gender: s.gender,
        address: s.address,
        previousSchool: s.previousSchool,
        emergencyContact: s.emergencyContact,
        bloodGroup: s.bloodGroup,
        allergies: s.allergies,
        transportMode: s.transportMode,
      );
      final err = await _students.addStudent(student: next);
      if (err != null) {
        skipped.add('${s.name} (roll ${s.roll}): $err');
        continue;
      }
      await _students.markPromoted(s);
      promoted++;
    }
    return PromotionResult(promoted, skipped);
  }
}

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
  static PromotionService? _instance;
  final StudentService _students;
  final TimetableService _timetable;

  factory PromotionService({
    StudentService? studentService,
    TimetableService? timetableService,
  }) {
    if (studentService != null || timetableService != null) {
      return PromotionService._(
        studentService ?? StudentService.instance,
        timetableService ?? TimetableService.instance,
      );
    }
    return _instance ??= PromotionService._(
      StudentService.instance,
      TimetableService.instance,
    );
  }

  PromotionService._(this._students, this._timetable);

  Future<PromotionAnalysis> analyzePromotion({
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

    // Fetch target class's raw roster to check for roll and admission ID collisions.
    final List<Student> targetStudents;
    try {
      targetStudents = await _students.getStudentsByClassRaw(
        className: targetClass,
        section: targetSection,
      );
    } catch (e) {
      // If fetching target students fails, we cannot proceed safely with checks.
      return PromotionAnalysis(
        [],
        [],
        students
            .map((s) =>
                '${s.name} (roll ${s.roll}): failed to query target class: $e')
            .toList(),
      );
    }

    final existingRolls = targetStudents.where((s) => !s.promoted).map((s) => s.roll).toSet();
    final existingAdmissions = targetStudents.where((s) => !s.promoted).map((s) => s.admissionId).toSet();

    final toPromoteNew = <Student>[];
    final toPromoteOld = <Student>[];
    final skipped = <String>[];

    for (final s in students) {
      if (s.promoted) {
        continue;
      }
      if (s.className == targetClass && s.section == targetSection) {
        skipped.add('${s.name} (roll ${s.roll}): already in $targetClass');
        continue;
      }

      // Check if student's admissionId is already in target class (i.e. already promoted)
      if (existingAdmissions.contains(s.admissionId)) {
        skipped.add(
            '${s.name} (roll ${s.roll}): already in $targetClass (by admission ID)');
        continue;
      }

      // Check for roll collision
      if (existingRolls.contains(s.roll)) {
        skipped.add(
            '${s.name} (roll ${s.roll}): roll number ${s.roll} already exists in $targetClass');
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

      // Sanitize fields before promoting (same as in StudentService.addStudent)
      final sanitizedNext = next.copyWith(
        name: stripHtml(next.name).trim(),
        fatherName: stripHtml(next.fatherName).trim(),
        motherName: next.motherName != null
            ? stripHtml(next.motherName!).trim()
            : null,
        phone: next.phone.isNotEmpty ? normalizePhone(next.phone) : '',
        parentPhone: next.parentPhone != null && next.parentPhone!.isNotEmpty
            ? normalizePhone(next.parentPhone!)
            : null,
      );

      toPromoteNew.add(sanitizedNext);
      toPromoteOld.add(s);
    }

    return PromotionAnalysis(toPromoteNew, toPromoteOld, skipped);
  }

  Future<PromotionResult> promoteStudents({
    required List<Student> students,
    required String targetClass,
    required String targetSection,
  }) async {
    final analysis = await analyzePromotion(
      students: students,
      targetClass: targetClass,
      targetSection: targetSection,
    );

    // Archive target class students that are currently marked promoted
    // to free up their roll number slots and archive their remarks before overwriting.
    try {
      final targetStudents = await _students.getStudentsByClassRaw(
        className: targetClass,
        section: targetSection,
      );
      for (final ts in targetStudents) {
        if (ts.promoted) {
          await _students.archivePromotedStudent(ts);
        }
      }
    } catch (e) {
      // Non-fatal error during pre-promotion archival, log it or fallback
    }

    if (analysis.toPromoteNew.isNotEmpty) {
      await _students.promoteStudents(analysis.toPromoteNew, analysis.toPromoteOld);
    }

    return PromotionResult(analysis.toPromoteNew.length, analysis.skipped);
  }
}

/// Analysis of a class-promotion run before committing database writes.
class PromotionAnalysis {
  final List<Student> toPromoteNew;
  final List<Student> toPromoteOld;
  final List<String> skipped;
  const PromotionAnalysis(this.toPromoteNew, this.toPromoteOld, this.skipped);
}


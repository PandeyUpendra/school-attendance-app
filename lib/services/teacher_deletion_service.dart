import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/teacher.dart';
import 'auth_service.dart';
import 'timetable_service.dart';

/// Service for the "coordinator requests a teacher deletion, principal or
/// owner approves" workflow.
///
/// Pattern mirrors [StudentService.approveDeletionRequest] but for teachers.
/// Storage:  /schools/{schoolId}/teacher_deletion_requests/{requestId}
/// Rules:    see `firestore.rules` — coordinator creates pending; principal/
///           admin/owner approves or rejects; coordinator can cancel their own.
///
/// Document shape:
///   teacherId          : Teachers collection doc ID
///   teacherName        : convenience for list rendering
///   teacherEmail       : convenience
///   reason             : optional free-text submitted by the coordinator
///   requestedBy        : caller's lowercased email
///   requestedByName    : caller's name (cache for UI)
///   requestedAt        : server timestamp
///   status             : 'pending' | 'approved' | 'rejected' | 'cancelled'
///   reviewedBy         : email of approver/rejecter
///   reviewedByRole     : 'principal' | 'admin' | 'owner'
///   reviewedByName     : cache
///   reviewedAt         : server timestamp
///   rejectionNote      : optional free-text on reject
///   cancelledAt        : server timestamp on cancel
class TeacherDeletionService {
  static final TeacherDeletionService _instance = TeacherDeletionService._();
  TeacherDeletionService._();
  factory TeacherDeletionService() => _instance;

  static final _db = FirebaseFirestore.instance;
  final _timetableService = TimetableService();

  CollectionReference<Map<String, dynamic>> _collection(String schoolId) =>
      _db.collection('schools').doc(schoolId).collection('teacher_deletion_requests');

  // ── Coordinator: request deletion ───────────────────────────────────────

  /// Files a deletion request for [teacher]. Returns the new request id.
  ///
  /// Fails (permission-denied) if the caller is not a coordinator of
  /// [schoolId], or if a pending request for the same teacher already exists
  /// (we enforce this client-side; rules accept the duplicate but the UI
  /// would then show two badges — guard early instead).
  Future<String> requestDeletion({
    required String schoolId,
    required Teacher teacher,
    required String requestedBy,
    String? requestedByName,
    String? reason,
  }) async {
    // Reject duplicate pending requests for the same teacher.
    final dup = await _collection(schoolId)
        .where('teacherId', isEqualTo: teacher.id)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();
    if (dup.docs.isNotEmpty) {
      throw StateError('A pending deletion request already exists for this teacher.');
    }

    final ref = await _collection(schoolId).add({
      'teacherId':       teacher.id,
      'teacherName':     teacher.name,
      'teacherEmail':    teacher.email,
      'reason':          (reason ?? '').trim(),
      'requestedBy':     requestedBy.toLowerCase().trim(),
      'requestedByName': requestedByName ?? '',
      'requestedAt':     FieldValue.serverTimestamp(),
      'status':          'pending',
    });
    return ref.id;
  }

  // ── Streams ─────────────────────────────────────────────────────────────

  /// Stream of pending requests for the approval screen.
  Stream<List<Map<String, dynamic>>> streamPending(String schoolId) =>
      _collection(schoolId)
          .where('status', isEqualTo: 'pending')
          .orderBy('requestedAt', descending: true)
          .snapshots()
          .map(_pack);

  /// Resolved tab — approved + rejected. Cancelled requests are excluded
  /// (they look like noise to the principal); coordinator sees their own
  /// cancelled via [streamMyRequests].
  Stream<List<Map<String, dynamic>>> streamResolved(String schoolId) =>
      _collection(schoolId)
          .where('status', whereIn: ['approved', 'rejected'])
          .orderBy('reviewedAt', descending: true)
          .snapshots()
          .map(_pack);

  /// All requests filed by [requesterEmail]. Used in the coordinator's
  /// "my requests" view if/when it lands; for now mainly handy for tests.
  Stream<List<Map<String, dynamic>>> streamMyRequests({
    required String schoolId,
    required String requesterEmail,
  }) =>
      _collection(schoolId)
          .where('requestedBy', isEqualTo: requesterEmail.toLowerCase().trim())
          .orderBy('requestedAt', descending: true)
          .snapshots()
          .map(_pack);

  /// Map of teacherId → requestId for currently-pending requests in the
  /// school. The management screen uses this to render the "Deletion
  /// requested" pending badge on each teacher card.
  Stream<Map<String, String>> streamPendingByTeacherId(String schoolId) =>
      _collection(schoolId)
          .where('status', isEqualTo: 'pending')
          .snapshots()
          .map((snap) {
        final out = <String, String>{};
        for (final d in snap.docs) {
          final tid = d.data()['teacherId'] as String?;
          if (tid != null && tid.isNotEmpty) out[tid] = d.id;
        }
        return out;
      });

  /// Pending count for dashboard badges.
  Stream<int> streamPendingCount(String schoolId) =>
      _collection(schoolId)
          .where('status', isEqualTo: 'pending')
          .snapshots()
          .map((s) => s.docs.length);

  // ── Approve / reject / cancel ───────────────────────────────────────────

  /// Approves [requestId] and **actually removes the teacher** — deletes the
  /// teacher doc, scrubs every timetable slot, and revokes their login.
  ///
  /// Caller must be principal/admin/owner per security rules.
  ///
  /// We update the request FIRST so the rules' "only status+reviewer fields"
  /// constraint is enforced cleanly. Then we remove the teacher. If the
  /// removal fails after approval, the request is left in 'approved' state
  /// but the teacher record remains — re-running with the same request id
  /// is a no-op on the doc and idempotent on the teacher delete.
  Future<void> approve({
    required String schoolId,
    required String requestId,
    required String reviewerEmail,
    required String reviewerRole,
    String? reviewerName,
  }) async {
    final reqRef = _collection(schoolId).doc(requestId);
    final snap = await reqRef.get();
    if (!snap.exists) throw StateError('Request no longer exists.');
    final teacherId = snap.data()!['teacherId'] as String?;
    final teacherEmail = snap.data()!['teacherEmail'] as String? ?? '';

    await reqRef.update({
      'status':         'approved',
      'reviewedBy':     reviewerEmail.toLowerCase().trim(),
      'reviewedByRole': reviewerRole,
      'reviewedByName': reviewerName ?? '',
      'reviewedAt':     FieldValue.serverTimestamp(),
    });

    if (teacherId != null && teacherId.isNotEmpty) {
      await _timetableService.removeTeacher(schoolId, teacherId);
    }
    if (teacherEmail.isNotEmpty) {
      // Revoke login. removeAllowedUser only deletes the Firestore doc;
      // the Firebase Auth account remains but cannot resolve a role on
      // next login, so the user falls through to the LoginScreen denial.
      try {
        await _timetableService.removeAllowedUser(teacherEmail);
      } catch (_) {
        // Non-fatal — the teacher record is already gone.
      }
    }
  }

  /// Rejects a pending request. [note] is shown back to the coordinator.
  Future<void> reject({
    required String schoolId,
    required String requestId,
    required String reviewerEmail,
    required String reviewerRole,
    String? reviewerName,
    String? note,
  }) async {
    await _collection(schoolId).doc(requestId).update({
      'status':         'rejected',
      'reviewedBy':     reviewerEmail.toLowerCase().trim(),
      'reviewedByRole': reviewerRole,
      'reviewedByName': reviewerName ?? '',
      'reviewedAt':     FieldValue.serverTimestamp(),
      'rejectionNote':  (note ?? '').trim(),
    });
  }

  /// Coordinator cancels their own pending request. The rules check that
  /// the caller matches `requestedBy`.
  Future<void> cancelMyRequest({
    required String schoolId,
    required String requestId,
  }) async {
    await _collection(schoolId).doc(requestId).update({
      'status':      'cancelled',
      'cancelledAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> _pack(QuerySnapshot<Map<String, dynamic>> snap) =>
      snap.docs.map((d) {
        final data = Map<String, dynamic>.from(d.data());
        data['id'] = d.id;
        return data;
      }).toList();

  /// Convenience: returns the current user's session role+email+name from
  /// AuthService. Cached per call site rather than session.
  static Future<Map<String, String>> sessionUser() async {
    final s = await AuthService().getSession();
    if (s == null) return {'role': '', 'email': '', 'name': ''};
    return {
      'role':  (s['role']  as String?) ?? '',
      'email': (s['email'] as String?) ?? '',
      'name':  (s['name']  as String?) ?? '',
    };
  }
}

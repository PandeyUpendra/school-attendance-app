import 'package:cloud_firestore/cloud_firestore.dart';
import '../shared/utils/app_logger.dart';
import 'timetable_service.dart';

/// Service for the "principal requests a coordinator deletion, owner approves" workflow.
///
/// Pattern mirrors [TeacherDeletionService] but for coordinators.
/// Storage:  /schools/{schoolId}/coordinator_deletion_requests/{requestId}
/// Rules:    see `firestore.rules`
///
/// Document shape:
///   coordinatorEmail   : Coordinator's lowercased email (corresponds to allowed_users doc ID)
///   coordinatorName    : convenience for list rendering
///   reason             : optional free-text submitted by the principal
///   requestedBy        : caller's lowercased email
///   requestedByName    : caller's name (cache for UI)
///   requestedAt        : server timestamp
///   status             : 'pending' | 'approved' | 'rejected' | 'cancelled'
///   reviewedBy         : email of approver/rejecter (owner)
///   reviewedByRole     : 'owner' | 'ownerPrincipal'
///   reviewedByName     : cache
///   reviewedAt         : server timestamp
///   rejectionNote      : optional free-text on reject
///   cancelledAt        : server timestamp on cancel
class CoordinatorDeletionService {
  static final CoordinatorDeletionService _instance = CoordinatorDeletionService._();
  CoordinatorDeletionService._();
  factory CoordinatorDeletionService() => _instance;

  static final _db = FirebaseFirestore.instance;
  final _timetableService = TimetableService.instance;

  CollectionReference<Map<String, dynamic>> _collection(String schoolId) =>
      _db.collection('schools').doc(schoolId).collection('coordinator_deletion_requests');

  // ── Principal: request deletion ───────────────────────────────────────

  /// Files a deletion request for [coordinatorEmail]. Returns the new request id.
  Future<String> requestDeletion({
    required String schoolId,
    required String coordinatorEmail,
    required String coordinatorName,
    required String requestedBy,
    String? requestedByName,
    String? reason,
  }) async {
    // Reject duplicate pending requests for the same coordinator.
    final dup = await _collection(schoolId)
        .where('coordinatorEmail', isEqualTo: coordinatorEmail.toLowerCase().trim())
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();
    if (dup.docs.isNotEmpty) {
      throw StateError('A pending deletion request already exists for this coordinator.');
    }

    final ref = await _collection(schoolId).add({
      'coordinatorEmail': coordinatorEmail.toLowerCase().trim(),
      'coordinatorName':  coordinatorName,
      'reason':           (reason ?? '').trim(),
      'requestedBy':      requestedBy.toLowerCase().trim(),
      'requestedByName':  requestedByName ?? '',
      'requestedAt':      FieldValue.serverTimestamp(),
      'status':           'pending',
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

  /// Resolved tab — approved + rejected.
  Stream<List<Map<String, dynamic>>> streamResolved(String schoolId) =>
      _collection(schoolId)
          .where('status', whereIn: ['approved', 'rejected'])
          .orderBy('reviewedAt', descending: true)
          .snapshots()
          .map(_pack);

  /// Map of coordinatorEmail → requestId for currently-pending requests.
  Stream<Map<String, String>> streamPendingByCoordinatorEmail(String schoolId) =>
      _collection(schoolId)
          .where('status', isEqualTo: 'pending')
          .snapshots()
          .map((snap) {
        final out = <String, String>{};
        for (final d in snap.docs) {
          final email = d.data()['coordinatorEmail'] as String?;
          if (email != null && email.isNotEmpty) out[email.toLowerCase().trim()] = d.id;
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

  /// Approves [requestId] and removes the coordinator from allowed_users.
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
    final data = snap.data()!;
    final coordinatorEmail = (data['coordinatorEmail'] as String? ?? '').trim().toLowerCase();

    final batch = _db.batch();

    // a. Update the deletion request status.
    batch.update(reqRef, {
      'status':         'approved',
      'reviewedBy':     reviewerEmail.toLowerCase().trim(),
      'reviewedByRole': reviewerRole,
      'reviewedByName': reviewerName ?? '',
      'reviewedAt':     FieldValue.serverTimestamp(),
    });

    // b. Remove the allowed_users doc to revoke login access.
    if (coordinatorEmail.isNotEmpty) {
      batch.delete(_db.collection('allowed_users').doc(coordinatorEmail));
    }

    await batch.commit();

    // c. Best-effort: revoke Firebase Auth account
    if (coordinatorEmail.isNotEmpty && coordinatorEmail.contains('@')) {
      try {
        await _timetableService.deleteAccountFully(coordinatorEmail);
      } catch (e) {
        AppLogger.d('CoordinatorDeletionService',
            'Post-approval Auth cleanup failed for $coordinatorEmail: $e');
      }
    }
  }

  /// Rejects a pending request.
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

  /// Principal cancels their own pending request.
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
}

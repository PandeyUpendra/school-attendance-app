import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'base_firestore_service.dart';
import 'firestore_service.dart';

/// Push notifications (#52).
///
/// Previously FCM was only half-wired: permission was requested and a token
/// helper existed, but the token was never saved and nothing ever SENT a push,
/// so guardians/teachers got nothing. This service makes it real using FCM
/// **topics**: each device subscribes to the topics that match the audiences it
/// is allowed to see (mirroring NotificationService), and a Cloud Function
/// (`pushOnNotificationCreate`) publishes to the matching topic whenever a
/// notification document is created. No per-token fan-out needed.
///
/// Topic names must stay byte-identical between this client and the server:
///   topic = "s_{schoolId}_{audience}"  with every non [A-Za-z0-9_-] char → "_"
class PushService {
  static final PushService _instance = PushService._();
  PushService._();
  factory PushService() => _instance;

  static const _kSubscribedTopics = 'fcm_subscribed_topics';

  final FirebaseMessaging _fm = FirebaseMessaging.instance;

  static String _sanitize(String s) =>
      s.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  static String topicFor(String schoolId, String audience) =>
      's_${_sanitize(schoolId)}_${_sanitize(audience)}';

  /// The audience channels a viewer is allowed to receive — mirrors
  /// NotificationService._audiencesFor so the device subscribes to exactly the
  /// topics the server publishes to.
  static List<String> _audiencesFor({
    required String role,
    String? teacherId,
    String? studentClass,
    int? studentRoll,
    String? studentAdmissionId,
  }) {
    final a = <String>{'all'};
    if (role == 'coordinator' || role == 'principal') a.add(role);
    if (role == 'teacher' || role == 'subjectTeacher') {
      a.add('teachers');
      if (teacherId != null && teacherId.isNotEmpty) a.add('teacher:$teacherId');
    }
    if (role == 'guardian') {
      a.add('guardians');
      if (studentClass != null && studentClass.isNotEmpty) {
        a.add('class:$studentClass');
        if (studentRoll != null) a.add('guardian:$studentClass:$studentRoll');
      }
      if (studentAdmissionId != null && studentAdmissionId.isNotEmpty) {
        a.add('guardian_adm:$studentAdmissionId');
      }
    }
    return a.toList();
  }

  /// Saves the device token and reconciles topic subscriptions for the current
  /// session. Safe to call repeatedly (diffs against the last subscribed set).
  /// Best-effort: any failure is swallowed so it never blocks login/startup.
  Future<void> syncForSession({
    required String role,
    String? schoolId,
    String? teacherId,
    String? studentClass,
    int? studentRoll,
    String? studentAdmissionId,
  }) async {
    try {
      final sid = (schoolId != null && schoolId.isNotEmpty)
          ? schoolId
          : BaseFirestoreService.currentSchoolId;
      // No 'school_1' fallback: subscribing with a guessed tenant id would
      // deliver another school's push notifications to this device
      // (SCALE-06). Sync is best-effort — skip now; the next login / session
      // restore retries with a resolved school id.
      if (sid == null || sid.isEmpty) return;

      // Persist the token too (makes the previously-dead saveFcmToken live and
      // enables future direct-to-device sends).
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final token = await _fm.getToken();
      if (uid != null && token != null) {
        await FirestoreService.saveFcmToken(uid, token);
      }

      final desired = _audiencesFor(
        role: role,
        teacherId: teacherId,
        studentClass: studentClass,
        studentRoll: studentRoll,
        studentAdmissionId: studentAdmissionId,
      ).map((aud) => topicFor(sid, aud)).toSet();

      final prefs = await SharedPreferences.getInstance();
      final prev = (prefs.getStringList(_kSubscribedTopics) ?? const <String>[])
          .toSet();

      for (final t in prev.difference(desired)) {
        try { await _fm.unsubscribeFromTopic(t); } catch (_) {}
      }
      for (final t in desired.difference(prev)) {
        try { await _fm.subscribeToTopic(t); } catch (_) {}
      }
      await prefs.setStringList(_kSubscribedTopics, desired.toList());
    } catch (_) {/* best-effort — push must never block auth */}
  }

  /// Unsubscribes from every previously-subscribed topic. Call on logout so a
  /// shared device stops receiving the previous user's notifications.
  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final prev = prefs.getStringList(_kSubscribedTopics) ?? const <String>[];
      for (final t in prev) {
        try { await _fm.unsubscribeFromTopic(t); } catch (_) {}
      }
      await prefs.remove(_kSubscribedTopics);
    } catch (_) {}
  }
}

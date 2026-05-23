import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/parental_consent.dart';
import 'audit_log_service.dart';
import 'auth_service.dart';
import 'base_firestore_service.dart';

/// Manages parental consent records for student data processing.
///
/// Firestore path: schools/{sid}/students/{studentDocId}/consents/{consentId}
class ConsentService {
  static final _db  = FirebaseFirestore.instance;
  static final _fba = FirebaseAuth.instance;

  static final ConsentService _instance = ConsentService._();
  ConsentService._();
  factory ConsentService() => _instance;

  // ── Path helpers ──────────────────────────────────────────────────────────

  String _schoolId() =>
      BaseFirestoreService.currentSchoolId ?? AuthService.currentSchoolId;

  CollectionReference _consentsCol(String studentDocId) => _db
      .collection('schools')
      .doc(_schoolId())
      .collection('students')
      .doc(studentDocId)
      .collection('consents');

  // ── OTP / Firebase Phone Auth ─────────────────────────────────────────────

  /// Sends an OTP SMS to [phoneNumber] (E.164, e.g. '+919876543210').
  ///
  /// Returns the [verificationId] needed for [verifyOtp].
  /// On Android, may return '__auto__{smsCode}' if the phone auto-reads it.
  Future<String> sendOtp({
    required String phoneNumber,
    int timeoutSeconds = 90,
  }) {
    final completer = Completer<String>();

    _fba.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: Duration(seconds: timeoutSeconds),
      verificationCompleted: (cred) {
        // Android SMS auto-retrieval; deliver the code separately
        if (!completer.isCompleted) {
          completer.complete('__auto__:${cred.smsCode ?? ''}');
        }
      },
      verificationFailed: (e) {
        if (!completer.isCompleted) {
          completer.completeError(
            Exception('OTP send failed: ${e.message ?? e.code}'),
          );
        }
      },
      codeSent: (verificationId, _) {
        if (!completer.isCompleted) completer.complete(verificationId);
      },
      codeAutoRetrievalTimeout: (_) {/* ignore */},
    );

    return completer.future;
  }

  /// Verifies [smsCode] against [verificationId].
  ///
  /// Returns `true` on success; throws a human-readable [Exception] on failure.
  Future<bool> verifyOtp({
    required String verificationId,
    required String smsCode,
  }) async {
    final cred = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode:        smsCode.trim(),
    );
    try {
      await _fba.signInWithCredential(cred);
      return true;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'invalid-verification-code':
        case 'invalid-verification-id':
          throw Exception('Incorrect OTP. Please try again.');
        case 'session-expired':
          throw Exception('OTP has expired. Please request a new one.');
        default:
          throw Exception('Verification failed: ${e.message ?? e.code}');
      }
    }
  }

  // ── Create consent ────────────────────────────────────────────────────────

  /// Records a new parental consent document.
  ///
  /// Call after [verifyOtp] succeeds, or when marking in-person signing.
  Future<ParentalConsent> createConsent({
    required String             studentDocId,
    required String             guardianName,
    required String             guardianPhone,
    String?                     guardianEmail,
    required ConsentMethod      method,
    String?                     otpVerificationId,
    required List<ConsentScope> scopes,
  }) async {
    final now = Timestamp.now();
    final ref = _consentsCol(studentDocId).doc();

    final consent = ParentalConsent(
      id:                ref.id,
      studentId:         studentDocId,
      guardianName:      guardianName,
      guardianPhone:     guardianPhone,
      guardianEmail:     guardianEmail,
      consentVersion:    kCurrentConsentVersion,
      consentedAt:       now,
      method:            method,
      otpVerificationId: otpVerificationId,
      scopes:            scopes,
    );

    await ref.set(consent.toJson());

    AuditService.emit(
      action:   'create',
      entity:   'consent',
      entityId: '${studentDocId}_${ref.id}',
      after:    {
        'guardianName':   guardianName,
        'method':         method.value,
        'consentVersion': kCurrentConsentVersion,
        'scopes':         scopes.map((s) => s.dataType).toList(),
      },
    );

    return consent;
  }

  // ── Read ──────────────────────────────────────────────────────────────────

  /// Returns all consent records for a student, newest first.
  Future<List<ParentalConsent>> getConsents(String studentDocId) async {
    final snap = await _consentsCol(studentDocId)
        .orderBy('consentedAt', descending: true)
        .get();
    return snap.docs
        .map((d) => ParentalConsent.fromDoc(
              d.id,
              Map<String, dynamic>.from(d.data() as Map),
            ))
        .toList();
  }

  /// Returns the most recent active (non-withdrawn, current-version) consent.
  /// Returns null when no active consent exists.
  Future<ParentalConsent?> getActiveConsent(String studentDocId) async {
    final list = await getConsents(studentDocId);
    for (final c in list) {
      if (c.isActive) return c;
    }
    return null;
  }

  /// Convenience: true when the student has a current, un-withdrawn consent.
  Future<bool> hasActiveConsent(String studentDocId) async =>
      (await getActiveConsent(studentDocId)) != null;

  // ── Withdraw ──────────────────────────────────────────────────────────────

  /// Withdraws [consentId] for [studentDocId].
  ///
  /// Stamps withdrawnAt on the consent doc and creates a workflow document
  /// under `schools/{sid}/consent_withdrawals/{id}` for admin review.
  Future<void> withdrawConsent({
    required String studentDocId,
    required String consentId,
    String? reason,
  }) async {
    final now     = Timestamp.now();
    final session = await AuthService().getSession();
    final actor   = session?['email'] ?? 'guardian';
    final role    = session?['role']  ?? 'guardian';

    await _consentsCol(studentDocId).doc(consentId).update({
      'withdrawnAt':     now,
      'withdrawnReason': reason ?? '',
      'withdrawnBy':     actor,
    });

    // Workflow doc — admin must review and decide on data deletion
    await _db
        .collection('schools')
        .doc(_schoolId())
        .collection('consent_withdrawals')
        .add({
      'studentDocId':    studentDocId,
      'consentId':       consentId,
      'withdrawnAt':     now,
      'withdrawnBy':     actor,
      'withdrawnByRole': role,
      'reason':          reason ?? '',
      'status':          'pending_review',
    });

    AuditService.emit(
      action:   'update',
      entity:   'consent',
      entityId: '${studentDocId}_$consentId',
      after:    {
        'withdrawnAt': now.toDate().toIso8601String(),
        'reason':      reason,
      },
      reason: 'consent_withdrawal',
    );
  }

  // ── Re-consent check ──────────────────────────────────────────────────────

  /// Returns true when the student previously consented but the version has
  /// since been bumped — guardian needs to re-consent.
  Future<bool> needsReConsent(String studentDocId) async {
    final list = await getConsents(studentDocId);
    if (list.isEmpty) return false; // New student — handled by enrollment flow

    final active = list.where((c) => c.withdrawnAt == null).toList();
    if (active.isEmpty) return false; // All withdrawn — not a re-consent case

    return active.every((c) => c.consentVersion != kCurrentConsentVersion);
  }

  // ── Batch helpers for dashboards ──────────────────────────────────────────

  /// Returns a set of studentDocIds that have at least one active consent,
  /// from the given [studentDocIds].
  Future<Set<String>> filterHasActiveConsent(
      List<String> studentDocIds) async {
    if (studentDocIds.isEmpty) return {};
    final results = await Future.wait(
      studentDocIds.map((id) async {
        final has = await hasActiveConsent(id);
        return has ? id : null;
      }),
    );
    return results.whereType<String>().toSet();
  }
}

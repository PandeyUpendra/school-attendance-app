import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../models/app_user.dart';

/// Admin-only service for creating and managing school users in the `users`
/// Firestore collection (separate from the legacy `allowed_users` collection).
class UserService {
  // Firebase Web API key — used only to create Auth accounts without
  // displacing the currently signed-in admin/owner session.
  static const _apiKey = 'AIzaSyB9dyjWRfwMeq8-J6juhYdizI-584MCkBE';
  static final _db     = FirebaseFirestore.instance;

  /// Creates a Firebase Auth account + Firestore `users/{uid}` document,
  /// then sends a password-setup invitation email to the new user.
  /// Returns the new user's uid.
  static Future<String> createUser({
    required String email,
    required String password,
    required String name,
    required UserRole role,
    required String schoolId,
    required List<String> classIds,
    String? studentId,
    String? createdBy,
  }) async {
    final normEmail = email.trim().toLowerCase();

    // 1. Create Firebase Auth account via REST (does not sign out the caller).
    final res = await http.post(
      Uri.parse(
          'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$_apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email':            normEmail,
        'password':         password,
        'returnSecureToken': false,
      }),
    );

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (data['localId'] == null) {
      final errMsg =
          (data['error'] as Map?)?['message'] as String? ?? 'Unknown error';
      throw Exception(_friendlyAuthError(errMsg));
    }

    final uid = data['localId'] as String;

    // 2. Create Firestore user doc with required security fields.
    await _db.collection('users').doc(uid).set({
      'name':      name,
      'email':     normEmail,
      'role':      role.name,
      'schoolId':  schoolId,
      'classIds':  classIds,
      'status':    'pending',
      'createdBy': createdBy ?? '',
      'createdAt': FieldValue.serverTimestamp(),
      if (studentId != null && studentId.isNotEmpty) 'studentId': studentId,
    });

    // 3. Send invitation / password-setup email.
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: normEmail);
    } catch (_) {
      // Non-fatal — admin can resend via [resendInvitation].
    }

    return uid;
  }

  /// Resends the password-setup invitation email.
  static Future<void> resendInvitation(String email) async {
    await FirebaseAuth.instance
        .sendPasswordResetEmail(email: email.trim().toLowerCase());
  }

  /// Fetches all users belonging to a school.
  static Future<List<AppUser>> getSchoolUsers(String schoolId) async {
    final snap = await _db
        .collection('users')
        .where('schoolId', isEqualTo: schoolId)
        .get();
    return snap.docs
        .map((d) => AppUser.fromFirestore(d.data(), d.id))
        .toList();
  }

  /// Updates a user's role, class assignments, and optionally studentId.
  static Future<void> updateUserAccess(
    String uid, {
    required UserRole role,
    required List<String> classIds,
    String? studentId,
  }) async {
    final update = <String, dynamic>{
      'role':     role.name,
      'classIds': classIds,
    };
    if (studentId != null) update['studentId'] = studentId;
    await _db.collection('users').doc(uid).update(update);
  }

  /// Sets a user's status to active/pending/suspended.
  static Future<void> setUserStatus(String uid, UserStatus status) async {
    await _db.collection('users').doc(uid).update({'status': status.name});
  }

  /// Deletes the Firestore user document (Firebase Auth account deletion
  /// requires Admin SDK; the Auth account becomes unreachable without the doc).
  static Future<void> deleteUser(String uid) async {
    await _db.collection('users').doc(uid).delete();
  }

  static String _friendlyAuthError(String msg) {
    if (msg.contains('EMAIL_EXISTS')) return 'This email is already registered.';
    if (msg.contains('WEAK_PASSWORD')) return 'Password must be at least 6 characters.';
    if (msg.contains('INVALID_EMAIL')) return 'Invalid email address.';
    return msg;
  }
}

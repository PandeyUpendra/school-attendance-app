import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/app_user.dart';

/// Admin-only service for creating and managing school users.
class UserService {
  // Firebase Web API key for the attendanceapp-e76e1 project
  static const _apiKey = 'AIzaSyB9dyjWRfwMeq8-J6juhYdizI-584MCkBE';
  static final _db = FirebaseFirestore.instance;

  /// Creates a Firebase Auth account + Firestore user doc.
  /// Returns the new user's uid.
  static Future<String> createUser({
    required String email,
    required String password,
    required String name,
    required UserRole role,
    required String schoolId,
    required List<String> classIds,
    String? studentId,
  }) async {
    // 1. Create Firebase Auth user via REST
    final res = await http.post(
      Uri.parse(
          'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$_apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'returnSecureToken': true,
      }),
    );

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (data['localId'] == null) {
      final errMsg =
          (data['error'] as Map?)?['message'] as String? ?? 'Unknown error';
      throw Exception(_friendlyAuthError(errMsg));
    }

    final uid = data['localId'] as String;

    // 2. Create Firestore user doc
    await _db.collection('users').doc(uid).set({
      'name': name,
      'email': email,
      'role': role.name,
      'schoolId': schoolId,
      'classIds': classIds,
      if (studentId != null && studentId.isNotEmpty) 'studentId': studentId,
    });

    return uid;
  }

  /// Fetch all users belonging to a school.
  static Future<List<AppUser>> getSchoolUsers(String schoolId) async {
    final snap = await _db
        .collection('users')
        .where('schoolId', isEqualTo: schoolId)
        .get();
    return snap.docs
        .map((d) => AppUser.fromFirestore(d.data(), d.id))
        .toList();
  }

  /// Update a user's role, class assignments, and optionally studentId.
  static Future<void> updateUserAccess(
    String uid, {
    required UserRole role,
    required List<String> classIds,
    String? studentId,
  }) async {
    final Map<String, dynamic> update = {
      'role': role.name,
      'classIds': classIds,
    };
    if (studentId != null) update['studentId'] = studentId;
    await _db.collection('users').doc(uid).update(update);
  }

  static String _friendlyAuthError(String msg) {
    if (msg.contains('EMAIL_EXISTS')) return 'Email already in use.';
    if (msg.contains('WEAK_PASSWORD')) return 'Password must be 6+ characters.';
    if (msg.contains('INVALID_EMAIL')) return 'Invalid email address.';
    return msg;
  }
}

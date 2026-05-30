import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// One-time migration: converts [allowed_users] from Firestore-password
/// authentication to Firebase Auth.
///
/// What it does for each document in [allowed_users]:
///   1. If the document has a [password] field (legacy hashed credential):
///      a. Creates a Firebase Auth account via REST if one doesn't exist.
///         (Uses a random temp password — EMAIL_EXISTS is silently skipped.)
///      b. Sends a password-reset email so the user sets their own password.
///      c. Deletes the [password] field from the Firestore document.
///   2. If the document already has no [password] field, no action is taken.
///
/// Safety:
///   - **Idempotent**: safe to run multiple times. EMAIL_EXISTS and
///     already-removed [password] fields are both handled gracefully.
///   - **Non-destructive**: only the [password] field is removed; every
///     other field is left intact.
///   - This script does NOT sign out the currently authenticated user.
///
/// Usage (run from any admin context where Firebase is initialised):
/// ```dart
/// final result = await MigrateUsersScript().run(onProgress: print);
/// print('Migrated ${result.migrated} / ${result.total} users');
/// ```
class MigrateUsersScript {
  static const _firebaseApiKey = 'AIzaSyB9dyjWRfwMeq8-J6juhYdizI-584MCkBE';

  final _db = FirebaseFirestore.instance;

  /// Runs the migration.
  ///
  /// [onProgress] is called with a human-readable status line for each user
  /// processed, suitable for display in a migration progress dialog.
  ///
  /// Returns a [MigrationResult] summary.
  Future<MigrationResult> run({
    void Function(String message)? onProgress,
  }) async {
    onProgress?.call('Starting migration…');

    final snap = await _db.collection('allowed_users').get();
    final total = snap.docs.length;
    int migrated = 0;
    int skipped  = 0;
    int errors   = 0;

    for (final doc in snap.docs) {
      final email = doc.id;
      final data  = Map<String, dynamic>.from(doc.data());

      // Skip documents that have already been migrated (no password field).
      if (!data.containsKey('password')) {
        onProgress?.call('  ✓ $email — already migrated, skipped');
        skipped++;
        continue;
      }

      onProgress?.call('  → $email …');

      try {
        // Step 1: create Firebase Auth account if it doesn't exist.
        final authCreated = await _ensureAuthAccount(email);

        // Step 2: send password-reset / invite email.
        if (authCreated) {
          try {
            await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
            onProgress?.call('      ✉ invite email sent');
          } catch (_) {
            // Non-fatal — admin can resend manually.
            onProgress?.call('      ⚠ invite email failed (non-fatal)');
          }
        } else {
          onProgress?.call('      ℹ Auth account already existed');
        }

        // Step 3: remove the password field from Firestore.
        await doc.reference.update({'password': FieldValue.delete()});

        onProgress?.call('      ✓ password field removed');
        migrated++;
      } catch (e) {
        onProgress?.call('      ✗ ERROR: $e');
        errors++;
      }
    }

    final result = MigrationResult(
      total:    total,
      migrated: migrated,
      skipped:  skipped,
      errors:   errors,
    );

    onProgress?.call(
      '\nDone. ${result.migrated} migrated, '
      '${result.skipped} already done, ${result.errors} errors.',
    );

    return result;
  }

  /// Creates a Firebase Auth account for [email] via the Identity Toolkit REST
  /// API (does not sign out the current user).
  ///
  /// Returns [true] if the account was newly created, [false] if it already
  /// existed (EMAIL_EXISTS).
  ///
  /// Throws on unexpected REST errors.
  Future<bool> _ensureAuthAccount(String email) async {
    // Use a random-enough temp password — the user will replace it via
    // the password-reset link.
    final tempPass =
        'Tmp_${email.hashCode.abs()}${DateTime.now().millisecondsSinceEpoch}!Aa1';

    final res = await http.post(
      Uri.parse(
          'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$_firebaseApiKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email':             email,
        'password':          tempPass,
        'returnSecureToken': false,
      }),
    );

    final body    = jsonDecode(res.body) as Map<String, dynamic>;
    final errCode = (body['error'] as Map?)?['message'] as String? ?? '';

    if (errCode == 'EMAIL_EXISTS') return false;   // already has Auth account
    if (body['localId'] != null)   return true;    // newly created

    // Unexpected error
    throw Exception('Firebase Auth REST error for $email: $errCode');
  }
}

/// Summary returned by [MigrateUsersScript.run].
class MigrationResult {
  final int total;
  final int migrated;
  final int skipped;
  final int errors;

  const MigrationResult({
    required this.total,
    required this.migrated,
    required this.skipped,
    required this.errors,
  });

  bool get hasErrors => errors > 0;

  @override
  String toString() =>
      'MigrationResult(total: $total, migrated: $migrated, '
      'skipped: $skipped, errors: $errors)';
}

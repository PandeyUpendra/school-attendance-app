#!/usr/bin/env dart
// tool/scripts/normalize_guardian_emails.dart
//
// One-time migration script (Issue 20 — Group E):
// Lowercases all guardianEmail fields on student documents to ensure that
// Firestore rules can reliably compare request.auth.token.email (always
// lowercase from Firebase Auth) against the stored email.
//
// Run once against production with a Firebase Admin SDK service account:
//   dart run tool/scripts/normalize_guardian_emails.dart
//
// Requirements: Must be run with GOOGLE_APPLICATION_CREDENTIALS set to a
// service-account JSON with Firestore read/write access.
//
// Safety: Skips documents where guardianEmail is already lowercase or empty.
// Sets a migrationVersion flag in system/migrations when done.

import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> main() async {
  print('🔄 Starting guardian email normalization migration...');

  final db = FirebaseFirestore.instance;

  // Check migration version — idempotent guard.
  final migrationRef = db.collection('system').doc('migrations');
  final migrationSnap = await migrationRef.get();
  final versions = (migrationSnap.data()?['completedMigrations'] as List<dynamic>?)
      ?.cast<String>()
      .toSet() ?? {};

  const migrationKey = 'normalize_guardian_emails_v1';
  if (versions.contains(migrationKey)) {
    print('✅ Migration "$migrationKey" already completed. Skipping.');
    return;
  }

  // Iterate all school collections
  final schoolsSnap = await db.collection('schools').get();
  int totalUpdated = 0;

  for (final schoolDoc in schoolsSnap.docs) {
    final schoolId = schoolDoc.id;
    print('  Processing school: $schoolId');

    final studentsSnap = await db
        .collection('schools')
        .doc(schoolId)
        .collection('students')
        .get();

    for (final studentDoc in studentsSnap.docs) {
      final data = studentDoc.data();
      final rawEmail = data['guardianEmail'] as String?;
      if (rawEmail == null || rawEmail.isEmpty) continue;
      final normalized = rawEmail.trim().toLowerCase();
      if (normalized == rawEmail) continue; // already normalized

      await studentDoc.reference.update({'guardianEmail': normalized});
      totalUpdated++;
      print('    Updated ${studentDoc.id}: "$rawEmail" → "$normalized"');
    }
  }

  // Mark migration as done.
  await migrationRef.set({
    'completedMigrations': FieldValue.arrayUnion([migrationKey]),
    'lastRunAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  print('✅ Migration complete. Updated $totalUpdated student documents.');
}

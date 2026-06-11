#!/usr/bin/env dart
// tool/scripts/migrate_attendance_format.dart
//
// One-time migration script (Issue 28 — Group J):
// Converts legacy boolean attendance records (roll → true/false) to the
// current string format (roll → 'Present'/'Absent').
//
// Run once against production:
//   dart run tool/scripts/migrate_attendance_format.dart
//
// Requirements: Must be run with GOOGLE_APPLICATION_CREDENTIALS set to a
// service-account JSON with Firestore read/write access.
//
// Safety: Only touches documents that have boolean values. String values
// ('Present', 'Absent', 'Leave') are left unchanged. Sets a migrationVersion
// flag in system/migrations when done.

import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> main() async {
  print('🔄 Starting attendance format migration (bool → string)...');

  final db = FirebaseFirestore.instance;

  // Idempotent guard via migration version.
  final migrationRef = db.collection('system').doc('migrations');
  final migrationSnap = await migrationRef.get();
  final versions = (migrationSnap.data()?['completedMigrations'] as List<dynamic>?)
      ?.cast<String>()
      .toSet() ?? {};

  const migrationKey = 'migrate_attendance_bool_to_string_v1';
  if (versions.contains(migrationKey)) {
    print('✅ Migration "$migrationKey" already completed. Skipping.');
    return;
  }

  final schoolsSnap = await db.collection('schools').get();
  int docsUpdated = 0;
  int rollsConverted = 0;

  for (final schoolDoc in schoolsSnap.docs) {
    final schoolId = schoolDoc.id;
    print('  Processing school: $schoolId');

    final attendanceSnap = await db
        .collection('schools')
        .doc(schoolId)
        .collection('attendance')
        .get();

    for (final attDoc in attendanceSnap.docs) {
      final data = attDoc.data();
      final rolls = data['rolls'] as Map<String, dynamic>?;
      if (rolls == null || rolls.isEmpty) continue;

      final updates = <String, dynamic>{};
      rolls.forEach((roll, value) {
        if (value is bool) {
          updates['rolls.$roll'] = value ? 'Present' : 'Absent';
          rollsConverted++;
        }
        // String values ('Present', 'Absent', 'Leave') are left as-is.
      });

      if (updates.isNotEmpty) {
        await attDoc.reference.update(updates);
        docsUpdated++;
        print('    Converted ${updates.length} rolls in ${attDoc.id}');
      }
    }
  }

  // Mark migration as done.
  await migrationRef.set({
    'completedMigrations': FieldValue.arrayUnion([migrationKey]),
    'lastRunAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  print('✅ Migration complete. Updated $docsUpdated docs, converted $rollsConverted roll entries.');
}

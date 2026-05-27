/// migrate_to_multitenant.dart
///
/// One-shot migration: copies every root Firestore collection to
/// schools/{targetSchoolId}/{collection}/. Run from a Dart VM with access to
/// the Firebase Admin SDK credentials (e.g. via FlutterFire CLI environment or
/// a service-account key injected via GOOGLE_APPLICATION_CREDENTIALS).
///
/// Usage:
///   dart run lib/scripts/migrate_to_multitenant.dart [school_id]
///
///   school_id  — target school document ID (default: school_1)
///
/// Safety guarantees:
///   • READS source → WRITES destination (no source deletion in this run).
///   • Idempotent: skips docs that already exist at the destination path.
///   • Verifies doc-count parity before marking a collection done.
///   • Writes a structured log to migration_log.txt beside the script.
///   • Deletion is a SEPARATE MANUAL STEP — see "Delete source" section at end.
///
/// Collections migrated:
///   students, attendance, teachers, settings, timetable, duties,
///   substitutions, leave_applications, notifications, announcements,
///   homework, exams, fees, copy_checks, student_deletion_requests
///
/// Collections that stay at root (intentionally skipped):
///   allowed_users  — user→school mapping; must remain at root for login.
///
/// NOTE: This script uses the `cloud_firestore` Dart package from the project's
/// pubspec. Run it from the project root so imports resolve correctly.
/// For large collections (>500 docs) the script batches in chunks of 400 to
/// stay within Firestore's 500-operations-per-batch limit.
library;

// ignore_for_file: avoid_print

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';

// ── Collections to migrate ────────────────────────────────────────────────────

/// Flat collections: every document is copied as-is.
const _flatCollections = [
  'students',
  'teachers',
  'timetable',
  'duties',
  'substitutions',
  'leave_applications',
  'notifications',
  'announcements',
  'homework',
  'exams',
  'fees',
  'copy_checks',
  'student_deletion_requests',
];

/// Collections that have a sub-collection that must be recursively migrated.
/// Format: { parentCollection: [subCollectionName, ...] }
const _collectionsWithSubs = {
  'students': ['remarks'],
};

/// Special: settings only has one doc ('main'); copy it verbatim.
const _settingsDocId = 'main';

/// attendance docs use the root collection directly (no sub-collections).
const _attendanceCollection = 'attendance';

// ── Firestore batch size (leave headroom under the 500-op limit) ──────────────
const _batchSize = 400;

// ── Log helpers ───────────────────────────────────────────────────────────────

late final IOSink _logSink;
int _migratedTotal  = 0;
int _skippedTotal   = 0;
int _errorTotal     = 0;

void _log(String msg) {
  final line = '[${DateTime.now().toIso8601String()}] $msg';
  print(line);
  _logSink.writeln(line);
}

// ── Main ──────────────────────────────────────────────────────────────────────

Future<void> main(List<String> args) async {
  final targetSchoolId = args.isNotEmpty ? args[0] : 'school_1';

  // Open log file next to the project root.
  final logFile = File('migration_log.txt');
  _logSink = logFile.openWrite(mode: FileMode.append);
  _log('━━━ Migration START — target school: $targetSchoolId ━━━');

  // Initialise Firebase (uses the project's firebase_options.dart).
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final db = FirebaseFirestore.instance;

  // Destination root reference.
  final schoolRef = db.collection('schools').doc(targetSchoolId);

  try {
    // 1. Migrate settings (single doc).
    await _migrateSettingsDoc(db, schoolRef);

    // 2. Migrate attendance (flat, no sub-collections).
    await _migrateFlatCollection(
        db, schoolRef, _attendanceCollection, subCollections: const []);

    // 3. Migrate all other flat collections.
    for (final col in _flatCollections) {
      final subs = _collectionsWithSubs[col] ?? [];
      await _migrateFlatCollection(db, schoolRef, col, subCollections: subs);
    }
  } catch (e, st) {
    _log('❌ FATAL: $e\n$st');
    _errorTotal++;
  }

  _log('━━━ Migration DONE — migrated: $_migratedTotal, '
      'skipped (already existed): $_skippedTotal, '
      'errors: $_errorTotal ━━━');
  _log('');
  _log('Next steps:');
  _log('  1. Verify counts in Firebase Console under schools/$targetSchoolId/');
  _log('  2. Run the app and test all features.');
  _log('  3. Only then delete source collections (see delete_source_collections.dart).');
  _log('');

  await _logSink.flush();
  await _logSink.close();
}

// ── Migrate settings/main ──────────────────────────────────────────────────────

Future<void> _migrateSettingsDoc(
    FirebaseFirestore db, DocumentReference schoolRef) async {
  _log('→ settings/$_settingsDocId');
  final srcDoc  = await db.collection('settings').doc(_settingsDocId).get();
  if (!srcDoc.exists || srcDoc.data() == null) {
    _log('  ⚠ settings/$_settingsDocId not found at root — skipping.');
    return;
  }

  final dstRef = schoolRef.collection('settings').doc(_settingsDocId);
  final dstDoc = await dstRef.get();
  if (dstDoc.exists) {
    _log('  ⏭ already exists — skipped.');
    _skippedTotal++;
    return;
  }

  await dstRef.set(srcDoc.data()!);
  _log('  ✓ copied settings/$_settingsDocId');
  _migratedTotal++;

  // Count parity (trivially 1 → 1).
  _log('  ✓ parity OK (1 → 1)');
}

// ── Generic flat-collection migration ─────────────────────────────────────────

Future<void> _migrateFlatCollection(
  FirebaseFirestore db,
  DocumentReference schoolRef,
  String collectionName, {
  required List<String> subCollections,
}) async {
  _log('→ $collectionName');

  final srcCol = db.collection(collectionName);
  final dstCol = schoolRef.collection(collectionName);

  // Fetch all source docs.
  final srcSnap = await srcCol.get();
  if (srcSnap.docs.isEmpty) {
    _log('  ⚠ empty — skipping.');
    return;
  }
  _log('  source docs: ${srcSnap.docs.length}');

  int collectionMigrated = 0;
  int collectionSkipped  = 0;

  // Process in batches.
  final chunks = _chunk(srcSnap.docs, _batchSize);
  for (final chunk in chunks) {
    final batch = db.batch();
    int batchOps = 0;

    for (final srcDoc in chunk) {
      final dstDocRef = dstCol.doc(srcDoc.id);

      // Idempotency check: skip if destination already exists.
      final dstSnap = await dstDocRef.get();
      if (dstSnap.exists) {
        collectionSkipped++;
        _skippedTotal++;
        continue;
      }

      batch.set(dstDocRef, srcDoc.data());
      batchOps++;
      collectionMigrated++;
      _migratedTotal++;
    }

    if (batchOps > 0) await batch.commit();
  }

  // Migrate sub-collections for each source doc.
  if (subCollections.isNotEmpty) {
    for (final srcDoc in srcSnap.docs) {
      for (final subCol in subCollections) {
        await _migrateSubCollection(
          db,
          srcRef: srcCol.doc(srcDoc.id),
          dstRef: dstCol.doc(srcDoc.id),
          subCollectionName: subCol,
        );
      }
    }
  }

  // Count parity verification.
  final dstSnap = await dstCol.get();
  final srcCount = srcSnap.docs.length;
  final dstCount = dstSnap.docs.length;

  _log('  migrated: $collectionMigrated, skipped: $collectionSkipped');
  if (dstCount >= srcCount) {
    _log('  ✓ parity OK (src=$srcCount, dst=$dstCount)');
  } else {
    _log('  ❌ PARITY MISMATCH (src=$srcCount, dst=$dstCount) — '
        'investigate before deleting source!');
    _errorTotal++;
  }
}

// ── Sub-collection migration ───────────────────────────────────────────────────

Future<void> _migrateSubCollection(
  FirebaseFirestore db, {
  required DocumentReference srcRef,
  required DocumentReference dstRef,
  required String subCollectionName,
}) async {
  final srcSubSnap = await srcRef.collection(subCollectionName).get();
  if (srcSubSnap.docs.isEmpty) return;

  final dstSubCol = dstRef.collection(subCollectionName);
  final chunks    = _chunk(srcSubSnap.docs, _batchSize);

  for (final chunk in chunks) {
    final batch = db.batch();
    int batchOps = 0;

    for (final subDoc in chunk) {
      final dstSubRef  = dstSubCol.doc(subDoc.id);
      final dstSubSnap = await dstSubRef.get();
      if (dstSubSnap.exists) {
        _skippedTotal++;
        continue;
      }
      batch.set(dstSubRef, subDoc.data());
      batchOps++;
      _migratedTotal++;
    }

    if (batchOps > 0) await batch.commit();
  }

  _log('    sub[$subCollectionName] under ${srcRef.id}: '
      '${srcSubSnap.docs.length} docs');
}

// ── Utility: split list into fixed-size chunks ────────────────────────────────

List<List<T>> _chunk<T>(List<T> items, int size) {
  final result = <List<T>>[];
  for (var i = 0; i < items.length; i += size) {
    result.add(items.sublist(i, (i + size).clamp(0, items.length)));
  }
  return result;
}

// ─────────────────────────────────────────────────────────────────────────────
//  DELETE SOURCE COLLECTIONS (separate manual step — do NOT run until verified)
// ─────────────────────────────────────────────────────────────────────────────
//
// After verifying the migration:
//
//   1. Open Firebase Console → Firestore.
//   2. For each collection in [_flatCollections] + ['attendance', 'settings']:
//      a. Click the collection.
//      b. Click the kebab menu → "Delete collection".
//   3. allowed_users must NOT be deleted — it stays at root permanently.
//
// Alternatively, write a dart script that calls:
//   await _deleteCollection(db, collectionName);
//
// where _deleteCollection batch-deletes all docs in chunks of 400.
// Do this only after the app has been running on the new paths for ≥ 24 hours.
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Database migration script to transition allowed_users collection from email keys to UID keys.
 *
 * Sourced from functions/scripts/backfill_claims.js style.
 *
 * Usage:
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccountKey.json
 *   node scripts/migrate_allowed_users_to_uid.js --dry-run
 *   node scripts/migrate_allowed_users_to_uid.js
 */
const admin = require("firebase-admin");

const DRY_RUN = process.argv.includes("--dry-run");
admin.initializeApp();

(async () => {
  const db = admin.firestore();
  const allowedUsersColl = db.collection("allowed_users");
  const snap = await allowedUsersColl.get();

  let migrated = 0;
  let skipped = 0;
  let errors = 0;

  console.log(`Starting allowed_users migration. Total documents: ${snap.docs.length}`);

  for (const doc of snap.docs) {
    const docId = doc.id;
    const data = doc.data() || {};

    // If docId does not contain '@', it's already migrated (since it's a UID).
    if (!docId.includes("@")) {
      console.log(`  ✓ ${docId} — already migrated (UID key), skipped`);
      skipped++;
      continue;
    }

    const email = docId.toLowerCase().trim();
    console.log(`  → Migrating email key: ${email} …`);

    try {
      // Find the user's UID by email.
      let user;
      try {
        user = await admin.auth().getUserByEmail(email);
      } catch (err) {
        if (err.code === "auth/user-not-found") {
          console.log(`    ⚠️ User not found in Firebase Auth. Creating user…`);
          if (!DRY_RUN) {
            user = await admin.auth().createUser({
              email: email,
              emailVerified: true,
              disabled: false,
            });
            console.log(`      ✓ Created Auth account with UID: ${user.uid}`);
          } else {
            console.log(`      (dry-run) would create Auth account`);
            skipped++;
            continue;
          }
        } else {
          throw err;
        }
      }

      const uid = user.uid;
      console.log(`    Found UID: ${uid}`);

      if (!DRY_RUN) {
        // Copy document to new ID (UID)
        await allowedUsersColl.doc(uid).set(data);
        // Delete old document
        await doc.ref.delete();
        console.log(`    ✓ Migrated allowed_users/${email} to allowed_users/${uid}`);
      } else {
        console.log(`    (dry-run) would migrate allowed_users/${email} to allowed_users/${uid}`);
      }
      migrated++;
    } catch (e) {
      console.error(`    ✗ ERROR migrating ${email}:`, e);
      errors++;
    }
  }

  console.log(`\nMigration complete. Migrated: ${migrated}, Skipped: ${skipped}, Errors: ${errors}`);
  process.exit(errors > 0 ? 1 : 0);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});

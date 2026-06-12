/**
 * Migration script: standardizes allowed_users document IDs.
 *
 * Standardizes all allowed_users documents to be keyed by the user's lowercased email
 * address. If a document is currently keyed by UID, it resolves the email from
 * Firebase Auth, copies the data to the email-keyed document, and deletes the old UID document.
 *
 * Usage (from functions/):
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccountKey.json
 *   node scripts/standardize_allowed_users.js --dry-run
 *   node scripts/standardize_allowed_users.js
 */
const admin = require("firebase-admin");

const DRY_RUN = process.argv.includes("--dry-run");

// Initialize admin if not already initialized
if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();
const auth = admin.auth();

const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

async function runMigration() {
  console.log(`Starting allowed_users standardization ${DRY_RUN ? "(DRY RUN)" : ""}`);
  
  const snap = await db.collection("allowed_users").get();
  console.log(`Found ${snap.docs.length} allowed_users documents.`);
  
  let migrated = 0;
  let kept = 0;
  let errors = 0;

  for (const doc of snap.docs) {
    const docId = doc.id;
    const data = doc.data() || {};
    
    // Check if the document ID is already a lowercased email
    if (EMAIL_RE.test(docId) && docId === docId.toLowerCase()) {
      kept++;
      continue;
    }

    let email = null;
    let isUid = false;

    if (EMAIL_RE.test(docId)) {
      // It is an email but not lowercased
      email = docId.toLowerCase().trim();
    } else {
      // It is likely a UID. Resolve email from Firebase Auth
      isUid = true;
      try {
        const userRecord = await auth.getUser(docId);
        if (userRecord.email) {
          email = userRecord.email.toLowerCase().trim();
        } else {
          console.warn(`User UID ${docId} does not have an email address in Auth.`);
        }
      } catch (err) {
        console.error(`Failed to lookup Auth user for UID ${docId}:`, err.message);
        errors++;
        continue;
      }
    }

    if (!email) {
      console.warn(`Skipping document ${docId} — cannot resolve email.`);
      errors++;
      continue;
    }

    console.log(`Migrating doc [${docId}] -> email [${email}]`);
    migrated++;

    if (!DRY_RUN) {
      const batch = db.batch();
      const newDocRef = db.collection("allowed_users").doc(email);
      const oldDocRef = db.collection("allowed_users").doc(docId);

      // Merge data if the email doc already exists, otherwise write new doc
      const newDocSnap = await newDocRef.get();
      if (newDocSnap.exists) {
        // Merge strategy: keep existing newDoc details, overlaying any old doc keys that are missing
        const mergedData = Object.assign({}, data, newDocSnap.data());
        batch.set(newDocRef, mergedData);
      } else {
        batch.set(newDocRef, data);
      }

      // Delete the old doc
      batch.delete(oldDocRef);

      await batch.commit();

      // Refresh custom claims for the user so it takes effect
      try {
        const userRecord = await auth.getUserByEmail(email);
        const claims = {
          role: data.role ? String(data.role) : null,
          schoolId: data.schoolId ? String(data.schoolId) : null,
          classIds: data.classIds ? data.classIds : [],
          studentClass: data.studentClass ? String(data.studentClass) : null,
          studentRoll: data.studentRoll ? Number(data.studentRoll) : null,
          studentSection: data.studentSection ? String(data.studentSection) : null,
          studentAdmissionId: data.studentAdmissionId ? String(data.studentAdmissionId) : null,
        };
        await auth.setCustomUserClaims(userRecord.uid, claims);
        console.log(`  Updated Auth custom claims for ${email}`);
      } catch (claimsErr) {
        console.warn(`  Could not set custom claims for ${email} (Auth account might not exist yet):`, claimsErr.message);
      }
    }
  }

  console.log("\nStandardization Summary:");
  console.log(`  Kept unchanged: ${kept}`);
  console.log(`  Migrated: ${migrated}`);
  console.log(`  Errors/Skipped: ${errors}`);
  console.log(`Standardization completed successfully.`);
}

runMigration().catch((e) => {
  console.error("Migration failed:", e);
  process.exit(1);
});

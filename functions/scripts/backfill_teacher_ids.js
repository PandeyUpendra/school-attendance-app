/**
 * Script to backfill missing teacherId fields in the allowed_users collection.
 * For each teacher, if teacherId is missing, it looks up the teacher profile in
 * schools/{schoolId}/teachers/ by email, updates the allowed_users document,
 * and sets the custom claims.
 *
 * Usage (from functions/):
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccountKey.json
 *   node scripts/backfill_teacher_ids.js --dry-run
 *   node scripts/backfill_teacher_ids.js
 */
const admin = require("firebase-admin");

const DRY_RUN = process.argv.includes("--dry-run");

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();
const auth = admin.auth();

(async () => {
  console.log(`Starting teacherId backfill migration ${DRY_RUN ? "(DRY RUN)" : ""}`);

  const snap = await db.collection("allowed_users").get();
  console.log(`Found ${snap.docs.length} allowed_users documents.`);

  let updated = 0;
  let alreadyCorrect = 0;
  let skippedNonTeacher = 0;
  let teacherNotFound = 0;
  let errors = 0;

  for (const doc of snap.docs) {
    const email = doc.id.toLowerCase().trim();
    const d = doc.data() || {};
    const role = d.role;

    if (role !== "teacher" && role !== "subjectTeacher") {
      skippedNonTeacher++;
      continue;
    }

    const currentTeacherId = d.teacherId;
    if (currentTeacherId && currentTeacherId.trim().length > 0) {
      // It already has a teacherId. Let's make sure claims are sync'd.
      alreadyCorrect++;
      
      // Ensure custom claims are sync'd as well (dry-run respect)
      if (!DRY_RUN) {
        try {
          const user = await auth.getUserByEmail(email);
          const claims = {
            role: d.role ? String(d.role) : null,
            schoolId: d.schoolId ? String(d.schoolId) : null,
            classIds: d.classIds ? d.classIds : [],
            studentClass: d.studentClass ? String(d.studentClass) : null,
            studentRoll: d.studentRoll ? Number(d.studentRoll) : null,
            studentSection: d.studentSection ? String(d.studentSection) : null,
            studentAdmissionId: d.studentAdmissionId ? String(d.studentAdmissionId) : null,
            studentIds: d.studentIds ? d.studentIds : [],
            teacherId: String(currentTeacherId),
          };
          await auth.setCustomUserClaims(user.uid, claims);
          console.log(`Claims synced for ${email} with existing teacherId ${currentTeacherId}`);
        } catch (e) {
          console.warn(`Could not sync claims for ${email}: ${e.message}`);
        }
      }
      continue;
    }

    // Missing teacherId! Resolve it from schools/{schoolId}/teachers
    const schoolId = d.schoolId;
    if (!schoolId) {
      console.warn(`Teacher ${email} has no schoolId in allowed_users! Skipping.`);
      errors++;
      continue;
    }

    console.log(`Resolving teacherId for ${email} in school ${schoolId}...`);
    try {
      const teachersRef = db.collection("schools").doc(schoolId).collection("teachers");
      const teachersSnap = await teachersRef.get();
      let matchedTeacherDoc = null;
      for (const tDoc of teachersSnap.docs) {
        const tData = tDoc.data() || {};
        if (tData.email && tData.email.toLowerCase().trim() === email) {
          matchedTeacherDoc = tDoc;
          break;
        }
      }

      if (!matchedTeacherDoc) {
        console.error(`Teacher profile NOT found for email ${email} in school ${schoolId}!`);
        teacherNotFound++;
        continue;
      }

      const resolvedTeacherId = matchedTeacherDoc.id;
      console.log(`Found teacherId [${resolvedTeacherId}] for ${email}`);
      updated++;

      if (!DRY_RUN) {
        // Update allowed_users doc
        await db.collection("allowed_users").doc(doc.id).update({
          teacherId: resolvedTeacherId,
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });

        // Set Auth custom claims
        try {
          const user = await auth.getUserByEmail(email);
          const claims = {
            role: d.role ? String(d.role) : null,
            schoolId: d.schoolId ? String(d.schoolId) : null,
            classIds: d.classIds ? d.classIds : [],
            studentClass: d.studentClass ? String(d.studentClass) : null,
            studentRoll: d.studentRoll ? Number(d.studentRoll) : null,
            studentSection: d.studentSection ? String(d.studentSection) : null,
            studentAdmissionId: d.studentAdmissionId ? String(d.studentAdmissionId) : null,
            studentIds: d.studentIds ? d.studentIds : [],
            teacherId: String(resolvedTeacherId),
          };
          await auth.setCustomUserClaims(user.uid, claims);
          console.log(`Successfully updated document and custom claims for ${email}`);
        } catch (claimsErr) {
          console.warn(`Updated document but could not set custom claims for ${email}: ${claimsErr.message}`);
        }
      }

    } catch (err) {
      console.error(`Error processing teacher ${email}:`, err.message);
      errors++;
    }
  }

  console.log("\nMigration Summary:");
  console.log(`  Non-teachers skipped: ${skippedNonTeacher}`);
  console.log(`  Already had teacherId: ${alreadyCorrect}`);
  console.log(`  Resolved and updated: ${updated}`);
  console.log(`  Profile not found: ${teacherNotFound}`);
  console.log(`  Errors: ${errors}`);
  console.log("Migration finished.");
  process.exit(0);
})().catch((e) => {
  console.error("Migration failed script level:", e);
  process.exit(1);
});

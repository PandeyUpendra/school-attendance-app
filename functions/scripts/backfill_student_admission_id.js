/**
 * #39 backfill — stamp `studentAdmissionId` on guardian `allowed_users` docs.
 *
 * The firestore.rules `guardian_adm:{admissionId}` notification branch reads
 * `getUserData().studentAdmissionId` (top-level). The app also stamps each entry
 * in `studentLinks[]`. Guardians provisioned before #39 lack both — so the app
 * subscribes to the stable channel only when this id is present (otherwise it
 * stays on the legacy roll channel). Running this backfill turns the stable
 * channel ON for every existing guardian.
 *
 * ⚠ DEPLOY ORDER: run this BEFORE shipping the app build that emits/subscribes
 * to `guardian_adm:`. A guardian whose allowed_users still lacks the id will not
 * receive `guardian_adm:`-addressed notices (delivery gap, NOT a crash — the
 * client self-gates, proven in test_rules/notifications.test.mjs).
 *
 * Idempotent: only fills a MISSING id; safe to re-run.
 *
 * Usage (from functions/):
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccountKey.json
 *   node scripts/backfill_student_admission_id.js --dry-run
 *   node scripts/backfill_student_admission_id.js
 */

const admin = require("firebase-admin");

const DRY_RUN = process.argv.includes("--dry-run");

admin.initializeApp();
const db = admin.firestore();

/** Resolves a student's stable admissionId from {schoolId, className, roll}. */
async function resolveAdmissionId(schoolId, className, roll) {
  if (!schoolId || className == null || roll == null) return null;
  const snap = await db
    .collection(`schools/${schoolId}/students`)
    .where("className", "==", className)
    .where("roll", "==", roll)
    .get();
  if (snap.empty) return null;
  // Roll can repeat across sections; only resolve when unambiguous.
  if (snap.size > 1) {
    console.warn(
      `  ! ${schoolId} ${className} roll ${roll}: ${snap.size} matches — skipped (ambiguous section)`
    );
    return null;
  }
  return snap.docs[0].data().admissionId || null;
}

async function main() {
  console.log(`#39 admissionId backfill${DRY_RUN ? " (dry-run)" : ""}\n`);
  const guardians = await db
    .collection("allowed_users")
    .where("role", "==", "guardian")
    .get();

  let scanned = 0;
  let stamped = 0;
  let skipped = 0;

  for (const doc of guardians.docs) {
    scanned++;
    const data = doc.data() || {};
    const schoolId = data.schoolId;

    // Per-link ids.
    const links = Array.isArray(data.studentLinks) ? [...data.studentLinks] : [];
    let linksChanged = false;
    for (const link of links) {
      if (link && !link.studentAdmissionId) {
        const adm = await resolveAdmissionId(
          schoolId, link.studentClass, link.studentRoll);
        if (adm) {
          link.studentAdmissionId = adm;
          linksChanged = true;
        }
      }
    }

    // Top-level id (what the rules read) — from the top-level studentClass/roll.
    let topAdm = data.studentAdmissionId || null;
    if (!topAdm) {
      topAdm = await resolveAdmissionId(
        schoolId, data.studentClass, data.studentRoll);
    }

    const update = {};
    if (linksChanged) update.studentLinks = links;
    if (!data.studentAdmissionId && topAdm) update.studentAdmissionId = topAdm;

    if (Object.keys(update).length === 0) {
      skipped++;
      continue;
    }
    stamped++;
    console.log(
      `  ${doc.id}: ${DRY_RUN ? "would set" : "set"} ${Object.keys(update).join(", ")}`
    );
    if (!DRY_RUN) await doc.ref.set(update, { merge: true });
  }

  console.log(
    `\nDone. scanned ${scanned}, ${DRY_RUN ? "would stamp" : "stamped"} ${stamped}, unchanged ${skipped}.`
  );
  process.exit(0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});

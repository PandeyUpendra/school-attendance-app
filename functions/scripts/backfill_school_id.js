/**
 * Multi-tenancy backfill — Phase 2.
 *
 * Stamps `schoolId` on every document that the multi-tenancy strict-isolation
 * rules (Phase 3) will rely on but that predates schoolId being written. With a
 * single school in production, the value is uniformly 'school_1'.
 *
 * MUST be run BEFORE deploying the Phase 3 rules. The Phase 3 rules make
 * `inSchool()` strict and add `schoolId` read-filters; any doc left without a
 * schoolId would then be denied/hidden, locking users out or hiding data.
 *
 * Idempotent: only docs MISSING `schoolId` are written, so it is safe to re-run.
 *
 * Usage (from the functions/ directory):
 *   # Authenticate with a service account that can write Firestore:
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccountKey.json
 *   # Dry run first (no writes, just counts):
 *   node scripts/backfill_school_id.js --dry-run
 *   # Then for real:
 *   node scripts/backfill_school_id.js
 *
 * Optionally override the school id:  SCHOOL_ID=school_1 node scripts/...
 */

const admin = require("firebase-admin");

const SCHOOL_ID = process.env.SCHOOL_ID || "school_1";
const DRY_RUN = process.argv.includes("--dry-run");
const BATCH_LIMIT = 400; // under Firestore's 500-op cap

admin.initializeApp();
const db = admin.firestore();

/** Root collections that need schoolId stamped on each doc. */
const ROOT_COLLECTIONS = [
  "allowed_users", // CRITICAL: strict inSchool() reads userSchoolId() from here
  "homework",
  "copy_checks",
  "substitution_history",
  "tasks", // class-task collection; tenant-scoped reads now require schoolId (#6)
];

/** Collection-group leaf names (matched at any depth) that need schoolId. */
const COLLECTION_GROUPS = [
  "remarks",  // schools/{sid}/students/{id}/remarks/{rid}
  "payments", // schools/{sid}/fee_payments/{cls}/students/{roll}/payments/{id}
];

async function backfillQuery(label, query) {
  let scanned = 0;
  let stamped = 0;
  let batch = db.batch();
  let inBatch = 0;

  const snap = await query.get();
  for (const doc of snap.docs) {
    scanned++;
    const data = doc.data() || {};
    if (data.schoolId) continue; // already stamped — idempotent skip
    stamped++;
    if (!DRY_RUN) {
      batch.set(doc.ref, { schoolId: SCHOOL_ID }, { merge: true });
      inBatch++;
      if (inBatch >= BATCH_LIMIT) {
        await batch.commit();
        batch = db.batch();
        inBatch = 0;
      }
    }
  }
  if (!DRY_RUN && inBatch > 0) await batch.commit();
  console.log(
    `  ${label}: scanned ${scanned}, ${DRY_RUN ? "would stamp" : "stamped"} ${stamped}`
  );
  return { scanned, stamped };
}

async function main() {
  console.log(
    `Backfill schoolId='${SCHOOL_ID}'${DRY_RUN ? " (DRY RUN — no writes)" : ""}\n`
  );

  let totalStamped = 0;

  console.log("Root collections:");
  for (const coll of ROOT_COLLECTIONS) {
    const r = await backfillQuery(coll, db.collection(coll));
    totalStamped += r.stamped;
  }

  console.log("Collection groups:");
  for (const group of COLLECTION_GROUPS) {
    const r = await backfillQuery(group, db.collectionGroup(group));
    totalStamped += r.stamped;
  }

  console.log(
    `\nDone. ${DRY_RUN ? "Would stamp" : "Stamped"} ${totalStamped} document(s).`
  );
  if (DRY_RUN) console.log("Re-run without --dry-run to apply.");
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("Backfill failed:", err);
    process.exit(1);
  });

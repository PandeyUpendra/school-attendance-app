/**
 * Custom-claims backfill (#3).
 *
 * Sets {role, schoolId} Firebase Auth custom claims for every existing user from
 * their allowed_users doc, so the tenant-scoped Storage rules can gate on the
 * schoolId claim. MUST be run BEFORE deploying the stricter storage.rules — a
 * user without the claim is denied all per-school storage once those rules are
 * live (same coordinated-release pattern as the schoolId Firestore backfill).
 *
 * Idempotent: re-running just re-sets the same claims. Users may need to sign
 * out/in (or wait up to ~1h for token refresh) for new claims to take effect;
 * the app forces a token refresh at login.
 *
 * Usage (from functions/):
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccountKey.json
 *   node scripts/backfill_claims.js --dry-run
 *   node scripts/backfill_claims.js
 */
const admin = require("firebase-admin");

const DRY_RUN = process.argv.includes("--dry-run");
admin.initializeApp();

(async () => {
  const snap = await admin.firestore().collection("allowed_users").get();
  let set = 0;
  let skipped = 0;
  for (const doc of snap.docs) {
    const email = doc.id;
    const d = doc.data() || {};
    const claims = {};
    if (d.role) claims.role = String(d.role);
    if (d.schoolId) claims.schoolId = String(d.schoolId);
    try {
      const user = await admin.auth().getUserByEmail(email);
      if (!DRY_RUN) await admin.auth().setCustomUserClaims(user.uid, claims);
      set++;
    } catch (e) {
      // No Auth account (pending invite) or lookup failed — skip.
      skipped++;
    }
  }
  console.log(`Claims ${DRY_RUN ? "(dry-run) would set" : "set"} ${set}; skipped ${skipped} (no Auth account).`);
  process.exit(0);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});

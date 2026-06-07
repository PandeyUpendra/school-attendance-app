/**
 * Money integer-paise backfill (review #31).
 *
 * Stamps the canonical `<field>Paise` integer fields on every money-bearing
 * document so totals can be summed without floating-point drift. The app reads
 * the paise field when present and falls back to the legacy rupee `double`
 * field, so running this is not strictly required for correctness — but it makes
 * the stored representation canonical and lets the legacy rupee fields be
 * dropped later.
 *
 * Documents touched:
 *   schools/{sid}/fee_structures/*                       totalAnnualFeePaise,
 *                                                        components[].amountPaise,
 *                                                        installments[].amountPaise
 *   schools/{sid}/fee_payments/{cls}/students/{roll}/payments/*   amountPaise
 *
 * IDEMPOTENT: a field is only written when its `*Paise` value is MISSING, so the
 * script never multiplies an already-converted amount by 100 a second time. Safe
 * to re-run.
 *
 * Usage (from the functions/ directory):
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccountKey.json
 *   node scripts/backfill_paise.js --dry-run    # counts only, no writes
 *   node scripts/backfill_paise.js              # apply
 */

const admin = require("firebase-admin");

const DRY_RUN = process.argv.includes("--dry-run");
const BATCH_LIMIT = 400; // under Firestore's 500-op cap

admin.initializeApp();
const db = admin.firestore();

const toPaise = (rupees) => Math.round(Number(rupees) * 100);
const hasNum = (v) => typeof v === "number" && !Number.isNaN(v);

let scanned = 0;
let updated = 0;

async function commitInChunks(updates) {
  // updates: array of { ref, data }
  for (let i = 0; i < updates.length; i += BATCH_LIMIT) {
    const slice = updates.slice(i, i + BATCH_LIMIT);
    if (DRY_RUN) {
      updated += slice.length;
      continue;
    }
    const batch = db.batch();
    slice.forEach((u) => batch.set(u.ref, u.data, { merge: true }));
    await batch.commit();
    updated += slice.length;
  }
}

/** Adds amountPaise to each map element of an array when missing. Returns a new
 * array, or null if nothing changed. */
function backfillArray(arr) {
  if (!Array.isArray(arr)) return null;
  let changed = false;
  const next = arr.map((el) => {
    if (el && typeof el === "object" && el.amountPaise == null && hasNum(el.amount)) {
      changed = true;
      return { ...el, amountPaise: toPaise(el.amount) };
    }
    return el;
  });
  return changed ? next : null;
}

async function backfillFeeStructures() {
  const snap = await db.collectionGroup("fee_structures").get();
  const updates = [];
  for (const doc of snap.docs) {
    scanned++;
    const d = doc.data();
    const patch = {};
    if (d.totalAnnualFeePaise == null && hasNum(d.totalAnnualFee)) {
      patch.totalAnnualFeePaise = toPaise(d.totalAnnualFee);
    }
    const comps = backfillArray(d.components);
    if (comps) patch.components = comps;
    const insts = backfillArray(d.installments);
    if (insts) patch.installments = insts;
    if (Object.keys(patch).length > 0) updates.push({ ref: doc.ref, data: patch });
  }
  await commitInChunks(updates);
}

async function backfillPayments() {
  // payments live at fee_payments/{cls}/students/{roll}/payments/{id}; a
  // collection-group query over "payments" reaches every leaf in one pass.
  const snap = await db.collectionGroup("payments").get();
  const updates = [];
  for (const doc of snap.docs) {
    // Only fee payments carry `amount`; ignore unrelated "payments" groups.
    const d = doc.data();
    if (!hasNum(d.amount)) continue;
    scanned++;
    if (d.amountPaise == null) {
      updates.push({ ref: doc.ref, data: { amountPaise: toPaise(d.amount) } });
    }
  }
  await commitInChunks(updates);
}

(async () => {
  console.log(`Money paise backfill ${DRY_RUN ? "(DRY RUN)" : ""}`);
  await backfillFeeStructures();
  await backfillPayments();
  console.log(`Scanned ${scanned} money docs; ${DRY_RUN ? "would update" : "updated"} ${updated}.`);
  process.exit(0);
})().catch((err) => {
  console.error(err);
  process.exit(1);
});

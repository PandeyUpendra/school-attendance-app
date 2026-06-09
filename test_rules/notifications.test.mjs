// Firestore security-rules tests for the notifications collection (#76).
// Run via:  firebase emulators:exec --only firestore "cd test_rules && npm test"
import { test, before, after, beforeEach } from 'node:test';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc } from 'firebase/firestore';

const here = dirname(fileURLToPath(import.meta.url));
const SID = 'school_test';

let testEnv;

// allowed_users docs are keyed by lowercased email (matches userEmail()).
const guardianA = { email: 'ga@x.com' };
const guardianB = { email: 'gb@x.com' };
const guardianOther = { email: 'gother@x.com' }; // different school

function ctx(g) {
  return testEnv.authenticatedContext(g.email, { email: g.email }).firestore();
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'school-app-rules-test',
    firestore: {
      rules: readFileSync(join(here, '..', 'firestore.rules'), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (admin) => {
    const db = admin.firestore();
    // Guardian A — Class 9 / roll 5 / section A, admissionId ADM-A, school_test
    await setDoc(doc(db, `allowed_users/${guardianA.email}`), {
      role: 'guardian', schoolId: SID,
      studentClass: 'Class 9', studentRoll: 5, studentSection: 'A',
      studentAdmissionId: 'ADM-A',
    });
    // Guardian B — same class, roll 6, admissionId ADM-B
    await setDoc(doc(db, `allowed_users/${guardianB.email}`), {
      role: 'guardian', schoolId: SID,
      studentClass: 'Class 9', studentRoll: 6, studentSection: 'A',
      studentAdmissionId: 'ADM-B',
    });
    // Guardian in a DIFFERENT school
    await setDoc(doc(db, `allowed_users/${guardianOther.email}`), {
      role: 'guardian', schoolId: 'other_school',
      studentClass: 'Class 9', studentRoll: 5, studentSection: 'A',
      studentAdmissionId: 'ADM-A',
    });

    const notifs = {
      n_roll_a:    { audience: 'guardian:Class 9:5', type: 'absent' },
      n_roll_b:    { audience: 'guardian:Class 9:6', type: 'absent' },
      n_adm_a:     { audience: 'guardian_adm:ADM-A', type: 'absent' },
      n_adm_b:     { audience: 'guardian_adm:ADM-B', type: 'absent' },
      n_broadcast: { audience: 'all', type: 'announcement' },
      n_guardians: { audience: 'guardians', type: 'announcement' },
      n_principal: { audience: 'principal', type: 'leave_submitted' },
    };
    for (const [id, data] of Object.entries(notifs)) {
      await setDoc(doc(db, `schools/${SID}/notifications/${id}`), data);
    }
  });
});

function n(db, id) {
  return getDoc(doc(db, `schools/${SID}/notifications/${id}`));
}

// ── Legacy roll-based audience (must keep working) ──────────────────────────
test('guardian reads their own roll-based notice', async () => {
  await assertSucceeds(n(ctx(guardianA), 'n_roll_a'));
});

test('guardian CANNOT read another roll in the same class', async () => {
  await assertFails(n(ctx(guardianA), 'n_roll_b'));
});

// ── New stable admissionId audience (#39) ───────────────────────────────────
test('guardian reads their own admissionId notice', async () => {
  await assertSucceeds(n(ctx(guardianA), 'n_adm_a'));
});

test('guardian CANNOT read another child admissionId notice', async () => {
  await assertFails(n(ctx(guardianA), 'n_adm_b'));
});

// ── Broadcast / group audiences ─────────────────────────────────────────────
test('guardian reads broadcast (all) and guardians group', async () => {
  await assertSucceeds(n(ctx(guardianA), 'n_broadcast'));
  await assertSucceeds(n(ctx(guardianA), 'n_guardians'));
});

test('guardian CANNOT read a principal-targeted notice', async () => {
  await assertFails(n(ctx(guardianA), 'n_principal'));
});

// ── Multi-tenant isolation ──────────────────────────────────────────────────
test('guardian in another school CANNOT read this school notices', async () => {
  const other = ctx(guardianOther);
  await assertFails(n(other, 'n_roll_a'));
  await assertFails(n(other, 'n_adm_a'));
  await assertFails(n(other, 'n_broadcast'));
});

// ── Create restrictions (anti-phishing) ─────────────────────────────────────
test('guardian CANNOT post to principal, CAN post to own class-teacher', async () => {
  const db = ctx(guardianA);
  await assertFails(
    setDoc(doc(db, `schools/${SID}/notifications/evil`),
      { audience: 'principal', title: 'x' }));
  await assertSucceeds(
    setDoc(doc(db, `schools/${SID}/notifications/legit`),
      { audience: 'class_teacher:Class 9', type: 'student_leave_submitted' }));
});

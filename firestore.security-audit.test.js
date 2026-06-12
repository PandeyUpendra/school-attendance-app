/**
 * firestore.security-audit.test.js
 *
 * Regression tests for the three Play-Store-blocking leaks identified in the
 * security audit:
 *
 *   Leak 1 — exam_results  : guardian could read ANY student's marks
 *   Leak 2 — notifications : guardian could read any parent's notification
 *                            in the same class (roll not enforced in rules)
 *   Leak 3 — attendance    : guardian reads entire class attendance doc,
 *                            exposing every child's status (OPTIONS PRESENTED,
 *                            awaiting schema decision — current leak is proved
 *                            by the CURRENT-LEAK tests below)
 *
 * Each test is labelled:
 *   [FIXED]        — leak is now closed by the updated rules
 *   [CURRENT-LEAK] — leak still exists pending schema/architecture decision
 *   [REGRESSION]   — must stay ALLOW after the fix (staff access unchanged)
 *
 * Run:
 *   npx jest /Users/upendrapandey/school_app/firestore.security-audit.test.js --no-coverage
 *
 * Prerequisites: Firestore emulator running on localhost:8080
 *   firebase emulators:start --only firestore
 */

'use strict';

const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const { readFileSync } = require('fs');
const path = require('path');
const { doc, getDoc, setDoc } = require('firebase/firestore');

// ═══════════════════════════════════════════════════════════════════════════
// CONSTANTS & FIXTURE DATA
// ═══════════════════════════════════════════════════════════════════════════

const PROJECT_ID = 'attendanceapp-e76e1';
const SCHOOL_ID  = 'school_1';

// ── User identities ─────────────────────────────────────────────────────────
//
//  guardian_A  →  child Alice in Class 9-A, roll 42, section A
//                 studentId: 'Class_9-A_A_42'
//
//  guardian_B  →  child Bob in Class 9-A, roll  7, section A
//                 (same class as guardian_A — intra-class leak test)
//                 studentId: 'Class_9-A_A_7'
//
//  guardian_C  →  child Carol in Class 10-B, roll 15, section B
//                 (different class — cross-class leak test)
//                 studentId: 'Class_10-B_B_15'
//
//  teacher9A   →  class teacher of Class 9-A
//  coordinator →  management
//  principal   →  management

const UID = {
  guardianA:   'uid-guardian-a',
  guardianB:   'uid-guardian-b',
  guardianC:   'uid-guardian-c',
  teacher9A:   'uid-teacher-9a',
  coordinator: 'uid-coordinator',
  principal:   'uid-principal',
};

const USERS = {
  [UID.guardianA]: {
    role: 'guardian', schoolId: SCHOOL_ID,
    name: 'Parent Alice', email: 'parent.alice@school.test',
    studentClass: 'Class 9-A', studentSection: 'A', studentRoll: 42,
    status: 'active',
  },
  [UID.guardianB]: {
    role: 'guardian', schoolId: SCHOOL_ID,
    name: 'Parent Bob', email: 'parent.bob@school.test',
    studentClass: 'Class 9-A', studentSection: 'A', studentRoll: 7,
    status: 'active',
  },
  [UID.guardianC]: {
    role: 'guardian', schoolId: SCHOOL_ID,
    name: 'Parent Carol', email: 'parent.carol@school.test',
    studentClass: 'Class 10-B', studentSection: 'B', studentRoll: 15,
    status: 'active',
  },
  [UID.teacher9A]: {
    role: 'teacher', schoolId: SCHOOL_ID,
    name: 'Ms. Nair', email: 'teacher9a@school.test',
    teacherId: UID.teacher9A,
    classIds:   ['Class 9-A'],
    studentIds: [],
    status: 'active',
  },
  [UID.coordinator]: {
    role: 'coordinator', schoolId: SCHOOL_ID,
    name: 'Coordinator', email: 'coord@school.test',
    classIds: [], studentIds: [], status: 'active',
  },
  [UID.principal]: {
    role: 'principal', schoolId: SCHOOL_ID,
    name: 'Principal', email: 'principal@school.test',
    classIds: [], studentIds: [], status: 'active',
  },
};

// ── Fixture: exam results ────────────────────────────────────────────────────
//
// Schema includes `studentId` field (proposed addition — see CLAUDE.md).
// This field is required for the fixed rule to allow guardian reads.

const EXAM_ID = 'exam-unit-test-1';

// Alice's result — guardian_A should be able to read this
const RESULT_ALICE = {
  examId: EXAM_ID, examName: 'Unit Test 1',
  className: 'Class 9-A', roll: 42, studentName: 'Alice Sharma',
  studentId: 'Class_9-A_A_42',   // ← proposed new field
  marks: { Maths: 85, Science: 90 }, maxMarks: 100,
  enteredBy: 'teacher9a@school.test',
};

// Bob's result — same class as Alice; guardian_A should NOT read this
const RESULT_BOB = {
  examId: EXAM_ID, examName: 'Unit Test 1',
  className: 'Class 9-A', roll: 7, studentName: 'Bob Kumar',
  studentId: 'Class_9-A_A_7',    // ← proposed new field
  marks: { Maths: 70, Science: 75 }, maxMarks: 100,
  enteredBy: 'teacher9a@school.test',
};

// Carol's result — different class; guardian_A should NOT read this
const RESULT_CAROL = {
  examId: EXAM_ID, examName: 'Unit Test 1',
  className: 'Class 10-B', roll: 15, studentName: 'Carol Verma',
  studentId: 'Class_10-B_B_15',  // ← proposed new field
  marks: { Maths: 92, Science: 88 }, maxMarks: 100,
  enteredBy: 'teacher9a@school.test',
};

// Legacy result WITHOUT studentId field — guardian should be denied
const RESULT_LEGACY_NO_STUDENT_ID = {
  examId: EXAM_ID, examName: 'Unit Test 1',
  className: 'Class 9-A', roll: 99, studentName: 'Legacy Student',
  // NOTE: no studentId field — simulates pre-migration document
  marks: { Maths: 55 }, maxMarks: 100,
  enteredBy: 'teacher9a@school.test',
};

// ── Fixture: notifications ───────────────────────────────────────────────────
//
// Uses `targetStudentId` field (proposed addition — see CLAUDE.md).
// This field must be written by NotificationService for guardian:{class}:{roll}
// audience notifications.

// Notification for Alice (Class 9-A, roll 42) — guardian_A should read
const NOTIF_ALICE = {
  audience:        'guardian:Class 9-A:42',
  targetStudentId: 'Class_9-A_A_42',   // ← proposed new field
  title: 'Alice was absent',
  body:  'Alice was marked absent on 2026-05-30.',
};

// Notification for Bob (Class 9-A, roll 7) — guardian_A must NOT read
const NOTIF_BOB = {
  audience:        'guardian:Class 9-A:7',
  targetStudentId: 'Class_9-A_A_7',    // ← proposed new field
  title: 'Bob was absent',
  body:  'Bob was marked absent on 2026-05-30.',
};

// Notification for Carol (Class 10-B, roll 15) — guardian_A must NOT read
const NOTIF_CAROL = {
  audience:        'guardian:Class 10-B:15',
  targetStudentId: 'Class_10-B_B_15',  // ← proposed new field
  title: 'Carol was absent',
  body:  'Carol was marked absent on 2026-05-30.',
};

// Notification WITHOUT targetStudentId — guardian should be denied
const NOTIF_LEGACY_NO_TARGET_ID = {
  audience: 'guardian:Class 9-A:42',
  // NOTE: no targetStudentId field — simulates old notification document
  title: 'Old notification',
  body:  'This notification has no targetStudentId.',
};

// Broadcast notification — every guardian should read
const NOTIF_ALL = {
  audience: 'all',
  title: 'School closed tomorrow',
  body:  'Holiday declared.',
};

// Broadcast to all guardians
const NOTIF_GUARDIANS = {
  audience: 'guardians',
  title:    'Parent-teacher meeting',
  body:     'PTM on Saturday.',
};

// ── Fixture: attendance ──────────────────────────────────────────────────────
//
// Attendance docs are per-class flat maps — the source of Leak 3.
// The entire class roll→status map is in one document.

const ATTENDANCE_9A = {
  '2026-5-30': {
    42: 'Present',   // Alice — guardian_A's child
     7: 'Absent',    // Bob   — guardian_B's child
    11: 'Present',   // other student
    22: 'Leave',     // other student
  },
};
const ATTENDANCE_10B = {
  '2026-5-30': {
    15: 'Present',  // Carol — guardian_C's child
  },
};

// ── Fixture: copy checks ─────────────────────────────────────────────────────

const COPY_CHECK_DOC = {
  teacherId:   UID.teacher9A,
  teacherName: 'Ms. Nair',
  className:   'Class 9-A',
  section:     'A',
  subject:     'Maths',
  checkDate:   new Date('2026-05-30'),
  createdAt:   new Date('2026-05-30'),
};

const COPY_STATUS_ALICE = {
  roll: 42, studentName: 'Alice Sharma',
  guardianPhone: '9999000001',
  status: 'checked', remarks: 'Good work',
};

// ═══════════════════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════════════════

let testEnv;

function db(uid) {
  const user = USERS[uid];
  // Mirror production: syncUserClaims mints {role, schoolId} custom claims, so
  // rules read identity from the claim (no getUserData() read) — SCALE-05.
  return testEnv.authenticatedContext(uid, {
    email: user.email.toLowerCase(),
    ...(user.role ? { role: user.role } : {}),
    ...(user.schoolId ? { schoolId: user.schoolId } : {}),
  }).firestore();
}

function sch(collection, docId) {
  return `schools/${SCHOOL_ID}/${collection}/${docId}`;
}

// ═══════════════════════════════════════════════════════════════════════════
// LIFECYCLE
// ═══════════════════════════════════════════════════════════════════════════

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync(path.resolve(__dirname, 'firestore.rules'), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const adb = ctx.firestore();

    // Seed allowed_users (keyed by UID)
    for (const [uid, data] of Object.entries(USERS)) {
      await setDoc(doc(adb, 'allowed_users', uid), data);
    }

    // Seed exam results
    await setDoc(doc(adb, `schools/${SCHOOL_ID}/exam_results/${EXAM_ID}/students/42`), RESULT_ALICE);
    await setDoc(doc(adb, `schools/${SCHOOL_ID}/exam_results/${EXAM_ID}/students/7`),  RESULT_BOB);
    await setDoc(doc(adb, `schools/${SCHOOL_ID}/exam_results/${EXAM_ID}/students/15`), RESULT_CAROL);
    await setDoc(doc(adb, `schools/${SCHOOL_ID}/exam_results/${EXAM_ID}/students/99`), RESULT_LEGACY_NO_STUDENT_ID);

    // Seed notifications
    await setDoc(doc(adb, sch('notifications', 'notif-alice')),            NOTIF_ALICE);
    await setDoc(doc(adb, sch('notifications', 'notif-bob')),              NOTIF_BOB);
    await setDoc(doc(adb, sch('notifications', 'notif-carol')),            NOTIF_CAROL);
    await setDoc(doc(adb, sch('notifications', 'notif-legacy-no-tid')),    NOTIF_LEGACY_NO_TARGET_ID);
    await setDoc(doc(adb, sch('notifications', 'notif-all')),              NOTIF_ALL);
    await setDoc(doc(adb, sch('notifications', 'notif-guardians')),        NOTIF_GUARDIANS);

    // Seed attendance
    await setDoc(doc(adb, sch('attendance', 'Class 9-A')),  ATTENDANCE_9A);
    await setDoc(doc(adb, sch('attendance', 'Class 10-B')), ATTENDANCE_10B);

    // Per-student attendance mirror (H2) — the guardian-readable projection.
    await setDoc(doc(adb, sch('student_attendance', 'Class_9-A_A_42')),
      { schoolId: SCHOOL_ID, roll: 42, days: { '2026-05-23': 'Present' } });
    await setDoc(doc(adb, sch('student_attendance', 'Class_9-A_A_7')),
      { schoolId: SCHOOL_ID, roll: 7, days: { '2026-05-23': 'Absent' } });
    await setDoc(doc(adb, sch('student_attendance', 'Class_10-B_B_15')),
      { schoolId: SCHOOL_ID, roll: 15, days: { '2026-05-23': 'Present' } });

    // Seed copy checks (parent doc + status subcollection)
    await setDoc(doc(adb, sch('copy_checks', 'check-9a')), COPY_CHECK_DOC);
    await setDoc(
      doc(adb, `schools/${SCHOOL_ID}/copy_checks/check-9a/statuses/42`),
      COPY_STATUS_ALICE,
    );
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});


// ═══════════════════════════════════════════════════════════════════════════
// LEAK 1 — EXAM RESULTS
// ═══════════════════════════════════════════════════════════════════════════

describe('Leak 1 — exam_results guardian isolation', () => {

  // ── Denial tests (the leak) ──────────────────────────────────────────────

  test('[FIXED] DENY — guardian cannot read another student\'s result (same class)', async () => {
    // guardian_A (Alice, Class 9-A roll 42) must not read Bob's result
    // (Class 9-A roll 7).  OLD rule: allowed (isSignedIn && inSchool).
    await assertFails(
      getDoc(doc(db(UID.guardianA), `schools/${SCHOOL_ID}/exam_results/${EXAM_ID}/students/7`)),
    );
  });

  test('[FIXED] DENY — guardian cannot read another student\'s result (different class)', async () => {
    // guardian_A must not read Carol's result (Class 10-B roll 15).
    await assertFails(
      getDoc(doc(db(UID.guardianA), `schools/${SCHOOL_ID}/exam_results/${EXAM_ID}/students/15`)),
    );
  });

  test('[FIXED] DENY — guardian cannot read legacy result without studentId field', async () => {
    // Pre-migration documents that lack studentId must be denied to guardians.
    await assertFails(
      getDoc(doc(db(UID.guardianA), `schools/${SCHOOL_ID}/exam_results/${EXAM_ID}/students/99`)),
    );
  });

  test('[FIXED] DENY — guardian_B cannot read guardian_A\'s child\'s result', async () => {
    // Even within the same class, cross-child reads must be blocked.
    await assertFails(
      getDoc(doc(db(UID.guardianB), `schools/${SCHOOL_ID}/exam_results/${EXAM_ID}/students/42`)),
    );
  });

  // ── Allow tests (regression — must still work) ───────────────────────────

  test('[REGRESSION] ALLOW — guardian can read their own child\'s result', async () => {
    // guardian_A reads Alice's result — studentId 'Class_9-A_A_42' ∈ studentIds[].
    await assertSucceeds(
      getDoc(doc(db(UID.guardianA), `schools/${SCHOOL_ID}/exam_results/${EXAM_ID}/students/42`)),
    );
  });

  test('[REGRESSION] ALLOW — teacher can read any exam result in their school', async () => {
    await assertSucceeds(
      getDoc(doc(db(UID.teacher9A), `schools/${SCHOOL_ID}/exam_results/${EXAM_ID}/students/15`)),
    );
  });

  test('[REGRESSION] ALLOW — coordinator can read any exam result', async () => {
    await assertSucceeds(
      getDoc(doc(db(UID.coordinator), `schools/${SCHOOL_ID}/exam_results/${EXAM_ID}/students/7`)),
    );
  });

  test('[REGRESSION] ALLOW — principal can read any exam result', async () => {
    await assertSucceeds(
      getDoc(doc(db(UID.principal), `schools/${SCHOOL_ID}/exam_results/${EXAM_ID}/students/15`)),
    );
  });
});


// ═══════════════════════════════════════════════════════════════════════════
// LEAK 1 (continued) — COPY CHECKS  guardian isolation
// ═══════════════════════════════════════════════════════════════════════════

describe('Leak 1 — copy_checks guardian isolation', () => {

  test('[FIXED] DENY — guardian cannot read a copy_check parent document', async () => {
    // Copy-checking is a staff workflow. Guardians have no use-case for it.
    // OLD rule: allowed (isSignedIn && inSchool).
    await assertFails(
      getDoc(doc(db(UID.guardianA), sch('copy_checks', 'check-9a'))),
    );
  });

  test('[FIXED] DENY — guardian cannot read a copy_check status (per-student PII)', async () => {
    // Statuses contain roll, studentName, guardianPhone — PII.
    await assertFails(
      getDoc(doc(
        db(UID.guardianA),
        `schools/${SCHOOL_ID}/copy_checks/check-9a/statuses/42`,
      )),
    );
  });

  test('[REGRESSION] ALLOW — teacher can read copy_check parent document', async () => {
    await assertSucceeds(
      getDoc(doc(db(UID.teacher9A), sch('copy_checks', 'check-9a'))),
    );
  });

  test('[REGRESSION] ALLOW — teacher can read copy_check statuses', async () => {
    await assertSucceeds(
      getDoc(doc(
        db(UID.teacher9A),
        `schools/${SCHOOL_ID}/copy_checks/check-9a/statuses/42`,
      )),
    );
  });

  test('[REGRESSION] ALLOW — coordinator can read copy_check parent document', async () => {
    await assertSucceeds(
      getDoc(doc(db(UID.coordinator), sch('copy_checks', 'check-9a'))),
    );
  });
});


// ═══════════════════════════════════════════════════════════════════════════
// LEAK 2 — NOTIFICATIONS roll-level enforcement
// ═══════════════════════════════════════════════════════════════════════════

describe('Leak 2 — notifications roll-level enforcement', () => {

  // ── Denial tests (the leak) ──────────────────────────────────────────────

  test('[FIXED] DENY — guardian cannot read another parent\'s notification (same class)', async () => {
    // guardian_A (Alice) must not read Bob's absence notification.
    // OLD rule: allowed because audience.split(':')[1] = 'Class 9-A' ∈ guardian_A.classIds[].
    await assertFails(
      getDoc(doc(db(UID.guardianA), sch('notifications', 'notif-bob'))),
    );
  });

  test('[FIXED] DENY — guardian cannot read another class\'s guardian notification', async () => {
    // guardian_A (Class 9-A) must not read Carol's notification (Class 10-B).
    await assertFails(
      getDoc(doc(db(UID.guardianA), sch('notifications', 'notif-carol'))),
    );
  });

  test('[FIXED] DENY — guardian cannot read a legacy notification lacking targetStudentId', async () => {
    // Old notifications without targetStudentId must be denied (no fallback to
    // class-only check — that was the original vulnerability).
    await assertFails(
      getDoc(doc(db(UID.guardianA), sch('notifications', 'notif-legacy-no-tid'))),
    );
  });

  test('[FIXED] DENY — guardian_B cannot read guardian_A\'s notification (same class)', async () => {
    // guardian_B (Bob, Class 9-A) must not read Alice's notification.
    await assertFails(
      getDoc(doc(db(UID.guardianB), sch('notifications', 'notif-alice'))),
    );
  });

  // ── Allow tests (regression — must still work) ───────────────────────────

  test('[REGRESSION] ALLOW — guardian reads own child\'s notification', async () => {
    // guardian_A reads Alice's notification — targetStudentId 'Class_9-A_A_42'
    // ∈ guardian_A.studentIds[].
    await assertSucceeds(
      getDoc(doc(db(UID.guardianA), sch('notifications', 'notif-alice'))),
    );
  });

  test('[REGRESSION] ALLOW — guardian can read "all" broadcast notification', async () => {
    await assertSucceeds(
      getDoc(doc(db(UID.guardianA), sch('notifications', 'notif-all'))),
    );
  });

  test('[REGRESSION] ALLOW — guardian can read "guardians" broadcast notification', async () => {
    await assertSucceeds(
      getDoc(doc(db(UID.guardianA), sch('notifications', 'notif-guardians'))),
    );
  });

  test('[REGRESSION] ALLOW — teacher can read "all" broadcast notification', async () => {
    await assertSucceeds(
      getDoc(doc(db(UID.teacher9A), sch('notifications', 'notif-all'))),
    );
  });

  test('[REGRESSION] ALLOW — coordinator can read a broadcast notification', async () => {
    // Coordinator reads 'all'-audience notification — always allowed.
    // NOTE: Coordinator intentionally CANNOT read 'guardian:*' personal
    // notifications (audience mismatch by design, same as original rules).
    await assertSucceeds(
      getDoc(doc(db(UID.coordinator), sch('notifications', 'notif-all'))),
    );
  });

  test('[REGRESSION] ALLOW — coordinator can read a coordinator-targeted notification', async () => {
    // Seed a coordinator-specific notification and verify access.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), sch('notifications', 'notif-coord')), {
        audience: 'coordinator',
        title: 'Meeting reminder',
        body: 'Staff meeting at 3pm.',
      });
    });
    await assertSucceeds(
      getDoc(doc(db(UID.coordinator), sch('notifications', 'notif-coord'))),
    );
  });

  test('[REGRESSION] ALLOW — guardian_C reads their own child\'s notification', async () => {
    // Verifies the rule works for a different class too.
    await assertSucceeds(
      getDoc(doc(db(UID.guardianC), sch('notifications', 'notif-carol'))),
    );
  });
});


// ═══════════════════════════════════════════════════════════════════════════
// LEAK 3 — ATTENDANCE  (schema decision pending)
//
// These tests PROVE the current leak exists and define what the fixed
// behaviour must look like once a schema decision is made.
//
// [CURRENT-LEAK] tests document the vulnerability.
// [FUTURE-ALLOW] tests document what the guardian-side access should look like
//                after the chosen schema fix is implemented.
// ═══════════════════════════════════════════════════════════════════════════

describe('Leak 3 — attendance (FIXED via per-student mirror, H2)', () => {

  test('[FIXED] DENY — guardian can no longer read the class-day doc (all classmates)', async () => {
    // The class doc holds rolls 7, 11, 22, 42… The leak was that a guardian
    // could read it whole. It is now staff-only.
    await assertFails(
      getDoc(doc(db(UID.guardianA), sch('attendance', 'Class 9-A'))),
    );
  });

  test('[FIXED] ALLOW — guardian reads ONLY their own child\'s mirror', async () => {
    await assertSucceeds(
      getDoc(doc(db(UID.guardianA), sch('student_attendance', 'Class_9-A_A_42'))),
    );
  });

  test('[FIXED] DENY — guardian cannot read a CLASSMATE\'s mirror (same class, roll 7)', async () => {
    // The strongest proof the intra-class leak is closed: guardianA and
    // guardianB share Class 9-A, but A cannot read B's child (roll 7).
    await assertFails(
      getDoc(doc(db(UID.guardianA), sch('student_attendance', 'Class_9-A_A_7'))),
    );
  });

  test('[REGRESSION] DENY — guardian cannot read another class\'s attendance doc', async () => {
    // This is already enforced (classIds[] check). Verify it remains enforced.
    await assertFails(
      getDoc(doc(db(UID.guardianA), sch('attendance', 'Class 10-B'))),
    );
  });

  test('[REGRESSION] DENY — guardian cannot read attendance for a class they\'re not assigned to', async () => {
    await assertFails(
      getDoc(doc(db(UID.guardianC), sch('attendance', 'Class 9-A'))),
    );
  });

  test('[REGRESSION] ALLOW — teacher can read attendance for any class', async () => {
    await assertSucceeds(
      getDoc(doc(db(UID.teacher9A), sch('attendance', 'Class 9-A'))),
    );
  });

  test('[REGRESSION] ALLOW — coordinator can read any class attendance', async () => {
    await assertSucceeds(
      getDoc(doc(db(UID.coordinator), sch('attendance', 'Class 10-B'))),
    );
  });

  test('[REGRESSION] ALLOW — principal can read any class attendance', async () => {
    await assertSucceeds(
      getDoc(doc(db(UID.principal), sch('attendance', 'Class 9-A'))),
    );
  });
});

/**
 * firestore.rules.test.js
 *
 * Unit tests for firestore.rules using @firebase/rules-unit-testing v2.
 *
 * Prerequisites
 * ─────────────
 *   npm install --save-dev @firebase/rules-unit-testing firebase jest
 *   firebase emulators:start --only firestore   (in another terminal)
 *
 * Run
 * ───
 *   npx jest firestore.rules.test.js
 */

const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const { readFileSync } = require('fs');
const path             = require('path');
const {
  doc,
  collection,
  getDoc,
  setDoc,
  addDoc,
  updateDoc,
  deleteDoc,
}                      = require('firebase/firestore');

// ════════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ════════════════════════════════════════════════════════════════════════════

const PROJECT_ID = 'attendanceapp-e76e1';
const SCHOOL_ID  = 'school_1';

// ── UIDs (Firebase Auth) ─────────────────────────────────────────────────────
const UID = {
  guardian:    'uid-guardian-1',   // Parent of Class_9-A_A_42
  guardian2:   'uid-guardian-2',   // Parent of Class_10-B_B_15
  guardianMulti: 'uid-guardian-multi', // Parent of both Class_9-A_A_42 and Class_10-B_B_15
  teacher9A:   'uid-teacher-9a',   // Class teacher of "Class 9-A"
  teacher10B:  'uid-teacher-10b',  // Class teacher of "Class 10-B"
  coordinator: 'uid-coordinator',
  principal:   'uid-principal',
  admin:       'uid-admin',
  rootAdmin:   'uid-root-admin',   // Root administrator
  anon:        null,               // unauthenticated — use unauthedDb()
};

// ── allowed_users documents ──────────────────────────────────────────────────
const USERS = {
  // Guardians are keyed to their child by studentClass / studentRoll /
  // studentSection (what TimetableService.addAllowedUser writes) — the app
  // never populates classIds/studentIds for guardians.
  [UID.guardian]: {
    role: 'guardian', schoolId: SCHOOL_ID,
    name: 'Parent One', email: 'parent1@school.test',
    studentClass: 'Class 9-A', studentSection: 'A', studentRoll: 42,
    status: 'active',
  },
  [UID.guardianMulti]: {
    role: 'guardian', schoolId: SCHOOL_ID,
    name: 'Parent Multi', email: 'parentmulti@school.test',
    studentClass: 'Class 9-A', studentSection: 'A', studentRoll: 42,
    studentLinks: [
      { studentClass: 'Class 9-A', studentRoll: 42, studentSection: 'A', studentName: 'Alice Sharma', studentAdmissionId: 'adm-1' },
      { studentClass: 'Class 10-B', studentRoll: 15, studentSection: 'B', studentName: 'Bob Verma', studentAdmissionId: 'adm-2' },
    ],
    studentIds: ['Class_9-A_A_42', 'Class_10-B_B_15'],
    classIds: ['Class 9-A', 'Class 10-B', 'Class 9-A-A', 'Class 10-B-B'],
    status: 'active',
  },
  [UID.guardian2]: {
    role: 'guardian', schoolId: SCHOOL_ID,
    name: 'Parent Two', email: 'parent2@school.test',
    studentClass: 'Class 10-B', studentSection: 'B', studentRoll: 15,
    status: 'active',
  },
  [UID.teacher9A]: {
    role: 'teacher', schoolId: SCHOOL_ID,
    name: 'Ms. Nair', email: 'teacher9a@school.test',
    teacherId: UID.teacher9A,
    classIds: ['Class 9-A'],
    studentIds: [],
    status: 'active',
  },
  [UID.teacher10B]: {
    role: 'teacher', schoolId: SCHOOL_ID,
    name: 'Mr. Singh', email: 'teacher10b@school.test',
    teacherId: UID.teacher10B,
    classIds: ['Class 10-B'],
    studentIds: [],
    status: 'active',
  },
  [UID.coordinator]: {
    role: 'coordinator', schoolId: SCHOOL_ID,
    name: 'Coordinator',
    email: 'coord@school.test',
    classIds: [], studentIds: [], status: 'active',
  },
  [UID.principal]: {
    role: 'principal', schoolId: SCHOOL_ID,
    name: 'Principal',
    email: 'principal@school.test',
    classIds: [], studentIds: [], status: 'active',
  },
  [UID.admin]: {
    role: 'admin', schoolId: SCHOOL_ID,
    name: 'Admin',
    email: 'admin@school.test',
    classIds: [], studentIds: [], status: 'active',
  },
  [UID.rootAdmin]: {
    role: 'admin', schoolId: SCHOOL_ID,
    name: 'Root Admin',
    email: 'admin@schoolapp.org',
    classIds: [], studentIds: [], status: 'active',
  },
};

// ── Student fixture data ──────────────────────────────────────────────────────
const STUDENT_ID_9A  = 'Class_9-A_A_42';
const STUDENT_ID_10B = 'Class_10-B_B_15';

const STUDENT_9A = {
  roll: 42, name: 'Alice Sharma',
  className: 'Class 9-A', section: 'A',
  fatherName: 'Ramesh Sharma', phone: '9999000001',
  feeStatus: 'Pending',
  guardianEmail: 'parent1@school.test',
};
const STUDENT_10B = {
  roll: 15, name: 'Bob Verma',
  className: 'Class 10-B', section: 'B',
  fatherName: 'Suresh Verma', phone: '9999000002',
  feeStatus: 'Paid',
  guardianEmail: 'parent2@school.test',
};


// ════════════════════════════════════════════════════════════════════════════
// HELPERS
// ════════════════════════════════════════════════════════════════════════════

let testEnv; // RulesTestEnvironment

/** Authenticated Firestore client for the given uid.
 *  Mirrors production: syncUserClaims mints {role, schoolId} custom claims, so
 *  the test token carries them too (SCALE-05). Rules read identity from the
 *  claim, not a getUserData() document read. */
function db(uid) {
  const user = USERS[uid];
  const customClaims = user ? {
    email: user.email.toLowerCase(),
    ...(user.role ? { role: user.role } : {}),
    ...(user.schoolId ? { schoolId: user.schoolId } : {}),
    ...(user.classIds ? { classIds: user.classIds } : {}),
    ...(user.studentClass ? { studentClass: user.studentClass } : {}),
    ...(user.studentRoll ? { studentRoll: user.studentRoll } : {}),
    ...(user.studentSection ? { studentSection: user.studentSection } : {}),
    ...(user.studentAdmissionId ? { studentAdmissionId: user.studentAdmissionId } : {}),
    ...(uid === UID.rootAdmin ? { isRootAdmin: true } : {}),
  } : {};
  return testEnv.authenticatedContext(uid, customClaims).firestore();
}

/** Unauthenticated Firestore client. */
function unauthedDb() {
  return testEnv.unauthenticatedContext().firestore();
}

/** Short-hand path helper. */
function schoolPath(collection, docId) {
  return `schools/${SCHOOL_ID}/${collection}/${docId}`;
}


// ════════════════════════════════════════════════════════════════════════════
// LIFECYCLE
// ════════════════════════════════════════════════════════════════════════════

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

  // Seed data with security rules disabled so tests start from a clean state.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const adb = ctx.firestore();

    // allowed_users (keyed by lowercased email)
    for (const data of Object.values(USERS)) {
      await setDoc(doc(adb, 'allowed_users', data.email.toLowerCase()), data);
    }

    // Seed Teachers (needed for dynamic lookup of teacher ID -> email)
    await setDoc(doc(adb, schoolPath('teachers', UID.teacher9A)), {
      id: UID.teacher9A,
      name: USERS[UID.teacher9A].name,
      email: USERS[UID.teacher9A].email,
      classIds: USERS[UID.teacher9A].classIds,
    });
    await setDoc(doc(adb, schoolPath('teachers', UID.teacher10B)), {
      id: UID.teacher10B,
      name: USERS[UID.teacher10B].name,
      email: USERS[UID.teacher10B].email,
      classIds: USERS[UID.teacher10B].classIds,
    });

    // Students
    await setDoc(doc(adb, schoolPath('students', STUDENT_ID_9A)),  STUDENT_9A);
    await setDoc(doc(adb, schoolPath('students', STUDENT_ID_10B)), STUDENT_10B);

    // Attendance (doc ID = class name string)
    await setDoc(doc(adb, schoolPath('attendance', 'Class 9-A')), {
      '2026-5-23': { rolls: { '42': 'Present' } },
    });
    await setDoc(doc(adb, schoolPath('attendance', 'Class 10-B')), {
      '2026-5-23': { rolls: { '15': 'Present' } },
    });

    // Per-student attendance mirror (H2) — what guardians actually read.
    await setDoc(doc(adb, schoolPath('student_attendance', 'Class_9-A_A_42')), {
      schoolId: SCHOOL_ID, roll: 42, days: { '2026-05-23': 'Present' },
    });
    await setDoc(doc(adb, schoolPath('student_attendance', 'Class_10-B_B_15')), {
      schoolId: SCHOOL_ID, roll: 15, days: { '2026-05-23': 'Present' },
    });

    // Leave application submitted by teacher9A
    await setDoc(doc(adb, schoolPath('leave_applications', 'leave-1')), {
      teacherId: UID.teacher9A,
      teacherEmail: USERS[UID.teacher9A].email,
      status: 'pending',
      startDate: '2026-06-01',
      days: 2,
    });

    // Guardian student leave application for student in Class 9-A
    await setDoc(doc(adb, schoolPath('leave_applications', 'student-leave-1')), {
      applicantType: 'guardian',
      studentClass: 'Class 9',
      studentSection: 'A',
      studentRoll: 42,
      studentName: 'Alice Sharma',
      startDate: '2026-07-01',
      days: 2,
      status: 'approved',
    });

    // Staff task assigned to teacher9A
    await setDoc(doc(adb, schoolPath('staff_tasks', 'task-1')), {
      title: 'Write progress report',
      assignedTo: UID.teacher9A,
      status: 'pending',
    });

    // Notifications — guardian-targeted docs must include `targetStudentId`
    // (matches allowed_users.studentIds[] format: classNameUnderscored_section_roll).
    await setDoc(doc(adb, schoolPath('notifications', 'notif-9a')), {
      audience:        'guardian:Class 9-A:42',
      targetStudentId: STUDENT_ID_9A,   // 'Class_9-A_A_42'
      title: 'Absent today',
      body: 'Alice was absent.',
    });
    await setDoc(doc(adb, schoolPath('notifications', 'notif-10b')), {
      audience:        'guardian:Class 10-B:15',
      targetStudentId: STUDENT_ID_10B,  // 'Class_10-B_B_15'
      title: 'Absent today',
      body: 'Bob was absent.',
    });
    await setDoc(doc(adb, schoolPath('notifications', 'notif-all')), {
      audience: 'all',
      title: 'Holiday tomorrow',
      body: 'School closed.',
    });

    // Fee structure
    await setDoc(doc(adb, schoolPath('fee_structures', 'fee-9a')), {
      className: 'Class 9-A',
      totalAnnualFee: 50000,
    });
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});


// ════════════════════════════════════════════════════════════════════════════
// TEST SUITES
// ════════════════════════════════════════════════════════════════════════════

describe('Firestore Security Rules', () => {

  // ── 1. Unauthenticated access ─────────────────────────────────────────────
  describe('1. Unauthenticated access', () => {
    test('DENY — cannot read students', async () => {
      await assertFails(
        getDoc(doc(unauthedDb(), schoolPath('students', STUDENT_ID_9A))),
      );
    });

    test('DENY — cannot read allowed_users', async () => {
      await assertFails(
        getDoc(doc(unauthedDb(), 'allowed_users', UID.teacher9A)),
      );
    });

    test('DENY — cannot write attendance', async () => {
      await assertFails(
        setDoc(doc(unauthedDb(), schoolPath('attendance', 'Class 9-A')), {
          '2026-5-24': { rolls: { '42': 'Absent' } },
        }),
      );
    });
  });


  // ── 2. Guardian — student access ─────────────────────────────────────────
  describe('2. Guardian — student access', () => {
    test('ALLOW — can read their own child\'s student record', async () => {
      await assertSucceeds(
        getDoc(doc(db(UID.guardian), schoolPath('students', STUDENT_ID_9A))),
      );
    });

    test('DENY — CRITICAL: cannot read another child\'s student record', async () => {
      // guardian.studentIds = ['Class_9-A_A_42'] — NOT Class_10-B_B_15
      await assertFails(
        getDoc(doc(db(UID.guardian), schoolPath('students', STUDENT_ID_10B))),
      );
    });

    test('ALLOW — guardian with multiple children can read all their student records', async () => {
      // Set guardian email for both students to parentmulti@school.test
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const adb = ctx.firestore();
        await updateDoc(doc(adb, schoolPath('students', STUDENT_ID_9A)), {
          guardianEmail: 'parentmulti@school.test',
        });
        await updateDoc(doc(adb, schoolPath('students', STUDENT_ID_10B)), {
          guardianEmail: 'parentmulti@school.test',
        });
      });

      // Assert guardianMulti can read both child student documents
      await assertSucceeds(
        getDoc(doc(db(UID.guardianMulti), schoolPath('students', STUDENT_ID_9A))),
      );
      await assertSucceeds(
        getDoc(doc(db(UID.guardianMulti), schoolPath('students', STUDENT_ID_10B))),
      );
    });

    test('ALLOW — can update guardianDetails for own child', async () => {
      await assertSucceeds(
        updateDoc(doc(db(UID.guardian), schoolPath('students', STUDENT_ID_9A)), {
          guardianDetails: { dob: '2010-01-01', gender: 'Female' },
        }),
      );
    });

    test('DENY — cannot update core student fields (name, roll, etc.)', async () => {
      await assertFails(
        updateDoc(doc(db(UID.guardian), schoolPath('students', STUDENT_ID_9A)), {
          name: 'Hacked Name',
        }),
      );
    });
  });


  // ── 3. Teacher — student write access ────────────────────────────────────
  describe('3. Teacher — student write access', () => {
    test('ALLOW — class teacher can write their own class students', async () => {
      await assertSucceeds(
        setDoc(
          doc(db(UID.teacher9A), schoolPath('students', STUDENT_ID_9A)),
          { ...STUDENT_9A, name: 'Alice Updated' },
        ),
      );
    });

    test('DENY — CRITICAL: teacher cannot write students in another class', async () => {
      // teacher9A.classIds = ['Class 9-A'] → cannot write Class 10-B
      await assertFails(
        setDoc(
          doc(db(UID.teacher9A), schoolPath('students', STUDENT_ID_10B)),
          STUDENT_10B,
        ),
      );
    });

    test('ALLOW — teacher can read all students (not just own class)', async () => {
      // Teachers may read all — needed for cross-class reports, etc.
      await assertSucceeds(
        getDoc(doc(db(UID.teacher9A), schoolPath('students', STUDENT_ID_10B))),
      );
    });
  });


  // ── 4. Role escalation prevention ────────────────────────────────────────
  describe('4. Role escalation prevention', () => {
    test('DENY — CRITICAL: teacher cannot escalate own role', async () => {
      await assertFails(
        updateDoc(doc(db(UID.teacher9A), 'allowed_users', USERS[UID.teacher9A].email.toLowerCase()), {
          role: 'coordinator',
        }),
      );
    });

    test('DENY — user cannot change their own schoolId', async () => {
      await assertFails(
        updateDoc(doc(db(UID.teacher9A), 'allowed_users', USERS[UID.teacher9A].email.toLowerCase()), {
          schoolId: 'evil_school',
        }),
      );
    });

    test('DENY — teacher cannot create a user document (no user provisioning)', async () => {
      await assertFails(
        setDoc(doc(db(UID.teacher9A), 'allowed_users', 'brand-new@school.test'), {
          role: 'admin', schoolId: SCHOOL_ID,
          name: 'Fake Admin', email: 'brand-new@school.test',
          classIds: [], studentIds: [], status: 'active',
        }),
      );
    });

    test('DENY — teacher cannot create a guardian allowed_users document directly', async () => {
      await assertFails(
        setDoc(doc(db(UID.teacher9A), 'allowed_users', 'new-guardian@school.test'), {
          role: 'guardian', schoolId: SCHOOL_ID,
          name: 'New Guardian', email: 'new-guardian@school.test',
          studentClass: 'Class 9-A', studentRoll: 42,
          status: 'pending',
        }),
      );
    });

    test('DENY — teacher cannot update a guardian allowed_users document directly', async () => {
      // Seed a guardian first
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), 'allowed_users', 'existing-guardian@school.test'), {
          role: 'guardian', schoolId: SCHOOL_ID,
          name: 'Existing Guardian', email: 'existing-guardian@school.test',
          studentClass: 'Class 9-A', studentRoll: 42,
          status: 'pending',
        });
      });

      await assertFails(
        updateDoc(doc(db(UID.teacher9A), 'allowed_users', 'existing-guardian@school.test'), {
          studentRoll: 43,
        }),
      );
    });

    test('DENY — user cannot update their own allowed_users fields directly', async () => {
      await assertFails(
        updateDoc(doc(db(UID.teacher9A), 'allowed_users', USERS[UID.teacher9A].email.toLowerCase()), {
          name: 'Ms. Nair Updated',
        }),
      );
    });

    test('DENY — normal admin cannot write directly to allowed_users', async () => {
      await assertFails(
        updateDoc(doc(db(UID.admin), 'allowed_users', USERS[UID.teacher9A].email.toLowerCase()), {
          role: 'coordinator',
        }),
      );
    });

    test('ALLOW — root admin can write to allowed_users directly', async () => {
      await assertSucceeds(
        updateDoc(doc(db(UID.rootAdmin), 'allowed_users', USERS[UID.teacher9A].email.toLowerCase()), {
          role: 'coordinator',
        }),
      );
    });

    test('DENY — coordinator cannot read a user from a different school', async () => {
      // Seed a user from another school
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), 'allowed_users', 'out@other.test'), {
          role: 'teacher', schoolId: 'school_other',
          name: 'Outsider', email: 'out@other.test',
          classIds: [], studentIds: [], status: 'active',
        });
      });

      await assertFails(
        getDoc(doc(db(UID.coordinator), 'allowed_users', 'out@other.test')),
      );
    });
  });


  // ── 5. Leave applications ─────────────────────────────────────────────────
  describe('5. Leave applications', () => {
    test('ALLOW — teacher can submit their own leave application', async () => {
      await assertSucceeds(
        setDoc(
          doc(db(UID.teacher9A), schoolPath('leave_applications', 'leave-new')),
          { teacherId: UID.teacher9A, teacherEmail: USERS[UID.teacher9A].email.toLowerCase(), status: 'pending', startDate: '2026-07-01', days: 1 },
        ),
      );
    });

    test('DENY — teacher cannot submit a leave with someone else\'s teacherEmail', async () => {
      await assertFails(
        setDoc(
          doc(db(UID.teacher9A), schoolPath('leave_applications', 'leave-impersonate')),
          { teacherId: UID.teacher9A, teacherEmail: USERS[UID.teacher10B].email.toLowerCase(), status: 'pending', startDate: '2026-07-01', days: 1 },
        ),
      );
    });

    test('DENY — CRITICAL: teacher cannot approve their own leave (status change)', async () => {
      await assertFails(
        updateDoc(
          doc(db(UID.teacher9A), schoolPath('leave_applications', 'leave-1')),
          { status: 'approved' },
        ),
      );
    });

    test('ALLOW — coordinator can approve a leave application', async () => {
      await assertSucceeds(
        updateDoc(
          doc(db(UID.coordinator), schoolPath('leave_applications', 'leave-1')),
          { status: 'approved', reviewedBy: UID.coordinator, reviewedAt: new Date(), remarks: 'OK' },
        ),
      );
    });

    test('DENY — coordinator cannot change non-review fields on a leave', async () => {
      // Coordinator may only touch status/reviewedBy/reviewedAt/remarks
      await assertFails(
        updateDoc(
          doc(db(UID.coordinator), schoolPath('leave_applications', 'leave-1')),
          { status: 'approved', startDate: '2026-08-01' }, // extra non-allowed field
        ),
      );
    });

    test('DENY — other teacher cannot read teacher9A\'s leave application', async () => {
      await assertFails(
        getDoc(doc(db(UID.teacher10B), schoolPath('leave_applications', 'leave-1'))),
      );
    });

    test('ALLOW — class teacher can read student leave applications for their class and section', async () => {
      await assertSucceeds(
        getDoc(doc(db(UID.teacher9A), schoolPath('leave_applications', 'student-leave-1'))),
      );
    });

    test('DENY — teacher from another class/section cannot read student leave applications', async () => {
      await assertFails(
        getDoc(doc(db(UID.teacher10B), schoolPath('leave_applications', 'student-leave-1'))),
      );
    });
  });


  // ── 6. Attendance ─────────────────────────────────────────────────────────
  describe('6. Attendance', () => {
    test('DENY — H2: guardian CANNOT read the class-day attendance doc (staff-only)', async () => {
      // The class doc holds every classmate's status; guardians read the
      // per-student mirror instead (next test).
      await assertFails(
        getDoc(doc(db(UID.guardian), schoolPath('attendance', 'Class 9-A'))),
      );
    });

    test('ALLOW — H2: guardian can read their OWN child\'s attendance mirror', async () => {
      await assertSucceeds(
        getDoc(doc(db(UID.guardian), schoolPath('student_attendance', 'Class_9-A_A_42'))),
      );
    });

    test('DENY — H2: guardian cannot read another student\'s attendance mirror', async () => {
      await assertFails(
        getDoc(doc(db(UID.guardian), schoolPath('student_attendance', 'Class_10-B_B_15'))),
      );
    });

    test('ALLOW — H2: guardian with multiple children can read attendance mirrors for all children', async () => {
      await assertSucceeds(
        getDoc(doc(db(UID.guardianMulti), schoolPath('student_attendance', 'Class_9-A_A_42'))),
      );
      await assertSucceeds(
        getDoc(doc(db(UID.guardianMulti), schoolPath('student_attendance', 'Class_10-B_B_15'))),
      );
    });

    test('DENY — H2: guardian cannot write their child\'s attendance mirror', async () => {
      await assertFails(
        setDoc(doc(db(UID.guardian), schoolPath('student_attendance', 'Class_9-A_A_42')),
          { days: { '2026-05-23': 'Present' } }, { merge: true }),
      );
    });

    test('ALLOW — staff can read any student attendance mirror', async () => {
      await assertSucceeds(
        getDoc(doc(db(UID.teacher9A), schoolPath('student_attendance', 'Class_10-B_B_15'))),
      );
    });

    test('ALLOW — class teacher can write attendance for their class', async () => {
      await assertSucceeds(
        setDoc(
          doc(db(UID.teacher9A), schoolPath('attendance', 'Class 9-A')),
          {
            '2026-5-24': { rolls: { '42': 'Absent' } },
            date: new Date(),
          },
        ),
      );
    });

    test('DENY — class teacher cannot write attendance older than 7 days', async () => {
      const oldDate = new Date();
      oldDate.setDate(oldDate.getDate() - 8);
      await assertFails(
        setDoc(
          doc(db(UID.teacher9A), schoolPath('attendance', 'Class 9-A')),
          {
            '2026-5-16': { rolls: { '42': 'Absent' } },
            date: oldDate,
          },
        ),
      );
    });

    test('DENY — CRITICAL: teacher cannot write attendance for another class', async () => {
      await assertFails(
        setDoc(
          doc(db(UID.teacher9A), schoolPath('attendance', 'Class 10-B')),
          {
            '2026-5-24': { rolls: { '15': 'Absent' } },
            date: new Date(),
          },
        ),
      );
    });

    test('ALLOW — coordinator can write attendance for any class', async () => {
      await assertSucceeds(
        setDoc(
          doc(db(UID.coordinator), schoolPath('attendance', 'Class 9-A')),
          {
            '2026-5-24': { rolls: { '42': 'Leave' } },
            date: new Date(),
          },
        ),
      );
    });

    test('ALLOW — coordinator/management can write attendance older than 7 days', async () => {
      const oldDate = new Date();
      oldDate.setDate(oldDate.getDate() - 10);
      await assertSucceeds(
        setDoc(
          doc(db(UID.coordinator), schoolPath('attendance', 'Class 9-A')),
          {
            '2026-5-14': { rolls: { '42': 'Leave' } },
            date: oldDate,
          },
        ),
      );
    });
  });


  // ── 7. Staff tasks ────────────────────────────────────────────────────────
  describe('7. Staff tasks', () => {
    test('ALLOW — assignee can update task status fields', async () => {
      await assertSucceeds(
        updateDoc(
          doc(db(UID.teacher9A), schoolPath('staff_tasks', 'task-1')),
          { status: 'completed', completedAt: new Date() },
        ),
      );
    });

    test('DENY — assignee cannot change task title or assignee', async () => {
      await assertFails(
        updateDoc(
          doc(db(UID.teacher9A), schoolPath('staff_tasks', 'task-1')),
          { title: 'Hacked title' },
        ),
      );
    });

    test('DENY — CRITICAL: non-assignee teacher cannot read another\'s task', async () => {
      // teacher10B is NOT the assignee of task-1
      await assertFails(
        getDoc(doc(db(UID.teacher10B), schoolPath('staff_tasks', 'task-1'))),
      );
    });

    test('ALLOW — coordinator can read all staff tasks', async () => {
      await assertSucceeds(
        getDoc(doc(db(UID.coordinator), schoolPath('staff_tasks', 'task-1'))),
      );
    });

    test('DENY — teacher cannot create a staff task', async () => {
      await assertFails(
        setDoc(
          doc(db(UID.teacher9A), schoolPath('staff_tasks', 'task-new')),
          { title: 'Self-assigned task', assignedTo: UID.teacher9A, status: 'pending' },
        ),
      );
    });

    test('ALLOW — principal can create a staff task', async () => {
      await assertSucceeds(
        setDoc(
          doc(db(UID.principal), schoolPath('staff_tasks', 'task-new')),
          { title: 'Review grade sheets', assignedTo: UID.teacher9A, status: 'pending' },
        ),
      );
    });
  });


  // ── 8. Notifications ─────────────────────────────────────────────────────
  describe('8. Notifications', () => {
    test('ALLOW — guardian can read their class notification', async () => {
      // notif-9a audience = 'guardian:Class 9-A:42'
      // guardian.classIds = ['Class 9-A'] → split(':')[1] = 'Class 9-A' ✓
      await assertSucceeds(
        getDoc(doc(db(UID.guardian), schoolPath('notifications', 'notif-9a'))),
      );
    });

    test('DENY — CRITICAL: guardian cannot read another class\'s notification', async () => {
      // notif-10b audience = 'guardian:Class 10-B:15'
      // guardian.classIds = ['Class 9-A'] → 'Class 10-B' ∉ classIds → DENY
      await assertFails(
        getDoc(doc(db(UID.guardian), schoolPath('notifications', 'notif-10b'))),
      );
    });

    test('ALLOW — any authenticated school member can read an "all" notification', async () => {
      await assertSucceeds(
        getDoc(doc(db(UID.guardian), schoolPath('notifications', 'notif-all'))),
      );
      await assertSucceeds(
        getDoc(doc(db(UID.teacher9A), schoolPath('notifications', 'notif-all'))),
      );
    });

    // ── M1: teacher create-audience scoping ──────────────────────────────────
    // teacher9A.classIds = ['Class 9-A'].
    test('ALLOW — M1: teacher posts to a guardian in their OWN class', async () => {
      await assertSucceeds(
        addDoc(collection(db(UID.teacher9A), `schools/${SCHOOL_ID}/notifications`),
          { audience: 'guardian:Class 9-A:42', title: 'x', body: 'y' }),
      );
    });

    test('DENY — M1: teacher CANNOT post to a guardian in ANOTHER class', async () => {
      await assertFails(
        addDoc(collection(db(UID.teacher9A), `schools/${SCHOOL_ID}/notifications`),
          { audience: 'guardian:Class 10-B:15', title: 'phish', body: 'y' }),
      );
    });

    test('DENY — M1: teacher CANNOT broadcast to all guardians', async () => {
      await assertFails(
        addDoc(collection(db(UID.teacher9A), `schools/${SCHOOL_ID}/notifications`),
          { audience: 'guardians', title: 'spam', body: 'y' }),
      );
    });

    test('ALLOW — M1: teacher posts a class notice for their OWN class', async () => {
      await assertSucceeds(
        addDoc(collection(db(UID.teacher9A), `schools/${SCHOOL_ID}/notifications`),
          { audience: 'class:Class 9-A', title: 'x', body: 'y' }),
      );
    });

    test('DENY — M1: teacher CANNOT post a class notice for ANOTHER class', async () => {
      await assertFails(
        addDoc(collection(db(UID.teacher9A), `schools/${SCHOOL_ID}/notifications`),
          { audience: 'class:Class 10-B', title: 'x', body: 'y' }),
      );
    });

    test('ALLOW — M1: teacher posts leave-submitted to coordinator', async () => {
      await assertSucceeds(
        addDoc(collection(db(UID.teacher9A), `schools/${SCHOOL_ID}/notifications`),
          { audience: 'coordinator', title: 'leave', body: 'y' }),
      );
    });
  });


  // ── 9. Fees — guardian scope ──────────────────────────────────────────────
  describe('9. Fees — guardian scope', () => {
    test('ALLOW — guardian can read fee structure for their child\'s class', async () => {
      await assertSucceeds(
        getDoc(doc(db(UID.guardian), schoolPath('fee_structures', 'fee-9a'))),
      );
    });

    test('DENY — CRITICAL: guardian cannot read fee structure for another class', async () => {
      // Seed fee doc for Class 10-B
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), schoolPath('fee_structures', 'fee-10b')), {
          className: 'Class 10-B', totalAnnualFee: 55000,
        });
      });

      await assertFails(
        getDoc(doc(db(UID.guardian), schoolPath('fee_structures', 'fee-10b'))),
      );
    });

    test('DENY — teacher cannot write fee documents', async () => {
      await assertFails(
        setDoc(
          doc(db(UID.teacher9A), schoolPath('fee_structures', 'fee-hack')),
          { className: 'Class 9-A', totalAnnualFee: 0 },
        ),
      );
    });
  });


  // ── 10. Coordinator / Principal global access ─────────────────────────────
  describe('10. Coordinator / Principal global access', () => {
    test('ALLOW — coordinator can read any student', async () => {
      await assertSucceeds(
        getDoc(doc(db(UID.coordinator), schoolPath('students', STUDENT_ID_10B))),
      );
    });

    test('ALLOW — principal can delete a student record', async () => {
      await assertSucceeds(
        deleteDoc(doc(db(UID.principal), schoolPath('students', STUDENT_ID_9A))),
      );
    });

    test('ALLOW — admin can provision a new user', async () => {
      await assertSucceeds(
        setDoc(doc(db(UID.admin), 'allowed_users', 'new-uid'), {
          role: 'teacher', schoolId: SCHOOL_ID,
          name: 'New Teacher', email: 'new@school.test',
          classIds: ['Class 8-A'], studentIds: [], status: 'active',
          createdBy: UID.admin,
        }),
      );
    });

    test('ALLOW — coordinator can update timetable / settings', async () => {
      await assertSucceeds(
        setDoc(
          doc(db(UID.coordinator), schoolPath('timetable', 'week-1')),
          { period1: 'Maths', period2: 'English' },
        ),
      );
    });

    test('DENY — guardian cannot write announcements', async () => {
      await assertFails(
        setDoc(
          doc(db(UID.guardian), schoolPath('announcements', 'ann-fake')),
          { title: 'Fake announcement', body: 'Ignore.' },
        ),
      );
    });
  });

  // ── 11. System configuration ──────────────────────────────────────────────
  describe('11. System configuration', () => {
    test('ALLOW — root admin can read and write system config', async () => {
      const rootDb = db(UID.rootAdmin);
      await assertSucceeds(
        setDoc(doc(rootDb, 'system/root_config'), {
          adminEmails: ['admin@schoolapp.org', 'mandvishal@gmail.com'],
        })
      );
      await assertSucceeds(
        getDoc(doc(rootDb, 'system/root_config'))
      );
    });

    test('DENY — non-root admins cannot read or write system config', async () => {
      const teacherDb = db(UID.teacher9A);
      const adminDb = db(UID.admin);
      await assertFails(
        getDoc(doc(teacherDb, 'system/root_config'))
      );
      await assertFails(
        getDoc(doc(adminDb, 'system/root_config'))
      );
      await assertFails(
        setDoc(doc(adminDb, 'system/root_config'), {
          adminEmails: ['evil@schoolapp.org'],
        })
      );
    });
  });

  // ── 12. Fee Summaries ──────────────────────────────────────────────────────
  describe('12. Fee Summaries', () => {
    test('ALLOW — coordinator can read school fee summaries', async () => {
      await assertSucceeds(
        getDoc(doc(db(UID.coordinator), schoolPath('summaries', 'fees')))
      );
    });

    test('ALLOW — coordinator can read class fee summaries', async () => {
      await assertSucceeds(
        getDoc(doc(db(UID.coordinator), schoolPath('class_fee_summaries', 'Class_9-A')))
      );
    });

    test('DENY — teacher cannot read school fee summaries', async () => {
      await assertFails(
        getDoc(doc(db(UID.teacher9A), schoolPath('summaries', 'fees')))
      );
    });

    test('DENY — teacher cannot read class fee summaries', async () => {
      await assertFails(
        getDoc(doc(db(UID.teacher9A), schoolPath('class_fee_summaries', 'Class_9-A')))
      );
    });

    test('DENY — guardian cannot read school fee summaries', async () => {
      await assertFails(
        getDoc(doc(db(UID.guardian), schoolPath('summaries', 'fees')))
      );
    });

    test('DENY — client writes to summaries are forbidden', async () => {
      await assertFails(
        setDoc(doc(db(UID.admin), schoolPath('summaries', 'fees')), {
          collectedPaise: 10000
        })
      );
      await assertFails(
        setDoc(doc(db(UID.admin), schoolPath('class_fee_summaries', 'Class_9-A')), {
          studentCount: 5
        })
      );
    });
  });

}); // describe('Firestore Security Rules')

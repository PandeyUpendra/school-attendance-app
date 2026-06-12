const {
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const { readFileSync } = require('fs');
const path             = require('path');
const {
  doc,
  getDoc,
  setDoc,
}                      = require('firebase/firestore');

const PROJECT_ID = 'attendanceapp-e76e1';
const SCHOOL_ID  = 'school_1';

const USERS = {
  'uid-guardian-1': {
    role: 'guardian', schoolId: SCHOOL_ID,
    name: 'Parent One', email: 'parent1@school.test',
    studentClass: 'Class 9-A', studentSection: 'A', studentRoll: 42,
    status: 'active',
  },
  'uid-teacher-9a': {
    role: 'teacher', schoolId: SCHOOL_ID,
    name: 'Ms. Nair', email: 'teacher9a@school.test',
    teacherId: 'uid-teacher-9a',
    classIds: ['Class 9-A'],
    studentIds: [],
    status: 'active',
  },
  'uid-coordinator': {
    role: 'coordinator', schoolId: SCHOOL_ID,
    name: 'Coordinator', email: 'coord@school.test',
    classIds: [], studentIds: [], status: 'active',
  }
};

async function runLoadTest() {
  console.log('Initializing Rules Test Environment for Load Test...');
  const testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync(path.resolve(__dirname, '../../firestore.rules'), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });

  // Seed data
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const adb = ctx.firestore();
    // seed allowed users
    for (const [uid, data] of Object.entries(USERS)) {
      await setDoc(doc(adb, 'allowed_users', uid), data);
    }
    // seed teacher profile
    await setDoc(doc(adb, `schools/${SCHOOL_ID}/teachers/uid-teacher-9a`), {
      id: 'uid-teacher-9a',
      name: 'Ms. Nair',
      email: 'teacher9a@school.test',
      classIds: ['Class 9-A'],
    });
    // seed student profile
    await setDoc(doc(adb, `schools/${SCHOOL_ID}/students/Class_9-A_A_42`), {
      roll: 42, name: 'Alice Sharma',
      className: 'Class 9-A', section: 'A',
      guardianEmail: 'parent1@school.test',
    });
  });

  // Helper to get authenticated db context
  function db(uid) {
    const user = USERS[uid];
    const customClaims = user ? {
      email: user.email.toLowerCase(),
      role: user.role,
      schoolId: user.schoolId,
    } : {};
    return testEnv.authenticatedContext(uid, customClaims).firestore();
  }

  const latencies = [];
  const operations = [];

  // Generate 1000 operations
  console.log('Generating 1000 concurrent Firestore operations...');
  for (let i = 0; i < 1000; i++) {
    const roleChoice = i % 3;
    let uid, operation;

    if (roleChoice === 0) {
      // Teacher role: reads student 9A
      uid = 'uid-teacher-9a';
      operation = async (adb) => {
        await getDoc(doc(adb, `schools/${SCHOOL_ID}/students/Class_9-A_A_42`));
      };
    } else if (roleChoice === 1) {
      // Guardian role: reads student 9A
      uid = 'uid-guardian-1';
      operation = async (adb) => {
        await getDoc(doc(adb, `schools/${SCHOOL_ID}/students/Class_9-A_A_42`));
      };
    } else {
      // Coordinator role: reads teacher profile
      uid = 'uid-coordinator';
      operation = async (adb) => {
        await getDoc(doc(adb, `schools/${SCHOOL_ID}/teachers/uid-teacher-9a`));
      };
    }

    const adb = db(uid);
    operations.push(async () => {
      const start = Date.now();
      try {
        await operation(adb);
      } catch (err) {
        console.error(`Operation failed: ${err.message}`);
      }
      const end = Date.now();
      latencies.push(end - start);
    });
  }

  console.log('Executing operations concurrently...');
  const testStart = Date.now();
  await Promise.all(operations.map(op => op()));
  const testEnd = Date.now();
  const totalDuration = testEnd - testStart;

  // Compute metrics
  latencies.sort((a, b) => a - b);
  const sum = latencies.reduce((a, b) => a + b, 0);
  const avg = sum / latencies.length;
  const p90 = latencies[Math.floor(latencies.length * 0.9)];
  const p95 = latencies[Math.floor(latencies.length * 0.95)];
  const p99 = latencies[Math.floor(latencies.length * 0.99)];
  const max = latencies[latencies.length - 1];

  console.log('\n--- LOAD TEST RESULTS ---');
  console.log(`Total Operations: ${latencies.length}`);
  console.log(`Total Duration:   ${totalDuration}ms`);
  console.log(`Avg Latency:      ${avg.toFixed(2)}ms`);
  console.log(`90th Percentile:  ${p90}ms`);
  console.log(`95th Percentile:  ${p95}ms`);
  console.log(`99th Percentile:  ${p99}ms`);
  console.log(`Max Latency:      ${max}ms`);
  console.log('-------------------------\n');

  await testEnv.cleanup();
}

runLoadTest().catch(console.error);

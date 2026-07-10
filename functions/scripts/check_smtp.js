const admin = require("firebase-admin");

// Initialize Firebase Admin (bypass rules, runs locally against live Firebase)
if (admin.apps.length === 0) {
  admin.initializeApp({
    projectId: "attendanceapp-e76e1"
  });
}

const db = admin.firestore();

async function run() {
  console.log("=== Checking SMTP settings across all schools ===");
  try {
    const schoolsSnap = await db.collection("schools").get();
    console.log(`Found ${schoolsSnap.size} schools.`);
    
    for (const schoolDoc of schoolsSnap.docs) {
      const schoolId = schoolDoc.id;
      const smtpSnap = await db.collection("schools").doc(schoolId)
        .collection("settings").doc("smtp").get();
        
      if (smtpSnap.exists) {
        console.log(`School: ${schoolId} - SMTP config exists:`, JSON.stringify(smtpSnap.data()));
      } else {
        console.log(`School: ${schoolId} - No SMTP settings doc found.`);
      }
    }
  } catch (err) {
    console.error("Error reading Firestore:", err);
  }
  process.exit(0);
}

run();

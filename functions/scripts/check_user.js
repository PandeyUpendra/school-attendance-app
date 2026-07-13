const admin = require("firebase-admin");

if (admin.apps.length === 0) {
  admin.initializeApp({
    projectId: "attendanceapp-e76e1"
  });
}

const db = admin.firestore();

async function run() {
  const email = "paneerbachu@gmail.com";
  console.log(`=== Checking user details for: ${email} ===`);

  // 1. Check in allowed_users
  try {
    const userDoc = await db.collection("allowed_users").doc(email).get();
    if (userDoc.exists) {
      console.log("Firestore allowed_users document found:");
      console.log(JSON.stringify(userDoc.data(), null, 2));
    } else {
      console.log("Firestore allowed_users document NOT found.");
    }
  } catch (err) {
    console.error("Error reading allowed_users:", err);
  }

  // 2. Check in Firebase Auth
  try {
    const userRecord = await admin.auth().getUserByEmail(email);
    console.log("Firebase Auth user found:");
    console.log({
      uid: userRecord.uid,
      email: userRecord.email,
      emailVerified: userRecord.emailVerified,
      disabled: userRecord.disabled,
      customClaims: userRecord.customClaims,
      metadata: userRecord.metadata
    });
  } catch (err) {
    if (err.code === "auth/user-not-found") {
      console.log("Firebase Auth user NOT found.");
    } else {
      console.error("Error checking Firebase Auth:", err);
    }
  }

  process.exit(0);
}

run();

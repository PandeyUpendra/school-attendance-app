"use strict";

/**
 * Cloud Functions for the School App.
 *
 * Password setup / reset emails are sent by Firebase Auth's BUILT-IN email
 * (client calls sendPasswordResetEmail) — there is no custom SendGrid function
 * anymore, so no Secret Manager / SENDGRID_API_KEY configuration is required to
 * deploy. (If inbox deliverability becomes an issue, reintroduce an
 * authenticated-domain sender; see git history for the previous SendGrid impl.)
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

admin.initializeApp();

const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

// Roles permitted to delete accounts.
const DELETE_ROLES = ["admin", "owner", "ownerPrincipal", "principal", "coordinator"];

// Role hierarchy used to gate WHO may delete WHOM. A caller may only delete a
// target they STRICTLY outrank (higher number), and deleting an owner —
// which cascades to a full-school wipe — additionally requires the caller to be
// at owner rank (or the root admin). Without this, the function only checked
// "same school", so a coordinator could call deleteAccount({email: <owner>})
// and recursively wipe the entire school, or delete the principal/peers
// (review #1, #2, #3).
const ROLE_RANK = {
  admin: 100,
  owner: 90,
  ownerPrincipal: 90,
  principal: 70,
  coordinator: 50,
  teacher: 30,
  subjectTeacher: 30,
  guardian: 10,
};
const OWNER_RANK = 90;
function rankOf(role) {
  return Object.prototype.hasOwnProperty.call(ROLE_RANK, role) ? ROLE_RANK[role] : 0;
}

// The single permanent system administrator. Mirrors AuthService.rootAdminEmail
// in the app and isRootAdmin() in the Firestore rules. The root admin signs in
// but deliberately has NO allowed_users document, so its role cannot be read
// from Firestore — it must be resolved from the email. Without this, deleteAccount
// rejects the admin as a roleless caller (the UNAUTHENTICATED/permission-denied
// failure when the admin tries to delete an owner).
const ROOT_ADMIN_EMAIL = "mandvishal@gmail.com";

// Resolves a caller's effective role. The root admin is authoritative by email
// (it has no allowed_users doc); every other caller's role comes from their doc.
function resolveCallerRole(callerEmail, snap) {
  if (callerEmail === ROOT_ADMIN_EMAIL) return "admin";
  return snap.exists ? snap.get("role") : null;
}

/**
 * Callable: deleteAccount({ email })
 *
 * Permanently deletes an account and its associated data, including the
 * Firebase Auth login (which the client SDK cannot remove for another user).
 * This is what makes a re-created email start completely fresh.
 *
 * Cascade by role:
 *   owner / ownerPrincipal → the ENTIRE school: every account in that school
 *     (+ their Auth logins), the whole schools/{schoolId} Firestore subtree,
 *     and best-effort Storage cleanup.
 *   teacher → the teacher document in their school + login + Auth.
 *   principal / coordinator / guardian / other → just that account + Auth.
 *     (Accounts they created are intentionally kept — they belong to the school.)
 */
exports.deleteAccount = onCall(
  { cors: true, region: "us-central1" },
  async (request) => {
    const db = admin.firestore();

    if (!request.auth || !request.auth.token || !request.auth.token.email) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const email = String(request.data && request.data.email ? request.data.email : "")
      .trim()
      .toLowerCase();
    if (!EMAIL_RE.test(email)) {
      throw new HttpsError("invalid-argument", "A valid email address is required.");
    }

    const callerEmail = String(request.auth.token.email).toLowerCase();
    if (callerEmail === email) {
      throw new HttpsError("failed-precondition", "You cannot delete your own account.");
    }

    // Resolve caller + target identity from allowed_users.
    const [callerSnap, targetSnap] = await Promise.all([
      db.collection("allowed_users").doc(callerEmail).get(),
      db.collection("allowed_users").doc(email).get(),
    ]);
    const callerRole = resolveCallerRole(callerEmail, callerSnap);
    const callerSchoolId = callerSnap.exists ? callerSnap.get("schoolId") : null;

    if (!DELETE_ROLES.includes(callerRole)) {
      throw new HttpsError("permission-denied", "You are not allowed to delete accounts.");
    }

    // If the target no longer has an allowed_users doc, still try to free the
    // Auth login so a half-deleted account can be cleaned up (idempotent).
    const targetData = targetSnap.exists ? targetSnap.data() : null;
    const targetRole = targetData ? targetData.role : null;
    const targetSchoolId = targetData ? targetData.schoolId : null;

    if (targetRole === "admin") {
      throw new HttpsError("permission-denied", "Admin accounts cannot be deleted here.");
    }

    // Authorization: admins may delete anyone (e.g. owners in other schools);
    // other management roles may only delete within their own school.
    const isAdmin = callerRole === "admin";
    const sameSchool =
      callerSchoolId && targetSchoolId && callerSchoolId === targetSchoolId;
    if (!isAdmin && !sameSchool) {
      throw new HttpsError("permission-denied", "You can only delete accounts in your own school.");
    }

    // Role-hierarchy enforcement (review #1–#3). The root admin is exempt; every
    // other caller must STRICTLY outrank the target so peers and superiors
    // cannot be deleted (e.g. a coordinator deleting the principal, or a
    // principal deleting another principal).
    if (!isAdmin) {
      const callerRank = rankOf(callerRole);
      const targetRank = rankOf(targetRole);
      if (callerRank <= targetRank) {
        throw new HttpsError(
          "permission-denied",
          "You can only delete accounts below your own role.",
        );
      }
      // Deleting an owner / ownerPrincipal cascades to a FULL-SCHOOL WIPE, so it
      // is restricted to owner-rank callers (or the root admin handled above) —
      // never a principal or coordinator.
      if ((targetRole === "owner" || targetRole === "ownerPrincipal") &&
          callerRank < OWNER_RANK) {
        throw new HttpsError(
          "permission-denied",
          "Only an owner (or the system administrator) can delete an owner account.",
        );
      }
    }

    const deleteAuth = async (e) => {
      try {
        const u = await admin.auth().getUserByEmail(e);
        await admin.auth().deleteUser(u.uid);
      } catch (err) {
        if (!err || err.code !== "auth/user-not-found") {
          logger.warn(`deleteAuth failed for ${e}`, err && err.code);
        }
      }
    };

    if ((targetRole === "owner" || targetRole === "ownerPrincipal") && targetSchoolId) {
      // Delete every account belonging to this school + their Auth logins.
      const members = await db
        .collection("allowed_users")
        .where("schoolId", "==", targetSchoolId)
        .get();
      // Delete Auth logins in bounded-parallel chunks and member docs in batched
      // writes, instead of a fully serial getUserByEmail+delete per member —
      // a large school previously risked exceeding the function timeout and
      // leaving the school half-deleted (#113).
      const memberEmails = members.docs.map((d) => d.id);
      const authChunk = 25;
      for (let i = 0; i < memberEmails.length; i += authChunk) {
        await Promise.all(memberEmails.slice(i, i + authChunk).map(deleteAuth));
      }
      const docChunk = 450; // under Firestore's 500-op batch limit
      for (let i = 0; i < members.docs.length; i += docChunk) {
        const batch = db.batch();
        members.docs.slice(i, i + docChunk).forEach((d) => batch.delete(d.ref));
        await batch.commit();
      }
      // Wipe the entire school subtree (students, teachers, attendance, fees, …).
      await db.recursiveDelete(db.collection("schools").doc(targetSchoolId));
      // Best-effort Storage cleanup.
      try {
        await admin.storage().bucket().deleteFiles({ prefix: `schools/${targetSchoolId}/` });
      } catch (err) {
        logger.warn(`Storage cleanup failed for ${targetSchoolId}`, err && err.message);
      }
    } else if ((targetRole === "teacher" || targetRole === "subjectTeacher") && targetSchoolId) {
      const teacherId = targetData && targetData.teacherId;
      if (teacherId) {
        const schoolRef = db.collection("schools").doc(targetSchoolId);
        await schoolRef
          .collection("teachers")
          .doc(teacherId)
          .delete()
          .catch((err) => logger.warn(`teacher doc delete failed`, err && err.message));
        // Remove the teacher's leave / duty / substitution records so they don't
        // linger as orphaned dashboard counts ("Leave Requests" / "Teacher absent").
        for (const coll of ["leave_applications", "duties", "substitutions"]) {
          try {
            const q = await schoolRef.collection(coll).where("teacherId", "==", teacherId).get();
            if (!q.empty) {
              const batch = db.batch();
              q.docs.forEach((d) => batch.delete(d.ref));
              await batch.commit();
            }
          } catch (err) {
            logger.warn(`${coll} cleanup failed for ${teacherId}`, err && err.message);
          }
        }
      }
    }

    // Always remove the target's own login record + Auth account (idempotent —
    // the owner loop above may have already handled it).
    await deleteAuth(email);
    await db.collection("allowed_users").doc(email).delete().catch(() => {});

    return { ok: true, role: targetRole || "unknown" };
  }
);

/**
 * Firestore trigger: send an FCM push whenever a notification document is
 * created (#52). Publishes to the topic that corresponds to the notification's
 * audience; client devices subscribe to the topics they're allowed to see
 * (PushService). Topic naming MUST match the client exactly:
 *   topic = "s_{schoolId}_{audience}"  with every non [A-Za-z0-9_-] char → "_"
 *
 * Best-effort: a send failure is logged and never throws (the in-app
 * notifications feed is the source of truth; push is a convenience layer).
 */
const sanitizeTopic = (s) => String(s).replace(/[^A-Za-z0-9_-]/g, "_");

exports.pushOnNotificationCreate = onDocumentCreated(
  { document: "schools/{sid}/notifications/{notifId}", region: "us-central1" },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data() || {};
    const audience = String(data.audience || "");
    if (!audience) return;

    const sid = event.params.sid;
    const topic = `s_${sanitizeTopic(sid)}_${sanitizeTopic(audience)}`;
    const title = String(data.title || "School App");
    const body = String(data.body || data.message || "");

    try {
      await admin.messaging().send({
        topic,
        notification: { title, body },
        android: { priority: "high", notification: { channelId: "default" } },
        data: { type: String(data.type || ""), audience },
      });
    } catch (err) {
      logger.warn(`push send failed for topic ${topic}`, err && err.message);
    }
  }
);

/**
 * Callable: deleteStudent({ schoolId, className, section, roll })
 *
 * Server-side cascade delete of a student's school-scoped data (#35). Runs the
 * whole cascade with the Admin SDK so it completes reliably server-side instead
 * of the client's best-effort sequence that could be interrupted (app
 * backgrounded, permission hiccup) and leave orphaned fee/exam records in class
 * totals. The CLIENT still writes the tombstone, revokes guardian access, and
 * emits the audit log — and falls back to its own cascade if this call fails,
 * so deletion never regresses.
 *
 * Deletes: the student doc (+ its remarks/consents/providedDetails
 * subcollections via recursiveDelete), the student's roll entry in every
 * attendance doc for the class, exam results, fee payments, and guardian
 * notifications + leave applications.
 */
const STUDENT_DELETE_ROLES = ["admin", "owner", "ownerPrincipal", "principal"];

function studentDocId(className, section, roll) {
  const base = String(className).replace(/ /g, "_");
  const sec = String(section || "").trim().replace(/ /g, "_");
  return sec ? `${base}_${sec}_${roll}` : `${base}_${roll}`;
}

exports.deleteStudent = onCall(
  { cors: true, region: "us-central1" },
  async (request) => {
    const db = admin.firestore();
    if (!request.auth || !request.auth.token || !request.auth.token.email) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const d = request.data || {};
    const schoolId = String(d.schoolId || "").trim();
    const className = String(d.className || "").trim();
    const section = String(d.section || "").trim();
    const roll = Number.parseInt(d.roll, 10);
    if (!schoolId || !className || !Number.isInteger(roll) || roll <= 0) {
      throw new HttpsError("invalid-argument", "schoolId, className and a valid roll are required.");
    }

    // Authorization: management of the SAME school (admins may cross schools).
    const callerEmail = String(request.auth.token.email).toLowerCase();
    const callerSnap = await db.collection("allowed_users").doc(callerEmail).get();
    const callerRole = resolveCallerRole(callerEmail, callerSnap);
    const callerSchoolId = callerSnap.exists ? callerSnap.get("schoolId") : null;
    if (!STUDENT_DELETE_ROLES.includes(callerRole)) {
      throw new HttpsError("permission-denied", "You are not allowed to delete students.");
    }
    if (callerRole !== "admin" && callerSchoolId !== schoolId) {
      throw new HttpsError("permission-denied", "You can only delete students in your own school.");
    }

    const schoolRef = db.collection("schools").doc(schoolId);
    const docId = studentDocId(className, section, roll);
    const classKey = String(className).replace(/ /g, "_");

    // 1. Student doc + its subcollections (remarks/consents/providedDetails).
    try {
      await db.recursiveDelete(schoolRef.collection("students").doc(docId));
    } catch (err) {
      logger.warn(`student doc delete failed for ${docId}`, err && err.message);
    }

    // 2. Remove the roll from every attendance doc for this class/section.
    try {
      const attKey = section ? `${className} ${section}` : className;
      const prefix = `${attKey.replace(/ /g, "_")}_`;
      const snap = await schoolRef
        .collection("attendance")
        .where(admin.firestore.FieldPath.documentId(), ">=", prefix)
        .where(admin.firestore.FieldPath.documentId(), "<", `${prefix}\uf8ff`)
        .get();
      const FV = admin.firestore.FieldValue;
      for (let i = 0; i < snap.docs.length; i += 400) {
        const batch = db.batch();
        snap.docs.slice(i, i + 400).forEach((doc) => {
          batch.set(doc.ref, {
            rolls: { [roll]: FV.delete() },
            reasons: { [roll]: FV.delete() },
            called: { [roll]: FV.delete() },
          }, { merge: true });
        });
        await batch.commit();
      }
    } catch (err) {
      logger.warn(`attendance cleanup failed for ${docId}`, err && err.message);
    }

    // 3. Exam results for the student in every exam of this class.
    try {
      const exams = await schoolRef.collection("exams").where("className", "==", className).get();
      for (let i = 0; i < exams.docs.length; i += 400) {
        const batch = db.batch();
        exams.docs.slice(i, i + 400).forEach((ex) => {
          batch.delete(schoolRef.collection("exam_results").doc(ex.id).collection("students").doc(String(roll)));
        });
        await batch.commit();
      }
    } catch (err) {
      logger.warn(`exam results cleanup failed for ${docId}`, err && err.message);
    }

    // 4. Fee payments node (+ payments subcollection).
    try {
      await db.recursiveDelete(
        schoolRef.collection("fee_payments").doc(classKey).collection("students").doc(String(roll)));
    } catch (err) {
      logger.warn(`fee cleanup failed for ${docId}`, err && err.message);
    }

    // 5. Guardian notifications + the class-teacher leave notice for this roll.
    try {
      const notifs = schoolRef.collection("notifications");
      const guardianNotifs = await notifs.where("audience", "==", `guardian:${className}:${roll}`).get();
      const leaveNotifs = await notifs.where("audience", "==", `class_teacher:${className}`).get();
      const toDelete = [
        ...guardianNotifs.docs,
        ...leaveNotifs.docs.filter((n) => n.get("studentRoll") === roll),
      ];
      for (let i = 0; i < toDelete.length; i += 400) {
        const batch = db.batch();
        toDelete.slice(i, i + 400).forEach((n) => batch.delete(n.ref));
        await batch.commit();
      }
    } catch (err) {
      logger.warn(`notification cleanup failed for ${docId}`, err && err.message);
    }

    // 6. Guardian-filed leave applications for this student.
    try {
      const leaves = await schoolRef
        .collection("leave_applications")
        .where("applicantType", "==", "guardian")
        .where("studentClass", "==", className)
        .where("studentRoll", "==", roll)
        .get();
      const matched = section
        ? leaves.docs.filter((l) => String(l.get("studentSection") || "").trim() === section)
        : leaves.docs;
      for (let i = 0; i < matched.length; i += 400) {
        const batch = db.batch();
        matched.slice(i, i + 400).forEach((l) => batch.delete(l.ref));
        await batch.commit();
      }
    } catch (err) {
      logger.warn(`leave cleanup failed for ${docId}`, err && err.message);
    }

    return { ok: true, studentId: docId };
  }
);

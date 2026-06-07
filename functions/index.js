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
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

admin.initializeApp();

const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

// Roles permitted to delete accounts.
const DELETE_ROLES = ["admin", "owner", "ownerPrincipal", "principal", "coordinator"];

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

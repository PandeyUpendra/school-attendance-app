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
const { onDocumentCreated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

admin.initializeApp();

/** Simple HTML escaping utility to prevent HTML injection in emails. */
function escapeHtml(unsafe) {
  if (unsafe === null || unsafe === undefined) return "";
  return String(unsafe)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

/**
 * Firestore trigger: mirror each user's {role, schoolId} into their Firebase
 * Auth CUSTOM CLAIMS whenever their allowed_users doc changes (#3). Storage
 * Security Rules can't read Firestore, so these claims are how storage.rules
 * tenant-scopes per-school assets. Best-effort: a pending invite with no Auth
 * account yet is skipped (claims get set on the next write once they sign up,
 * or via scripts/backfill_claims.js).
 *
 * Claims take effect on the user's NEXT ID-token refresh (the app forces one at
 * login).
 */
exports.syncUserClaims = onDocumentWritten(
  { document: "allowed_users/{email}", region: "us-central1" },
  async (event) => {
    const email = event.params.email; // doc id is the lowercased email
    try {
      const user = await admin.auth().getUserByEmail(email);
      const after = event.data && event.data.after;
      if (!after || !after.exists) {
        await admin.auth().setCustomUserClaims(user.uid, null); // doc deleted
        return;
      }
      const d = after.data() || {};
      const claims = {};
      if (d.role) claims.role = String(d.role);
      if (d.schoolId) claims.schoolId = String(d.schoolId);
      await admin.auth().setCustomUserClaims(user.uid, claims);
    } catch (err) {
      logger.warn(`claims sync skipped for ${email}`, err && err.code);
    }
  }
);

// Keep this in sync with Validators._emailRe in lib/utils/validators.dart to prevent drift risk (#12).
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

// The permanent system administrators. Mirrors AuthService.rootAdminEmails
// in the app and isRootAdmin() in the Firestore rules. The root admins sign in
// but deliberately have NO allowed_users document, so their role cannot be read
// from Firestore — it must be resolved from the email. Without this, deleteAccount
// rejects the admin as a roleless caller (the UNAUTHENTICATED/permission-denied
// failure when the admin tries to delete an owner).
const ROOT_ADMIN_EMAILS = ["mandvishal@gmail.com", "admin@schoolapp.org"];

// Resolves a caller's effective role. The root admin is authoritative by email
// (it has no allowed_users doc); every other caller's role comes from their doc.
function resolveCallerRole(callerEmail, snap) {
  if (ROOT_ADMIN_EMAILS.includes(callerEmail)) return "admin";
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
  { cors: true, region: "us-central1", invoker: "public" },
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

    if (targetRole === "admin" || ROOT_ADMIN_EMAILS.includes(email)) {
      throw new HttpsError("permission-denied", "Admin accounts cannot be deleted here.");
    }

    // Authorization: admins may delete anyone; other management roles may delete
    // within their own school, or if the target has no school/allowed_users doc (i.e. is an orphan).
    const isAdmin = callerRole === "admin";
    const targetHasNoSchool = !targetSnap.exists || !targetSchoolId;
    const sameSchool =
      callerSchoolId && targetSchoolId && callerSchoolId === targetSchoolId;
    if (!isAdmin && !sameSchool && !targetHasNoSchool) {
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

async function performStudentDeleteCascade(db, schoolId, className, section, roll) {
  const schoolRef = db.collection("schools").doc(schoolId);
  const docId = studentDocId(className, section, roll);
  const classKey = className.replace(/ /g, "_");

  // A. Fetch student first to get name & guardianEmail for tombstone & guardian revoke
  const studentSnap = await schoolRef.collection("students").doc(docId).get();
  if (!studentSnap.exists) {
    return; // Already deleted
  }
  const studentData = studentSnap.data() || {};
  const studentName = studentData.name || "";
  const guardianEmail = (studentData.guardianEmail || "").trim().toLowerCase();
  const teacherId = studentData.teacherId || "";

  // C. Revoke guardian login record
  if (guardianEmail) {
    try {
      const guardianRef = db.collection("allowed_users").doc(guardianEmail);
      const guardianSnap = await guardianRef.get();
      if (guardianSnap.exists) {
        const data = guardianSnap.data() || {};
        let links = data.studentLinks || [];
        links = links.filter((l) => !(l.studentClass === className && l.studentRoll === roll && (l.studentSection || '') === section));
        if (links.length === 0) {
          // No remaining students linked to this guardian, remove allowed_users + Auth
          await guardianRef.delete();
          // Delete Auth account
          try {
            const u = await admin.auth().getUserByEmail(guardianEmail);
            await admin.auth().deleteUser(u.uid);
          } catch (authErr) {
            if (!authErr || authErr.code !== "auth/user-not-found") {
              logger.warn(`deleteAuth failed for guardian ${guardianEmail}`, authErr && authErr.code);
            }
          }
        } else {
          // Update links
          await guardianRef.update({ studentLinks: links });
        }
      }
    } catch (err) {
      logger.warn(`guardian revoke failed for ${docId}`, err && err.message);
    }
  }

  // 1. Remove the roll from every attendance doc for this class/section.
  try {
    const attKey = section ? `${className} ${section}` : className;
    const prefix = `${attKey.replace(/ /g, "_")}_`;
    const snap = await schoolRef
      .collection("attendance")
      .where(admin.firestore.FieldPath.documentId(), ">=", prefix)
      .where(admin.firestore.FieldPath.documentId(), "<", `${prefix}\uf8ff`)
      .get();
    const FV = admin.firestore.FieldValue;

    const expectedPrefix = section
      ? `${classKey}_${section.replace(/ /g, "_")}_`
      : `${classKey}_`;

    const matchedDocs = snap.docs.filter((doc) => {
      const id = doc.id;
      if (!id.startsWith(expectedPrefix)) return false;
      if (!section) {
        const suffix = id.substring(expectedPrefix.length);
        if (suffix.includes("_")) return false; // Contains section part (e.g. Class_9_A_2026...)
      }
      return true;
    });

    for (let i = 0; i < matchedDocs.length; i += 400) {
      const batch = db.batch();
      matchedDocs.slice(i, i + 400).forEach((doc) => {
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

  // 2. Exam results for the student in every exam of this class.
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

  // 3. Fee payments node (+ payments subcollection).
  try {
    await db.recursiveDelete(
      schoolRef.collection("fee_payments").doc(classKey).collection("students").doc(String(roll)));
  } catch (err) {
    logger.warn(`fee cleanup failed for ${docId}`, err && err.message);
  }

  // 4. Guardian notifications + the class-teacher leave notice for this roll.
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

  // 5. Guardian-filed leave applications for this student.
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

  // 6. Student doc + its subcollections (remarks/consents/providedDetails).
  try {
    await db.recursiveDelete(schoolRef.collection("students").doc(docId));
  } catch (err) {
    logger.warn(`student doc delete failed for ${docId}`, err && err.message);
  }

  // 7. Write tombstone to deleted_students (Issue 29 alignment: write after successful cascade)
  try {
    await schoolRef.collection("deleted_students").add({
      roll: roll,
      name: studentName,
      className: className,
      section: section,
      teacherId: teacherId,
      deletedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (err) {
    logger.warn(`tombstone write failed for ${docId}`, err && err.message);
  }
}

exports.deleteStudent = onCall(
  { cors: true, region: "us-central1", invoker: "public" },
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

    await performStudentDeleteCascade(db, schoolId, className, section, roll);

    return { ok: true, studentId: studentDocId(className, section, roll) };
  }
);

exports.approveDeletionRequest = onCall(
  { cors: true, region: "us-central1", invoker: "public" },
  async (request) => {
    const db = admin.firestore();
    if (!request.auth || !request.auth.token || !request.auth.token.email) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const d = request.data || {};
    const schoolId = String(d.schoolId || "").trim();
    const requestId = String(d.requestId || "").trim();
    if (!schoolId || !requestId) {
      throw new HttpsError("invalid-argument", "schoolId and requestId are required.");
    }

    // Authorization: management of the SAME school (admins may cross schools).
    const callerEmail = String(request.auth.token.email).toLowerCase();
    const callerSnap = await db.collection("allowed_users").doc(callerEmail).get();
    const callerRole = resolveCallerRole(callerEmail, callerSnap);
    const callerSchoolId = callerSnap.exists ? callerSnap.get("schoolId") : null;
    if (!STUDENT_DELETE_ROLES.includes(callerRole)) {
      throw new HttpsError("permission-denied", "You are not allowed to approve deletion requests.");
    }
    if (callerRole !== "admin" && callerSchoolId !== schoolId) {
      throw new HttpsError("permission-denied", "You can only resolve deletion requests in your own school.");
    }

    const reqRef = db.collection("schools").doc(schoolId).collection("student_deletion_requests").doc(requestId);
    const reqSnap = await reqRef.get();
    if (!reqSnap.exists) {
      throw new HttpsError("not-found", "Deletion request not found.");
    }
    const reqData = reqSnap.data() || {};
    if (reqData.status !== "pending") {
      return { ok: true, status: reqData.status }; // already approved / rejected
    }

    const students = reqData.students || [];
    for (const student of students) {
      const roll = Number.parseInt(student.roll, 10);
      const className = String(student.className || "").trim();
      const section = String(student.section || "").trim();
      if (className && Number.isInteger(roll) && roll > 0) {
        await performStudentDeleteCascade(db, schoolId, className, section, roll);
      }
    }

    await reqRef.update({
      status: "approved",
      resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
      resolvedBy: callerEmail,
    });

    return { ok: true };
  }
);

/**
 * Callable: writeAudit({ schoolId, action, entity, entityId, before, after, reason })
 *
 * Server-side audit writer (#1). The actor identity (uid, email, role, name) is
 * stamped from the VERIFIED token + the caller's allowed_users doc — never from
 * client input — so entries can't be attributed to someone else or carry a
 * spoofed role, and (once the audit_logs create rule is locked to Admin SDK
 * only) clients can't write arbitrary or flooded entries directly. The
 * before/after payloads are still supplied by the caller (the server can't know
 * the "true" diff of an arbitrary client operation), but they are now bound to a
 * server-verified actor.
 */
exports.writeAudit = onCall(
  { cors: true, region: "us-central1", invoker: "public" },
  async (request) => {
    const db = admin.firestore();
    if (!request.auth || !request.auth.token || !request.auth.token.email) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const d = request.data || {};
    const action = String(d.action || "");
    const entity = String(d.entity || "");
    if (!action || !entity) {
      throw new HttpsError("invalid-argument", "action and entity are required.");
    }

    const callerEmail = String(request.auth.token.email).toLowerCase();
    const snap = await db.collection("allowed_users").doc(callerEmail).get();
    const role = resolveCallerRole(callerEmail, snap); // 'admin' for root admin
    const callerSchoolId = snap.exists ? snap.get("schoolId") : null;
    // Confine the entry to the caller's own school; the root admin may target
    // any school via the request payload.
    const schoolId = role === "admin"
      ? String(d.schoolId || callerSchoolId || "")
      : callerSchoolId;
    if (!schoolId) {
      throw new HttpsError("failed-precondition", "No school for the audit entry.");
    }

    const entry = {
      action,
      entity,
      entityId: String(d.entityId || ""),
      actorUid: request.auth.uid,
      actorEmail: callerEmail,
      actorName: (snap.exists && snap.get("name")) || callerEmail,
      actorRole: role || "unknown",
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (d.before && typeof d.before === "object") entry.before = d.before;
    if (d.after && typeof d.after === "object") entry.after = d.after;
    if (d.reason) entry.reason = String(d.reason);

    await db.collection("schools").doc(schoolId).collection("audit_logs").add(entry);
    return { ok: true };
  }
);

/**
 * Callable: purgeOldData({ schoolId, daysToKeepNotifications, daysToKeepAuditLogs, daysToKeepTombstones })
 *
 * Purges notifications, audit logs, and deleted student tombstones that exceed the
 * data retention policy period (#18). Restricted to owner and admin roles.
 */
const PURGE_ROLES = ["admin", "owner", "ownerPrincipal"];

exports.purgeOldData = onCall(
  { cors: true, region: "us-central1", invoker: "public" },
  async (request) => {
    const db = admin.firestore();
    if (!request.auth || !request.auth.token || !request.auth.token.email) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const d = request.data || {};
    const schoolId = String(d.schoolId || "").trim();
    if (!schoolId) {
      throw new HttpsError("invalid-argument", "schoolId is required.");
    }

    const callerEmail = String(request.auth.token.email).toLowerCase();
    const callerSnap = await db.collection("allowed_users").doc(callerEmail).get();
    const callerRole = resolveCallerRole(callerEmail, callerSnap);
    const callerSchoolId = callerSnap.exists ? callerSnap.get("schoolId") : null;

    if (!PURGE_ROLES.includes(callerRole)) {
      throw new HttpsError("permission-denied", "You are not authorized to purge data.");
    }
    if (callerRole !== "admin" && callerSchoolId !== schoolId) {
      throw new HttpsError("permission-denied", "You can only purge data for your own school.");
    }

    const schoolRef = db.collection("schools").doc(schoolId);

    // Default retention limits:
    // - Notifications: 90 days
    // - Audit logs: 365 days
    // - Deleted student tombstones: 365 days
    const daysNotif = Number.parseInt(d.daysToKeepNotifications, 10) || 90;
    const daysAudit = Number.parseInt(d.daysToKeepAuditLogs, 10) || 365;
    const daysTombstone = Number.parseInt(d.daysToKeepTombstones, 10) || 365;

    const now = new Date();
    const notifCutoff = admin.firestore.Timestamp.fromDate(new Date(now.getTime() - daysNotif * 24 * 60 * 60 * 1000));
    const auditCutoff = admin.firestore.Timestamp.fromDate(new Date(now.getTime() - daysAudit * 24 * 60 * 60 * 1000));
    const tombstoneCutoff = admin.firestore.Timestamp.fromDate(new Date(now.getTime() - daysTombstone * 24 * 60 * 60 * 1000));

    let notificationsPurged = 0;
    let auditLogsPurged = 0;
    let tombstonesPurged = 0;

    // 1. Purge old notifications
    try {
      const snap = await schoolRef
        .collection("notifications")
        .where("timestamp", "<", notifCutoff)
        .get();
      for (let i = 0; i < snap.docs.length; i += 400) {
        const batch = db.batch();
        snap.docs.slice(i, i + 400).forEach((doc) => {
          batch.delete(doc.ref);
          notificationsPurged++;
        });
        await batch.commit();
      }
    } catch (err) {
      logger.warn(`Failed purging notifications for school ${schoolId}`, err && err.message);
    }

    // 2. Purge old audit logs
    try {
      const snap = await schoolRef
        .collection("audit_logs")
        .where("timestamp", "<", auditCutoff)
        .get();
      for (let i = 0; i < snap.docs.length; i += 400) {
        const batch = db.batch();
        snap.docs.slice(i, i + 400).forEach((doc) => {
          batch.delete(doc.ref);
          auditLogsPurged++;
        });
        await batch.commit();
      }
    } catch (err) {
      logger.warn(`Failed purging audit logs for school ${schoolId}`, err && err.message);
    }

    // 3. Purge old deleted students tombstones
    try {
      const snap = await schoolRef
        .collection("deleted_students")
        .where("deletedAt", "<", tombstoneCutoff)
        .get();
      for (let i = 0; i < snap.docs.length; i += 400) {
        const batch = db.batch();
        snap.docs.slice(i, i + 400).forEach((doc) => {
          batch.delete(doc.ref);
          tombstonesPurged++;
        });
        await batch.commit();
      }
    } catch (err) {
      logger.warn(`Failed purging deleted students tombstones for school ${schoolId}`, err && err.message);
    }

    return {
      success: true,
      purged: {
        notifications: notificationsPurged,
        auditLogs: auditLogsPurged,
        deletedStudentsTombstones: tombstonesPurged
      }
    };
  }
);

/**
 * Firestore trigger: send payment receipt email automatically.
 * Scopes to the subcollection path:
 * schools/{sid}/fee_payments/{classKey}/students/{roll}/payments/{paymentId}
 */
exports.sendReceiptEmail = onDocumentCreated(
  {
    document: "schools/{sid}/fee_payments/{classKey}/students/{roll}/payments/{paymentId}",
    region: "us-central1"
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const payment = snap.data() || {};
    // Skip if payment is reversed
    if (payment.reversed) return;

    const receiptNo = payment.receiptNo || "—";
    const amountPaise = payment.amountPaise || 0;
    const amountRupees = amountPaise / 100;
    const mode = payment.mode || "—";
    const note = payment.note || "";
    const installmentName = payment.installmentName || "";

    const sid = event.params.sid;
    const classKey = event.params.classKey;
    const roll = event.params.roll;

    const db = admin.firestore();

    try {
      // 1. Fetch student details to get guardian email
      const classKeyClean = classKey.replace(/_/g, " ");
      const studentSnap = await db.collection("schools").doc(sid)
        .collection("students")
        .where("roll", "==", parseInt(roll, 10))
        .get();

      const studentDoc = studentSnap.docs.find(d => {
        const cName = d.get("className") || "";
        return cName.replace(/ /g, "_") === classKey;
      });

      if (!studentDoc) {
        logger.warn(`[sendReceiptEmail] Student not found for roll ${roll} and classKey ${classKey}`);
        return;
      }

      const studentData = studentDoc.data() || {};
      const studentName = studentData.name || "Student";
      const guardianEmail = (studentData.guardianEmail || "").trim();

      if (!guardianEmail) {
        logger.info(`[sendReceiptEmail] Student ${studentName} has no guardian email. Logging failure.`);
        await db.collection("communication_logs").doc(sid).collection("logs").add({
          targetUid: `guardian:${classKeyClean}:${roll}`,
          type: "payment_receipt_email",
          payload: {
            receiptNo,
            amountRupees,
            studentName,
            error: "No guardian email set for student",
          },
          success: false,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
        return;
      }

      // 2. Fetch school settings for branding
      const schoolSettingsSnap = await db.collection("schools").doc(sid)
        .collection("settings").doc("school").get();
      const schoolSettings = schoolSettingsSnap.data() || {};
      const schoolName = schoolSettings.schoolName || "School App";
      const logoUrl = schoolSettings.logoUrl || "";

      // 3. Construct receipt HTML body
      const htmlContent = `
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #e0e0e0; border-radius: 8px;">
          <div style="text-align: center; margin-bottom: 20px;">
            ${logoUrl ? `<img src="${escapeHtml(logoUrl)}" alt="${escapeHtml(schoolName)}" style="max-height: 80px; margin-bottom: 10px;" />` : ''}
            <h2 style="color: #333; margin: 0;">${escapeHtml(schoolName)}</h2>
            <p style="color: #666; margin: 5px 0 0 0;">Payment Receipt</p>
          </div>
          
          <div style="background-color: #f9f9f9; padding: 15px; border-radius: 6px; margin-bottom: 20px;">
            <table style="width: 100%; border-collapse: collapse;">
              <tr>
                <td style="padding: 6px 0; color: #666; font-size: 14px;">Receipt No:</td>
                <td style="padding: 6px 0; font-weight: bold; text-align: right; font-size: 14px;">${escapeHtml(receiptNo)}</td>
              </tr>
              <tr>
                <td style="padding: 6px 0; color: #666; font-size: 14px;">Student Name:</td>
                <td style="padding: 6px 0; text-align: right; font-size: 14px;">${escapeHtml(studentName)} (Roll: ${escapeHtml(roll)})</td>
              </tr>
              <tr>
                <td style="padding: 6px 0; color: #666; font-size: 14px;">Class:</td>
                <td style="padding: 6px 0; text-align: right; font-size: 14px;">${escapeHtml(classKeyClean)}</td>
              </tr>
              <tr>
                <td style="padding: 6px 0; color: #666; font-size: 14px;">Installment:</td>
                <td style="padding: 6px 0; text-align: right; font-size: 14px;">${escapeHtml(installmentName || 'General')}</td>
              </tr>
              <tr>
                <td style="padding: 6px 0; color: #666; font-size: 14px;">Payment Mode:</td>
                <td style="padding: 6px 0; text-align: right; font-size: 14px;">${escapeHtml(mode)}</td>
              </tr>
            </table>
          </div>
          
          <div style="text-align: center; margin-bottom: 30px;">
            <span style="font-size: 12px; color: #666;">Amount Paid</span>
            <h1 style="color: #2e7d32; margin: 5px 0 0 0;">₹${amountRupees.toFixed(2)}</h1>
          </div>
          
          ${note ? `<div style="margin-bottom: 20px; font-size: 13px; color: #555;"><strong>Note:</strong> ${escapeHtml(note)}</div>` : ''}
          
          <div style="text-align: center; border-top: 1px solid #eeeeee; padding-top: 15px; font-size: 11px; color: #888;">
            This is an electronically generated receipt. No signature is required.
            <br />
            Thank you for your payment.
          </div>
        </div>
      `;

      // 4. Configure nodemailer transporter
      const nodemailer = require("nodemailer");
      const smtpSnap = await db.collection("schools").doc(sid)
        .collection("settings").doc("smtp").get();
      let transporter;

      if (smtpSnap.exists && smtpSnap.data()) {
        const smtp = smtpSnap.data();
        transporter = nodemailer.createTransport({
          host: smtp.host,
          port: parseInt(smtp.port, 10) || 587,
          secure: smtp.secure || false,
          auth: {
            user: smtp.username,
            pass: smtp.password,
          },
        });
      } else {
        transporter = nodemailer.createTransport({
          host: process.env.SMTP_HOST || "smtp.gmail.com",
          port: parseInt(process.env.SMTP_PORT, 10) || 587,
          secure: process.env.SMTP_SECURE === "true",
          auth: {
            user: process.env.SMTP_USER || "noreply@yourschooldomain.com",
            pass: process.env.SMTP_PASS || "",
          },
        });
      }

      const mailFrom = process.env.MAIL_FROM || "noreply@yourschooldomain.com";
      const mailFromName = process.env.MAIL_FROM_NAME || schoolName;

      const mailOptions = {
        from: `"${mailFromName}" <${mailFrom}>`,
        to: guardianEmail,
        subject: `Fee Payment Receipt - ${receiptNo}`,
        html: htmlContent,
      };

      let success = false;
      let errorMsg = "";
      try {
        await transporter.sendMail(mailOptions);
        success = true;
      } catch (err) {
        logger.error("Failed to send receipt email via nodemailer", err);
        errorMsg = err.message;
      }

      // 5. Log to communication logs
      await db.collection("communication_logs").doc(sid).collection("logs").add({
        targetUid: `guardian:${classKeyClean}:${roll}`,
        type: "payment_receipt_email",
        payload: {
          receiptNo,
          amountRupees,
          studentName,
          guardianEmail,
          ...(errorMsg ? { error: errorMsg } : {}),
        },
        success,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });

    } catch (globalErr) {
      logger.error("Global error in sendReceiptEmail trigger", globalErr);
    }
  }
);

/**
 * Firestore trigger: publish absence/leave notifications to the guardian's topic channel
 * when an absence or leave status is recorded, subject to consent validation (DPDP compliance).
 */
exports.onAttendanceWritten = onDocumentWritten(
  { document: "schools/{sid}/attendance/{docId}", region: "us-central1" },
  async (event) => {
    const after = event.data && event.data.after;
    if (!after || !after.exists) return; // deleted

    const sid = event.params.sid;
    const docId = event.params.docId; // e.g. "Class_6_A_2026-06-11"

    const dataAfter = after.data() || {};
    const before = event.data && event.data.before;
    const dataBefore = (before && before.exists) ? (before.data() || {}) : {};

    const rollsAfter = dataAfter.rolls || {};
    const rollsBefore = dataBefore.rolls || {};

    const db = admin.firestore();

    // The date suffix is always 11 characters: e.g. "_2026-06-11"
    const dateSfxLen = 11;
    if (docId.length <= dateSfxLen) return;
    const classSectionPrefix = docId.substring(0, docId.length - dateSfxLen);

    for (const [rollStr, status] of Object.entries(rollsAfter)) {
      if (status === "Absent" || status === "Leave") {
        const prevStatus = rollsBefore[rollStr];
        if (prevStatus !== status) {
          // Status newly changed to Absent or Leave!
          const roll = parseInt(rollStr, 10);
          const studentDocId = `${classSectionPrefix}_${roll}`;

          try {
            // Fetch student document
            const studentSnap = await db.collection("schools").doc(sid)
              .collection("students").doc(studentDocId).get();
            
            if (!studentSnap.exists) {
              logger.warn(`[onAttendanceWritten] Student document not found: ${studentDocId}`);
              continue;
            }

            const studentData = studentSnap.data() || {};
            const studentName = studentData.name || "Student";
            const studentClass = studentData.className || "";

            // Check DPDP Consent
            const consentSnap = await db.collection("schools").doc(sid)
              .collection("students").doc(studentDocId)
              .collection("consents")
              .where("consentVersion", "==", "v1.0")
              .get();

            let hasConsent = false;
            for (const doc of consentSnap.docs) {
              const cData = doc.data() || {};
              if (!cData.withdrawnAt) {
                const scopes = cData.scopes || [];
                // Check if 'communication' or 'attendance' dataType scope is optedIn
                const targetScope = scopes.find(s => s.dataType === "communication" || s.dataType === "attendance");
                if (targetScope && targetScope.optedIn) {
                  hasConsent = true;
                  break;
                }
              }
            }

            if (!hasConsent) {
              logger.info(`[onAttendanceWritten] Skip alert for ${studentName} (no active consent for communication/attendance)`);
              continue;
            }

            // Write notification
            await db.collection("schools").doc(sid).collection("notifications").add({
              type: "attendance_alert",
              title: "Attendance Alert",
              body: `${studentName} has been marked ${status} today.`,
              audience: `guardian:${studentClass}:${roll}`,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            logger.info(`[onAttendanceWritten] Sent attendance alert for ${studentName} (${status})`);
          } catch (err) {
            logger.error(`[onAttendanceWritten] Error processing student ${studentDocId}:`, err);
          }
        }
      }
    }
  }
);



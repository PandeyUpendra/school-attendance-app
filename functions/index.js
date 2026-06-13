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

const { setGlobalOptions } = require("firebase-functions/v2");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

// SCALE-15: billing/runaway safety rail. Without a cap, a synchronised spike
// (e.g. every class across many schools marking attendance at 9 AM, each save
// firing onAttendanceWritten → notification → pushOnNotificationCreate) can fan
// out to thousands of concurrent instances → runaway cost + Firestore write
// contention. 100 is a safety ceiling, NOT a throughput tune — a single school,
// or even ~100 schools, will not sustain 100 concurrent instances of one
// trigger; revisit under load testing once real multi-school traffic exists.
// Region (SCALE-08): asia-south1 (Mumbai), CO-LOCATED with the Firestore
// database (confirmed `(default)` lives in asia-south1). The functions
// originally ran in us-central1, which put an Iowa↔Mumbai round-trip inside
// EVERY trigger/callable Firestore operation (and billed cross-region egress).
// Keep function region == database region; the Flutter app must call callables
// via FirebaseFunctions.instanceFor(region: kFunctionsRegion) — see
// lib/shared/utils/app_functions.dart — because instance() defaults to
// us-central1.
setGlobalOptions({ region: "asia-south1", maxInstances: 100 });

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

// ── Data retention / TTL (unbounded collection growth) ───────────────────────
// notifications and audit_logs grow without bound. Rather than a per-school
// scheduled purge (purgeOldData is onCall and won't be invoked across 10k
// schools), every doc is stamped with an `expireAt` timestamp and a Firestore
// TTL policy on that field deletes it automatically — free, no function runtime.
// Windows match purgeOldData's defaults: notifications 90d, audit_logs 365d.
// One-time setup (per database, NOT in this repo) — enable the TTL policies:
//   gcloud firestore fields ttls update expireAt \
//     --collection-group=notifications --enable-ttl
//   gcloud firestore fields ttls update expireAt \
//     --collection-group=audit_logs --enable-ttl
const NOTIFICATION_RETENTION_DAYS = 90;
const AUDIT_LOG_RETENTION_DAYS = 365;
function expireAtAfterDays(days) {
  return admin.firestore.Timestamp.fromMillis(
    Date.now() + days * 24 * 60 * 60 * 1000);
}
function notificationExpireAt() {
  return expireAtAfterDays(NOTIFICATION_RETENTION_DAYS);
}

// ── DPDP consent (SCALE-14) ──────────────────────────────────────────────────
// Must stay in lock-step with kCurrentConsentVersion in
// lib/models/parental_consent.dart.
const CURRENT_CONSENT_VERSION = "v1.0";

/**
 * Given a student's consent docs (the `consents` subcollection), returns true
 * iff there is a current-version, un-withdrawn consent that opts in to the
 * 'communication' or 'attendance' data scope. This is the SINGLE source of the
 * rule for whether attendance alerts may be sent — both the per-consent-write
 * `syncCommsConsent` trigger and the `backfillCommsConsent` callable derive the
 * denormalized `students/{id}.commsConsent` flag from it, and it matches the
 * logic onAttendanceWritten falls back to when that flag is absent.
 */
function consentDocsGrantComms(consentDocs) {
  for (const doc of consentDocs) {
    const cData = doc.data() || {};
    if (cData.consentVersion !== CURRENT_CONSENT_VERSION) continue;
    if (cData.withdrawnAt) continue;
    const scopes = cData.scopes || [];
    const targetScope = scopes.find(
      (s) => s.dataType === "communication" || s.dataType === "attendance");
    if (targetScope && targetScope.optedIn) return true;
  }
  return false;
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
  { document: "allowed_users/{email}", region: "asia-south1" },
  async (event) => {
    const email = event.params.email.toLowerCase(); // doc id is the lowercased email
    try {
      const user = await admin.auth().getUserByEmail(email);
      const after = event.data && event.data.after;
      if (!after || !after.exists) {
        await admin.auth().setCustomUserClaims(user.uid, null); // doc deleted
        return;
      }
      const d = after.data() || {};

      // Auto-backfill studentLinks, studentIds, and classIds for guardians if missing or outdated
      if (d.role === "guardian") {
        const db = admin.firestore();
        const schoolId = d.schoolId || "";
        let finalLinks = d.studentLinks || [];
        if (schoolId) {
          const studentsQuery = await db.collection("schools").doc(schoolId).collection("students")
            .where("guardianEmail", "==", email)
            .get();
          if (studentsQuery.docs.length > 0) {
            const matchedLinks = studentsQuery.docs.map(doc => {
              const s = doc.data();
              return {
                studentClass: s.className || "",
                studentRoll: typeof s.roll === "number" ? s.roll : 0,
                studentSection: s.section || "",
                studentName: s.name || "",
                studentAdmissionId: s.admissionId || ""
              };
            });
            const seen = new Set();
            const merged = [];
            [...finalLinks, ...matchedLinks].forEach(l => {
              const key = `${l.studentClass}|${l.studentRoll}|${l.studentSection}`;
              if (!seen.has(key) && l.studentClass && l.studentRoll !== undefined) {
                seen.add(key);
                merged.push(l);
              }
            });
            finalLinks = merged;
          }
        }

        const studentIds = finalLinks.map((l) => studentDocId(l.studentClass, l.studentSection, l.studentRoll));
        const classIds = [...new Set(finalLinks.map((l) => {
          const cls = l.studentClass || "";
          const sec = l.studentSection || "";
          return sec ? `${cls}-${sec}` : cls;
        }))];

        const hasLinks = Array.isArray(d.studentLinks) && d.studentLinks.length === finalLinks.length;
        const hasIds = Array.isArray(d.studentIds) && d.studentIds.length === studentIds.length;
        const hasClassIds = Array.isArray(d.classIds) && d.classIds.length === classIds.length;
        
        if (!hasLinks || !hasIds || !hasClassIds) {
          await after.ref.update({
            studentLinks: finalLinks,
            studentIds: studentIds,
            classIds: classIds
          });
          return;
        }
      }

      const claims = {
        role: d.role ? String(d.role) : null,
        schoolId: d.schoolId ? String(d.schoolId) : null,
        classIds: d.classIds ? d.classIds : [],
        studentClass: d.studentClass ? String(d.studentClass) : null,
        studentRoll: d.studentRoll ? Number(d.studentRoll) : null,
        studentSection: d.studentSection ? String(d.studentSection) : null,
        studentAdmissionId: d.studentAdmissionId ? String(d.studentAdmissionId) : null,
        studentIds: d.studentIds ? d.studentIds : [],
      };
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
  { cors: true, region: "asia-south1", invoker: "public", enforceAppCheck: false },
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
    const targetExists = targetSnap.exists;

    if (!DELETE_ROLES.includes(callerRole)) {
      throw new HttpsError("permission-denied", "You are not allowed to delete accounts.");
    }

    // If the target no longer has an allowed_users doc, still try to free the
    // Auth login so a half-deleted account can be cleaned up (idempotent).
    const targetData = targetExists ? targetSnap.data() : null;
    const targetRole = targetData ? targetData.role : null;
    const targetSchoolId = targetData ? targetData.schoolId : null;

    // Resolve target's tenant info from Custom Claims if they lack a document (orphan verification).
    let targetSchoolIdFromClaims = null;
    let targetRoleFromClaims = null;
    try {
      const targetUser = await admin.auth().getUserByEmail(email);
      if (targetUser.customClaims) {
        targetSchoolIdFromClaims = targetUser.customClaims.schoolId || null;
        targetRoleFromClaims = targetUser.customClaims.role || null;
      }
    } catch (e) {
      // Auth user doesn't exist either. This is a true orphan.
    }

    const targetSchoolIdResolved = targetSchoolId || targetSchoolIdFromClaims;
    const targetRoleResolved = targetRole || targetRoleFromClaims;

    if (targetRoleResolved === "admin" || ROOT_ADMIN_EMAILS.includes(email)) {
      throw new HttpsError("permission-denied", "Admin accounts cannot be deleted here.");
    }

    const isAdmin = callerRole === "admin" || ROOT_ADMIN_EMAILS.includes(callerEmail);
    const sameSchoolResolved = callerSchoolId && targetSchoolIdResolved && callerSchoolId === targetSchoolIdResolved;

    if (!isAdmin) {
      if (!sameSchoolResolved) {
        throw new HttpsError(
          "permission-denied",
          "You can only delete accounts in your own school. Orphan accounts in other schools or without school associations require admin privileges."
        );
      }

      const callerRank = rankOf(callerRole);
      const targetRank = rankOf(targetRoleResolved);
      if (callerRank <= targetRank) {
        throw new HttpsError(
          "permission-denied",
          "You can only delete accounts below your own role.",
        );
      }
      // Deleting an owner / ownerPrincipal cascades to a FULL-SCHOOL WIPE, so it
      // is restricted to owner-rank callers (or the root admin handled above) —
      // never a principal or coordinator.
      if ((targetRoleResolved === "owner" || targetRoleResolved === "ownerPrincipal") &&
          callerRank < OWNER_RANK) {
        throw new HttpsError(
          "permission-denied",
          "Only an owner (or the system administrator) can delete an owner account.",
        );
      }
    }

    const deleteAuthUid = async (uid) => {
      try {
        await admin.auth().deleteUser(uid);
      } catch (err) {
        if (!err || err.code !== "auth/user-not-found") {
          logger.warn(`deleteAuth failed for UID ${uid}`, err && err.code);
        }
      }
    };

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
    if (targetSnap) {
      await deleteAuthUid(targetSnap.id);
      await targetSnap.ref.delete().catch(() => {});
    } else {
      await deleteAuth(email);
    }

    return { ok: true, role: targetRole || "unknown" };
  }
);

/**
 * Callable: createAllowedUser({ email, password, role, name, schoolId, studentClass, studentRoll, studentSection, studentAdmissionId, assignedClasses })
 *
 * Securely provisions a new user account (handles Auth signup, creates the allowed_users document, and triggers custom claims sync).
 */
exports.createAllowedUser = onCall(
  { cors: true, region: "asia-south1", enforceAppCheck: false },
  async (request) => {
    const db = admin.firestore();
    
    if (!request.auth || !request.auth.token || !request.auth.token.email) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    
    const email = String(request.data && request.data.email ? request.data.email : "")
      .trim()
      .toLowerCase();
    const password = String(request.data && request.data.password ? request.data.password : "").trim();
    const role = String(request.data && request.data.role ? request.data.role : "").trim();
    const name = String(request.data && request.data.name ? request.data.name : "").trim();
    const schoolId = String(request.data && request.data.schoolId ? request.data.schoolId : "").trim();
    const studentClass = request.data && request.data.studentClass ? String(request.data.studentClass).trim() : null;
    const studentRoll = request.data && request.data.studentRoll !== undefined && request.data.studentRoll !== null ? Number(request.data.studentRoll) : null;
    const studentSection = request.data && request.data.studentSection ? String(request.data.studentSection).trim() : null;
    const studentAdmissionId = request.data && request.data.studentAdmissionId ? String(request.data.studentAdmissionId).trim() : null;
    const assignedClasses = request.data && request.data.assignedClasses ? request.data.assignedClasses : [];

    if (!EMAIL_RE.test(email)) {
      throw new HttpsError("invalid-argument", "A valid email address is required.");
    }
    if (!role || !schoolId) {
      throw new HttpsError("invalid-argument", "Role and School ID are required.");
    }

    const callerEmail = request.auth.token.email.toLowerCase();
    const callerRole = request.auth.token.role;
    const callerSchoolId = request.auth.token.schoolId;
    const callerClassIds = request.auth.token.classIds || [];

    const isAdmin = callerRole === "admin" || ROOT_ADMIN_EMAILS.includes(callerEmail);

    // School check
    if (!isAdmin && schoolId !== callerSchoolId) {
      throw new HttpsError("permission-denied", "You can only create users in your own school.");
    }

    // Role Hierarchy check
    if (!isAdmin) {
      if (callerRole === "owner" || callerRole === "ownerPrincipal") {
        if (!["principal", "coordinator", "teacher", "subjectTeacher", "guardian"].includes(role)) {
          throw new HttpsError("permission-denied", "Unauthorized target role creation.");
        }
      } else if (callerRole === "principal") {
        if (!["coordinator", "teacher", "subjectTeacher", "guardian"].includes(role)) {
          throw new HttpsError("permission-denied", "Principal cannot create this role.");
        }
      } else if (callerRole === "coordinator") {
        if (!["teacher", "subjectTeacher", "guardian"].includes(role)) {
          throw new HttpsError("permission-denied", "Coordinator cannot create this role.");
        }
      } else if (callerRole === "teacher" || callerRole === "subjectTeacher") {
        if (role !== "guardian") {
          throw new HttpsError("permission-denied", "Teachers can only create guardian accounts.");
        }
        if (!studentClass || !callerClassIds.includes(studentClass)) {
          throw new HttpsError("permission-denied", "Teachers can only create guardians for their assigned classes.");
        }
      } else {
        throw new HttpsError("permission-denied", "You do not have permission to create users.");
      }
    }

    // Verify duplicate / conflict in allowed_users doc (keyed by lowercased email)
    const docRef = db.collection("allowed_users").doc(email);
    const docSnap = await docRef.get();
    if (docSnap.exists) {
      const existingData = docSnap.data();
      if (existingData.role !== role) {
        throw new HttpsError("already-exists", `This email is already in use under a different role (${existingData.role}).`);
      }
    }

    // Create Firebase Auth user (if they don't exist yet)
    let user;
    try {
      user = await admin.auth().getUserByEmail(email);
    } catch (e) {
      if (e.code === "auth/user-not-found") {
        // If not found, create new Auth user with temp password
        const tempPass = password || Math.random().toString(36).substring(2, 10) + "A!";
        user = await admin.auth().createUser({
          email: email,
          password: tempPass,
        });
      } else {
        throw new HttpsError("internal", e.message);
      }
    }

    // Write allowed_users document keyed by email
    const data = {
      role: role,
      email: email,
      status: "pending",
      schoolId: schoolId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      name: name || "",
      createdByEmail: request.data.createdByEmail ? String(request.data.createdByEmail).trim().toLowerCase() : callerEmail,
      createdByRole: request.data.createdByRole ? String(request.data.createdByRole).trim() : (callerRole || ""),
    };
    if (role === "guardian") {
      data.studentClass = studentClass || null;
      data.studentRoll = studentRoll || null;
      data.studentSection = studentSection || null;
      data.studentAdmissionId = studentAdmissionId || null;

      const links = [];
      const studentIds = [];
      const classIds = [];
      if (studentClass && studentRoll !== null) {
        links.push({
          studentClass: studentClass,
          studentRoll: studentRoll,
          studentSection: studentSection || "",
          studentAdmissionId: studentAdmissionId || "",
          studentName: "",
        });
        studentIds.push(studentDocId(studentClass, studentSection, studentRoll));
        classIds.push(studentSection ? `${studentClass}-${studentSection}` : studentClass);
      }
      data.studentLinks = links;
      data.studentIds = studentIds;
      data.classIds = classIds;
    }
    if (["coordinator", "principal", "owner"].includes(role)) {
      data.assignedClasses = assignedClasses || [];
    }

    await docRef.set(data);

    return { success: true, uid: user.uid };
  }
);

/**
 * Callable: updateUserMetadata({ email, classIds, studentClass, studentRoll, studentSection, studentAdmissionId, name, teacherId })
 *
 * Securely updates a user's permissions, class assignments, or guardian mapping.
 */
exports.updateUserMetadata = onCall(
  { cors: true, region: "asia-south1", enforceAppCheck: false },
  async (request) => {
    const db = admin.firestore();

    if (!request.auth || !request.auth.token || !request.auth.token.email) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }

    const callerEmail = request.auth.token.email.toLowerCase();
    const callerRole = request.auth.token.role;
    const callerSchoolId = request.auth.token.schoolId;
    const callerClassIds = request.auth.token.classIds || [];

    const email = String(request.data && request.data.email ? request.data.email : "")
      .trim()
      .toLowerCase();
    if (!email) {
      throw new HttpsError("invalid-argument", "Target email is required.");
    }

    const targetDoc = await db.collection("allowed_users").doc(email).get();
    if (!targetDoc.exists) {
      throw new HttpsError("not-found", "Target user does not exist.");
    }

    const targetData = targetDoc.data();
    const targetRole = targetData.role;
    const targetSchoolId = targetData.schoolId;

    const isAdmin = callerRole === "admin" || ROOT_ADMIN_EMAILS.includes(callerEmail);

    if (!isAdmin && targetSchoolId !== callerSchoolId) {
      throw new HttpsError("permission-denied", "Target user belongs to a different school.");
    }

    let isAuthorized = false;
    if (isAdmin || ["owner", "ownerPrincipal", "principal", "coordinator"].includes(callerRole)) {
      isAuthorized = true;
    } else if (callerRole === "teacher" || callerRole === "subjectTeacher") {
      // Teachers can only update guardians in classes they teach
      if (targetRole === "guardian" && targetData.studentClass && callerClassIds.includes(targetData.studentClass)) {
        isAuthorized = true;
      }
    }

    if (!isAuthorized) {
      throw new HttpsError("permission-denied", "You are not authorized to update this user's details.");
    }

    const updates = {
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (request.data.name !== undefined) {
      updates.name = String(request.data.name).trim();
    }

    if (targetRole === "guardian") {
      if (request.data.studentClass !== undefined) {
        if ((callerRole === "teacher" || callerRole === "subjectTeacher") && 
            !callerClassIds.includes(request.data.studentClass)) {
          throw new HttpsError("permission-denied", "Cannot assign guardian to a class you do not teach.");
        }
        updates.studentClass = request.data.studentClass;
      }
      if (request.data.studentRoll !== undefined) updates.studentRoll = Number(request.data.studentRoll);
      if (request.data.studentSection !== undefined) updates.studentSection = request.data.studentSection;
      if (request.data.studentAdmissionId !== undefined) updates.studentAdmissionId = request.data.studentAdmissionId;
    } else if (["teacher", "subjectTeacher"].includes(targetRole)) {
      if (request.data.classIds !== undefined) {
        updates.classIds = Array.isArray(request.data.classIds) ? request.data.classIds.map(String) : [];
      }
      if (request.data.teacherId !== undefined) {
        updates.teacherId = String(request.data.teacherId).trim();
      }
    }

    await db.collection("allowed_users").doc(email).update(updates);

    return { success: true };
  }
);

/**
 * Firestore trigger: send an FCM push whenever a notification document is
 * created (#52). Publishes to the topic that corresponds to the notification's
 * audience; client devices subscribe to the topics they're allowed to see
 * (PushService). Topic naming MUST match the client exactly:
 *   topic = "s_{schoolId}_{audience}"  with every non [A-Za-z0-9_-] char → "_"
 *
 * SECURITY (H1): FCM **topic** subscription is NOT access-controlled by Firebase
 * — any client can subscribe to any topic, and topic names are predictable
 * (`s_{schoolId}_{audience}`), so a malicious client could subscribe to another
 * school's / another parent's topic and receive the push copy. The Firestore
 * notification *document* is protected by rules, but the *push payload* is not.
 * Therefore per-student / per-individual channels carry NO PII in the push: a
 * generic "you have a new notification" is sent and the app fetches the real,
 * rules-protected document on open. Only intentional in-school broadcasts
 * (announcements to all/teachers/guardians and role digests) keep their text.
 *
 * Best-effort: a send failure is logged and never throws (the in-app
 * notifications feed is the source of truth; push is a convenience layer).
 */
const sanitizeTopic = (s) => String(s).replace(/[^A-Za-z0-9_-]/g, "_");

// Audiences that are intentional in-school broadcasts and carry no per-student
// PII — safe to show their text in the push. Everything else (guardian:*,
// guardian_adm:*, teacher:*, class:*, class_teacher:*) is genericised.
const BROADCAST_AUDIENCES = new Set([
  "all", "teachers", "guardians", "coordinator", "principal",
]);

exports.pushOnNotificationCreate = onDocumentCreated(
  { document: "schools/{sid}/notifications/{notifId}", region: "asia-south1" },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data() || {};
    const audience = String(data.audience || "");
    if (!audience) return;

    const sid = event.params.sid;
    const topic = `s_${sanitizeTopic(sid)}_${sanitizeTopic(audience)}`;

    // Only broadcast audiences expose their real title/body in the push. For any
    // targeted (per-student / per-individual) audience, send a contentless
    // notice so a rogue topic subscriber learns nothing — the app opens to the
    // rules-protected feed to show the actual content.
    const isBroadcast = BROADCAST_AUDIENCES.has(audience);
    const title = isBroadcast
      ? String(data.title || "School App")
      : "School App";
    const body = isBroadcast
      ? String(data.body || data.message || "")
      : "You have a new notification. Open the app to view.";

    try {
      await admin.messaging().send({
        topic,
        notification: { title, body },
        android: { priority: "high", notification: { channelId: "default" } },
        // No student name / status / free text in the data payload either.
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
      const guardianQuery = await db.collection("allowed_users").where("email", "==", guardianEmail).limit(1).get();
      if (!guardianQuery.empty) {
        const guardianSnap = guardianQuery.docs[0];
        const guardianRef = guardianSnap.ref;
        const data = guardianSnap.data() || {};
        let links = data.studentLinks || [];
        links = links.filter((l) => !(l.studentClass === className && l.studentRoll === roll && (l.studentSection || '') === section));
        if (links.length === 0) {
          // No remaining students linked to this guardian, remove allowed_users + Auth
          await guardianRef.delete();
          // Delete Auth account
          try {
            await admin.auth().deleteUser(guardianSnap.id);
          } catch (authErr) {
            if (!authErr || authErr.code !== "auth/user-not-found") {
              logger.warn(`deleteAuth failed for guardian UID ${guardianSnap.id}`, authErr && authErr.code);
            }
          }
        } else {
          // Update links
          const studentIds = links.map((l) => studentDocId(l.studentClass, l.studentSection, l.studentRoll));
          const classIds = [...new Set(links.map((l) => {
            const cls = l.studentClass || "";
            const sec = l.studentSection || "";
            return sec ? `${cls}-${sec}` : cls;
          }))];
          await guardianRef.update({
            studentLinks: links,
            studentIds: studentIds,
            classIds: classIds
          });
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

  // 3b. Flat fee payments
  try {
    const pSnap = await schoolRef.collection("payments")
      .where("className", "==", className)
      .where("roll", "==", roll)
      .get();
    for (let i = 0; i < pSnap.docs.length; i += 400) {
      const batch = db.batch();
      pSnap.docs.slice(i, i + 400).forEach((pDoc) => batch.delete(pDoc.ref));
      await batch.commit();
    }
  } catch (err) {
    logger.warn(`flat fee payments cleanup failed for ${docId}`, err && err.message);
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
  { cors: true, region: "asia-south1", invoker: "public", enforceAppCheck: false },
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
  { cors: true, region: "asia-south1", invoker: "public", enforceAppCheck: false },
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
  { cors: true, region: "asia-south1", invoker: "public", enforceAppCheck: false },
  async (request) => {
    const db = admin.firestore();
    if (!request.auth || !request.auth.token || !request.auth.token.email) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const d = request.data || {};
    const action = String(d.action || "").trim();
    const entity = String(d.entity || "").trim();
    if (!action || !entity) {
      throw new HttpsError("invalid-argument", "action and entity are required.");
    }

    const callerEmail = String(request.auth.token.email).toLowerCase();
    const snap = await db.collection("allowed_users").doc(callerEmail).get();
    const role = resolveCallerRole(callerEmail, snap); // 'admin' for root admin
    
    if (!role) {
      throw new HttpsError("permission-denied", "Unauthorized actor role.");
    }

    // Role-based Gating:
    // Guardians can only audit consent or leave_application operations
    if (role === "guardian") {
      const allowedGuardianEntities = ["consent", "leave_application"];
      if (!allowedGuardianEntities.includes(entity)) {
        throw new HttpsError("permission-denied", "Guardians cannot audit this entity.");
      }
    }

    // Teachers/subjectTeachers cannot audit sensitive administrative or financial entities
    if (role === "teacher" || role === "subjectTeacher") {
      const forbiddenTeacherEntities = [
        "fee_payment",
        "fee_reconciliation",
        "fee_structure",
        "teacher",
        "timetable",
        "school_settings",
        "expense",
        "audit_logs"
      ];
      if (forbiddenTeacherEntities.includes(entity)) {
        throw new HttpsError("permission-denied", "Teachers cannot audit administrative or financial entities.");
      }
    }

    // Strict allowed lists for actions and entities
    const ALLOWED_ACTIONS = ["create", "update", "delete", "reverse", "promote"];
    const ALLOWED_ENTITIES = [
      "student", "attendance", "fee_payment", "homework", "announcement",
      "copy_check", "leave_application", "teacher", "timetable",
      "reconciled_payment", "fee_structure", "fee_reconciliation",
      "school_settings", "datesheet", "duties", "consent", "expense",
      "marks", "syllabus", "study_material", "class_diary"
    ];
    if (!ALLOWED_ACTIONS.includes(action)) {
      throw new HttpsError("invalid-argument", `Invalid action: ${action}`);
    }
    if (!ALLOWED_ENTITIES.includes(entity)) {
      throw new HttpsError("invalid-argument", `Invalid entity: ${entity}`);
    }

    const callerSchoolId = snap.exists ? snap.get("schoolId") : null;
    // Confine the entry to the caller's own school; the root admin may target
    // any school via the request payload.
    const schoolId = role === "admin"
      ? String(d.schoolId || callerSchoolId || "")
      : callerSchoolId;
    if (!schoolId) {
      throw new HttpsError("failed-precondition", "No school for the audit entry.");
    }

    // Limit string lengths to prevent DoS/bloating
    const entityId = String(d.entityId || "").substring(0, 100);
    const reason = d.reason ? String(d.reason).substring(0, 250) : null;

    const entry = {
      action,
      entity,
      entityId,
      actorUid: request.auth.uid,
      actorEmail: callerEmail,
      actorName: (snap.exists && snap.get("name")) || callerEmail,
      actorRole: role,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (d.before && typeof d.before === "object") entry.before = d.before;
    if (d.after && typeof d.after === "object") entry.after = d.after;
    if (reason) entry.reason = reason;
    entry.expireAt = expireAtAfterDays(AUDIT_LOG_RETENTION_DAYS); // TTL

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
  { cors: true, region: "asia-south1", invoker: "public", enforceAppCheck: false },
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
      // Every notification writer (NotificationService._addAndLog, the fee
      // reminder, onAttendanceWritten's alerts) stamps `createdAt` — there is no
      // `timestamp` field on notifications, so the previous where("timestamp")
      // matched NOTHING and the purge silently skipped the entire collection.
      // (audit_logs genuinely uses `timestamp` and tombstones `deletedAt`; the
      // two queries below are correct.)
      const snap = await schoolRef
        .collection("notifications")
        .where("createdAt", "<", notifCutoff)
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
 * Scopes to the flat collection path:
 * schools/{sid}/payments/{paymentId}
 */
exports.sendReceiptEmail = onDocumentCreated(
  {
    document: "schools/{sid}/payments/{paymentId}",
    region: "asia-south1"
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
    const className = payment.className || "";
    const classKey = className.replace(/ /g, "_");
    const roll = payment.roll;

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
 * SCALE-14: maintain the denormalized `students/{id}.commsConsent` flag.
 *
 * onAttendanceWritten needs to know, per absent student, whether attendance
 * alerts are consented. Querying the `consents` subcollection per absent student
 * per day is the dominant read cost on that hot path. Consent changes RARELY, so
 * we recompute the boolean here — once per consent write — and stamp it onto the
 * parent student doc, which the attendance trigger already fetches for name/class.
 *
 * The flag is written with set+merge (single field) and is SERVER-OWNED: it is
 * deliberately NOT part of Student.toJson, because student docs are saved with a
 * full `.set()` overwrite (student_repository.dart) that would clobber it. A
 * clobbered flag reads back as `undefined`, which onAttendanceWritten treats as
 * "unknown → fall back to the subcollection query" — so the worst case is the
 * old (correct) behaviour, never a wrong/stale decision.
 */
exports.syncCommsConsent = onDocumentWritten(
  { document: "schools/{sid}/students/{studentId}/consents/{consentId}", region: "asia-south1" },
  async (event) => {
    const sid = event.params.sid;
    const studentId = event.params.studentId;
    const db = admin.firestore();
    try {
      const consentsSnap = await db.collection("schools").doc(sid)
        .collection("students").doc(studentId)
        .collection("consents").get();
      const commsConsent = consentDocsGrantComms(consentsSnap.docs);
      await db.collection("schools").doc(sid)
        .collection("students").doc(studentId)
        .set({ commsConsent }, { merge: true });
    } catch (err) {
      logger.warn(`[syncCommsConsent] failed for ${sid}/${studentId}`, err && err.message);
    }
  }
);

/**
 * SCALE-02: maintain per-class visible-enrollment counters (`class_stats/{key}`).
 *
 * The dashboards need each class's TOTAL student count (the "Present X/total"
 * denominator) without reading every student doc. We keep an exact counter,
 * adjusted by the delta of THIS write: a student counts toward its class iff it
 * is "visible" (not promoted, not deletion-pending) — matching
 * StudentService._visibleOnly. Handling before/after independently covers create
 * (no before), delete (no after), a visibility toggle, AND a class change (which
 * moves the count between two class keys). Counter key = className with spaces
 * → underscores, matching the dashboard's sanitisation. Drift is repaired by the
 * `backfillClassStats` callable (also the initial seed).
 */
function isVisibleStudent(data) {
  return !!data && data.promoted !== true && data.deletionPending !== true;
}
function classStatsKey(className) {
  return String(className || "").replace(/ /g, "_");
}

exports.syncClassStats = onDocumentWritten(
  { document: "schools/{sid}/students/{studentId}", region: "asia-south1" },
  async (event) => {
    const sid = event.params.sid;
    const before = event.data && event.data.before;
    const after = event.data && event.data.after;
    const beforeData = (before && before.exists) ? (before.data() || {}) : null;
    const afterData = (after && after.exists) ? (after.data() || {}) : null;

    const beforeVisible = isVisibleStudent(beforeData);
    const afterVisible = isVisibleStudent(afterData);
    const beforeKey = beforeVisible ? classStatsKey(beforeData.className) : null;
    const afterKey = afterVisible ? classStatsKey(afterData.className) : null;

    // No net change to any class total — nothing to do.
    if (beforeKey === afterKey) return;

    const db = admin.firestore();
    const statsCol = db.collection("schools").doc(sid).collection("class_stats");
    const deltas = {}; // key → net increment
    if (beforeKey) deltas[beforeKey] = (deltas[beforeKey] || 0) - 1;
    if (afterKey) deltas[afterKey] = (deltas[afterKey] || 0) + 1;

    try {
      const batch = db.batch();
      for (const [key, delta] of Object.entries(deltas)) {
        if (delta === 0) continue;
        const className = (afterKey === key ? afterData.className : beforeData.className);
        batch.set(statsCol.doc(key), {
          className,
          total: admin.firestore.FieldValue.increment(delta),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      }
      await batch.commit();
    } catch (err) {
      logger.warn(`[syncClassStats] failed for ${sid}/${event.params.studentId}`, err && err.message);
    }
  }
);

/**
 * Firestore trigger: publish absence/leave notifications to the guardian's topic channel
 * when an absence or leave status is recorded, subject to consent validation (DPDP compliance).
 */
exports.onAttendanceWritten = onDocumentWritten(
  { document: "schools/{sid}/attendance/{docId}", region: "asia-south1" },
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
    // The padded date key, e.g. "2026-06-11" — the part after the prefix's "_".
    const dateKey = docId.substring(classSectionPrefix.length + 1);

    // ── H2: mirror each student's status into a per-student doc ────────────────
    // The class-day `attendance/{docId}` doc holds EVERY classmate's status, so
    // guardians can no longer read it (staff-only rule). Instead we mirror each
    // student's own status into `student_attendance/{studentDocId}.days_{YYYY}[dateKey]`
    // (year-partitioned, SCALE-13), which the guardian rule scopes to their own
    // child. Only rolls whose status
    // actually changed are written (idempotent — re-saving the same status is a
    // no-op), keeping write amplification proportional to real changes.
    try {
      const changed = Object.entries(rollsAfter)
        .filter(([rollStr, status]) => rollsBefore[rollStr] !== status)
        .map(([rollStr, status]) => [parseInt(rollStr, 10), status])
        .filter(([roll]) => Number.isInteger(roll));
      // Chunk under Firestore's 500-op batch limit (classes are small, but be safe).
      for (let i = 0; i < changed.length; i += 450) {
        const mirrorBatch = db.batch();
        for (const [roll, status] of changed.slice(i, i + 450)) {
          const studentDocId = `${classSectionPrefix}_${roll}`;
          // SCALE-13: year-partition the mirror. A flat `days` map grows one key
          // per school-day forever (unbounded doc, re-sent in full to the
          // guardian listener on every change). Writing into `days_{YYYY}`
          // instead caps each map at ~250 keys/year. set+merge deep-merges the
          // nested map, so prior days in the same year are retained.
          const yearField = `days_${dateKey.slice(0, 4)}`;
          mirrorBatch.set(
            db.collection("schools").doc(sid)
              .collection("student_attendance").doc(studentDocId),
            {
              schoolId: sid,
              roll,
              [yearField]: { [dateKey]: status },
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
        }
        await mirrorBatch.commit();
      }
    } catch (err) {
      logger.warn(`[onAttendanceWritten] mirror write failed for ${docId}`, err && err.message);
    }

    // ── Guardian absence/leave alerts (SCALE-14) ───────────────────────────────
    // Process every NEWLY absent/leave student in parallel (was a serial loop,
    // which stretched function wall-time on high-absence classes), and decide
    // consent from the denormalized `commsConsent` flag (maintained by
    // syncCommsConsent) instead of a per-student `consents` subcollection query.
    // The flag is trusted ONLY when present as a boolean; when absent — never
    // computed yet, or clobbered by a full-overwrite student save — we fall back
    // to the subcollection query, so the consent decision is never wrong, only
    // (rarely) slower. Notification docs are batched; each still triggers
    // pushOnNotificationCreate (the single push path — intentionally unchanged).
    const newlyAbsent = [];
    for (const [rollStr, status] of Object.entries(rollsAfter)) {
      if (status !== "Absent" && status !== "Leave") continue;
      if (rollsBefore[rollStr] === status) continue; // not a NEW change
      const roll = parseInt(rollStr, 10);
      if (!Number.isInteger(roll)) continue;
      newlyAbsent.push({ roll, status, studentDocId: `${classSectionPrefix}_${roll}` });
    }

    if (newlyAbsent.length > 0) {
      try {
        const studentsCol = db.collection("schools").doc(sid).collection("students");
        const studentSnaps = await db.getAll(
          ...newlyAbsent.map((e) => studentsCol.doc(e.studentDocId)));

        const alerts = (await Promise.all(newlyAbsent.map(async (entry, i) => {
          const snap = studentSnaps[i];
          if (!snap.exists) {
            logger.warn(`[onAttendanceWritten] Student document not found: ${entry.studentDocId}`);
            return null;
          }
          const data = snap.data() || {};
          let hasConsent;
          if (typeof data.commsConsent === "boolean") {
            hasConsent = data.commsConsent; // fast path: denormalized flag
          } else {
            const consentsSnap = await studentsCol.doc(entry.studentDocId)
              .collection("consents").get(); // fallback when flag not yet set
            hasConsent = consentDocsGrantComms(consentsSnap.docs);
          }
          if (!hasConsent) return null;
          return {
            studentDocId: entry.studentDocId,
            roll: entry.roll,
            status: entry.status,
            studentName: data.name || "Student",
            studentClass: data.className || "",
          };
        }))).filter(Boolean);

        // targetStudentId (L2) is REQUIRED by the guardian notification read rule
        // for a `guardian:{class}:{roll}` audience — without it the guardian is
        // denied their own alert (fail-closed). It is the student doc id, i.e.
        // the attendance doc's class-section prefix + roll.
        const notifsCol = db.collection("schools").doc(sid).collection("notifications");
        for (let i = 0; i < alerts.length; i += 450) {
          const batch = db.batch();
          for (const a of alerts.slice(i, i + 450)) {
            batch.set(notifsCol.doc(), {
              type: "attendance_alert",
              title: "Attendance Alert",
              body: `${a.studentName} has been marked ${a.status} today.`,
              audience: `guardian:${a.studentClass}:${a.roll}`,
              targetStudentId: a.studentDocId,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
              expireAt: notificationExpireAt(), // TTL — see retention note
            });
          }
          await batch.commit();
        }
        if (alerts.length > 0) {
          logger.info(`[onAttendanceWritten] Sent ${alerts.length} attendance alert(s) for ${docId}`);
        }
      } catch (err) {
        logger.error(`[onAttendanceWritten] alert processing failed for ${docId}:`, err);
      }
    }

    // ── SCALE-02: maintain the per-section attendance ROLLUP ───────────────────
    // The coordinator/principal dashboards used to read EVERY student doc in the
    // school (StudentService.fetchAll) on every open just to render per-class
    // present/absent/leave counts + the inline absent/leave list. We instead
    // mirror exactly what they render into `attendance_summary/{sameDocId}` (1:1
    // with this attendance doc, so no write hotspot), keyed by `dateKey` so the
    // dashboard can fetch "today" in one query with ZERO student reads. The
    // denominator (enrolled total) comes from `class_stats` (syncClassStats).
    try {
      const reasons = dataAfter.reasons || {};
      let present = 0, absent = 0, leave = 0;
      const absentRolls = [];
      for (const [rollStr, status] of Object.entries(rollsAfter)) {
        if (status === "Present") present++;
        else if (status === "Absent") { absent++; absentRolls.push(rollStr); }
        else if (status === "Leave") { leave++; absentRolls.push(rollStr); }
      }

      // Fetch ONLY the absent/leave students for their name/phone (small subset);
      // present students never need a read. Then build the inline detail list.
      const studentsCol = db.collection("schools").doc(sid).collection("students");
      const absentLeave = [];
      if (absentRolls.length > 0) {
        const snaps = await db.getAll(
          ...absentRolls.map((r) => studentsCol.doc(`${classSectionPrefix}_${r}`)));
        absentRolls.forEach((rollStr, i) => {
          const snap = snaps[i];
          if (!snap || !snap.exists) return; // deleted student still in rolls — drop
          const d = snap.data() || {};
          const roll = parseInt(rollStr, 10);
          absentLeave.push({
            name: d.name || "Student",
            roll: Number.isInteger(roll) ? roll : rollStr,
            status: rollsAfter[rollStr],
            reason: reasons[rollStr] != null ? String(reasons[rollStr]) : null,
            phone: d.phone || "",
          });
        });
      }

      await db.collection("schools").doc(sid)
        .collection("attendance_summary").doc(docId)
        .set({
          schoolId: sid,
          dateKey,
          date: dataAfter.date || null,
          present, absent, leave,
          marked: Object.keys(rollsAfter).length > 0,
          absentLeave,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    } catch (err) {
      logger.error(`[onAttendanceWritten] summary rollup failed for ${docId}:`, err);
    }
  }
);

/**
 * Callable: backfillStudentAttendance({ schoolId })
 *
 * One-time backfill for H2: builds the per-student attendance mirror
 * (`student_attendance/{studentDocId}.days_{YYYY}`, year-partitioned per
 * SCALE-13) from all EXISTING class-day
 * `attendance/{cls}` docs, so guardians see their historical calendar after the
 * class doc is locked down to staff-only. Going forward, `onAttendanceWritten`
 * keeps the mirror current; this only seeds the past. Idempotent — safe to
 * re-run. Restricted to admin/owner of the school (root admin may target any).
 */
exports.backfillStudentAttendance = onCall(
  { cors: true, region: "asia-south1", invoker: "public", enforceAppCheck: false },
  async (request) => {
    const db = admin.firestore();
    if (!request.auth || !request.auth.token || !request.auth.token.email) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const schoolId = String((request.data && request.data.schoolId) || "").trim();
    if (!schoolId) {
      throw new HttpsError("invalid-argument", "schoolId is required.");
    }
    const callerEmail = String(request.auth.token.email).toLowerCase();
    const callerSnap = await db.collection("allowed_users").doc(callerEmail).get();
    const callerRole = resolveCallerRole(callerEmail, callerSnap);
    const callerSchoolId = callerSnap.exists ? callerSnap.get("schoolId") : null;
    if (!PURGE_ROLES.includes(callerRole)) {
      throw new HttpsError("permission-denied", "You are not authorized to run this backfill.");
    }
    if (callerRole !== "admin" && callerSchoolId !== schoolId) {
      throw new HttpsError("permission-denied", "You can only backfill your own school.");
    }

    const dateSfxLen = 11; // "_2026-06-11"
    const attendance = await db.collection("schools").doc(schoolId)
      .collection("attendance").get();

    // Accumulate days per studentDocId across every day-doc, bucketed by YEAR
    // so the mirror seeds into the same `days_{YYYY}` partitions the live
    // onAttendanceWritten trigger writes (SCALE-13). A flat `days` map would
    // re-introduce the unbounded-doc growth this partitioning exists to avoid.
    const perStudent = {}; // studentDocId → { roll, daysByYear: { '2026': { dateKey: status } } }
    for (const doc of attendance.docs) {
      const id = doc.id;
      if (id.length <= dateSfxLen) continue;
      const prefix = id.substring(0, id.length - dateSfxLen);
      const dateKey = id.substring(prefix.length + 1);
      const year = dateKey.slice(0, 4);
      const rolls = (doc.data() || {}).rolls || {};
      for (const [rollStr, status] of Object.entries(rolls)) {
        if (typeof status !== "string" || !status) continue;
        const roll = parseInt(rollStr, 10);
        if (!Number.isInteger(roll)) continue;
        const studentDocId = `${prefix}_${roll}`;
        if (!perStudent[studentDocId]) perStudent[studentDocId] = { roll, daysByYear: {} };
        const byYear = perStudent[studentDocId].daysByYear;
        if (!byYear[year]) byYear[year] = {};
        byYear[year][dateKey] = status;
      }
    }

    const ids = Object.keys(perStudent);
    let written = 0;
    for (let i = 0; i < ids.length; i += 400) {
      const batch = db.batch();
      ids.slice(i, i + 400).forEach((studentDocId) => {
        const { roll, daysByYear } = perStudent[studentDocId];
        const payload = {
          schoolId,
          roll,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };
        for (const [year, days] of Object.entries(daysByYear)) {
          payload[`days_${year}`] = days;
        }
        batch.set(
          db.collection("schools").doc(schoolId)
            .collection("student_attendance").doc(studentDocId),
          payload,
          { merge: true },
        );
        written++;
      });
      await batch.commit();
    }

    return { ok: true, studentsBackfilled: written, dayDocsScanned: attendance.size };
  }
);

/**
 * Callable: backfillCommsConsent({ schoolId })
 *
 * One-time seed for SCALE-14: computes the denormalized `students/{id}.commsConsent`
 * flag for EVERY existing student from their `consents` subcollection, so
 * onAttendanceWritten can take the fast path immediately instead of falling back
 * to a per-student consent query until each student's consent happens to change.
 * Idempotent — safe to re-run (also useful after bulk student edits that
 * overwrite the flag). Restricted to admin/owner of the school (root admin may
 * target any). Mirrors backfillStudentAttendance's auth.
 */
exports.backfillCommsConsent = onCall(
  { cors: true, region: "asia-south1", invoker: "public", enforceAppCheck: false },
  async (request) => {
    const db = admin.firestore();
    if (!request.auth || !request.auth.token || !request.auth.token.email) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const schoolId = String((request.data && request.data.schoolId) || "").trim();
    if (!schoolId) {
      throw new HttpsError("invalid-argument", "schoolId is required.");
    }
    const callerEmail = String(request.auth.token.email).toLowerCase();
    const callerSnap = await db.collection("allowed_users").doc(callerEmail).get();
    const callerRole = resolveCallerRole(callerEmail, callerSnap);
    const callerSchoolId = callerSnap.exists ? callerSnap.get("schoolId") : null;
    if (!PURGE_ROLES.includes(callerRole)) {
      throw new HttpsError("permission-denied", "You are not authorized to run this backfill.");
    }
    if (callerRole !== "admin" && callerSchoolId !== schoolId) {
      throw new HttpsError("permission-denied", "You can only backfill your own school.");
    }

    const studentsCol = db.collection("schools").doc(schoolId).collection("students");
    const studentsSnap = await studentsCol.get();

    let updated = 0;
    // Resolve consent for each student in parallel, then write the flags in
    // chunked batches (under the 500-op limit).
    const flags = await Promise.all(studentsSnap.docs.map(async (s) => {
      const consentsSnap = await studentsCol.doc(s.id).collection("consents").get();
      return { id: s.id, commsConsent: consentDocsGrantComms(consentsSnap.docs) };
    }));
    for (let i = 0; i < flags.length; i += 450) {
      const batch = db.batch();
      flags.slice(i, i + 450).forEach(({ id, commsConsent }) => {
        batch.set(studentsCol.doc(id), { commsConsent }, { merge: true });
        updated++;
      });
      await batch.commit();
    }

    return { ok: true, studentsUpdated: updated };
  }
);

/**
 * Callable: backfillClassStats({ schoolId })
 *
 * SCALE-02 seed/repair: recomputes EVERY `class_stats/{key}.total` exactly by
 * counting visible students (not promoted, not deletion-pending) per class.
 * Run once after deploying syncClassStats, and any time counts may have drifted
 * (e.g. a bulk import/promotion that pre-dated the trigger). Idempotent — it
 * overwrites totals with the freshly counted values. admin/owner-gated.
 */
exports.backfillClassStats = onCall(
  { cors: true, region: "asia-south1", invoker: "public", enforceAppCheck: false },
  async (request) => {
    const db = admin.firestore();
    if (!request.auth || !request.auth.token || !request.auth.token.email) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const schoolId = String((request.data && request.data.schoolId) || "").trim();
    if (!schoolId) {
      throw new HttpsError("invalid-argument", "schoolId is required.");
    }
    const callerEmail = String(request.auth.token.email).toLowerCase();
    const callerSnap = await db.collection("allowed_users").doc(callerEmail).get();
    const callerRole = resolveCallerRole(callerEmail, callerSnap);
    const callerSchoolId = callerSnap.exists ? callerSnap.get("schoolId") : null;
    if (!PURGE_ROLES.includes(callerRole)) {
      throw new HttpsError("permission-denied", "You are not authorized to run this backfill.");
    }
    if (callerRole !== "admin" && callerSchoolId !== schoolId) {
      throw new HttpsError("permission-denied", "You can only backfill your own school.");
    }

    const schoolRef = db.collection("schools").doc(schoolId);
    const studentsSnap = await schoolRef.collection("students").get();

    // Count visible students per class key + remember a display className.
    const totals = {};       // key → count
    const classNames = {};   // key → className
    for (const s of studentsSnap.docs) {
      const data = s.data() || {};
      if (!isVisibleStudent(data)) continue;
      const key = classStatsKey(data.className);
      totals[key] = (totals[key] || 0) + 1;
      classNames[key] = data.className || "";
    }

    // Overwrite existing class_stats docs (so stale/removed classes go to 0) and
    // write the freshly counted ones.
    const statsCol = schoolRef.collection("class_stats");
    const existing = await statsCol.get();
    const keys = new Set([...existing.docs.map((d) => d.id), ...Object.keys(totals)]);

    let written = 0;
    const keyList = [...keys];
    for (let i = 0; i < keyList.length; i += 450) {
      const batch = db.batch();
      keyList.slice(i, i + 450).forEach((key) => {
        batch.set(statsCol.doc(key), {
          className: classNames[key] || key.replace(/_/g, " "),
          total: totals[key] || 0,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        written++;
      });
      await batch.commit();
    }

    return { ok: true, classesWritten: written, studentsScanned: studentsSnap.size };
  }
);

/**
 * Callable: backfillAttendanceSummary({ schoolId, dateKey? })
 *
 * SCALE-02 seed: rebuilds `attendance_summary/{docId}` for one day (default
 * today) from the existing `attendance/{docId}` day-docs, so the dashboards have
 * complete summaries for attendance already marked BEFORE onAttendanceWritten's
 * summary write was deployed. Only the requested day is rebuilt (the dashboard
 * only reads "today"); going forward the trigger keeps it current. Idempotent.
 * admin/owner-gated.
 */
exports.backfillAttendanceSummary = onCall(
  { cors: true, region: "asia-south1", invoker: "public", enforceAppCheck: false },
  async (request) => {
    const db = admin.firestore();
    if (!request.auth || !request.auth.token || !request.auth.token.email) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const schoolId = String((request.data && request.data.schoolId) || "").trim();
    if (!schoolId) {
      throw new HttpsError("invalid-argument", "schoolId is required.");
    }
    const callerEmail = String(request.auth.token.email).toLowerCase();
    const callerSnap = await db.collection("allowed_users").doc(callerEmail).get();
    const callerRole = resolveCallerRole(callerEmail, callerSnap);
    const callerSchoolId = callerSnap.exists ? callerSnap.get("schoolId") : null;
    if (!PURGE_ROLES.includes(callerRole)) {
      throw new HttpsError("permission-denied", "You are not authorized to run this backfill.");
    }
    if (callerRole !== "admin" && callerSchoolId !== schoolId) {
      throw new HttpsError("permission-denied", "You can only backfill your own school.");
    }

    // Default to "today" in the same padded YYYY-MM-DD form the app uses. The
    // attendance doc id suffix is always 11 chars ("_2026-06-11").
    const requestedKey = String((request.data && request.data.dateKey) || "").trim();
    const dateKey = requestedKey || new Date().toISOString().slice(0, 10);
    const dateSfx = `_${dateKey}`;

    const schoolRef = db.collection("schools").doc(schoolId);
    const studentsCol = schoolRef.collection("students");
    const attendanceSnap = await schoolRef.collection("attendance").get();

    const dayDocs = attendanceSnap.docs.filter((d) => d.id.endsWith(dateSfx));

    let written = 0;
    for (const doc of dayDocs) {
      const docId = doc.id;
      const data = doc.data() || {};
      const rolls = data.rolls || {};
      const reasons = data.reasons || {};
      const classSectionPrefix = docId.substring(0, docId.length - dateSfx.length);

      let present = 0, absent = 0, leave = 0;
      const absentRolls = [];
      for (const [rollStr, status] of Object.entries(rolls)) {
        if (status === "Present") present++;
        else if (status === "Absent") { absent++; absentRolls.push(rollStr); }
        else if (status === "Leave") { leave++; absentRolls.push(rollStr); }
      }

      const absentLeave = [];
      if (absentRolls.length > 0) {
        const snaps = await db.getAll(
          ...absentRolls.map((r) => studentsCol.doc(`${classSectionPrefix}_${r}`)));
        absentRolls.forEach((rollStr, i) => {
          const snap = snaps[i];
          if (!snap || !snap.exists) return;
          const d = snap.data() || {};
          const roll = parseInt(rollStr, 10);
          absentLeave.push({
            name: d.name || "Student",
            roll: Number.isInteger(roll) ? roll : rollStr,
            status: rolls[rollStr],
            reason: reasons[rollStr] != null ? String(reasons[rollStr]) : null,
            phone: d.phone || "",
          });
        });
      }

      await schoolRef.collection("attendance_summary").doc(docId).set({
        schoolId,
        dateKey,
        date: data.date || null,
        present, absent, leave,
        marked: Object.keys(rolls).length > 0,
        absentLeave,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      written++;
    }

    return { ok: true, dateKey, summariesWritten: written };
  }
);


// ═══════════════════════════════════════════════════════════════════════════
// FEES — server-authoritative payment recording (M3)
//
// These callables own the receipt-number counter, the overpayment cap, and the
// cached totals server-side (Admin SDK) so they cannot be bypassed by a direct
// client write that forges receiptNo / totalPaidPaise / amount or skips the cap.
// They are a faithful port of FeeService.addPayment / deletePayment.
//
// ADDITIVE FOR NOW: nothing is wired to these yet and the fee_payments rules
// still allow management writes, so live fee collection is unchanged. CUTOVER
// (separate, staged deploy) = (1) deploy these, (2) point FeeService at them,
// (3) lock the fee_payments leaf-doc writes to Admin-SDK-only in firestore.rules.
// Do those three together / in that order or collection breaks.
// ═══════════════════════════════════════════════════════════════════════════

// Management roles permitted to record/reverse fees (mirrors FeeService callers).
const FEE_ROLES = ["admin", "owner", "ownerPrincipal", "principal", "coordinator"];
const ALLOWED_FEE_MODES = ["Cash", "UPI", "Bank", "Cheque"];
const MONTH_INDEX = {
  January: 1, February: 2, March: 3, April: 4, May: 5, June: 6,
  July: 7, August: 8, September: 9, October: 10, November: 11, December: 12,
};

/** Mask 13–19 digit card/account numbers in free text (port of
 *  FeeService.maskSensitiveInfo). */
function maskCardNumbers(input) {
  if (input == null) return input;
  return String(input).replace(/\b(?:\d[ -]*?){13,19}\b/g, (match) => {
    const clean = match.replace(/\D/g, "");
    return (clean.length >= 13 && clean.length <= 19)
      ? `****-****-****-${clean.slice(-4)}`
      : match;
  });
}

/** Resolve + authorize a fee caller (management of the same school; admin is
 *  cross-school). Returns { callerEmail, callerRole, callerSchoolId }. */
async function authorizeFeeCaller(db, request, schoolId) {
  if (!request.auth || !request.auth.token || !request.auth.token.email) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  const callerEmail = String(request.auth.token.email).toLowerCase();
  const snap = await db.collection("allowed_users").doc(callerEmail).get();
  const callerRole = resolveCallerRole(callerEmail, snap);
  const callerSchoolId = snap.exists ? snap.get("schoolId") : null;
  const callerName = snap.exists ? snap.get("name") : callerEmail;
  if (!FEE_ROLES.includes(callerRole)) {
    throw new HttpsError("permission-denied", "You are not allowed to record fees.");
  }
  if (callerRole !== "admin" && callerSchoolId !== schoolId) {
    throw new HttpsError("permission-denied", "You can only record fees for your own school.");
  }
  return { callerEmail, callerRole, callerSchoolId, callerName };
}

/**
 * Callable: recordPayment({ schoolId, className, roll, payment, clientTxnId,
 *                           enforceCap = true, studentId })
 *
 * `payment` is the client-built body MINUS any server-owned field: the function
 * IGNORES client-supplied receiptNo / totalPaidPaise and stamps its own. Returns
 * { ok, receiptNo }.
 */
exports.recordPayment = onCall(
  { cors: true, region: "asia-south1", invoker: "public", enforceAppCheck: false },
  async (request) => {
    const db = admin.firestore();
    const d = request.data || {};
    const schoolId = String(d.schoolId || "").trim();
    const className = String(d.className || "").trim();
    const roll = Number.parseInt(d.roll, 10);
    const enforceCap = d.enforceCap !== false; // default true
    const clientTxnId = d.clientTxnId ? String(d.clientTxnId) : "";
    const studentId = d.studentId ? String(d.studentId) : "";
    const p = (d.payment && typeof d.payment === "object") ? d.payment : {};

    if (!schoolId || !className || !Number.isInteger(roll) || roll <= 0) {
      throw new HttpsError("invalid-argument", "schoolId, className and a valid roll are required.");
    }
    const amountPaise = Number.parseInt(p.amountPaise, 10);
    if (!Number.isInteger(amountPaise) || amountPaise <= 0) {
      throw new HttpsError("invalid-argument", "A positive integer amountPaise is required.");
    }
    const mode = String(p.mode || "");
    if (!ALLOWED_FEE_MODES.includes(mode)) {
      throw new HttpsError("invalid-argument", `Invalid payment mode "${mode}".`);
    }
    const installmentName = p.installmentName ? String(p.installmentName) : "";
    const note = (p.note != null) ? maskCardNumbers(String(p.note)) : null;

    const { callerEmail } = await authorizeFeeCaller(db, request, schoolId);

    const classKey = className.replace(/ /g, "_");
    const schoolRef = db.collection("schools").doc(schoolId);
    const studentFeeRef = schoolRef.collection("fee_payments").doc(classKey)
      .collection("students").doc(String(roll));
    const paymentsCol = schoolRef.collection("payments");
    const ref = clientTxnId ? paymentsCol.doc(clientTxnId) : paymentsCol.doc();
    const counterRef = schoolRef.collection("fee_meta").doc("counters");
    const structureRef = schoolRef.collection("fee_structures").doc(classKey);
    const academicRef = schoolRef.collection("settings").doc("academic");
    const classDocRef = schoolRef.collection("fee_payments").doc(classKey);

    // Cold-start fallback (parity with FeeService.getTotalPaid): if the summary
    // doc lacks totalPaidPaise, fall back to the sum of non-reversed payments so
    // the cap can't be bypassed for legacy students with no cached total. Read
    // OUTSIDE the transaction (a query can't run inside one).
    let fallbackPaidPaise = 0;
    try {
      const prior = await paymentsCol
        .where("className", "==", className)
        .where("roll", "==", roll)
        .get();
      for (const pdoc of prior.docs) {
        const pd = pdoc.data() || {};
        if (pd.reversed === true) continue;
        fallbackPaidPaise += (typeof pd.amountPaise === "number")
          ? pd.amountPaise : Math.round((pd.amount || 0) * 100);
      }
    } catch (_) { /* fall back to 0 */ }

    const receiptNo = await db.runTransaction(async (tx) => {
      // ── reads (all before writes) ──
      const existing = await tx.get(ref);
      if (existing.exists) {
        // Idempotent: a retry with the same clientTxnId reuses the receipt.
        return existing.data().receiptNo || (p.receiptNo || "");
      }

      let capPaise = 0;
      if (studentId) {
        const sSnap = await tx.get(schoolRef.collection("students").doc(studentId));
        const customFee = sSnap.exists ? sSnap.data().feeAmount : null;
        if (typeof customFee === "number") capPaise = Math.round(customFee * 100);
      }

      const structSnap = await tx.get(structureRef);
      const validInstallments = new Set();
      if (structSnap.exists) {
        const struct = structSnap.data() || {};
        for (const inst of (struct.installments || [])) {
          if (inst && inst.name) validInstallments.add(inst.name);
        }
        if (capPaise === 0 && typeof struct.totalAnnualFeePaise === "number") {
          capPaise = struct.totalAnnualFeePaise;
        }
      }
      if (installmentName && !validInstallments.has(installmentName)) {
        throw new HttpsError("invalid-argument",
          `Invalid installment name "${installmentName}".`);
      }

      const feeSnap = await tx.get(studentFeeRef);
      const alreadyPaise = (feeSnap.exists && typeof feeSnap.data().totalPaidPaise === "number")
        ? feeSnap.data().totalPaidPaise : fallbackPaidPaise;

      if (enforceCap && capPaise > 0 && alreadyPaise + amountPaise > capPaise) {
        const remaining = Math.max(0, capPaise - alreadyPaise);
        throw new HttpsError("failed-precondition",
          `Payment exceeds the outstanding due of ₹${Math.round(remaining / 100)}.`);
      }

      const counterSnap = await tx.get(counterRef);
      const current = (counterSnap.exists && typeof counterSnap.data().receiptSeq === "number")
        ? counterSnap.data().receiptSeq : 0;
      const next = current + 1;

      let prefixYear = new Date().getFullYear();
      const acadSnap = await tx.get(academicRef);
      if (acadSnap.exists) {
        const startMonth = MONTH_INDEX[acadSnap.data().academicYearStart] || 4;
        const now = new Date();
        if ((now.getMonth() + 1) < startMonth) prefixYear = now.getFullYear() - 1;
      }
      const rno = `RCP-${prefixYear}-${String(next).padStart(6, "0")}`;

      // ── writes ──
      const data = {
        amountPaise,
        mode,
        note,
        installmentName: installmentName || null,
        reversed: false,
        receiptNo: rno,
        schoolId,
        className,
        roll,
        enteredBy: callerEmail,
        reconciled: false,
        paidOn: admin.firestore.FieldValue.serverTimestamp(),
      };
      if (studentId) {
        data.studentId = studentId;
      }
      tx.set(counterRef, { receiptSeq: next }, { merge: true });
      tx.set(ref, data);
      const newTotal = alreadyPaise + amountPaise;
      tx.set(studentFeeRef, { totalPaidPaise: newTotal }, { merge: true });
      tx.set(classDocRef, { rolls: { [String(roll)]: newTotal } }, { merge: true });
      return rno;
    });

    return { ok: true, receiptNo, paymentId: ref.id };
  }
);

/**
 * Callable: reversePayment({ schoolId, className, roll, paymentId, reason })
 * Flags a payment reversed and decrements the cached totals (port of
 * FeeService.deletePayment). Money records are never hard-deleted.
 */
exports.reversePayment = onCall(
  { cors: true, region: "asia-south1", invoker: "public", enforceAppCheck: false },
  async (request) => {
    const db = admin.firestore();
    const d = request.data || {};
    const schoolId = String(d.schoolId || "").trim();
    const className = String(d.className || "").trim();
    const roll = Number.parseInt(d.roll, 10);
    const paymentId = String(d.paymentId || "").trim();
    const reason = String(d.reason || "").trim();

    if (!schoolId || !className || !Number.isInteger(roll) || roll <= 0 || !paymentId) {
      throw new HttpsError("invalid-argument", "schoolId, className, roll and paymentId are required.");
    }
    if (!reason) {
      throw new HttpsError("invalid-argument", "A reversal reason is required.");
    }

    const { callerEmail, callerRole, callerName } = await authorizeFeeCaller(db, request, schoolId);

    const classKey = className.replace(/ /g, "_");
    const schoolRef = db.collection("schools").doc(schoolId);
    const studentFeeRef = schoolRef.collection("fee_payments").doc(classKey)
      .collection("students").doc(String(roll));
    const ref = schoolRef.collection("payments").doc(paymentId);
    const classDocRef = schoolRef.collection("fee_payments").doc(classKey);

    await db.runTransaction(async (tx) => {
      const doc = await tx.get(ref);
      if (!doc.exists) return;
      const data = doc.data() || {};
      if (data.reversed === true) return; // already reversed
      const amountPaise = (typeof data.amountPaise === "number")
        ? data.amountPaise
        : Math.round((data.amount || 0) * 100);

      const feeSnap = await tx.get(studentFeeRef);
      const totalPaidPaise = (feeSnap.exists && typeof feeSnap.data().totalPaidPaise === "number")
        ? feeSnap.data().totalPaidPaise : 0;
      const newTotal = Math.max(0, totalPaidPaise - amountPaise);

      tx.set(ref, {
        reversed: true,
        reversedAt: admin.firestore.FieldValue.serverTimestamp(),
        reversedReason: reason,
      }, { merge: true });
      tx.set(studentFeeRef, { totalPaidPaise: newTotal }, { merge: true });
      tx.set(classDocRef, { rolls: { [String(roll)]: newTotal } }, { merge: true });

      // Add audit log inside the transaction
      const auditRef = schoolRef.collection("audit_logs").doc();
      tx.set(auditRef, {
        action: "reverse",
        entity: "fee_payment",
        entityId: paymentId,
        actorUid: request.auth.uid,
        actorEmail: callerEmail,
        actorName: callerName || callerEmail,
        actorRole: callerRole,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        reason: reason.substring(0, 250),
        expireAt: expireAtAfterDays(AUDIT_LOG_RETENTION_DAYS),
        before: {
          amountPaise: amountPaise,
          mode: data.mode,
          receiptNo: data.receiptNo,
          installmentName: data.installmentName || null
        },
        after: {
          reversed: true,
          reversedReason: reason
        }
      });
    });

    return { ok: true };
  }
);


// ── Fee Pre-Aggregation Triggers and Backfill ───────────────────────────────

function getDaysOverdueHelper(structure, paidPaise, now = new Date()) {
  const installments = structure.installments || [];
  if (installments.length === 0) return 0;

  // Sort installments by dueDate
  const sorted = [...installments].sort((a, b) => {
    const dateA = a.dueDate.toDate ? a.dueDate.toDate() : new Date(a.dueDate);
    const dateB = b.dueDate.toDate ? b.dueDate.toDate() : new Date(b.dueDate);
    return dateA - dateB;
  });

  let cumulativePaise = 0;
  for (const inst of sorted) {
    const instAmountPaise = typeof inst.amountPaise === "number"
      ? inst.amountPaise
      : Math.round((inst.amount || 0) * 100);
    cumulativePaise += instAmountPaise;
    if (paidPaise < cumulativePaise) {
      const dueDate = inst.dueDate.toDate ? inst.dueDate.toDate() : new Date(inst.dueDate);
      if (dueDate < now) {
        return Math.floor((now - dueDate) / (1000 * 60 * 60 * 24));
      }
      return 0;
    }
  }
  return 0;
}

exports.onStudentFeePaidWritten = onDocumentWritten(
  { document: "schools/{sid}/fee_payments/{classKey}/students/{roll}", region: "asia-south1" },
  async (event) => {
    const sid = event.params.sid;
    const classKey = event.params.classKey;
    const roll = Number.parseInt(event.params.roll, 10);
    const after = event.data && event.data.after;
    if (!after || !after.exists) {
      return;
    }
    const afterData = after.data() || {};
    const totalPaidPaise = typeof afterData.totalPaidPaise === "number" ? afterData.totalPaidPaise : 0;

    const db = admin.firestore();
    const className = classKey.replace(/_/g, " ");

    try {
      const studentSnap = await db.collection("schools").doc(sid).collection("students")
        .where("className", "==", className)
        .where("roll", "==", roll)
        .limit(1)
        .get();

      if (studentSnap.empty) {
        logger.warn(`[onStudentFeePaidWritten] Student not found for class: ${className}, roll: ${roll} in school ${sid}`);
        return;
      }

      const studentDoc = studentSnap.docs[0];
      await studentDoc.ref.update({
        totalPaidPaise: totalPaidPaise,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    } catch (err) {
      logger.error(`[onStudentFeePaidWritten] failed for ${sid}/${classKey}/${roll}`, err);
    }
  }
);

exports.syncStudentFeeAggregates = onDocumentWritten(
  { document: "schools/{sid}/students/{studentId}", region: "asia-south1" },
  async (event) => {
    const sid = event.params.sid;
    const studentId = event.params.studentId;
    const before = event.data && event.data.before;
    const after = event.data && event.data.after;
    const beforeData = (before && before.exists) ? (before.data() || {}) : null;
    const afterData = (after && after.exists) ? (after.data() || {}) : null;

    const isVisible = (d) => !!d && d.promoted !== true && d.deletionPending !== true;
    const beforeVisible = isVisible(beforeData);
    const afterVisible = isVisible(afterData);

    const db = admin.firestore();

    if (!beforeVisible && !afterVisible) return;

    try {
      let newCollected = 0;
      let newPending = 0;
      let newOverdue = 0;
      let newFullyPaid = false;
      let newDaysOverdue = 0;
      let newDuePaise = 0;

      const afterClassKey = afterVisible ? afterData.className.replace(/ /g, "_") : null;
      const beforeClassKey = beforeVisible ? beforeData.className.replace(/ /g, "_") : null;

      if (afterVisible) {
        let customFee = typeof afterData.feeAmount === "number" ? afterData.feeAmount : null;
        if (customFee === null && typeof afterData.feeAmount === "string") {
          customFee = parseFloat(afterData.feeAmount);
        }

        let duePaise = 0;
        let structure = null;

        if (customFee !== null && !isNaN(customFee)) {
          duePaise = Math.round(customFee * 100);
        } else if (afterClassKey) {
          const structDoc = await db.collection("schools").doc(sid).collection("fee_structures").doc(afterClassKey).get();
          if (structDoc.exists) {
            structure = structDoc.data() || {};
            duePaise = typeof structure.totalAnnualFeePaise === "number"
              ? structure.totalAnnualFeePaise
              : Math.round((structure.totalAnnualFee || 0) * 100);
          }
        }
        newDuePaise = duePaise;

        const paidPaise = typeof afterData.totalPaidPaise === "number" ? afterData.totalPaidPaise : 0;
        newCollected = paidPaise < duePaise ? paidPaise : duePaise;
        newPending = Math.max(0, duePaise - paidPaise);

        if (newPending > 0 && structure && structure.installments && structure.installments.length > 0) {
          newDaysOverdue = getDaysOverdueHelper(structure, paidPaise);
          if (newDaysOverdue > 0) {
            newOverdue = newPending;
          }
        }
        newFullyPaid = duePaise > 0 && paidPaise >= duePaise;
      }

      const oldCollected = (beforeVisible && typeof beforeData.feeCollectedPaise === "number") ? beforeData.feeCollectedPaise : 0;
      const oldPending = (beforeVisible && typeof beforeData.feePendingPaise === "number") ? beforeData.feePendingPaise : 0;
      const oldOverdue = (beforeVisible && typeof beforeData.feeOverduePaise === "number") ? beforeData.feeOverduePaise : 0;
      const oldDuePaise = (beforeVisible && typeof beforeData.feeDuePaise === "number") ? beforeData.feeDuePaise : 0;
      const oldFullyPaid = beforeVisible && beforeData.feeFullyPaid === true;

      const deltaCollected = newCollected - oldCollected;
      const deltaPending = newPending - oldPending;
      const deltaOverdue = newOverdue - oldOverdue;
      const deltaStudentCount = (afterVisible ? 1 : 0) - (beforeVisible ? 1 : 0);
      const deltaFullyPaid = (newFullyPaid ? 1 : 0) - (oldFullyPaid ? 1 : 0);
      const deltaDue = newDuePaise - oldDuePaise;

      const studentFieldsChanged =
        afterVisible && (
          afterData.feeCollectedPaise !== newCollected ||
          afterData.feePendingPaise !== newPending ||
          afterData.feeOverduePaise !== newOverdue ||
          afterData.feeDaysOverdue !== newDaysOverdue ||
          afterData.feeFullyPaid !== newFullyPaid ||
          afterData.feeDuePaise !== newDuePaise
        );

      const batch = db.batch();

      if (studentFieldsChanged) {
        batch.update(db.collection("schools").doc(sid).collection("students").doc(studentId), {
          feeCollectedPaise: newCollected,
          feePendingPaise: newPending,
          feeOverduePaise: newOverdue,
          feeDaysOverdue: newDaysOverdue,
          feeFullyPaid: newFullyPaid,
          feeDuePaise: newDuePaise
        });
      }

      const schoolSummaryRef = db.collection("schools").doc(sid).collection("summaries").doc("fees");
      batch.set(schoolSummaryRef, {
        collectedPaise: admin.firestore.FieldValue.increment(deltaCollected),
        pendingPaise: admin.firestore.FieldValue.increment(deltaPending),
        overduePaise: admin.firestore.FieldValue.increment(deltaOverdue),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }, { merge: true });

      if (beforeClassKey === afterClassKey && afterClassKey) {
        const classSummaryRef = db.collection("schools").doc(sid).collection("class_fee_summaries").doc(afterClassKey);
        batch.set(classSummaryRef, {
          studentCount: admin.firestore.FieldValue.increment(deltaStudentCount),
          fullyPaid: admin.firestore.FieldValue.increment(deltaFullyPaid),
          totalCollectedPaise: admin.firestore.FieldValue.increment(deltaCollected),
          totalDuePaise: admin.firestore.FieldValue.increment(deltaDue),
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });
      } else {
        if (beforeClassKey) {
          const oldClassRef = db.collection("schools").doc(sid).collection("class_fee_summaries").doc(beforeClassKey);
          batch.set(oldClassRef, {
            studentCount: admin.firestore.FieldValue.increment(-1),
            fullyPaid: admin.firestore.FieldValue.increment(oldFullyPaid ? -1 : 0),
            totalCollectedPaise: admin.firestore.FieldValue.increment(-oldCollected),
            totalDuePaise: admin.firestore.FieldValue.increment(-oldDuePaise),
            updatedAt: admin.firestore.FieldValue.serverTimestamp()
          }, { merge: true });
        }
        if (afterClassKey) {
          const newClassRef = db.collection("schools").doc(sid).collection("class_fee_summaries").doc(afterClassKey);
          batch.set(newClassRef, {
            studentCount: admin.firestore.FieldValue.increment(1),
            fullyPaid: admin.firestore.FieldValue.increment(newFullyPaid ? 1 : 0),
            totalCollectedPaise: admin.firestore.FieldValue.increment(newCollected),
            totalDuePaise: admin.firestore.FieldValue.increment(newDuePaise),
            updatedAt: admin.firestore.FieldValue.serverTimestamp()
          }, { merge: true });
        }
      }

      await batch.commit();

    } catch (err) {
      logger.error(`[syncStudentFeeAggregates] failed for ${sid}/${studentId}`, err);
    }
  }
);

exports.backfillFeeSummaries = onCall(
  { cors: true, region: "asia-south1", invoker: "public", enforceAppCheck: false },
  async (request) => {
    const db = admin.firestore();

    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Auth required.");
    }

    try {
      const schoolsSnap = await db.collection("schools").get();
      const results = [];

      for (const schoolDoc of schoolsSnap.docs) {
        const sid = schoolDoc.id;

        await db.collection("schools").doc(sid).collection("summaries").doc("fees").delete();

        const classSummariesSnap = await db.collection("schools").doc(sid).collection("class_fee_summaries").get();
        const summaryBatch = db.batch();
        for (const doc of classSummariesSnap.docs) {
          summaryBatch.delete(doc.ref);
        }
        await summaryBatch.commit();

        const structuresSnap = await db.collection("schools").doc(sid).collection("fee_structures").get();
        const structures = {};
        for (const doc of structuresSnap.docs) {
          structures[doc.id] = doc.data() || {};
        }

        const studentsSnap = await db.collection("schools").doc(sid).collection("students").get();

        let totalCollectedPaise = 0;
        let totalPendingPaise = 0;
        let totalOverduePaise = 0;

        const classStats = {};

        const studentBatch = db.batch();
        let studentBatchCount = 0;

        for (const studentDoc of studentsSnap.docs) {
          const sData = studentDoc.data() || {};
          const isVisible = sData.promoted !== true && sData.deletionPending !== true;

          if (!isVisible) {
            studentBatch.update(studentDoc.ref, {
              feeCollectedPaise: 0,
              feePendingPaise: 0,
              feeOverduePaise: 0,
              feeDaysOverdue: 0,
              feeFullyPaid: false,
              feeDuePaise: 0
            });
            studentBatchCount++;
            if (studentBatchCount >= 400) {
              await studentBatch.commit();
              studentBatchCount = 0;
            }
            continue;
          }

          const className = sData.className || "";
          const classKey = className.replace(/ /g, "_");
          const roll = typeof sData.roll === "number" ? sData.roll : 0;

          let totalPaidPaise = typeof sData.totalPaidPaise === "number" ? sData.totalPaidPaise : 0;
          if (totalPaidPaise === 0 && className && roll > 0) {
            const feePaymentDoc = await db.collection("schools").doc(sid)
              .collection("fee_payments").doc(classKey)
              .collection("students").doc(String(roll)).get();
            if (feePaymentDoc.exists) {
              totalPaidPaise = feePaymentDoc.data().totalPaidPaise || 0;
            }
          }

          let customFee = typeof sData.feeAmount === "number" ? sData.feeAmount : null;
          if (customFee === null && typeof sData.feeAmount === "string") {
            customFee = parseFloat(sData.feeAmount);
          }

          let duePaise = 0;
          const structure = structures[classKey];
          if (customFee !== null && !isNaN(customFee)) {
            duePaise = Math.round(customFee * 100);
          } else if (structure) {
            duePaise = typeof structure.totalAnnualFeePaise === "number"
              ? structure.totalAnnualFeePaise
              : Math.round((structure.totalAnnualFee || 0) * 100);
          }

          const collectedPaise = totalPaidPaise < duePaise ? totalPaidPaise : duePaise;
          const pendingPaise = Math.max(0, duePaise - totalPaidPaise);
          let overduePaise = 0;
          let daysOverdue = 0;

          if (pendingPaise > 0 && structure && structure.installments && structure.installments.length > 0) {
            daysOverdue = getDaysOverdueHelper(structure, totalPaidPaise);
            if (daysOverdue > 0) {
              overduePaise = pendingPaise;
            }
          }

          const fullyPaid = duePaise > 0 && totalPaidPaise >= duePaise;

          totalCollectedPaise += collectedPaise;
          totalPendingPaise += pendingPaise;
          totalOverduePaise += overduePaise;

          if (!classStats[classKey]) {
            classStats[classKey] = {
              className,
              studentCount: 0,
              fullyPaid: 0,
              totalCollectedPaise: 0,
              totalDuePaise: 0
            };
          }
          classStats[classKey].studentCount++;
          if (fullyPaid) classStats[classKey].fullyPaid++;
          classStats[classKey].totalCollectedPaise += collectedPaise;
          classStats[classKey].totalDuePaise += duePaise;

          studentBatch.update(studentDoc.ref, {
            totalPaidPaise: totalPaidPaise,
            feeCollectedPaise: collectedPaise,
            feePendingPaise: pendingPaise,
            feeOverduePaise: overduePaise,
            feeDaysOverdue: daysOverdue,
            feeFullyPaid: fullyPaid,
            feeDuePaise: duePaise
          });
          studentBatchCount++;

          if (studentBatchCount >= 400) {
            await studentBatch.commit();
            studentBatchCount = 0;
          }
        }

        if (studentBatchCount > 0) {
          await studentBatch.commit();
        }

        const classBatch = db.batch();
        for (const [ckey, stats] of Object.entries(classStats)) {
          const classRef = db.collection("schools").doc(sid).collection("class_fee_summaries").doc(ckey);
          classBatch.set(classRef, {
            ...stats,
            updatedAt: admin.firestore.FieldValue.serverTimestamp()
          });
        }
        await classBatch.commit();

        const schoolRef = db.collection("schools").doc(sid).collection("summaries").doc("fees");
        await schoolRef.set({
          collectedPaise: totalCollectedPaise,
          pendingPaise: totalPendingPaise,
          overduePaise: totalOverduePaise,
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });

        results.push({ schoolId: sid, studentsProcessed: studentsSnap.size });
      }

      return { ok: true, results };
    } catch (err) {
      logger.error("[backfillFeeSummaries] failed", err);
      throw new HttpsError("internal", err.message);
    }
  }
);




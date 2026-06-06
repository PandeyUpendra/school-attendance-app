"use strict";

/**
 * Authenticated transactional email for password setup / reset.
 *
 * WHY THIS EXISTS
 * Firebase Auth's built-in password emails are sent from
 * `noreply@<project>.firebaseapp.com` over Google's shared infrastructure.
 * Because that domain is not authenticated for you (no SPF/DKIM/DMARC alignment
 * you control), Gmail routes them to spam. This function instead:
 *   1. generates the password-reset / setup link with the Admin SDK, and
 *   2. sends it through SendGrid from a domain YOU have authenticated,
 * so the message passes SPF + DKIM + DMARC and lands in the inbox.
 *
 * IMPORTANT: SendGrid alone does not fix spam — you must complete
 * "Sender Authentication → Authenticate Your Domain" in the SendGrid dashboard
 * (it gives you DNS CNAME records to add). Without that step, mail still lacks
 * DKIM alignment and can be filtered. See README.md.
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret, defineString } = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const sgMail = require("@sendgrid/mail");

admin.initializeApp();

// ── Configuration ───────────────────────────────────────────────────────────
// Secrets (set with: firebase functions:secrets:set SENDGRID_API_KEY)
const SENDGRID_API_KEY = defineSecret("SENDGRID_API_KEY");
// Non-secret config (set in .env or via firebase deploy params).
// MAIL_FROM must be an address on the domain you authenticated in SendGrid.
const MAIL_FROM = defineString("MAIL_FROM", { default: "noreply@example.com" });
const MAIL_FROM_NAME = defineString("MAIL_FROM_NAME", { default: "School App" });

// Roles permitted to send privileged "invite" emails to arbitrary addresses.
const INVITE_ROLES = ["admin", "owner", "ownerPrincipal", "principal", "coordinator"];

const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

/**
 * Callable: sendPasswordEmail({ email, type })
 *   type "invite" → privileged: caller must be a signed-in management user.
 *   type "reset"  → self-service: open (mirrors Firebase's own reset email),
 *                   but never reveals whether the account exists.
 */
exports.sendPasswordEmail = onCall(
  { secrets: [SENDGRID_API_KEY], cors: true, region: "us-central1" },
  async (request) => {
    const email = String(request.data && request.data.email ? request.data.email : "")
      .trim()
      .toLowerCase();
    const type = request.data && request.data.type === "invite" ? "invite" : "reset";

    if (!EMAIL_RE.test(email)) {
      throw new HttpsError("invalid-argument", "A valid email address is required.");
    }

    // Privileged path: only authenticated management users may invite others.
    if (type === "invite") {
      if (!request.auth || !request.auth.token || !request.auth.token.email) {
        throw new HttpsError("unauthenticated", "Sign in required to send invites.");
      }
      const callerEmail = String(request.auth.token.email).toLowerCase();
      const snap = await admin
        .firestore()
        .collection("allowed_users")
        .doc(callerEmail)
        .get();
      const role = snap.exists ? snap.get("role") : null;
      if (!INVITE_ROLES.includes(role)) {
        throw new HttpsError("permission-denied", "You are not allowed to invite users.");
      }
    }

    // Self-service reset: only send for emails registered in the school system,
    // but NEVER reveal whether the email exists — returning registered:false
    // turned this into an account-enumeration oracle that leaks which families
    // are enrolled (#19, #84). Unregistered emails get the same neutral { ok }
    // response as registered ones; the UI shows "if an account exists…".
    if (type === "reset") {
      const reg = await admin.firestore().collection("allowed_users").doc(email).get();
      if (!reg.exists) {
        return { ok: true };
      }
    }

    // Generate the password setup/reset link via the Admin SDK.
    let link;
    try {
      link = await admin.auth().generatePasswordResetLink(email);
    } catch (err) {
      // The account is registered in allowed_users but has no Firebase Auth
      // login yet (rare — provisioning gap). Report it as registered so the UI
      // is truthful; an admin can re-send the invite to create the login.
      if (err && err.code === "auth/user-not-found") {
        logger.info("sendPasswordEmail: registered but no auth account", { type });
        return { ok: true };
      }
      logger.error("generatePasswordResetLink failed", err);
      throw new HttpsError("internal", "Could not generate the password link.");
    }

    // Send via SendGrid from the authenticated domain.
    sgMail.setApiKey(SENDGRID_API_KEY.value());
    const appName = MAIL_FROM_NAME.value();
    const subject =
      type === "invite"
        ? `You're invited to ${appName} — set your password`
        : `Reset your ${appName} password`;
    const intro =
      type === "invite"
        ? `An account has been created for you on ${appName}. Tap the button below to set your password and sign in.`
        : `We received a request to reset your ${appName} password. Tap the button below to choose a new one.`;

    const msg = {
      to: email,
      from: { email: MAIL_FROM.value(), name: appName },
      subject,
      // Plain-text part matters for deliverability — keep it real and link-light.
      text:
        `${intro}\n\n${link}\n\n` +
        `If you didn't expect this email, you can safely ignore it.\n\n— ${appName}`,
      html: renderHtml({ appName, intro, link, type }),
      // Tracking pixels/click-rewriting hurt deliverability for low-volume senders.
      trackingSettings: {
        clickTracking: { enable: false, enableText: false },
        openTracking: { enable: false },
      },
      mailSettings: { bypassListManagement: { enable: true } },
    };

    try {
      await sgMail.send(msg);
    } catch (err) {
      logger.error("SendGrid send failed", err && err.response ? err.response.body : err);
      throw new HttpsError("internal", "Could not send the email.");
    }

    return { ok: true };
  }
);

// Roles permitted to delete accounts.
const DELETE_ROLES = ["admin", "owner", "ownerPrincipal", "principal", "coordinator"];

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
    const callerRole = callerSnap.exists ? callerSnap.get("role") : null;
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
      for (const doc of members.docs) {
        await deleteAuth(doc.id);
        await doc.ref.delete();
      }
      // Wipe the entire school subtree (students, teachers, attendance, fees, …).
      await db.recursiveDelete(db.collection("schools").doc(targetSchoolId));
      // Best-effort Storage cleanup (gallery photos, etc.).
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

function renderHtml({ appName, intro, link, type }) {
  const cta = type === "invite" ? "Set your password" : "Reset password";
  return `<!doctype html>
<html>
  <body style="margin:0;padding:0;background:#F3EAFB;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="padding:24px 0;">
      <tr><td align="center">
        <table role="presentation" width="480" cellpadding="0" cellspacing="0"
               style="background:#ffffff;border-radius:16px;overflow:hidden;max-width:480px;width:100%;">
          <tr><td style="background:#6A1B9A;padding:20px 28px;">
            <span style="color:#ffffff;font-size:18px;font-weight:700;">${escapeHtml(appName)}</span>
          </td></tr>
          <tr><td style="padding:28px;color:#333;font-size:15px;line-height:1.55;">
            <p style="margin:0 0 20px;">${escapeHtml(intro)}</p>
            <p style="margin:0 0 28px;">
              <a href="${link}"
                 style="display:inline-block;background:#6A1B9A;color:#ffffff;text-decoration:none;
                        font-weight:600;font-size:15px;padding:13px 26px;border-radius:10px;">
                ${cta}
              </a>
            </p>
            <p style="margin:0 0 6px;color:#777;font-size:13px;">
              If the button doesn't work, copy and paste this link:
            </p>
            <p style="margin:0 0 24px;word-break:break-all;font-size:12px;color:#6A1B9A;">${link}</p>
            <p style="margin:0;color:#999;font-size:12px;">
              If you didn't expect this email, you can safely ignore it.
            </p>
          </td></tr>
          <tr><td style="padding:16px 28px;background:#FAF5FE;color:#999;font-size:11px;">
            © ${new Date().getFullYear()} ${escapeHtml(appName)}
          </td></tr>
        </table>
      </td></tr>
    </table>
  </body>
</html>`;
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

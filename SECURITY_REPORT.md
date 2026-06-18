# Security Audit Report: School Attendance Application (`school_app`)

This document presents the findings from a comprehensive security audit of the `school_app` codebase. The audit covers Firestore Security Rules (`firestore.rules`), Cloud Storage Rules (`storage.rules`), Cloud Functions (`functions/index.js`), Flutter client-side logic, authentication mechanisms, data leakage risks, hardcoded secrets, role escalation paths, and input validations.

---

## Executive Summary

While the `school_app` codebase features tenant-isolated database access and offline synchronization, several critical and high-severity security vulnerabilities were identified. These issues could compromise tenant isolation boundaries, allow database spoofing, permit unauthorized access by suspended users, expose API keys/SMTP credentials, or cause Denial of Service (DoS) across AI operations.

The audit has identified **22 distinct security findings**, categorized as follows:
* **Critical**: 4 findings (Immediate remediation required)
* **High**: 9 findings (Remediation required before next release)
* **Medium**: 6 findings (Remediation recommended)
* **Low**: 3 findings (Best practices / hygiene improvements)

---

## Summary of Findings

| ID | Finding Title | Severity | Area | Status |
| :--- | :--- | :--- | :--- | :--- |
| **SEC-01** | [ReferenceError in `callGemini` Cloud Function](#sec-01-referenceerror-in-callgemini-cloud-function) | 🔴 **Critical** | Unsafe API Calls / DoS | Open |
| **SEC-02** | [Complete Bypass of Account Suspension / Disabling](#sec-02-complete-bypass-of-account-suspension--disabling) | 🔴 **Critical** | Firestore Rules / Access Control | Open |
| **SEC-03** | [Self-Reactivation of Suspended Accounts](#sec-03-self-reactivation-of-suspended-accounts) | 🔴 **Critical** | Role Escalation | Open |
| **SEC-04** | [Privilege Escalation via Pre-Approved Leave Applications](#sec-04-privilege-escalation-via-pre-approved-leave-applications) | 🟠 **High** | Role Escalation | Open |
| **SEC-05** | [Lack of Write/Delete Restrictions on Payment Records](#sec-05-lack-of-writedelete-restrictions-on-payment-records) | 🟠 **High** | Firestore Rules / Audit Integrity | Open |
| **SEC-06** | [Gemini API Key Stored in Publicly Readable Settings](#sec-06-gemini-api-key-stored-in-publicly-readable-settings) | 🟠 **High** | Data Leakage / Secrets | Open |
| **SEC-07** | [SMTP Cleartext Credentials Accessible to Lower Management](#sec-07-smtp-cleartext-credentials-accessible-to-lower-management) | 🟠 **High** | Data Leakage / Secrets | Open |
| **SEC-08** | [Client-Side Deletions Bypass in allowed_users (Owner Lockout)](#sec-08-client-side-deletions-bypass-in-allowed_users-owner-lockout) | 🟠 **High** | Firestore Rules / DoS | Open |
| **SEC-09** | [Root-Admin Privilege Compromise via Hardcoded Email Addresses](#sec-09-root-admin-privilege-compromise-via-hardcoded-email-addresses) | 🟠 **High** | Hardcoded Secrets / Role Escalation | Open |
| **SEC-10** | [Bypass of Cloud Function Audit Safeguards via Direct Client Creation](#sec-10-bypass-of-cloud-function-audit-safeguards-via-direct-client-creation) | 🟠 **High** | Firestore Rules / Audit Integrity | Open |
| **SEC-11** | [Audit Log Poisoning via Direct Client Writes](#sec-11-audit-log-poisoning-via-direct-client-writes) | 🟠 **High** | Firestore Rules / Audit Integrity | Open |
| **SEC-12** | [Missing Firebase App Check Integration](#sec-12-missing-firebase-app-check-integration) | 🟠 **High** | Authentication Weakness | Open |
| **SEC-13** | [Audit Log Spoofing in `createAllowedUser` Cloud Function](#sec-13-audit-log-spoofing-in-createalloweduser-cloud-function) | 🟠 **High** | Unsafe API Calls / Audit Integrity | Open |
| **SEC-14** | [Invite Code Enumeration / Brute-Force in Guardian Registration](#sec-14-invite-code-enumeration--brute-force-in-guardian-registration) | 🟡 **Medium** | Authentication Weakness | Open |
| **SEC-15** | [Permissive Write Access to Main Settings for Coordinators](#sec-15-permissive-write-access-to-main-settings-for-coordinators) | 🟡 **Medium** | Firestore Rules / Access Control | Open |
| **SEC-16** | [Notification Impersonation / Phishing Vector](#sec-16-notification-impersonation--phishing-vector) | 🟡 **Medium** | Missing Input Validation | Open |
| **SEC-17** | [Suspended/Fired Staff Retain Access Offline (Session Persistence)](#sec-17-suspendedfired-staff-retain-access-offline-session-persistence) | 🟡 **Medium** | Authentication Weakness | Open |
| **SEC-18** | [Phone-OTP Guardians Session Validation Drift on Child Removal](#sec-18-phone-otp-guardians-session-validation-drift-on-child-removal) | 🟡 **Medium** | Authentication Weakness | Open |
| **SEC-19** | [Device Clock Dependency for Session Timeouts](#sec-19-device-clock-dependency-for-session-timeouts) | 🟡 **Medium** | Authentication Weakness | Open |
| **SEC-20** | [Unsanitized URL Launcher Injection via Phone/WhatsApp Fields](#sec-20-unsanitized-url-launcher-injection-via-phonewhatsapp-fields) | 🔵 **Low** | Unsafe API Calls | Open |
| **SEC-21** | [Report-Card Division-by-Zero Crash Vector](#sec-21-report-card-division-by-zero-crash-vector) | 🔵 **Low** | Missing Input Validation / DoS | Open |
| **SEC-22** | [Impersonation & Lack of Input Validation in CRM Leads](#sec-22-impersonation--lack-of-input-validation-in-crm-leads) | 🔵 **Low** | Missing Input Validation | Open |

---

## Detailed Findings & Remediation Plans

### SEC-01: ReferenceError in `callGemini` Cloud Function
* **Severity:** 🔴 **Critical**
* **Area:** Unsafe API Calls / DoS
* **Vulnerable Files:** 
  * [functions/index.js](file:///Users/upendrapandey/school_app/functions/index.js#L2980)
* **Description:** 
  In the `callGemini` Cloud Function, the code attempts to fetch the caller's `allowed_users` document on line 2980:
  ```javascript
  const callerSnap = await db.collection("allowed_users").doc(callerEmail).get();
  ```
  However, the Firestore database instance variable `db` is not declared or initialized until line 2993:
  ```javascript
  const db = admin.firestore();
  ```
* **Threat Vector:** 
  Every call to `callGemini` encounters a `ReferenceError: db is not defined` and crashes. This creates a Denial of Service (DoS) for all AI-enabled features (e.g., AI report card remark generation, homework checking, risk predictions).
* **Impact:** 
  Complete breakdown of the server-side AI integration layer.
* **Remediation Plan:**
  Move the database definition to the top of the callable function handler before any database queries.

#### Code Fix:
**In `functions/index.js`:**
```diff
 exports.callGemini = onCall(
   { cors: true, region: "asia-south1", enforceAppCheck: false },
   async (request) => {
     // 1. Authenticate user
     if (!request.auth || !request.auth.token || !request.auth.token.email) {
       throw new HttpsError("unauthenticated", "Sign in required.");
     }
 
+    const db = admin.firestore();
     const callerEmail = request.auth.token.email.toLowerCase();
     const callerSnap = await db.collection("allowed_users").doc(callerEmail).get();
     const callerSchoolId = callerSnap.exists ? callerSnap.get("schoolId") : request.auth.token.schoolId;
     if (!callerSchoolId) {
       throw new HttpsError("permission-denied", "User is not associated with any school.");
     }
 
     const prompt = request.data && request.data.prompt;
     const systemInstruction = request.data && request.data.systemInstruction;
     if (!prompt || typeof prompt !== "string") {
       throw new HttpsError("invalid-argument", "A valid prompt string is required.");
     }
 
     // 2. Fetch the Gemini API key for this school
-    const db = admin.firestore();
     let apiKey = null;
```

---

### SEC-02: Complete Bypass of Account Suspension / Disabling
* **Severity:** 🔴 **Critical**
* **Area:** Firestore Rules / Access Control
* **Vulnerable Files:** 
  * [functions/index.js](file:///Users/upendrapandey/school_app/functions/index.js#L117)
  * [firestore.rules](file:///Users/upendrapandey/school_app/firestore.rules#L130)
* **Description:** 
  When a school administrator suspends or disables an account, the user's status in their `allowed_users` document transitions to `'suspended'` or `'disabled'`.
  However, this status check is only enforced on the client side (e.g. during splash screen checks or UI flows). 
  1. The Cloud Function trigger `syncUserClaims` still assigns custom claims (role, schoolId) to suspended users upon document updates.
  2. Firestore security rules do not verify the `status` field in `allowed_users` when validating permissions.
  3. Sensitive Cloud Functions (like `deleteStudent`, `createAllowedUser`, etc.) do not verify the caller's status before execution.
* **Threat Vector:** 
  A suspended user bypasses client-side UI constraints (e.g. by using direct REST API requests or custom scripts with their current ID token). Since their custom claims are intact and rules do not verify status, they can continue to query and mutate Firestore or invoke admin Cloud Functions.
* **Impact:** 
  Complete failure of the suspension mechanism, allowing terminated or rogue employees to steal or alter school data.
* **Remediation Plan:**
  1. Update `syncUserClaims` to wipe or omit custom claims if the user is suspended or disabled.
  2. Update the `getUserData()` helper in `firestore.rules` to return `null` if the user's status is not `'active'`, causing rules to fail closed.
  3. Validate caller status in Cloud Functions.

#### Code Fix:
**In `functions/index.js` (`syncUserClaims`):**
```diff
       const d = after.data() || {};
 
+      // Revoke claims immediately if account is not active
+      if (d.status === "suspended" || d.status === "disabled") {
+        await admin.auth().setCustomUserClaims(user.uid, null);
+        return;
+      }
+
        // Auto-backfill studentLinks, studentIds, and classIds for guardians if missing or outdated
```

**In `firestore.rules` (`getUserData`):**
```diff
     function getUserData() {
-      return get(/databases/$(database)/documents/allowed_users/$(request.auth.token.email.lower())).data;
+      let docPath = /databases/$(database)/documents/allowed_users/$(request.auth.token.email.lower());
+      return exists(docPath) && get(docPath).data.status == 'active' ? get(docPath).data : null;
     }
```

---

### SEC-03: Self-Reactivation of Suspended Accounts
* **Severity:** 🔴 **Critical**
* **Area:** Role Escalation
* **Vulnerable Files:** 
  * [firestore.rules](file:///Users/upendrapandey/school_app/firestore.rules#L629)
* **Description:** 
  The Firestore update rule for `allowed_users` allows a user to update their own document's status:
  ```javascript
  (userEmail() == email &&
   request.resource.data.role == resource.data.role &&
   request.resource.data.diff(resource.data).affectedKeys().hasOnly(['schoolId', 'status']) && ...)
  ```
  This is designed to allow new users in `'pending'` status to set their status to `'active'` upon first login. However, the rule does not check the *prior* status of the document.
* **Threat Vector:** 
  A suspended or disabled user issues a direct Firestore update request on their own `allowed_users` document, changing `status` from `'suspended'` to `'active'`.
* **Impact:** 
  Suspended users can reactivate their own accounts without administrative consent, restoring their database permissions.
* **Remediation Plan:**
  Restrict status self-updates so they can only transition from `'pending'` to `'active'`.

#### Code Fix:
**In `firestore.rules`:**
```diff
       allow update: if isRootAdmin() || (isSignedIn() && (
         // Self update: status can transition to 'active', schoolId can switch (other fields require Cloud Functions)
         (userEmail() == email &&
          request.resource.data.role == resource.data.role &&
+         resource.data.status == 'pending' &&
+         request.resource.data.status == 'active' &&
          request.resource.data.diff(resource.data).affectedKeys().hasOnly(['schoolId', 'status']) &&
          (request.resource.data.schoolId == resource.data.schoolId || 
           ('schoolIds' in resource.data && request.resource.data.schoolId in resource.data.schoolIds))) ||
```

---

### SEC-04: Privilege Escalation via Pre-Approved Leave Applications
* **Severity:** 🟠 **High**
* **Area:** Role Escalation
* **Vulnerable Files:** 
  * [firestore.rules](file:///Users/upendrapandey/school_app/firestore.rules#L1133-L1144)
* **Description:** 
  The `leave_applications` collection rules govern how teachers and guardians request leaves. While the `update` rule correctly gates status changes, the `create` rule does not enforce that the status of newly created leave applications must be `'pending'`.
* **Threat Vector:** 
  A teacher or guardian creates a leave application document directly in Firestore with `status` set to `'approved'`.
* **Impact:** 
  The user bypasses the coordinator or principal review workflow entirely. The application immediately shows as approved on the dashboards.
* **Remediation Plan:**
  Enforce that the `status` field must equal `'pending'` on creation.

#### Code Fix:
**In `firestore.rules`:**
```diff
       // No impersonation: teacherId must equal the calling user's teacherId, or guardian matches student info.
       allow create: if isSignedIn() && inSchool(sid) && (
         (isAnyTeacher()
           && 'teacherId' in request.resource.data
           && request.resource.data.teacherId == userTeacherId()
           && 'teacherEmail' in request.resource.data
           && request.resource.data.teacherEmail.lower() == userEmail()
+          && 'status' in request.resource.data
+          && request.resource.data.status == 'pending') ||
         (isRole('guardian')
           && 'applicantType' in request.resource.data && request.resource.data.applicantType == 'guardian'
           && 'studentClass' in request.resource.data && request.resource.data.studentClass == userStudentClass()
           && 'studentRoll' in request.resource.data && request.resource.data.studentRoll == userStudentRoll()
-          && 'studentSection' in request.resource.data && request.resource.data.studentSection == userStudentSection())
+          && 'studentSection' in request.resource.data && request.resource.data.studentSection == userStudentSection()
+          && 'status' in request.resource.data
+          && request.resource.data.status == 'pending')
       );
```

---

### SEC-05: Lack of Write/Delete Restrictions on Payment Records
* **Severity:** 🟠 **High**
* **Area:** Firestore Rules / Audit Integrity
* **Vulnerable Files:** 
  * [firestore.rules](file:///Users/upendrapandey/school_app/firestore.rules#L1316-L1329)
* **Description:** 
  The rules for `/schools/{sid}/payments/{paymentId}` use general `allow write: if isFinanceAdmin()`. The `write` helper implicitly includes `update` and `delete` permissions.
  According to business guidelines, fee payments must be immutable; they can only be *reversed* (using a `reversed` flag) and never deleted.
* **Threat Vector:** 
  A compromised finance admin (or principal/owner) bypasses client-side reversal logic and directly issues a Firestore `delete` or `update` to alter/remove a transaction record.
* **Impact:** 
  Irreversible loss of financial audit trails, making financial reconciliation, fraud detection, and auditing impossible.
* **Remediation Plan:**
  1. Restrict deletion entirely (`allow delete: if false`).
  2. Restrict updates to only reversing-related fields.

#### Code Fix:
**In `firestore.rules`:**
```diff
     match /schools/{sid}/payments/{paymentId} {
       allow read: if isSignedIn() && inSchool(sid) && (
         ...
       );
-      allow write: if isSignedIn() && inSchool(sid) && isFinanceAdmin();
+      allow create: if isSignedIn() && inSchool(sid) && isFinanceAdmin();
+      allow update: if isSignedIn() && inSchool(sid) && isFinanceAdmin()
+        && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['reversed', 'reversedReason', 'reversedAt', 'reversedBy']);
+      allow delete: if false;
     }
```

---

### SEC-06: Gemini API Key Stored in Publicly Readable Settings
* **Severity:** 🟠 **High**
* **Area:** Data Leakage / Secrets
* **Vulnerable Files:** 
  * [firestore.rules](file:///Users/upendrapandey/school_app/firestore.rules#L1601-L1610)
  * [lib/services/ai_service.dart](file:///Users/upendrapandey/school_app/lib/services/ai_service.dart)
* **Description:** 
  The application originally stored and read the Gemini API key from the document `/schools/{sid}/settings/main`. Any signed-in user in the school (including students/parents) could read all setting documents except `smtp`.
* **Threat Vector:** 
  A student or parent extracts the cleartext API key from the `main` document.
* **Impact:** 
  API key theft, leading to massive financial charges, quota exhaustion, or service suspension.
* **Remediation Plan:**
  Move the API key into a dedicated `keys` document and restrict read access to management roles. Keep the server-side Cloud Function (`callGemini`) as the single entry point.

#### Code Fix:
**In `firestore.rules`:**
```diff
     match /schools/{sid}/settings/{docId} {
-      allow read:  if isSignedIn() && inSchool(sid) && (docId != 'smtp' || isManagement());
+      allow read:  if isSignedIn() && inSchool(sid) && (
+        (docId != 'smtp' && docId != 'keys') || isManagement()
+      );
```

---

### SEC-07: SMTP Cleartext Credentials Accessible to Lower Management
* **Severity:** 🟠 **High**
* **Area:** Data Leakage / Secrets
* **Vulnerable Files:** 
  * [firestore.rules](file:///Users/upendrapandey/school_app/firestore.rules#L1601-L1610)
* **Description:** 
  Cleartext SMTP server credentials (host, username, password) are stored in the `/schools/{sid}/settings/smtp` document. The read rules permit any member of `isManagement()` (which includes coordinators and principals) to read this document.
* **Threat Vector:** 
  Coordinators or principals query the `smtp` settings document and extract the cleartext SMTP password.
* **Impact:** 
  Compromised coordinator accounts can abuse the credentials to send phishing emails or access the school's mail server.
* **Remediation Plan:**
  Restrict the `smtp` settings document read permission to `isStrictAdmin()` (admin and owner) only.

#### Code Fix:
**In `firestore.rules`:**
```diff
     match /schools/{sid}/settings/{docId} {
       allow read:  if isSignedIn() && inSchool(sid) && (
-        (docId != 'smtp' && docId != 'keys') || isManagement()
+        (docId != 'smtp' || isStrictAdmin()) &&
+        (docId != 'keys' || isManagement())
       );
```

---

### SEC-08: Client-Side Deletions Bypass in allowed_users (Owner Lockout)
* **Severity:** 🟠 **High**
* **Area:** Firestore Rules / DoS
* **Vulnerable Files:** 
  * [firestore.rules](file:///Users/upendrapandey/school_app/firestore.rules#L656-L660)
* **Description:** 
  The client-side delete rule for `/allowed_users/{email}` allowed school admins to delete any user in their school without verifying role hierarchy. Deleting an owner's document triggers `syncUserClaims` which clears their claims and locks them out.
* **Threat Vector:** 
  A rogue local admin deletes the school owner's metadata document.
* **Impact:** 
  Denial of Service and owner lockout, requiring root admin database intervention to restore.
* **Remediation Plan:**
  Enforce rank-checking. Local admins must not be able to delete roles equal to or higher than them.

#### Code Fix:
**In `firestore.rules`:**
```diff
       allow delete: if isRootAdmin() || (isSignedIn() && (
         // Management delete in same school (with strict rank checking)
-        (isStrictAdmin() && resource.data.schoolId == userSchoolId()) ||
+        (isStrictAdmin() && resource.data.schoolId == userSchoolId() && !(resource.data.role in ['admin', 'owner', 'ownerPrincipal'])) ||
         (isRole('principal') && resource.data.schoolId == userSchoolId() && resource.data.role in ['coordinator', 'teacher', 'subjectTeacher', 'guardian']) ||
         (isRole('coordinator') && resource.data.schoolId == userSchoolId() && resource.data.role in ['teacher', 'subjectTeacher', 'guardian'])
       ));
```

---

### SEC-09: Root-Admin Privilege Compromise via Hardcoded Email Addresses
* **Severity:** 🟠 **High**
* **Area:** Hardcoded Secrets / Role Escalation
* **Vulnerable Files:** 
  * [firestore.rules](file:///Users/upendrapandey/school_app/firestore.rules#L417)
  * [storage.rules](file:///Users/upendrapandey/school_app/storage.rules#L37)
  * [functions/index.js](file:///Users/upendrapandey/school_app/functions/index.js#L291)
  * [lib/services/auth_service.dart](file:///Users/upendrapandey/school_app/lib/services/auth_service.dart#L77)
* **Description:** 
  System root-admin functions are gated on hardcoded emails (`mandvishal@gmail.com` and `admin@schoolapp.org`) inside Firestore rules, storage rules, server functions, and client auth services. 
* **Threat Vector:** 
  A compromise of either email yields administrative control over all tenants. Additionally, these root admin accounts cannot be rotated or revoked without a full codebase rebuild and redeploy.
* **Impact:** 
  Complete takeover of multi-tenant boundaries.
* **Remediation Plan:**
  Migrate root-admin authorization from hardcoded strings to custom user claims (e.g. `rootAdmin: true`) checked dynamically, or verify membership in a dedicated system admin collection that is strictly locked down.

---

### SEC-10: Bypass of Cloud Function Audit Safeguards via Direct Client Creation
* **Severity:** 🟠 **High**
* **Area:** Firestore Rules / Audit Integrity
* **Vulnerable Files:** 
  * [firestore.rules](file:///Users/upendrapandey/school_app/firestore.rules#L614-L627)
* **Description:** 
  The `createAllowedUser` Cloud Function verifies the creator's metadata to prevent audit log spoofing. However, the Firestore rules still allow direct client-side creation of `allowed_users` documents by management.
* **Threat Vector:** 
  A coordinator or principal bypasses the Cloud Function and writes directly to `/allowed_users/{email}`, spoofing the `createdByEmail` or `createdByRole` fields.
* **Impact:** 
  Tampering with the audit trail of account provisioning.
* **Remediation Plan:**
  Block direct client-side creation of allowed users entirely, forcing all provisioning to go through the hardened `createAllowedUser` Cloud Function.

#### Code Fix:
**In `firestore.rules`:**
```diff
     match /allowed_users/{email} {
       ...
-      allow create: if isRootAdmin() || (isSignedIn() && (
-        // Management can provision users in their own school
-        (isStrictAdmin() &&
-         request.resource.data.schoolId == userSchoolId() &&
-         request.resource.data.role in ['principal', 'coordinator', 'teacher', 'subjectTeacher', 'guardian']) ||
-        
-        (isRole('principal') &&
-         request.resource.data.schoolId == userSchoolId() &&
-         request.resource.data.role in ['coordinator', 'teacher', 'subjectTeacher', 'guardian']) ||
-
-        (isRole('coordinator') &&
-         request.resource.data.schoolId == userSchoolId() &&
-         request.resource.data.role in ['teacher', 'subjectTeacher', 'guardian'])
-      ));
+      allow create: if isRootAdmin(); // Enforced through createAllowedUser function
```

---

### SEC-11: Audit Log Poisoning via Direct Client Writes
* **Severity:** 🟠 **High**
* **Area:** Firestore Rules / Audit Integrity
* **Vulnerable Files:** 
  * [firestore.rules](file:///Users/upendrapandey/school_app/firestore.rules)
* **Description:** 
  The `audit_logs` collection permits clients to perform direct `create` writes. Although the rule binds `actorUid` to the caller's auth UID, it does not validate fields like `action`, `entity`, `before`, or `after`.
* **Threat Vector:** 
  A compromised school member scripts fake audit logs to cover up illicit actions, creating false records of changes to grades, fees, or permissions.
* **Impact:** 
  Destruction of audit log trustworthiness.
* **Remediation Plan:**
  Remove direct client-side write access to `audit_logs` collection. Emit all audit entries server-side via Cloud Functions or Admin SDK triggers.

#### Code Fix:
**In `firestore.rules`:**
```diff
     match /schools/{sid}/audit_logs/{logId} {
       allow read: if isSignedIn() && inSchool(sid) && isManagement();
-      allow create: if isSignedIn() && inSchool(sid) && request.resource.data.actorUid == request.auth.uid;
+      allow create: if false; // Only written server-side
       allow update, delete: if false;
     }
```

---

### SEC-12: Missing Firebase App Check Integration
* **Severity:** 🟠 **High**
* **Area:** Authentication Weakness
* **Vulnerable Files:** 
  * [pubspec.yaml](file:///Users/upendrapandey/school_app/pubspec.yaml)
  * [lib/main.dart](file:///Users/upendrapandey/school_app/lib/main.dart)
* **Description:** 
  The application does not integrate Firebase App Check. No app attestation provider (Device Check, Play Integrity, reCAPTCHA Enterprise) is configured.
* **Threat Vector:** 
  Attackers or curious students reverse-engineer the Firestore rules and execute automated scrapers directly using raw API credentials, extracting personal details of students/staff or spamming functions.
* **Impact:** 
  Massive scale data harvesting and endpoint abuse.
* **Remediation Plan:**
  Add the `firebase_app_check` package to `pubspec.yaml`, initialize it in `lib/main.dart`, and enforce App Check verification in the Firebase Console and Cloud Functions.

---

### SEC-13: Audit Log Spoofing in `createAllowedUser` Cloud Function
* **Severity:** 🟠 **High**
* **Area:** Unsafe API Calls / Audit Integrity
* **Vulnerable Files:** 
  * [functions/index.js](file:///Users/upendrapandey/school_app/functions/index.js#L542-L543)
* **Description:** 
  The `createAllowedUser` Cloud Function prioritized client-supplied values for creator metadata if they were passed in the request body.
* **Threat Vector:** 
  A caller passes `createdByEmail: 'principal@school.test'` or `createdByRole: 'owner'` in the request payload to falsify the audit logs.
* **Impact:** 
  Falsified audit trail for account provisioning.
* **Remediation Plan:**
  Always populate log metadata fields from verified context token claims.

#### Code Fix:
**In `functions/index.js`:**
```diff
     const data = {
       role: role,
       email: email,
       status: "pending",
       schoolId: schoolId,
       createdAt: admin.firestore.FieldValue.serverTimestamp(),
       name: name || "",
-      createdByEmail: request.data.createdByEmail ? String(request.data.createdByEmail).trim().toLowerCase() : callerEmail,
-      createdByRole: request.data.createdByRole ? String(request.data.createdByRole).trim() : (callerRole || ""),
+      createdByEmail: callerEmail,
+      createdByRole: callerRole || "",
     };
```

---

### SEC-14: Invite Code Enumeration / Brute-Force in Guardian Registration
* **Severity:** 🟡 **Medium**
* **Area:** Authentication Weakness
* **Vulnerable Files:** 
  * [functions/index.js](file:///Users/upendrapandey/school_app/functions/index.js#L2775-L2880)
* **Description:** 
  The Cloud Function `registerGuardianWithInviteCode` registers a guardian using a 6-character alphanumeric code (`parentInviteCode`). Since the function has App Check disabled (`enforceAppCheck: false`) and does not implement rate limiting, it is vulnerable to automated brute-force attacks.
* **Threat Vector:** 
  An attacker runs a script calling `registerGuardianWithInviteCode` repeatedly, brute-forcing the 6-character codes.
* **Impact:** 
  Gaining unauthorized access to random students' dashboards, exposing grades, attendance, and fee history.
* **Remediation Plan:**
  Enable App Check on this function (`enforceAppCheck: true`) and implement rate-limiting or backoff logic.

---

### SEC-15: Permissive Write Access to Main Settings for Coordinators
* **Severity:** 🟡 **Medium**
* **Area:** Firestore Rules / Access Control
* **Vulnerable Files:** 
  * [firestore.rules](file:///Users/upendrapandey/school_app/firestore.rules#L1601-L1610)
* **Description:** 
  The write permission rule for `/schools/{sid}/settings/{docId}` allows any user in `isManagement()` to update settings documents. This includes coordinators and class teachers who are not supposed to modify core school properties.
* **Threat Vector:** 
  A coordinator account overwrites the school's SMTP settings or Gemini key, causing functional failure.
* **Impact:** 
  Unauthorized configuration modifications and Denial of Service.
* **Remediation Plan:**
  Restrict settings write operations to `isStrictAdmin()` (admin and owner) only.

#### Code Fix:
**In `firestore.rules`:**
```diff
     match /schools/{sid}/settings/{docId} {
       ...
-      allow write: if isSignedIn() && inSchool(sid) && isManagement();
+      allow write: if isSignedIn() && inSchool(sid) && isStrictAdmin();
     }
```

---

### SEC-16: Notification Impersonation / Phishing Vector
* **Severity:** 🟡 **Medium**
* **Area:** Missing Input Validation
* **Vulnerable Files:** 
  * [firestore.rules](file:///Users/upendrapandey/school_app/firestore.rules#L1552-L1570)
* **Description:** 
  The rules for creating notifications allow guardians to write leave notifications but do not verify that the sender-related fields match the authenticated parent's email.
* **Threat Vector:** 
  A guardian writes a notification setting `postedBy: 'admin@schoolapp.org'`.
* **Impact:** 
  Phishing and social engineering attacks targeting class teachers.
* **Remediation Plan:**
  Validate that `postedBy` matches the authenticated user's email.

#### Code Fix:
**In `firestore.rules`:**
```diff
        allow create: if isSignedIn() && inSchool(sid) && (
          isManagement() ||
          (isAnyTeacher()
            && 'audience' in request.resource.data
            && teacherMayPostAudience(request.resource.data.audience)
+           && 'postedBy' in request.resource.data
+           && request.resource.data.postedBy.lower() == userEmail()) ||
          (isRole('guardian')
            && 'audience' in request.resource.data
-           && request.resource.data.audience == ('class_teacher:' + userStudentClass()))
+           && request.resource.data.audience == ('class_teacher:' + userStudentClass())
+           && 'postedBy' in request.resource.data
+           && request.resource.data.postedBy.lower() == userEmail())
        );
```

---

### SEC-17: Suspended/Fired Staff Retain Access Offline (Session Persistence)
* **Severity:** 🟡 **Medium**
* **Area:** Authentication Weakness
* **Vulnerable Files:** 
  * [lib/main.dart](file:///Users/upendrapandey/school_app/lib/main.dart)
  * [lib/services/auth_service.dart](file:///Users/upendrapandey/school_app/lib/services/auth_service.dart)
* **Description:** 
  The application utilizes a splash-gate revalidation flow. If a dismissed/suspended teacher is offline (e.g. airplane mode), the network call to retrieve their `allowed_users` status fails. The application falls back to local cached session data, keeping the user logged in for up to 7 days.
* **Threat Vector:** 
  A terminated teacher goes offline and continues to browse local caches of student records, grades, and contact lists.
* **Impact:** 
  PII exposure and data confidentiality breach.
* **Remediation Plan:**
  Force an online status refresh check regularly, and reduce the offline validation window for high-privilege roles.

---

### SEC-18: Phone-OTP Guardians Session Validation Drift on Child Removal
* **Severity:** 🟡 **Medium**
* **Area:** Authentication Weakness
* **Vulnerable Files:** 
  * [lib/services/auth_service.dart](file:///Users/upendrapandey/school_app/lib/services/auth_service.dart)
* **Description:** 
  Guardians who sign in via Phone-OTP do not get their linked children checked regularly. If a child is removed from the roster, the parent's session remains active on their phone. They see a broken dashboard and can still read historic caches.
* **Threat Vector:** 
  A parent whose child was expelled or transferred keeps access to old databases.
* **Impact:** 
  Unauthorized access to historical school information.
* **Remediation Plan:**
  Periodically refresh student links on app resume.

---

### SEC-19: Device Clock Dependency for Session Timeouts
* **Severity:** 🟡 **Medium**
* **Area:** Authentication Weakness
* **Vulnerable Files:** 
  * [lib/services/auth_service.dart](file:///Users/upendrapandey/school_app/lib/services/auth_service.dart)
* **Description:** 
  The 7-day session timeout validation checks the device's clock.
* **Threat Vector:** 
  A user rolls back their phone's clock to prevent session expiration.
* **Impact:** 
  Bypass of session security controls.
* **Remediation Plan:**
  Validate session expiry using the Firebase ID Token expiration or server-side sync dates.

---

### SEC-20: Unsanitized URL Launcher Injection via Phone/WhatsApp Fields
* **Severity:** 🔵 **Low**
* **Area:** Unsafe API Calls
* **Vulnerable Files:** 
  * client contact widgets utilizing `url_launcher`
* **Description:** 
  The application builds `tel:` and `wa.me` links using raw values stored in phone fields of the database.
* **Threat Vector:** 
  If an administrator inputs a malicious string in a phone number field, the phone launcher executes arbitrary URL paths or injects control commands.
* **Impact:** 
  App crashes or unintended URL redirections.
* **Remediation Plan:**
  Sanitize all phone numbers before building URI strings.

#### Code Fix:
```dart
// Before calling launchUrl, sanitize input
String sanitizePhoneNumber(String rawPhone) {
  return rawPhone.replaceAll(RegExp(r'[^0-9+]'), '');
}
```

---

### SEC-21: Report-Card Division-by-Zero Crash Vector
* **Severity:** 🔵 **Low**
* **Area:** Missing Input Validation / DoS
* **Vulnerable Files:** 
  * `lib/shared/utils/report_card_pdf_builder.dart:345`
* **Description:** 
  The report card PDF builder calculates student mark percentages using the formula:
  ```dart
  double percent = (marks / maxMarks) * 100;
  ```
  If an exam is misconfigured or has no subjects, and `maxMarks` is set to `0`, this results in division by zero.
* **Threat Vector:** 
  Generating report cards for classes with 0 max marks throws an unhandled exception (`Infinity` / `NaN`), crashing the UI.
* **Impact:** 
  Denial of Service of the report card generation screen.
* **Remediation Plan:**
  Add input validation checks ensuring `maxMarks > 0` before calculating percentages.

#### Code Fix:
```dart
double calculatePercentage(double marks, double maxMarks) {
  if (maxMarks <= 0) return 0.0;
  return (marks / maxMarks) * 100;
}
```

---

### SEC-22: Impersonation & Lack of Input Validation in CRM Leads
* **Severity:** 🔵 **Low**
* **Area:** Missing Input Validation
* **Vulnerable Files:** 
  * [firestore.rules](file:///Users/upendrapandey/school_app/firestore.rules#L986-L997)
* **Description:** 
  The rules for the `leads` collection allow guardians to create admission enquiries, but they do not enforce that `createdByEmail` matches the authenticated user's email.
* **Threat Vector:** 
  A user creates a lead document and sets the `createdByEmail` to another user's email address to pollute the records.
* **Impact:** 
  Impersonation and database record pollution.
* **Remediation Plan:**
  Enforce `request.resource.data.createdByEmail.lower() == userEmail()` during creation.

#### Code Fix:
**In `firestore.rules`:**
```diff
       allow create: if isSignedIn() && inSchool(sid) && (
         isManagement() ||
         isAnyTeacher() ||
         (isRole('guardian') && 'createdByEmail' in request.resource.data 
+                            && request.resource.data.createdByEmail.lower() == userEmail())
       );
```

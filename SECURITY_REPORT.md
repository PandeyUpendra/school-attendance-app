# Security Audit Report: School Attendance Application (`school_app`)

This document presents the findings from a comprehensive security audit of the `school_app` codebase. The audit covered Firestore Security Rules (`firestore.rules`), Cloud Functions (`functions/index.js`), Flutter client-side logic, authentication mechanisms, data leakage risks, hardcoded secrets, role escalation paths, and input validations.

---

## Executive Summary

The codebase implements a robust, tenant-isolated architecture. However, several critical and high-severity security vulnerabilities were identified that could compromise tenant boundary integrity, allow database and workflow spoofing, and permit unauthorized access by suspended users.

The most critical vulnerabilities are:
1. **ReferenceError in `callGemini` Cloud Function (Critical / DoS)**: A missing database reference definition causes a server-side crash on invocation.
2. **Account Suspension Bypass & Self-Reactivation (Critical)**: Suspended users can bypass UI blocks, retain their Firestore access, and self-reactivate their accounts to `'active'` status directly via client-side writes.
3. **Privilege Escalation in Leave Applications (High)**: Missing creation-time status checks allow teachers and guardians to write pre-approved leave documents directly to the database.
4. **Permissive Writes/Deletions on Financial Records (High)**: Financial admins can directly edit or delete transaction receipts in Firestore, bypassing the immutable audit ledger.

---

## Summary of Findings

| ID | Finding Title | Severity | Area | Status |
| :--- | :--- | :--- | :--- | :--- |
| **SEC-01** | [ReferenceError in `callGemini` Cloud Function](#sec-01-referenceerror-in-callgemini-cloud-function) | **Critical** | Code Correctness / DoS | Open |
| **SEC-02** | [Complete Bypass of Account Suspension / Disabling](#sec-02-complete-bypass-of-account-suspension--disabling) | **Critical** | Privilege Escalation / Access Control | Open |
| **SEC-03** | [Self-Reactivation of Suspended Accounts](#sec-03-self-reactivation-of-suspended-accounts) | **Critical** | Privilege Escalation | Open |
| **SEC-04** | [Privilege Escalation via Pre-Approved Leave Applications](#sec-04-privilege-escalation-via-pre-approved-leave-applications) | **High** | Privilege Escalation / Workflow Bypass | Open |
| **SEC-05** | [Lack of Write/Delete Restrictions on Payment Records](#sec-05-lack-of-writedelete-restrictions-on-payment-records) | **High** | Access Control / Audit Integrity | Open |
| **SEC-06** | [Gemini API Key Stored in Publicly Readable Settings](#sec-06-gemini-api-key-stored-in-publicly-readable-settings) | **High** | Data Leakage | Open |
| **SEC-07** | [SMTP Cleartext Credentials Accessible to Lower Management](#sec-07-smtp-cleartext-credentials-accessible-to-lower-management) | **High** | Data Leakage | Open |
| **SEC-08** | [Client-Side Deletions Bypass in allowed_users (Owner Lockout)](#sec-08-client-side-deletions-bypass-in-allowed_users-owner-lockout) | **High** | Denial of Service / Bypass | Open |
| **SEC-09** | [Invite Code Enumeration / Brute-Force in Guardian Registration](#sec-09-invite-code-enumeration--brute-force-in-guardian-registration) | **Medium** | Authentication / Brute-Force | Open |
| **SEC-10** | [Bypass of Cloud Function Audit Safeguards via Direct Client Creation](#sec-10-bypass-of-cloud-function-audit-safeguards-via-direct-client-creation) | **Medium** | Audit Log Integrity | Open |
| **SEC-11** | [Permissive Write Access to Main Settings for Coordinators](#sec-11-permissive-write-access-to-main-settings-for-coordinators) | **Medium** | Access Control | Open |
| **SEC-12** | [Audit Log Spoofing in `createAllowedUser` Cloud Function](#sec-12-audit-log-spoofing-in-createalloweduser-cloud-function) | **Medium** | Audit Log Integrity | Open |
| **SEC-13** | [Notification Impersonation / Phishing Vector](#sec-13-notification-impersonation--phishing-vector) | **Medium** | Input Validation / Impersonation | Open |
| **SEC-14** | [Impersonation & Lack of Input Validation in CRM Leads](#sec-14-impersonation--lack-of-input-validation-in-crm-leads) | **Low** | Input Validation | Open |

---

## Detailed Findings & Remediation Plans

### SEC-01: ReferenceError in `callGemini` Cloud Function
* **Severity:** **Critical**
* **Vulnerable Files:** 
  * [functions/index.js](file:///Users/upendrapandey/school_app/functions/index.js#L2896)
* **Description:** 
  In the `callGemini` Cloud Function, the code attempts to fetch the caller's allowed_users document on line 2896:
  ```javascript
  const callerSnap = await db.collection("allowed_users").doc(callerEmail).get();
  ```
  However, the Firestore database instance `db` is not declared or initialized until line 2909:
  ```javascript
  const db = admin.firestore();
  ```
* **Threat Vector:** 
  Every time a user calls the `callGemini` Cloud Function, it encounters a `ReferenceError: db is not defined` and crashes, causing a denial of service (DoS) for all AI-enabled features (e.g. AI report card remark generation, homework checking, risk predictions).
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
* **Severity:** **Critical**
* **Vulnerable Files:** 
  * [functions/index.js](file:///Users/upendrapandey/school_app/functions/index.js#L108-L190)
  * [firestore.rules](file:///Users/upendrapandey/school_app/firestore.rules#L67-L69)
* **Description:** 
  When a school administrator suspends or disables an account, the user's status in their `allowed_users` document transitions to `'suspended'` or `'disabled'`.
  However, this status check is only enforced on the client side (e.g. during splash checks or UI flows). 
  1. The Cloud Function trigger `syncUserClaims` still assigns custom claims (role, schoolId) to suspended users upon document updates.
  2. Firestore security rules do not check the `status` field in `allowed_users` when validating permissions.
  3. Sensitive Cloud Functions (like `deleteStudent`, `createAllowedUser`, etc.) do not verify the caller's status before execution.
* **Threat Vector:** 
  A suspended user bypasses the UI constraints (e.g. by using direct REST API requests or custom scripts with their current ID token). Since their custom claims are intact and rules do not verify status, they can continue to query and mutate Firestore or invoke admin Cloud Functions.
* **Impact:** 
  Complete failure of the suspension mechanism, allowing rogue or fired employees to steal or alter school data.
* **Remediation Plan:**
  1. Update `syncUserClaims` to wipe or omit custom claims if the user is suspended or disabled.
  2. Update the `getUserData()` helper in `firestore.rules` to return `null` if the user's status is not `'active'`, effectively failing closed.
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
* **Severity:** **Critical**
* **Vulnerable Files:** 
  * [firestore.rules](file:///Users/upendrapandey/school_app/firestore.rules#L629-L636)
* **Description:** 
  The Firestore update rule for `allowed_users` allows a user to update their own document's status:
  ```javascript
  (userEmail() == email &&
   request.resource.data.role == resource.data.role &&
   request.resource.data.diff(resource.data).affectedKeys().hasOnly(['schoolId', 'status']) && ...)
  ```
  This is designed to allow new users in `'pending'` status to set their status to `'active'` upon first login. However, the rule does not check the *prior* status of the document.
* **Threat Vector:** 
  A user who has been suspended or disabled issues a direct Firestore update request on their own `allowed_users` document, changing `status` from `'suspended'` to `'active'`.
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
* **Severity:** **High**
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
* **Severity:** **High**
* **Vulnerable Files:** 
  * [firestore.rules](file:///Users/upendrapandey/school_app/firestore.rules#L1316-L1329)
  * [firestore.rules](file:///Users/upendrapandey/school_app/firestore.rules#L1264-L1283)
* **Description:** 
  The rules for `/schools/{sid}/payments/{paymentId}` and `/schools/{sid}/fee_payments/{classId}` use general `allow write: if isFinanceAdmin()`. The `write` helper implicitly includes `update` and `delete` permissions.
  According to business guidelines, fee payments must be immutable; they can only be *reversed* (using a `reversed` flag) and never deleted.
* **Threat Vector:** 
  A compromised finance admin (or principal/owner) bypasses the client-side reversal logic and directly issues a Firestore `delete` or `update` to alter/remove a transaction record.
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
* **Severity:** **High**
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
* **Severity:** **High**
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
* **Severity:** **High**
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

### SEC-09: Invite Code Enumeration / Brute-Force in Guardian Registration
* **Severity:** **Medium**
* **Vulnerable Files:** 
  * [functions/index.js](file:///Users/upendrapandey/school_app/functions/index.js#L2775-L2880)
* **Description:** 
  The Cloud Function `registerGuardianWithInviteCode` registers a guardian using a 6-character alphanumeric code (`parentInviteCode`). Since the function is publicly invokable, has App Check disabled (`enforceAppCheck: false`), and does not implement rate limiting, it is vulnerable to automated brute-force attacks.
* **Threat Vector:** 
  An attacker runs a script that calls `registerGuardianWithInviteCode` repeatedly, brute-forcing the 6-character codes.
* **Impact:** 
  The attacker gains access to random students' dashboards, exposing grades, attendance, and fee history.
* **Remediation Plan:**
  Enable App Check (`enforceAppCheck: true`) and enforce API rate-limiting.

---

### SEC-10: Bypass of Cloud Function Audit Safeguards via Direct Client Creation
* **Severity:** **Medium**
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

### SEC-11: Permissive Write Access to Main Settings for Coordinators
* **Severity:** **Medium**
* **Vulnerable Files:** 
  * [firestore.rules](file:///Users/upendrapandey/school_app/firestore.rules#L1601-L1610)
* **Description:** 
  The write permission rule for `/schools/{sid}/settings/{docId}` allows any user in `isManagement()` to update setting documents. This includes coordinators and class teachers who are not supposed to modify core school properties.
* **Threat Vector:** 
  A coordinator account overwrites the school's SMTP settings or Gemini key, causing functional failure.
* **Impact:** 
  Unauthorized configuration modifications and Denial of Service.
* **Remediation Plan:**
  Restrict setting write operations to `isStrictAdmin()` (admin and owner) only.

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

### SEC-12: Audit Log Spoofing in `createAllowedUser` Cloud Function
* **Severity:** **Medium**
* **Vulnerable Files:** 
  * [functions/index.js](file:///Users/upendrapandey/school_app/functions/index.js#L542-L543)
* **Description:** 
  The `createAllowedUser` function prioritized client-supplied values for creator metadata if they were passed in the request body.
* **Threat Vector:** 
  A caller passes `createdByEmail: 'principal@school.test'` to forge the log entry.
* **Impact:** 
  Falsified audit trail for account provisioning.
* **Remediation Plan:**
  Always populate metadata fields from verified context token claims.

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

### SEC-13: Notification Impersonation / Phishing Vector
* **Severity:** **Medium**
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

### SEC-14: Impersonation & Lack of Input Validation in CRM Leads
* **Severity:** **Low**
* **Vulnerable Files:** 
  * [firestore.rules](file:///Users/upendrapandey/school_app/firestore.rules#L986-L997)
* **Description:** 
  The rules for the `leads` collection allow guardians to create admission enquiries, but they do not enforce that `createdByEmail` in `request.resource.data` matches the authenticated user's email.
* **Threat Vector:** 
  A user creates a lead document and sets the `createdByEmail` to another user's email address.
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

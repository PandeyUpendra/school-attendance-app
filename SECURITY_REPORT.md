# Security Audit Report: School Attendance Application (`school_app`)

This document presents the findings from a comprehensive security audit of the `school_app` codebase. The audit covered Firestore Security Rules, Cloud Functions (`functions/index.js`), Flutter clientside logic, authentication mechanisms, data leakage risks, hardcoded secrets, role escalation paths, and input validations.

---

## Executive Summary

The codebase implements a robust, tenant-isolated architecture. However, several critical and high-severity security vulnerabilities were identified that could compromise tenant boundary integrity, expose API secrets, and allow database and workflow spoofing.

The most critical vulnerabilities are:
1. **API Key Leakage (High/Critical)**: The Gemini API key is stored in a publicly readable Firestore settings document.
2. **SMTP Credentials Exposure (High)**: Cleartext SMTP credentials (host, username, password) are readable by lower management roles.
3. **Owner Account Lockout/Bypass (High)**: Weak client-side user deletion permissions allow local school admins to delete the school owner's metadata document, triggering a claims wipe.
4. **Notification Impersonation (Medium/High)**: Missing sender-validation checks in notification creation rules enable phishing and impersonation vectors.

---

## Summary of Findings

| ID | Finding Title | Severity | Area | Status |
| :--- | :--- | :--- | :--- | :--- |
| **SEC-01** | [Gemini API Key Stored in Publicly Readable Settings](#sec-01-gemini-api-key-stored-in-publicly-readable-settings) | **High / Critical** | Data Leakage / Access Control | Open |
| **SEC-02** | [SMTP Cleartext Credentials Accessible to Lower Management](#sec-02-smtp-cleartext-credentials-accessible-to-lower-management) | **High** | Data Leakage / Access Control | Open |
| **SEC-03** | [Client-Side Deletions Bypass in allowed_users (Owner Lockout)](#sec-03-client-side-deletions-bypass-in-allowed_users-owner-lockout) | **High** | Privilege Escalation / DoS | Open |
| **SEC-04** | [Notification Impersonation / Phishing Vector](#sec-04-notification-impersonation--phishing-vector) | **Medium / High** | Input Validation / Authentication | Open |
| **SEC-05** | [Audit Log Spoofing in `createAllowedUser` Cloud Function](#sec-05-audit-log-spoofing-in-createalloweduser-cloud-function) | **Medium** | Authentication / Input Validation | Open |
| **SEC-06** | [Permissive Homework Document Writes for Non-Assigned Classes](#sec-06-permissive-homework-document-writes-for-non-assigned-classes) | **Low** | Access Control | Open |
| **SEC-07** | [App Check Disabled Across Cloud Functions](#sec-07-app-check-disabled-across-cloud-functions) | **Medium** | Security Hardening | Open |

---

## Detailed Findings & Remediation Plans

### SEC-01: Gemini API Key Stored in Publicly Readable Settings
* **Severity:** **High / Critical**
* **Vulnerable Files:** 
  * [firestore.rules](file:///Users/upendrapandey/school_app/firestore.rules#L1480-L1490)
  * [lib/services/ai_service.dart](file:///Users/upendrapandey/school_app/lib/services/ai_service.dart#L35-L40)
* **Description:** 
  The Flutter application stores and retrieves the Gemini API key from the document `/schools/{sid}/settings/main`. 
  According to [firestore.rules](file:///Users/upendrapandey/school_app/firestore.rules#L1481):
  ```javascript
  allow read:  if isSignedIn() && inSchool(sid) && (docId != 'smtp' || isManagement());
  ```
  Any signed-in member of the school (including students and parents/guardians) can read any settings document except `'smtp'`. Therefore, the `main` document is publicly readable by all students/parents.
* **Threat Vector:** 
  An authenticated student or guardian client queries `/schools/{sid}/settings/main` and extracts the cleartext `geminiApiKey` field. 
* **Impact:** 
  An attacker can steal the API key to run arbitrary LLM queries, causing massive billing charges, API quota exhaustion, or account suspension.
* **Remediation Plan:**
  1. Move the API key out of the `main` document into a dedicated `keys` or `ai` document (e.g. `/schools/{sid}/settings/keys`).
  2. Update [firestore.rules](file:///Users/upendrapandey/school_app/firestore.rules) to block reading of the `keys` document for non-management.
  3. Update [ai_service.dart](file:///Users/upendrapandey/school_app/lib/services/ai_service.dart) to fetch the key from the new path.

#### Code Fix:
**In `firestore.rules`:**
```diff
     match /schools/{sid}/settings/{docId} {
-      allow read:  if isSignedIn() && inSchool(sid) && (docId != 'smtp' || isManagement());
+      allow read:  if isSignedIn() && inSchool(sid) && (
+        (docId != 'smtp' && docId != 'keys') || isManagement()
+      );
       allow write: if isSignedIn() && inSchool(sid) && isManagement();
```

**In `lib/services/ai_service.dart`:**
```diff
   Future<String?> _getApiKey() async {
     ...
     try {
-      final settingsDoc = await db.collection('schools').doc(sid).collection('settings').doc('main').get();
+      final settingsDoc = await db.collection('schools').doc(sid).collection('settings').doc('keys').get();
       if (settingsDoc.exists) {
         final data = settingsDoc.data();
         if (data != null && data['geminiApiKey'] != null && data['geminiApiKey'].toString().isNotEmpty) {
```

---

### SEC-02: SMTP Cleartext Credentials Accessible to Lower Management
* **Severity:** **High**
* **Vulnerable Files:** 
  * [firestore.rules](file:///Users/upendrapandey/school_app/firestore.rules#L1480-L1490)
* **Description:** 
  Cleartext SMTP server credentials (host, username, password) are stored in the `/schools/{sid}/settings/smtp` document. 
  The Firestore rule:
  ```javascript
  allow read:  if isSignedIn() && inSchool(sid) && (docId != 'smtp' || isManagement());
  ```
  allows any user matching `isManagement()` to read this document. `isManagement()` includes coordinators, principals, local admins, owners, and ownerPrincipals.
* **Threat Vector:** 
  Coordinators or principals (who do not manage the email server configuration) read the `/schools/{sid}/settings/smtp` document and retrieve the cleartext SMTP password.
* **Impact:** 
  Leakage of company/school email credentials allows compromised or malicious coordinator accounts to send phishing emails, intercept communications, or log in to the school's SMTP service.
* **Remediation Plan:**
  Restrict the `smtp` document read permission to `isStrictAdmin()` (which includes admins and owners) or `isRootAdmin()` only.

#### Code Fix:
**In `firestore.rules`:**
```diff
     match /schools/{sid}/settings/{docId} {
-      allow read:  if isSignedIn() && inSchool(sid) && (docId != 'smtp' || isManagement());
+      allow read:  if isSignedIn() && inSchool(sid) && (
+        (docId != 'smtp' || isStrictAdmin()) &&
+        (docId != 'keys' || isManagement())
+      );
```

---

### SEC-03: Client-Side Deletions Bypass in allowed_users (Owner Lockout)
* **Severity:** **High**
* **Vulnerable Files:** 
  * [firestore.rules](file:///Users/upendrapandey/school_app/firestore.rules#L633-L638)
* **Description:** 
  The Firestore deletion rule for `/allowed_users/{email}` is:
  ```javascript
  allow delete: if isRootAdmin() || (isSignedIn() && (
    (isStrictAdmin() && resource.data.schoolId == userSchoolId()) ||
    ...
  ));
  ```
  `isStrictAdmin()` matches the local school `admin` role. The rule does not enforce any role hierarchy check. Thus, a local school `admin` can delete the school `owner`'s document in Firestore.
  This triggers `syncUserClaims`, which immediately sets the owner's custom user claims to `null` (since the document no longer exists), locking them out of their owner actions.
* **Threat Vector:** 
  A rogue local `admin` issues a direct Firestore delete request on the `allowed_users` document of their school's `owner`.
* **Impact:** 
  Denial of Service (DoS) and de-authorization of the school owner, preventing them from managing settings, finances, or restoring their account without system admin intervention.
* **Remediation Plan:**
  Deny direct client-side deletions of users who hold equal or higher ranks. Local admins should only be able to delete roles lower than them (e.g. principal, coordinator, teacher, guardian).

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

### SEC-04: Notification Impersonation / Phishing Vector
* **Severity:** **Medium / High**
* **Vulnerable Files:** 
  * [firestore.rules](file:///Users/upendrapandey/school_app/firestore.rules#L1431-L1465)
* **Description:** 
  The rule for creating notifications allows parents (guardians) to submit leave notifications to their class teachers:
  ```javascript
  (isRole('guardian')
    && 'audience' in request.resource.data
    && request.resource.data.audience == ('class_teacher:' + userStudentClass()))
  ```
  However, the rule does not check whether the sender-related fields in the document (like `postedBy` or `senderEmail`) match the actual authenticated user's email.
* **Threat Vector:** 
  A guardian writes a notification document with `audience: 'class_teacher:Class 9-A'` but sets `postedBy: 'admin@schoolapp.org'` and `title: 'URGENT: Tuition Fees Due immediately'`.
* **Impact:** 
  The class teacher's feed displays a forged message appearing to come from the admin/principal, facilitating phishing attacks or social engineering.
* **Remediation Plan:**
  Enforce that the notification's creator email field (`postedBy`) matches the authenticated user's email.

#### Code Fix:
**In `firestore.rules`:**
```diff
       allow create: if isSignedIn() && inSchool(sid) && (
         isManagement() ||
         // Teachers: targeted audiences ONLY, and class/guardian audiences must
         // be for a class they teach (M1 — see teacherMayPostAudience).
         (isAnyTeacher()
           && 'audience' in request.resource.data
           && teacherMayPostAudience(request.resource.data.audience)
+          && 'postedBy' in request.resource.data
+          && request.resource.data.postedBy.lower() == userEmail()) ||
         // Guardians: ONLY the legitimate student-leave notice addressed to their
         // OWN child's class teacher.
         (isRole('guardian')
           && 'audience' in request.resource.data
-          && request.resource.data.audience == ('class_teacher:' + userStudentClass()))
+          && request.resource.data.audience == ('class_teacher:' + userStudentClass())
+          && 'postedBy' in request.resource.data
+          && request.resource.data.postedBy.lower() == userEmail())
       );
```

---

### SEC-05: Audit Log Spoofing in `createAllowedUser` Cloud Function
* **Severity:** **Medium**
* **Vulnerable Files:** 
  * [functions/index.js](file:///Users/upendrapandey/school_app/functions/index.js#L480-L481)
* **Description:** 
  In the `createAllowedUser` Cloud Function, the creator metadata fields `createdByEmail` and `createdByRole` prioritized client-supplied values if they were present in `request.data`:
  ```javascript
  createdByEmail: request.data.createdByEmail ? String(request.data.createdByEmail).trim().toLowerCase() : callerEmail,
  createdByRole: request.data.createdByRole ? String(request.data.createdByRole).trim() : (callerRole || ""),
  ```
* **Threat Vector:** 
  A compromised coordinator account calls `createAllowedUser` but passes `createdByEmail: 'principal@school.test'` and `createdByRole: 'principal'` in the request body.
* **Impact:** 
  Writers of accounts can forge the creator audit trail, making it difficult to trace unauthorized account provisioning.
* **Remediation Plan:**
  Always populate these metadata fields from the authenticated context token claims (`callerEmail` and `callerRole`).

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

### SEC-06: Permissive Homework Document Writes for Non-Assigned Classes
* **Severity:** **Low**
* **Vulnerable Files:** 
  * [firestore.rules](file:///Users/upendrapandey/school_app/firestore.rules#L1515-L1523)
* **Description:** 
  The rules for the `homework` collection allow any teacher to write homework documents for any class in the school:
  ```javascript
  allow write: if isSignedIn() && inSchool(sid) && (isManagement() || isAnyTeacher());
  ```
* **Threat Vector:** 
  A teacher of Class 1-A accidentally (or maliciously) writes or deletes homework documents for Class 10-C.
* **Impact:** 
  Unintended modification or data loss of homework assignments.
* **Remediation Plan:**
  Restrict write access to either management or teachers assigned to the targeted class (using their custom claims `classIds` or matching their `userClassIds()` helper).

#### Code Fix:
**In `firestore.rules`:**
```diff
     match /schools/{sid}/homework/{docId} {
       allow read:  if isSignedIn() && inSchool(sid);
       allow write: if isSignedIn() && inSchool(sid)
-        && (isManagement() || isAnyTeacher());
+        && (isManagement() || (isAnyTeacher() && request.resource.data.className in userClassIds()));
     }
```

---

### SEC-07: App Check Disabled Across Cloud Functions
* **Severity:** **Medium**
* **Vulnerable Files:** 
  * [functions/index.js](file:///Users/upendrapandey/school_app/functions/index.js) (Multi-line occurrences)
* **Description:** 
  Almost all Cloud Functions (such as `deleteAccount`, `createAllowedUser`, `recordPayment`, `reversePayment`) specify `enforceAppCheck: false`.
* **Threat Vector:** 
  A malicious client script makes requests directly to the Cloud Functions endpoints bypassing the client application code completely.
* **Impact:** 
  Allows automated attacks/spamming of administrative operations if user credentials are leaked or compromised.
* **Remediation Plan:**
  Enable App Check across the Firebase project and set `enforceAppCheck: true` for sensitive production callable functions.

# Firestore Security Rules — Deployment & Testing Guide

## Overview

`firestore.rules` enforces role-based access control for the School App Firestore
database using a **future-proof multi-tenant layout** (`schools/{sid}/...`) with a
root-level `allowed_users/{uid}` identity collection.

---

## Files

| File | Purpose |
|---|---|
| `firestore.rules` | The security rules deployed to Firebase |
| `firestore.rules.test.js` | Jest unit tests using the Firebase Emulator |
| `FIRESTORE_RULES_README.md` | This guide |

---

## Roles & Permissions Matrix

| Collection | guardian | teacher | subjectTeacher | coordinator | principal | admin/owner |
|---|:---:|:---:|:---:|:---:|:---:|:---:|
| `allowed_users` | read self | read self | read self | read same school | read same school | full CRUD |
| `students` | read own child; update guardianDetails | read all; write own class | read all; write own class | full | full | full |
| `teachers` | read | read | read | full | full | full |
| `attendance` | read own class | read all; write own class | read all; write own class | full | full | full |
| `announcements` | read | read | read | full | full | full |
| `leave_applications` | — | read/create own; update body | read/create own; update body | read all; update status | read all; update status | full |
| `fees` | read own class | — | — | full | full | full |
| `fee_payments` | read own children | — | — | full | full | full |
| `exams` / `exam_results` / `copy_checks` | read | read; write own class | read; write own class | full | full | full |
| `staff_tasks` | — | read if assignee; update status | read if assignee; update status | read all | read all; full | full |
| `notifications` | read matching audience | read matching audience | read matching audience | read matching audience | read matching audience | read all; write |
| `timetable` / `settings` / `duties` / `substitutions` | read | read | read | full | full | full |
| `homework` | read | full | full | full | full | full |
| `albums` / `photos` | read (incl. published) | read (incl. published) | read | full | full | full |

**Hard guarantees enforced by the rules:**

1. **Default deny** — a catch-all `/{document=**} { allow read, write: if false; }` is the first match block.
2. **inSchool(sid)** — every school-scoped rule verifies the caller's `schoolId == sid` before any other check.
3. **Role escalation blocked** — non-admin self-update on `allowed_users` cannot change `role` or `schoolId`.

---

## Deploying

### Prerequisites

- Firebase CLI ≥ 12:
  ```bash
  npm install -g firebase-tools
  firebase login
  ```
- Project initialised: `firebase init firestore` (creates `firebase.json` / `.firebaserc` if missing).

### One-line deploy

```bash
firebase deploy --only firestore:rules
```

### Verify deployment

```bash
firebase firestore:rules get   # prints the active rules
```

### Dry-run (simulate without deploying)

Open the [Firebase Emulator](https://console.firebase.google.com/) and use
**Rules Playground** to test individual paths, or run the unit tests below.

---

## Running Unit Tests

### 1 — Install dependencies (Node.js project alongside Flutter)

```bash
cd /path/to/school_app        # repo root
npm init -y                   # only needed once
npm install --save-dev @firebase/rules-unit-testing firebase jest
```

Add to `package.json`:

```json
{
  "scripts": {
    "test:rules": "jest firestore.rules.test.js"
  },
  "jest": {
    "testEnvironment": "node"
  }
}
```

### 2 — Start the Firestore Emulator

```bash
firebase emulators:start --only firestore
# or with the full suite:
firebase emulators:start
```

The test file expects the emulator on `localhost:8080`.  
Override with `FIRESTORE_EMULATOR_HOST=localhost:8080` if your port differs.

### 3 — Run tests

```bash
npm run test:rules
# or directly:
npx jest firestore.rules.test.js --verbose
```

### Expected output (all green)

```
Firestore Security Rules
  1. Unauthenticated access
    ✓ DENY — cannot read students
    ✓ DENY — cannot read allowed_users
    ✓ DENY — cannot write attendance
  2. Guardian — student access
    ✓ ALLOW — can read their own child's student record
    ✓ DENY — CRITICAL: cannot read another child's student record
    ✓ ALLOW — can update guardianDetails for own child
    ✓ DENY — cannot update core student fields (name, roll, etc.)
  3. Teacher — student write access
    ✓ ALLOW — class teacher can write their own class students
    ✓ DENY — CRITICAL: teacher cannot write students in another class
    ✓ ALLOW — teacher can read all students (not just own class)
  4. Role escalation prevention
    ✓ DENY — CRITICAL: teacher cannot escalate own role
    ✓ DENY — user cannot change their own schoolId
    ✓ DENY — teacher cannot create a user document (no user provisioning)
    ✓ ALLOW — user can update their own non-privileged fields
    ✓ ALLOW — admin can upgrade a user's role
    ✓ DENY — coordinator cannot read a user from a different school
  5. Leave applications
    ✓ ALLOW — teacher can submit their own leave application
    ✓ DENY — teacher cannot submit a leave with someone else's teacherId
    ✓ DENY — CRITICAL: teacher cannot approve their own leave
    ✓ ALLOW — coordinator can approve a leave application
    ✓ DENY — coordinator cannot change non-review fields on a leave
    ✓ DENY — other teacher cannot read teacher9A's leave application
  6. Attendance
    ✓ ALLOW — guardian can read attendance for their child's class
    ✓ DENY — CRITICAL: guardian cannot read attendance for another class
    ✓ ALLOW — class teacher can write attendance for their class
    ✓ DENY — CRITICAL: teacher cannot write attendance for another class
    ✓ ALLOW — coordinator can write attendance for any class
  7. Staff tasks
    ✓ ALLOW — assignee can update task status fields
    ✓ DENY — assignee cannot change task title or assignee
    ✓ DENY — CRITICAL: non-assignee teacher cannot read another's task
    ✓ ALLOW — coordinator can read all staff tasks
    ✓ DENY — teacher cannot create a staff task
    ✓ ALLOW — principal can create a staff task
  8. Notifications
    ✓ ALLOW — guardian can read their class notification
    ✓ DENY — CRITICAL: guardian cannot read another class's notification
    ✓ ALLOW — any authenticated school member can read an "all" notification
  9. Fees — guardian scope
    ✓ ALLOW — guardian can read fee structure for their child's class
    ✓ DENY — CRITICAL: guardian cannot read fee structure for another class
    ✓ DENY — teacher cannot write fee documents
  10. Coordinator / Principal global access
    ✓ ALLOW — coordinator can read any student
    ✓ ALLOW — principal can delete a student record
    ✓ ALLOW — admin can provision a new user
    ✓ ALLOW — coordinator can update timetable / settings
    ✓ DENY — guardian cannot write announcements

42 tests passed.
```

---

## Migration Notes (current flat collections → multi-tenant)

The current app writes to root-level collections (`/students`, `/attendance`, etc.).
These rules target the **future nested layout** (`/schools/{sid}/students`, etc.).

**Transition plan:**

1. Deploy rules targeting both layouts during migration:
   - Keep the existing wide-open rules for root collections temporarily.
   - Add the new school-scoped rules alongside them.
2. Migrate Firestore data using the [Cloud Firestore Data Migration guide](https://firebase.google.com/docs/firestore/manage-data/export-import).
3. Update every `FirebaseFirestore.instance.collection('students')` call to
   `FirebaseFirestore.instance.collection('schools/$schoolId/students')`.
4. Once all clients are updated and data is migrated, remove the root-level permissive rules.

The `schoolId` for the current single-tenant installation is `'school_1'`
(hardcoded in `GalleryService`). Use the same value as the path segment `sid`
for all existing data.

---

## Known Limitations & TODOs

| Area | Limitation | Recommended fix |
|---|---|---|
| Notifications write | Any authenticated school member can write | Move writes to Cloud Functions / Admin SDK; remove client write permission |
| Gallery public read | Published photos are readable without auth | Fine for share links; add signed URLs via Storage if stricter access is needed |
| Guardian notification roll matching | Rules grant class-level access; roll filtering is the client's responsibility | Store `recipientUid` field on notifications so rules can do exact UID match |
| Notification `split(':')[1]` | Assumes class names don't contain colons | Replace with a dedicated `audienceClass` field on the notification doc |
| `allowed_users` self-read of another user | `userDoc()` inside the `allowed_users` match reads the *caller's* doc, not the target — no circular dependency, but if the caller's doc is missing the rule silently denies | Ensure every Firebase Auth user has a corresponding `allowed_users` doc (e.g. via Cloud Functions `auth.onCreate` trigger) |

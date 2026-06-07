# School App — 200-Issue Pre-Production Review

Reviewer perspective: principal, coordinator, teacher, and guardian.
Scope: `lib/` (79k LOC, ~185 files), `firestore.rules`, `storage.rules`, `functions/index.js`.
Severity: 🔴 critical · 🟠 high · 🟡 medium · 🔵 low/polish.

> Note: several issues depend on **whether `firestore.rules` / `functions` are actually deployed**. Project memory says they were not deployed at last check. If true, escalate every "rules enforce X" item — the app would currently run on whatever rules are live in `attendanceapp-e76e1`.

---

## A. Critical security & destructive-action flaws

1. 🔴 **`deleteAccount` Cloud Function has no role-hierarchy check** (`functions/index.js:82-103`). `DELETE_ROLES` includes `coordinator` and `principal`, and authorization only requires *same school*. A coordinator can call `deleteAccount({email: <owner email>})` → `targetRole==='owner'` → the function **recursively wipes the entire `schools/{schoolId}` subtree, deletes every account, and best-effort-deletes Storage**. Any coordinator or principal can destroy their whole school. Add a hierarchy matrix (who may delete whom) and forbid deleting `owner`/`principal` from below.
2. 🔴 **Coordinator can delete the principal (and vice-versa)** via the same function — peers/superiors are deletable as long as they're not literally `admin`. Privilege sabotage.
3. 🔴 **Full-school wipe is a single API call with no confirmation token, no soft-delete, no backup/export step, no cool-down.** `recursiveDelete` of `schools/{id}` is irreversible. Require a typed confirmation + time-delayed/2-person approval for owner deletion.
4. 🟠 **`deleteAccount` deletes Auth + `allowed_users` but partially orphans data** for non-owner roles (a deleted coordinator's `staff_remarks`, `audit_logs`, meeting tasks, todos remain). Cascade is only implemented for owner and teacher.
5. 🟠 **`notifications` create rule lets ANY school member post targeted notices** (`firestore.rules:1204-1209`) — a guardian can write `audience: 'coordinator'`, `'principal'`, `'class_teacher:..'`, or `'guardian:<otherClass>:<roll>'` with arbitrary title/body. Phishing/impersonation vector ("— School Management"). The rule's own TODO admits this; move notification creation to a Cloud Function / Admin SDK.
6. 🟠 **`tasks` (root) is readable by every authenticated user across all schools** (`firestore.rules:252` `allow read: if isSignedIn()`). Tasks carry `studentStatuses` and student keys — cross-tenant PII leak. Scope by `schoolId`.
7. 🟠 **`copy_checks` (root) write rule has no school or class scoping** (`firestore.rules:344` `allow write: if isSignedIn() && (isManagement()||isAnyTeacher())`). Any teacher of any school can create/overwrite/delete any copy-check doc. Reads are school-scoped but writes are not.
8. 🟠 **`calendar_events` (root) writable by any staff of any school** (`firestore.rules:1429`). A teacher in school B can mutate the global calendar seen by school A.
9. 🟠 **Legacy `/settings/{docId}` is readable by any signed-in user regardless of school** (`firestore.rules:1248`) and holds the holiday calendar — cross-tenant read; one school's holidays bleed into another in a multi-tenant deployment.
10. 🟠 **Storage `policy` assets are cross-tenant** (`storage.rules:34-37`): any signed-in user (incl. a guardian from a different school) can read AND write `schools/{anySchoolId}/policy/...`. Combined with a 15 MB image allowance and no per-user quota, this is a storage-cost / defacement vector.
11. 🟠 **Audit-log poisoning**: any school member may `create` `audit_logs` docs (`firestore.rules:1305-1306`) with arbitrary `action/entity/before/after`, only `actorUid` is pinned. A user can flood or fabricate (non-self-attributed) audit noise. Restrict creation to the service/Cloud Function.
12. 🟡 **Root-admin identity is a single hardcoded Gmail** (`auth_service.dart:47`, `firestore.rules:213`, `functions/index.js:30`). If that one Google account is phished, the entire multi-school platform is owned, and the value cannot be rotated without a coordinated client+rules+function redeploy.
13. 🟡 **`homework` (root) update/delete allows any teacher to edit/delete any other teacher's homework** in the same school (`firestore.rules:325`) — no `teacherId == own` check on update (create has it, update/delete don't).
14. 🟡 **`classIdInList` section matching is over-permissive** (`firestore.rules:150-162`): `cls.split('-')[0] in ids` means a teacher whose `classIds` contains the grade ("Class 9") is treated as class-teacher of *every* section (9-A, 9-B, …). May be intended for grade leads, but currently silent and ungated.
15. 🟡 **No App Check / no abuse throttling.** A signed-in guardian can script reads of everything their rules permit (their child's whole history) and there is no bot/automation gate. Enable Firebase App Check.
16. 🔵 **No re-auth required for self password change beyond Firebase's `requires-recent-login`** — fine, but there's no audit entry for a *successful* self password change (only for admin-sent resets, `auth_service.dart:109-117`).

## B. Multi-tenancy / data isolation (deferred but shipping risk)

17. 🔴 **Multi-tenancy is "Phase 3" in the rules but the app still hardcodes `'school_1'` fallbacks** (`auth_service.dart:58`, `student_service.dart:236`, `GalleryService` per CLAUDE.md). If `schoolId` is ever missing on a doc, rules fail closed (lockout) while the app silently reads/writes `school_1` — a split-brain that can cross tenants or lock users out.
18. 🟠 **Root collections (`tasks`, `homework`, `copy_checks`, `calendar_events`, `settings`, `personal_todos`, `substitution_history`, `feeReminders`)** mix all schools in one collection scoped only by a `schoolId` *field*. Every list query MUST add `.where('schoolId', ==)` or it's denied/over-broad; easy to forget and there's no lint enforcing it.
19. 🟠 **CLAUDE.md says `allowed_users` is keyed by Firebase Auth UID; it is actually keyed by lowercased email** (`timetable_service.dart:124`, rules `getUserData()` uses `userEmail()`). Stale architecture doc → future contributors will write UID-keyed code that silently breaks auth/rules.
20. 🟡 **Email-keyed identity means a user who changes their email loses their entire identity doc** — there's no migration path; the `allowed_users` doc id can't change (`timetable_service.dart:172`). Email changes orphan the account.
21. 🟡 **`inSchool()` performs a Firestore `get()` per evaluation** and is called on nearly every rule; combined with the 1000-expression ceiling (documented at length in the rules), complex docs risk denial. This is fragile and already bit teachers once (see comments at `firestore.rules:131-162`).

## C. Authentication & session

22. 🟠 **No in-session/idle timeout while the app is open.** The 7-day check (`main.dart:137-150`) only fires on cold start and is refreshed on every open. On a shared staff device, an open session stays authenticated indefinitely. Add a foreground idle lock.
23. 🟠 **Suspended/fired staff retain access while offline.** On resume, if the `allowed_users` re-read throws (offline), the app keeps cached routing (`main.dart:215-217`). A dismissed teacher in airplane mode keeps full local access until reconnect or the 7-day window.
24. 🟠 **Phone-OTP guardians are never revalidated on resume** (`main.dart:207-209`) — a guardian whose child was removed keeps routing into a (now permission-denied) dashboard until the 7-day timeout, showing a broken/empty UI instead of a clean re-login.
25. 🟡 **Session timeout trusts device clock** (`DateTime.now()`), so a rolled-back clock defeats the 7-day expiry.
26. 🟡 **Guardian session stores only one child** (`studentClass/studentRoll`, `main.dart:261-263`); multi-child guardians always land on child #1 and must switch manually, and deep links/notifications can't target the right child.
27. 🟡 **Login error swallows all non-FirebaseAuth exceptions into one generic message** (`login_screen.dart:133-142`) — config/permission/Firestore errors are indistinguishable from a typo, frustrating real onboarding.
28. 🟡 **`weak-password` message hardcodes "at least 6 characters"** (`auth_service.dart:321`) but the app mints 20-char temp passwords; guardians setting their own password aren't told the real policy up front.
29. 🔵 **No account-lockout messaging path for guardians** beyond Firebase's `too-many-requests`; OTP rate-limit feedback should be surfaced in `PhoneOtpScreen`.
30. 🔵 **`markUserActive` is fire-and-forget on login** (`login_screen.dart:100`, no await) — a failure leaves `status: 'pending'` and can repeatedly attempt on every login.

## D. Business logic — fees & money

31. 🔴 **All money is `double` (floating-point).** `Payment.amount`, totals, `toStringAsFixed` (121 sites), `getFeesSummary` accumulation (`fee_service.dart:269-318`). Summing many fees in `double` produces rounding drift (e.g. ₹ off-by-a-paisa), which is unacceptable for financial records and receipts. Store paise as `int`.
32. 🟠 **"Collected" total is computed wrong.** `getFeesSummary` only adds `totalDue` to `collected` when a student is *fully* paid (`fee_service.dart:296-308`); partial payments contribute **0** to "collected" and the unpaid remainder to "pending". The dashboard's collected figure understates actual cash received and won't reconcile with the receipt ledger.
33. 🟠 **Defaulter "amount overdue" uses annual fee, not schedule-to-date.** A student current on installments but not yet at the annual total is reported as owing the gap to the *annual* fee (`fee_service.dart:308`), inflating "pending"/"overdue".
34. 🟠 **No double-charge / over-payment guard.** `addPayment` accepts any amount with no check against remaining balance; a cashier can record more than the fee due, and nothing flags it.
35. 🟠 **Receipt number is gapless via a single counter doc** (`fee_service.dart:97-121`) — good — but **reversal does not void/track the receipt number**, so a reversed payment leaves a "used" receipt number with no visible void marker on printed receipts. Auditors expect voided receipt numbers.
36. 🟠 **Fee reports are O(students) Firestore reads.** `getClassFeeOverview` calls `getTotalPaid` → `getPayments` per roll (`fee_service.dart:189-197`), and `getFeesSummary` does it per class (`258-318`). A 1,000-student school triggers ~1,000+ reads per dashboard open → slow + costly. Pre-aggregate per student.
37. 🟡 **`getTotalPaid` sums all non-reversed payments without currency/precision care** and re-reads on every call; no caching.
38. 🟡 **Fee structure is keyed by class only** (`fee_structures/{className}`), so sibling discounts, scholarships, or per-student fee overrides are impossible to express.
39. 🟡 **No partial-receipt allocation across installments is enforced** — `installmentName` is free-text on the payment (`fee_service.dart:178`); a typo silently creates a phantom installment bucket.
40. 🟡 **`saveFeeStructure` overwrites the whole structure** with no version/history; a fee revision mid-year destroys the prior schedule used by existing receipts.
41. 🔵 **Currency symbol/format is ad-hoc** (`toStringAsFixed` + manual `₹`), not `NumberFormat` with locale grouping — large amounts render as `123456.0` not `1,23,456.00` (Indian grouping).
42. 🔵 **No payment mode reconciliation** (cash vs UPI vs cheque) totals on the overview, despite `dropdown_options` for fee modes.

## E. Business logic — attendance

43. 🟠 **Attendance "today" is the *device's* local date.** `_todayKey` uses `DateTime.now()` (`student_service.dart:464-467`). A device in the wrong timezone or with a wrong clock writes attendance under the wrong day; a guardian on a device a day ahead/behind sees mismatched "today". Anchor to a server/school timezone.
44. 🟠 **`markLeaveForDateRange` only skips Sundays** (`student_service.dart:532`). Many Indian schools have working Saturdays, alternate Saturdays, or 6-day weeks; this hardcodes a 6-day assumption AND ignores declared holidays, marking "Leave" on days school wasn't in session.
45. 🟠 **`markLeaveForDateRange` blindly overwrites existing status** for each day (`{roll: 'Leave'}` merge), so a day already marked "Present" flips to "Leave" — silent attendance corruption when a leave range overlaps already-recorded days.
46. 🟠 **Offline last-write-wins silently clobbers co-teacher edits.** Two staff marking the same class on the same day from different offline devices: on sync, the last entry overwrites the other with no merge or conflict notice (`offline_queue_service.dart:17-18,52-54`).
47. 🟡 **Date keys are not zero-padded** (`2026-6-4`, `student_service.dart:466`). Internally consistent, but any lexicographic range/order over attendance doc IDs is wrong (e.g. `-1-` sorts before `-12-`), and export/debugging is error-prone.
48. 🟡 **`loadTodayAttendance(className)` keys without section but `loadTodayFullSummary` keys with section** (`student_service.dart:471-481` vs `587-601`). The attendance screen computes `_attendanceKey` from class+section (`attendance_screen.dart:84-86`), so the read path is consistent only if every caller passes the section-combined name — fragile coupling that will silently split a class's attendance into two docs if a caller forgets the section.
49. 🟡 **No "school closed / holiday" attendance state** — only Present/Absent/Leave. Holidays look like "not marked", indistinguishable from a teacher who forgot.
50. 🟡 **`int.parse` on roll keys throws on any malformed key** (`student_service.dart:478,632,747`). One bad `rolls` map entry (e.g. a stray non-numeric key from a bad write) crashes the whole class summary. Use `int.tryParse` and skip.
51. 🟡 **Attendance has no lock/cutoff.** A class teacher (or any management) can rewrite past attendance indefinitely; audit logs it, but there's no "finalized after N days" guard against altering historical records.
52. 🔵 **Consecutive-absence streak (`loadConsecutiveAbsenceDays`) treats unmarked days as "skip", not "break"** (`student_service.dart:759-794`), so a gap of unmarked days can inflate a streak across non-attended periods.

## F. Students, exams, marks

53. 🟠 **`removeStudent` cascade is non-transactional best-effort** (`student_service.dart:310-376`): tombstone, doc delete, attendance/notifications/exam/fee cleanups each run separately and swallow errors. An interruption leaves a deleted student with lingering fee/exam records that still surface in totals.
54. 🟠 **`approveDeletionRequest` loops `removeStudent` sequentially with no atomicity** (`student_service.dart:427-441`); a mid-batch failure leaves some students deleted and the request still `pending`/half-applied.
55. 🟠 **Exam-results guardian read requires `studentId` field but legacy docs without it fail closed** (good for security) — but the marks-write path stamps results keyed by `roll` only in some paths; verify every `exam_results/{examId}/students/{roll}` write also sets `studentId`, or guardians silently can't see results (`firestore.rules:1000-1003`).
56. 🟠 **Duplicate-roll check is class+section scoped at add time only** (`student_service.dart:172-178`); changing a student's section to one where the roll already exists isn't blocked on update (`updateStudent` has no dup check), creating a roll collision.
57. 🟡 **Marks validation is per-subject 0..maxMarks** (`marks_entry_screen.dart:94-98`) but there's **no "absent in exam" state** distinct from blank — a blank could mean "not entered" or "absent (0)"; report cards can't distinguish.
58. 🟡 **No grade-boundary / pass-fail configuration surfaced** — grading appears hardcoded in the PDF builder; schools can't set their own grade bands.
59. 🟡 **Student doc ID encodes class/section/roll** (`{cls}_{sec}_{roll}`); promoting a student to the next class or changing their roll requires delete+recreate, losing the stable identity (remarks/consents subcollections are keyed under the old ID).
60. 🟡 **`getStudentsByGuardianEmail` relies on lowercased `guardianEmail` equality** (`student_service.dart:84-97`); a guardian email stored with different casing/whitespace in a legacy record won't match and the parent sees no children.
61. 🔵 **`_cascadeDeleteAttendance` upper-bound sentinel is `■` (U+25A0)** (`student_service.dart:1021`); a class name containing a char above it would escape the range. Unlikely but undocumented.

## G. Notifications & privacy

62. 🟠 **WhatsApp links use raw digits with NO country code** (`attendance_screen.dart:1676-1678`, `daily_calls_screen.dart:158-160`, `student_remarks_screen.dart:259`, `student_list_screen.dart:958`). A 10-digit Indian number → `wa.me/9876543210` which WhatsApp can't resolve (or routes to the wrong international number). Prepend the school's country code.
63. 🟠 **Child attendance/remark messages are sent in cleartext via the staff member's personal WhatsApp**, exposing parent numbers in the staff member's chat history and routing PII through a third party with no consent record. No opt-out is checked at send time despite a `whatsappEnabled` setting existing (`school_settings_provider.dart:139`).
64. 🟡 **Unread state is per-device SharedPreferences** (`notification_service.dart:13`). Reinstall, new device, or cache clear marks everything unread again; reading on one device doesn't clear the badge on another.
65. 🟡 **Notification audience matching is string-`split(':')`** (`firestore.rules:1174-1193`, `notification_service.dart`); a class name containing `:` silently breaks targeting/authorization. No validation forbids `:` in class names at creation.
66. 🟡 **`whereIn` audience query is capped at 10 values** in Firestore; `_audiencesFor` builds a set that for a multi-child guardian + roles could exceed 10 audiences and throw (`notification_service.dart:241-282`).
67. 🔵 **No notification retention/cleanup** beyond per-student delete on student removal — the `notifications` collection grows unbounded per school.

## H. Workflow gaps

68. 🟠 **Teacher deletion has TWO contradictory paths**: the approval workflow (`teacher_deletion_requests`, coordinator→principal) AND the `deleteAccount` Cloud Function that lets a coordinator delete a teacher directly. The careful approval rule is bypassable.
69. 🟠 **No bulk student import.** Onboarding a real school means typing hundreds of students by hand (`add_student_screen.dart`); `csv` is a dependency but there's no visible import flow for students. Huge adoption blocker.
70. 🟠 **No student promotion / new-academic-year rollover.** There's no flow to advance a class to the next grade, archive last year, or reset rolls — schools will be stuck re-entering everyone each year (compounded by F59's identity coupling).
71. 🟠 **No data export / backup for the school** (attendance registers, fee ledgers, mark sheets). Schools need printable/exportable statutory registers; only some PDFs exist (calls, report cards). And the only "export everything" path is the destructive `recursiveDelete`.
72. 🟡 **Guardian-provided detail corrections have no notification to staff** — `submitGuardianProvidedDetails` just `add`s a doc (`student_service.dart:1046-1050`); staff must happen to open the student to notice. No pending-count badge.
73. 🟡 **Substitution suggester** exists but there's no guarantee a suggested substitute isn't themselves on leave that day — verify `substitution_suggester_service` cross-checks `leave_applications`.
74. 🟡 **Leave approval doesn't auto-mark attendance.** An approved student leave doesn't create the corresponding `Leave` attendance entries unless someone runs `markLeaveForDateRange` manually — two disconnected systems.
75. 🟡 **Reversed fee payments stay in audit but there's no UI to view/restore them** — `getPayments` filters `reversed` out (`fee_service.dart:73`) with no "show reversed" toggle for reconciliation.
76. 🟡 **Coordinator can't be created by a coordinator (correct), but there's no "request coordinator" path** — adding a second coordinator always requires principal/owner, which may not match how schools delegate.
77. 🔵 **No "draft" state for announcements/homework** — posting is immediate and broadcast; a typo means delete+repost (which fans out duplicate notifications).
78. 🔵 **Meeting tasks and staff tasks are separate systems** with separate screens and rules (`meetingTasks` vs `staff_tasks`) — staff see two task inboxes.

## I. Usability / UX

79. 🟠 **i18n is implemented in only 1 of ~148 screens** (`grep context.tr` → 1 file) despite Hindi being a shipped feature (`lib/l10n/app_strings.dart`). Nearly every label, button, SnackBar, and error is hardcoded English — unusable for the Hindi-first staff/guardians the app targets.
80. 🟠 **Destructive actions frequently lack confirmation.** Only ~4 screens reference delete + a dialog together; verify each `delete`/reverse/remove has a confirm step (student delete, payment reversal, account delete, announcement delete).
81. 🟠 **157 raw `Color(0x...)` literals across the app** (32 screen/widget files) directly violate the project rule that `AppTheme` is the single color source — inconsistent theming, broken dark-mode/accessibility, and drift from the brand palette.
82. 🟡 **27 silent `catch (_) {}` blocks** swallow errors with no user feedback or log — failures (failed save, failed sync) appear to "succeed" to the user.
83. 🟡 **Long forms (137 `TextField`/`TextFormField`) — verify keyboard types & maxLength**: phone fields should be `TextInputType.phone`, fee amounts numeric, names capitalized; several appear to use defaults.
84. 🟡 **No pull-to-refresh consistency** — `RefreshableData`/`refreshable_data.dart` exists but adoption is partial; some dashboards only refresh on navigation.
85. 🟡 **Empty states are inconsistent.** Several Future/StreamBuilders (12 of 33 builders lack `hasError`) render a spinner or blank on error instead of an actionable empty/error state.
86. 🟡 **No offline indicator on most screens** even though attendance has an offline queue — users don't know whether their save is queued or live.
87. 🟡 **Date/number formatting is locale-naive** — months are hand-indexed (`mo[d.month-1]`, `attendance_screen.dart`), so localization and DST/edge dates are fragile.
88. 🟡 **Roll-number-as-identity in guardian UX** — guardians are shown "(Roll No. X)" in messages; if rolls are reassigned across years this misidentifies the child.
89. 🔵 **No accessibility semantics** (Semantics labels, min tap targets, font scaling) audited — icon-only WhatsApp/phone buttons have no labels for screen readers.
90. 🔵 **WhatsApp/phone buttons fail silently** when the app isn't installed (`if (await canLaunchUrl) launchUrl` with no else, `daily_calls_screen.dart:150`) — nothing happens, no toast.
91. 🔵 **PDF generation has no progress/cancel** for large classes/report-card batches.
92. 🔵 **No search/filter on long student lists** beyond class scoping in several screens.
93. 🔵 **Debug `AppLogger.d` + an `assert` SECTION MISMATCH guard ships in attendance load** (`attendance_screen.dart:248-259`) — asserts are stripped in release, so the safety check is dev-only; the underlying wrong-section-students risk has no release-mode guard.

## J. Code quality / reliability

94. 🟠 **`setState` after `await` without `mounted`**: 658 `await`s in screens; spot-checks show guarded ones, but this volume needs an audit — any unguarded `setState`/`context` use after await crashes on a disposed widget.
95. 🟡 **33 `int.parse` (vs `tryParse`) sites** are latent crash points on malformed Firestore data (see E50).
96. 🟡 **Singletons hold per-session state** (`BaseFirestoreService.currentSchoolId`, `DropdownOptionsService` cache) cleared on logout (`auth_service.dart:300-302`) — but any code path that signs out via `FirebaseAuth.signOut()` directly (not `clearSession`) would leave stale school state. Centralize.
97. 🟡 **`TimetableService._settingsCache`** (per CLAUDE.md) is invalidated only on `saveSettings()` in the same session — a settings change by another admin isn't seen until app restart.
98. 🟡 **Best-effort guardian provisioning swallows failures** (`student_service.dart:289-300`): if Auth account creation fails, the student saves with a `guardianEmail` that can never log in, and there's no "invite failed, retry" surfacing.
99. 🔵 **`sendPasswordResetEmail` audit fires even if the email send threw** earlier? It awaits the send first (`auth_service.dart:109-111`), OK — but `sendResetIfRegistered` (self-service) emits no audit at all, so password-reset attempts via the public flow aren't logged.
100. 🔵 **Mixed money types** (`num`→`double` casts guarded in places, `fee_service.dart:320-322`) indicate inconsistent stored types (int vs double) for the same field across documents.

## K. Data integrity, dates, validation

101. 🟡 **Email regex is permissive** (`validators.dart:7`, `^[^@\s]+@[^@\s]+\.[^@\s]+$`) — accepts `a@b.c`; fine for syntax but no normalization beyond trim/lowercase, and the same regex is duplicated in `functions/index.js:19` (drift risk).
102. 🟡 **No phone-number validation/normalization** anywhere — phones are stored as typed and later stripped to digits for WhatsApp (G62). Invalid/short numbers silently produce dead links.
103. 🟡 **No max-length on most free-text fields** except remarks (200 chars, `student_service.dart:816`). Announcement/homework/notification bodies are unbounded → oversized docs, layout breakage.
104. 🟡 **Class-name canonicalization is heuristic** (spaces→underscores, `split('-')`, `split(' ')` in rules) — a class named "Class 9 - A" vs "Class 9-A" vs "9A" will mismatch attendance keys, classIds membership, and fee structure lookups. No single canonical class-name function.
105. 🟡 **Section can be empty string OR absent** and the two are handled differently across rules/services (`userStudentSection() == '' || == null`, `firestore.rules:107`) — a guardian whose section is stored as `null` vs `''` may fail `guardianStudentId()` matching and lose access to remarks/consents.
106. 🔵 **`DateTime(year, month, day)` with non-padded month in keys** is consistent but the offline sync re-parses `dateKey.split('-')` (`offline_queue_service.dart:103`) — a class name with a digit-only segment is safe, but the parser assumes exactly `Y-M-D` tail; a malformed key throws inside sync.
107. 🔵 **No validation that `maxMarks > 0`** before computing percentages → division-by-zero / NaN on report cards if an exam is misconfigured.

## L. Platform, config, compliance

108. 🟠 **Parental-consent feature exists** (`parental_consent.dart`, consent rules) **but consent is not enforced as a gate** — there's no check that prevents processing a child's data (attendance, photos, messaging) before consent is recorded. For minors' PII this is a compliance gap (DPDP Act, India).
109. 🟠 **No privacy policy / data-retention enforcement.** `privacy_notice.dart` exists but data (notifications, audit logs, attendance, deleted-student tombstones) is retained indefinitely with no purge schedule.
110. 🟡 **Guardian PII (email, phone, name) readable by all management in school** (`firestore.rules:370-373`) with no field-level minimization or access logging beyond audit.
111. 🟡 **`firebase.json` / indexes**: verify `firestore.indexes.json` covers every composite query used (`students` by class+section+teacherId is flagged as needing an index in `student_service.dart:104-105`); a missing index throws at runtime for that role.
112. 🟡 **Hardcoded region `us-central1`** for the callable (`functions/index.js:55`) — for an India-based school, this adds latency to every account operation; consider `asia-south1`.
113. 🔵 **`google-services.json` and `firebase_options.dart` are checked in** (expected for Firebase web/mobile config, low risk) but ensure no service-account keys are in the repo (`functions/scripts`).
114. 🔵 **No crash reporting / analytics** (no Crashlytics in deps) — production crashes will be invisible.

## M. Additional rule-level findings

115. 🟡 **`staff_tasks` create/delete restricted to `principal/admin/owner`** but **not `ownerPrincipal`** (`firestore.rules:1065-1066`) — an owner-principal combined account can't create staff tasks, a silent feature dead-spot for that role.
116. 🟡 **`meetingTasks` update by assignee allows changing only `status`** (`firestore.rules:1373`) but `staff_tasks` allows `status,updatedAt,completedAt,checkpoints` (`1074`) — inconsistent assignee permissions across the two task systems.
117. 🟡 **`student_deletion_requests` excludes coordinators from read** (`firestore.rules:722-723`) even though coordinators are "management" elsewhere — a coordinator who filed via some path can't see status. (Intentional per comment, but surprising.)
118. 🟡 **`leave_applications` class-teacher update allows touching `status,coordinatorNote`** on guardian-submitted student leaves (`firestore.rules:863-868`) — a class teacher can approve student leave, but the *guardian* who submitted gets no rule-enforced notification of the decision.
119. 🟡 **`announcements` teacher-create requires `audience.split(':')[1] in userClassIds`** (`firestore.rules:800`) — but `classIds` canonical form vs the audience class string must match exactly; the heuristic mismatch (K104) will deny legitimate teacher posts.
120. 🔵 **`fee_meta` counter is management-only read/write** (`firestore.rules:946`) — correct, but if a non-management cashier role is ever added, receipts break with a cryptic permission error.

## N. Spot usability issues in high-traffic screens (sampled)

121. 🟡 Attendance screen: no "mark all present" undo / confirmation before bulk save.
122. 🟡 Attendance screen: WhatsApp absent-notice is per-student manual taps — no "notify all absentees" batch.
123. 🟡 Daily-calls screen: `tel:` dial doesn't record call outcome automatically; reasons are saved separately and can desync.
124. 🟡 Student-list WhatsApp button sends with no prefilled message (`student_list_screen.dart:958`) vs attendance which prefills — inconsistent.
125. 🟡 Marks entry: total/percentage shown but no per-subject pass/fail highlight.
126. 🟡 Report card: verify it handles a student missing some subjects' marks (null) without rendering blanks as 0.
127. 🟡 Fee collection: no receipt reprint/share from history visible.
128. 🟡 Onboarding (6 steps): no resume-if-interrupted — verify partial onboarding state persists.
129. 🟡 No "forgot which class I teach" recovery — teacher screen depends on `teacherId`→`teachers` doc; if the teacher doc is missing, splash routes to LoginScreen (`main.dart:283-284`) with no explanation.
130. 🔵 Profile/change-password: re-auth failure message ("requires-recent-login") is technical, not guiding the user to re-login.

## O. Reliability / scale (sampled, need load testing)

131. 🟠 **Coordinator/principal dashboards fan out reads across all classes/students** (`student_service.loadTodayFullSummary` reads every student + N attendance docs; `principal_digest_service` uses collection-group queries). At a 2,000-student school these dashboards will be slow and read-heavy on every open.
132. 🟡 `watchDeletedStudents` caps at 300 (`student_service.dart:163`) — good — but other streams (students, notifications) appear uncapped; a large class/long history pulls everything each snapshot.
133. 🟡 No pagination on student lists, notifications, or audit logs.
134. 🟡 Parallel `Future.wait` over per-day attendance (e.g. `loadMonthAttendance` fires ~31 reads, `loadConsecutiveAbsenceDays` ~20, `loadRecentAbsenceDays` ~14) — multiplied across classes on a dashboard this is a read storm.
135. 🔵 `getClassSummaries`/`getFeesSummary` load ALL students then per-class per-roll — quadratic-ish read amplification (D36).

---

## P. Consolidated lower-severity / polish backlog (136–200)

136. 🔵 CLAUDE.md attendance doc-ID format ("YYYY-M-D") documents the non-padded format — propagate a single `dateKey()` util instead of inlined string interpolation in ≥6 places.
137. 🔵 Duplicate email regex in app + functions — extract to shared constant/config.
138. 🔵 `friendlyAuthError` default returns raw Firebase `e.message` (`auth_service.dart:325`) — can leak internal detail to users.
139. 🔵 No "resend invite" rate limiting — `resendInvitationEmail`/`sendPasswordResetEmail` can be spammed (cost + user annoyance).
140. 🔵 `sendPasswordEmailViaFunction(invite:)` param is dead (`auth_service.dart:83-86`) — misleading API surface.
141. 🔵 Deprecated `@Deprecated` password method still present (`timetable_service.dart:509`) — remove dead code.
142. 🔵 `_visibleOnly` filtering happens client-side after fetch (`student_service.dart:73`) — deletion-pending students are still downloaded; not a leak (staff-only) but wasteful.
143. 🔵 Tombstones in `deleted_students` duplicate guardian email — PII retained post-deletion with no purge (ties to L109).
144. 🔵 `markStudentsDeletionPending` swallows per-student failures (`student_service.dart:410-412`) — a student stuck "pending deletion" after a rejected request is invisible.
145. 🔵 No confirmation that guardian link removal succeeded before `removeAllowedUser` (`student_service.dart:367-369`) — a multi-child guardian could be de-provisioned if a link read fails.
146. 🔵 `getStudentsByClass` with `teacherId` "may require composite index" comment (`student_service.dart:104`) — ship the index or the coordinator/teacher view throws first-run.
147. 🔵 Attendance reasons (`saveReasons`) and called (`saveCalled`) are separate writes to the same doc — 3 round-trips to fully save one day; batch them.
148. 🔵 `loadTodayAttendance` migrates legacy bool→string on read but never writes back — every read re-migrates (minor compute).
149. 🔵 No upper bound on remark history per student — `getStudentRemarks` fetches all.
150. 🔵 `StudentNote.phone` defaults to first non-empty of parentPhone/phone (`fee_service.dart:305`) — inconsistent precedence vs other screens that use `phone` only.
151. 🔵 Defaulter list has no de-dup if a student appears in multiple fee buckets.
152. 🔵 `getFeesSummary` skips classes with `totalDue<=0` (`fee_service.dart:289`) — students in a fee-free class vanish from counts entirely (may understate enrollment-based metrics).
153. 🔵 Receipt number format embeds `DateTime.now().year` (`fee_service.dart:111`) — a payment recorded just after midnight Jan 1 for the prior academic year gets the new calendar year prefix.
154. 🔵 No idempotency on `saveFeeStructure` audit — repeated identical saves create churn audit entries.
155. 🔵 No validation that installment amounts sum to `totalAnnualFee`.
156. 🔵 Exam `maxMarks` is single per exam (`marks_entry_screen.dart:122`) — can't have different max per subject in one exam.
157. 🔵 No "exam published" gate — guardians may see results the instant a teacher saves a partial mark sheet.
158. 🔵 `_cascadeDeleteExamResults` only deletes the `students/{roll}` leaf, not any aggregate stored on the parent `exam_results/{examId}` doc.
159. 🔵 Leaderboard entries are management-written only (`firestore.rules:1390-1392`) — no automatic recompute on new marks; stale standings.
160. 🔵 `birthday_service` — verify it respects guardian privacy (broadcasting a child's birthday to a class audience without consent).
161. 🔵 `analytics_screen` — confirm charts handle zero-data without rendering empty axes/NaN.
162. 🔵 `audit_log_screen` readable by coordinator (`firestore.rules:1298`) — coordinators can see fee/role-change audit they may not need; consider scoping.
163. 🔵 `index_building_notice` widget implies users see raw "index building" — ensure it's friendly, not a Firebase console link.
164. 🔵 `consent_pending_banner`/`todo_reminder_banner` — verify they don't stack and crowd small screens.
165. 🔵 No deep-link handling — notifications can't open the relevant screen (no `firebase_messaging` tap routing visible).
166. 🔵 `firebase_messaging` is a dependency but there's "no push server" (per CLAUDE.md) — dead weight or half-wired FCM; tokens saved (`users/{uid}`) but unused → user confusion about why they get no pushes.
167. 🔵 No "mark all read" for notifications.
168. 🔵 Announcement templates (`announcement_templates.dart`) are English-only.
169. 🔵 `role_selection_screen` shown to guardians with no child in session (`main.dart:269`) — confusing dead-end if they truly have no linked child.
170. 🔵 `admin_login_screen` + `admin_screen` exist separately from the in-login admin dialog (`login_screen.dart:219`) — two admin entry points, maintenance hazard.
171. 🔵 `staff_directory_helpers` / owner screens — verify owner can't accidentally cross schools in UI now that rules forbid it (UI may still list cross-school data and then fail on tap).
172. 🔵 No "school logo/branding" per tenant — single hardcoded theme; multi-school deployments look identical.
173. 🔵 `pdf_theme`/`report_card_pdf_builder` — verify Unicode (Hindi names) render in the chosen PDF font, else garbled report cards.
174. 🔵 Share/export uses `share_plus` — ensure temp files are cleaned and not world-readable.
175. 🔵 `image_picker`/`flutter_image_compress` — enforce the 15 MB storage cap client-side before upload to avoid failed uploads after a long compress.
176. 🔵 No EXIF stripping on uploaded policy/photo images — location metadata leak.
177. 🔵 `connectivity_plus` used for offline queue — verify a captive-portal "connected but no internet" doesn't falsely trigger sync.
178. 🔵 `url_launcher` `tel:`/`wa.me` not validated against injection (phone from Firestore concatenated into URL) — sanitize.
179. 🔵 `android_intent_plus` usage — verify intents are not exported/abusable.
180. 🔵 No biometric/app-lock option for staff devices holding student PII.
181. 🔵 `secure_password` excludes ambiguous chars (good) but 20-char symbol set includes `$%^&*` which some email clients mangle in invite display (cosmetic; user resets anyway).
182. 🔵 Temp password is generated but the *invite email is Firebase's generic reset template* (`auth_service.dart:83-86`) — guardians get a "reset your password" email for an account they never knew existed; confusing onboarding copy.
183. 🔵 `forgot_password_screen` neutral message is good (anti-enumeration) but offers no "didn't get it? check spam / contact admin" guidance.
184. 🔵 `phone_otp_screen` — verify OTP resend cooldown and that OTP isn't logged.
185. 🔵 `guardian_login_screen` vs `login_screen` — two login UIs; ensure consistent error styling/branding.
186. 🔵 No terms-of-use / version / "about" screen for support.
187. 🔵 No in-app way to report a problem / contact support.
188. 🔵 `app_logger` — confirm it doesn't log PII (emails, phones, marks) to device logs in release.
189. 🔵 `template_seeds`/`student_data` (`lib/data/`) — confirm no real student PII is seeded/checked into the repo.
190. 🔵 `dropdown_options_service` cache cleared on logout but not on school switch within a session (owner viewing multiple schools) — stale options.
191. 🔵 `school_settings_provider` `whatsappEnabled` default false — but WhatsApp buttons appear unconditionally on attendance/calls screens; the setting isn't checked at the button (G63).
192. 🔵 No rate limit on remark/announcement creation — a compromised teacher account can spam guardians.
193. 🔵 `copy_check` statuses store `guardianPhone` (per rules comment, `firestore.rules:1023`) — PII in a staff-only collection with no purge.
194. 🔵 `substitution_history` root collection grows unbounded; reads are school-filtered but no archival.
195. 🔵 `feeReminders` audit collection — management-only, but no UI to review whether reminders actually reached guardians.
196. 🔵 `principal_digest_service` collection-group queries require the `schoolId` where-clause on every leaf (`firestore.rules:1466-1474`) — one missed filter makes the whole digest fail with permission-denied.
197. 🔵 No automated test coverage visible for the security rules (no emulator test suite referenced) — rules are complex and have already regressed once (the 1000-expression incident).
198. 🔵 `flutter analyze` / lints — run and gate CI; 157 raw colors and dead code suggest lints aren't enforced.
199. 🔵 No environment separation (dev/staging/prod) — single Firebase project `attendanceapp-e76e1`; testing against production data risk.
200. 🔵 **Deployment gap (from project memory): `firestore.rules` and `functions` were not yet deployed.** Until they are, the app may be running on permissive/old rules — making A1–A16 and every "rules enforce X" assumption potentially void in production *right now*. Verify live rules + function version before launch.

---

### Top 10 to fix before any real school touches this
1. (#1–3) `deleteAccount` role-hierarchy + full-school-wipe safeguards.
2. (#200) Confirm rules & functions are actually deployed.
3. (#5) Lock down notification creation (phishing).
4. (#6–10) Close cross-tenant root-collection / storage leaks.
5. (#31–32) Money as integer paise + correct "collected" total.
6. (#43–45) Attendance timezone + holiday/working-Saturday handling + no silent overwrite.
7. (#62–63) WhatsApp country code + consent-gated messaging.
8. (#69–71) Bulk import, year rollover, data export (adoption blockers).
9. (#79) i18n the app (Hindi) before claiming bilingual support.
10. (#108) Enforce parental consent as an actual processing gate (DPDP compliance).

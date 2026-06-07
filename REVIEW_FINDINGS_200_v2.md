# School App — 200-Issue Review (v2, against current `main` @ 9f891cf)

Perspective: principal · coordinator · teacher · guardian.
Scope: `lib/` (87 screens), `firestore.rules`, `storage.rules`, `functions/index.js`.
Severity: 🔴 critical · 🟠 high · 🟡 medium · 🔵 low/polish.

> This is a **re-review of `main` after this session's fix pass**. The headline criticals from v1 are now FIXED in code (see "Already fixed" below) — so this list is the *next layer*: what survives the fixes, plus new findings. Several items still depend on the deployed rules/functions being the ones in this repo.

## Already fixed on `main` (do NOT re-report)
deleteAccount role hierarchy · notification-create phishing lockdown · copy_checks/calendar/homework/tasks cross-tenant scoping · staff_tasks ownerPrincipal · integer-paise money + correct "collected" total · attendance IST timezone + working-week leave + crash-safe roll parsing + no-overwrite-Present · WhatsApp country code · idle lock · CSV export + import hardening · year-rollover/promotion + stable admissionId · consent gate on all WhatsApp sends · i18n on 7 auth/entry screens.

---

## A. Security & privacy (still open / new)

1. 🟠 **Audit-log poisoning** — any school member can `create` `audit_logs` with arbitrary `action/entity/before/after`; only `actorUid` is pinned. No rate limit. Proper fix: emit audit server-side (Cloud Function / Admin SDK).
2. 🟠 **No Firebase App Check** (`grep app_check` → 0). A signed-in guardian can script-scrape everything their rules allow; OTP/abuse endpoints have no attestation. Enable App Check.
3. 🟠 **Storage `policy/` assets are cross-tenant + unthrottled** — any signed-in user (any school) can read/write `schools/{anySid}/policy/...` up to 15 MB (Storage rules can't read Firestore roles without custom claims). Mint role/schoolId custom claims and gate on them.
4. 🟠 **Root-admin is a single hardcoded Gmail** in app + rules + function. Compromise of that one account owns every school; can't be rotated without a coordinated redeploy.
5. 🟡 **`classIdInList` grade-wildcard** — a teacher whose `classIds` holds the bare grade ("Class 9") is treated as class-teacher of *every* section (9-A/B/C). Intended for grade leads? Currently silent/ungated.
6. 🟡 **Suspended/fired staff retain access offline** — splash-gate revalidation keeps cached routing when the `allowed_users` read throws (offline), so a dismissed teacher in airplane mode keeps local access until reconnect or the 7-day window.
7. 🟡 **Phone-OTP guardians never revalidated on resume** (no session email) — a guardian whose child was removed keeps routing into a now-permission-denied dashboard (broken UI) until 7-day timeout.
8. 🟡 **7-day timeout trusts device clock** — a rolled-back clock defeats it.
9. 🟡 **`friendlyAuthError` default leaks raw `e.message`** to users.
10. 🟡 **No re-auth audit on successful self password change** (only admin-sent resets are logged).
11. 🟡 **Guardian PII (email/phone/name) readable by all in-school management** with no field minimization or access logging beyond audit.
12. 🔵 **Duplicate email regex** in app (`validators.dart`) and `functions/index.js` — drift risk.
13. 🔵 **No EXIF stripping** on uploaded policy/photo images — location-metadata leak.
14. 🔵 **`url_launcher` builds `tel:`/`wa.me` from Firestore phone** without sanitizing for injection (mostly mitigated by digits-only, but `tel:` uses raw phone).
15. 🔵 **No biometric / app-lock** option for shared staff devices holding student PII.
16. 🔵 **No rate limit on remark/announcement/notification creation** — a compromised teacher account can spam guardians.

## B. Compliance & data lifecycle

17. 🟠 **Consent gate is partial** — enforced on WhatsApp sends only. Attendance/exam/photo *processing* and the data stored in Firestore are not gated on consent; no "block processing until consent" for new minors (DPDP Act).
18. 🟠 **No data-retention/purge policy** — notifications, audit logs, attendance, `deleted_students` tombstones (which retain guardian email/phone) grow forever with no deletion schedule.
19. 🟡 **No per-school data export of statutory registers** beyond the new CSV (attendance register, fee ledger PDF, mark sheets) — schools need printable official registers.
20. 🟡 **No privacy policy / consent-withdrawal UX surfaced** to guardians beyond the banner; withdrawal workflow exists but isn't discoverable.
21. 🔵 **`deleted_students` tombstones keep guardian email/phone** indefinitely (ties to #18).
22. 🔵 **`app_logger`** — confirm it never logs PII (emails/phones/marks) in release builds.
23. 🔵 **`lib/data/student_data.dart` / template_seeds** — confirm no real student PII is seeded/checked into the repo.

## C. Business logic — fees

24. 🟠 **No over-payment / double-charge guard** — `addPayment` accepts any amount with no check against remaining balance; a cashier can record more than due and nothing flags it.
25. 🟠 **Fee reports are O(students) reads** — `getClassFeeOverview`/`getFeesSummary` fan out per-roll `getPayments`; a 1,000-student school does ~1,000+ reads per dashboard open. Pre-aggregate.
26. 🟡 **Reversed payments have no void marker on the receipt** — the gapless receipt number stays "used" with no visible void; auditors expect voided numbers.
27. 🟡 **Fee structure is class-level only** — no sibling discount, scholarship, or per-student override beyond the optional `feeAmount`.
28. 🟡 **No version/history on `saveFeeStructure`** — a mid-year revision destroys the schedule prior receipts were issued against.
29. 🟡 **`installmentName` is free-text on the payment** — a typo silently creates a phantom installment bucket.
30. 🟡 **No validation installment amounts sum to the annual fee.**
31. 🔵 **Currency not `NumberFormat`-grouped** — large amounts render `123456.0` not Indian `1,23,456.00` (129 `toStringAsFixed` sites).
32. 🔵 **Receipt prefix uses `DateTime.now().year`** — a payment just after midnight Jan 1 for the prior academic year gets the new calendar-year prefix.
33. 🔵 **No payment-mode reconciliation totals** (cash/UPI/cheque) on the overview despite mode dropdowns.

## D. Business logic — attendance / exams / students

34. 🟠 **Attendance has no lock/cutoff** — any class teacher or management can rewrite historical attendance indefinitely (audited, but no "finalized after N days" guard).
35. 🟠 **`removeStudent` cascade is non-transactional best-effort** — an interruption leaves orphaned fee/exam records that still surface in totals; `approveDeletionRequest` loops it sequentially with no atomicity.
36. 🔴 **Report-card division-by-zero** — `report_card_pdf_builder.dart:345` `marks / maxMarks * 100` with no `maxMarks > 0` guard → Infinity/NaN on the report card if an exam is misconfigured with maxMarks 0.
37. 🟠 **No "absent in exam" state** distinct from blank marks — report cards can't tell "not entered" from "absent (0)".
38. 🟡 **No grade-boundary config surfaced per school** beyond template `gradeScheme`; verify every percentage path uses it (some fall back to `result.grade`).
39. 🟡 **Roll-as-identity in guardian-facing messages** — if rolls are reassigned across years a message can misidentify the child (mitigated by new `admissionId`, but messages still use roll).
40. 🟡 **`updateStudent` has no duplicate-roll guard** — moving a student to a section where the roll already exists creates a collision (add-time guard only).
41. 🟡 **No holiday-calendar awareness in leave** — `markLeaveForDateRange` now respects the working-week setting but still ignores one-off declared holidays.
42. 🔵 **Consecutive-absence streak treats unmarked days as "skip"** — can inflate a streak across non-attended gaps.
43. 🔵 **Promotion carries `feeAmount` override** to the new class (copyWith semantics) — a per-student override may be wrong for the new class.

## E. Workflow gaps

44. 🟠 **Teacher-deletion has two paths** — the approval workflow (`teacher_deletion_requests`) AND `deleteAccount` (coordinator can now delete a teacher directly within hierarchy). The approval flow is still bypassable for teachers.
45. 🟠 **Approved leave doesn't auto-mark attendance** — leave approval and attendance are disconnected; staff must run the leave-range tool manually.
46. 🟡 **Guardian detail-correction submissions have no staff notification/badge** — staff must happen to open the student to see them.
47. 🟡 **Substitution suggester** — verify it excludes teachers who are themselves on leave that day.
48. 🟡 **Two separate task systems** (`tasks` class-tasks vs `staff_tasks`) with separate screens/rules — staff see two task inboxes; the `tasks` collection has no create path in-app (half-removed feature).
49. 🟡 **Reversed payments have no "show reversed" view** for reconciliation.
50. 🔵 **No draft state for announcements/homework** — posting is immediate; edit = delete+repost which re-fans-out notifications.
51. 🔵 **No "promote" reversal** — the new promotion archives the source; there's no undo if done wrong (only manual fix).

## F. Notifications / messaging

52. 🟠 **FCM is half-wired** — `requestPermission` + `onBackgroundMessage` + `saveFcmToken` exist, but CLAUDE.md says there's no push server, so tokens are stored and permission is requested yet no push is ever sent. Either ship a sender or remove the dead wiring (user confusion: "why no notifications?").
53. 🟡 **Unread state is per-device SharedPreferences** — reinstall/new device/cache-clear marks everything unread again; reading on one device doesn't clear another.
54. 🟡 **Notification audience matching is `split(':')`** — a class name containing `:` breaks targeting/authorization; no validation forbids `:` in class names.
55. 🟡 **`whereIn` audience query caps at 10/30** — a multi-child guardian + roles could exceed the limit and throw.
56. 🔵 **No notification retention/cleanup** beyond per-student delete on removal.
57. 🔵 **WhatsApp/phone buttons fail silently** when the app isn't installed in some sites (no else/toast).

## G. Usability / UX

58. 🟠 **i18n still 7 of 87 screens** — every dashboard, attendance, fees, marks, homework, announcements screen is hardcoded English despite Hindi support. The Hindi-first staff/guardians still see English everywhere post-login.
59. 🟠 **157 raw `Color(0x...)` literals** across screens/widgets violate the AppTheme single-source rule — inconsistent theming, no dark-mode/accessibility path, brand drift.
60. 🟡 **27 silent `catch (_) {}`** swallow errors with no user feedback or log — failed saves/syncs look like success.
61. 🟡 **~12 of 33 Stream/FutureBuilders lack `hasError`** — show a spinner or blank on error instead of an actionable state.
62. 🟡 **No pagination** on student lists, notifications, audit logs, fee history (only 9 `.limit()` calls total in services).
63. 🟡 **666 `await`s vs 488 `mounted` refs in screens** — audit for unguarded `setState`/`context` after await (crash on disposed widget).
64. 🟡 **No offline indicator** on most screens despite the attendance offline queue — users don't know if a save is queued or live.
65. 🟡 **Locale-naive date/number formatting** — hand-indexed months, `toStringAsFixed`, no `intl` grouping.
66. 🔵 **No accessibility semantics** (labels on icon-only buttons, tap-target sizes, font-scaling already clamped 0.8–1.2).
67. 🔵 **No search/filter** on long lists beyond class scoping in several screens.
68. 🔵 **PDF generation has no progress/cancel** for large batches.
69. 🔵 **Destructive actions** — confirm every delete/reverse/archive has a confirmation (student delete, payment reversal, account delete, promotion, clear-all notifications).
70. 🔵 **Empty-state inconsistency** across list screens.

## H. Reliability / scale / ops

71. 🟠 **No crash reporting** (no Crashlytics/Sentry in deps) — production crashes are invisible.
72. 🟠 **Dashboards fan out reads across all classes/students** (coordinator summary, principal digest collection-group queries) — slow + read-heavy at 2,000 students on every open.
73. 🟡 **`TimetableService._settingsCache`** only invalidates on same-session `saveSettings` — another admin's change isn't seen until restart.
74. 🟡 **Parallel per-day attendance reads** (month ≈31, recent ≈14, consecutive ≈20) multiplied across classes = read storms.
75. 🟡 **No environment separation** (single Firebase project for dev/prod) — testing risks production data.
76. 🟡 **No automated security-rules test suite** — complex rules have regressed before (the 1000-expression incident, a `)` syntax error caught at deploy).
77. 🟡 **`flutter analyze` not gated in CI** — 157 raw colors + 2 standing info lints + dead code suggest lints aren't enforced.
78. 🔵 **Region `us-central1`** for the callable adds latency for India; consider `asia-south1`.
79. 🔵 **No force-upgrade / min-version gate** — old app builds hitting new schoolId-filtered rules get permission-denied.
80. 🔵 **25 `int.parse` sites remain** (down from 33) — latent crashes on malformed Firestore data outside attendance.

---

## I. Module spot-findings (81–140)

81. 🟡 birthday_service uses `DateTime.now()` (device tz) — inconsistent with attendance's IST anchor; a child's birthday "today" can differ from the school's day.
82. 🔵 birthday_service broadcasts a child's birthday to a class audience — verify consent/opt-out.
83. 🟡 leaderboard entries are management-written only — no auto-recompute on new marks → stale standings.
84. 🟡 leaderboard exposes per-student ranking — confirm it's not visible to other guardians (privacy/comparison concerns).
85. 🔵 calendar_events is a global (cross-school) collection by design — holidays of one school appear for all in a multi-tenant deploy.
86. 🟡 analytics_screen — verify charts handle zero-data without NaN/empty-axis (`structure.totalAnnualFee as double` cast and per-class division).
87. 🔵 analytics fan-out mirrors fee/attendance read amplification.
88. 🟡 onboarding (6 steps) — confirm partial progress persists if interrupted (draft save exists; verify resume).
89. 🔵 onboarding step4 fees parse `int.tryParse` ok, but no upper bounds / negative guards on late-fee per day.
90. 🟡 report_card_pdf_builder — verify Hindi/Unicode student names render (font embedding) or report cards garble.
91. 🔵 report card shows blank vs 0 for missing subject marks — clarify.
92. 🟡 exam maxMarks is single per exam — can't set different max per subject.
93. 🔵 no "exam published" gate — guardians may see results the instant a teacher saves a partial mark sheet.
94. 🟡 marks recompute / fee-status recompute jobs — verify they're idempotent and don't race with manual edits.
95. 🔵 meeting tasks vs staff tasks assignee permissions differ (status-only vs status+checkpoints) — inconsistent.
96. 🟡 principal digest collection-group queries require a `schoolId` where-clause on every leaf — one missed filter fails the whole digest with permission-denied.
97. 🔵 substitution_history grows unbounded; reads school-filtered but no archival.
98. 🔵 feeReminders audit has no UI to confirm reminders actually reached guardians.
99. 🟡 copy_check statuses store `guardianPhone` (PII) in a staff-only collection with no purge.
100. 🔵 homework/announcement bodies are unbounded length → oversized docs / layout breakage (remarks are capped at 200; others aren't).
101. 🟡 class-name canonicalization is heuristic (spaces↔underscores, split('-'), split(' ')) across rules/services — "Class 9 - A" vs "Class 9-A" vs "9A" mismatch attendance keys, classIds, fee lookups. No single canonical function.
102. 🟡 section stored as `''` vs `null` handled differently across rules/services — a guardian with a null section may fail `guardianStudentId()` matching and lose remarks/consents access.
103. 🔵 email-keyed `allowed_users` means an email change orphans the account (doc id can't change).
104. 🔵 guardian session stores only one child; multi-child guardians land on child #1 and switch manually; deep links can't target the right child.
105. 🟡 `markUserActive` on login is fire-and-forget (no await) — a failure leaves status 'pending' and re-attempts each login.
106. 🔵 no "resend invite" rate limiting — reset/invite emails can be spammed (cost + annoyance).
107. 🔵 deprecated/dead code remains (e.g., `@Deprecated` password method in timetable_service; FCM wiring).
108. 🟡 offline queue last-write-wins silently clobbers a co-teacher's edits on sync (no merge/conflict notice).
109. 🔵 attendance date keys non-zero-padded ("2026-6-4") — internally consistent but breaks any lexicographic ordering/export.
110. 🟡 `getStudentsByClass` with `teacherId` needs the composite index (now deployed) — ensure other role views don't silently rely on a missing index.
111. 🔵 `_cascadeDeleteAttendance` upper-bound sentinel `■` — undocumented edge for class names above it.
112. 🟡 no validation that a promoted target class exists / has a fee structure — students land in a class with no fees configured.
113. 🔵 promotion assigns target class teacher by `classTeacherOf==class && section` match — if none configured, records stay unowned (invisible to teacher-scoped roster until assigned).
114. 🔵 `staff_remarks` immutable (no edit) — a typo can't be corrected, only deleted+recreated.
115. 🟡 leave application body length unbounded; no attachment support for medical certificates.
116. 🔵 `dropdown_options` cache not cleared on in-session school switch (owner viewing multiple schools).
117. 🔵 `school_settings_provider.whatsappEnabled` default false, but WhatsApp buttons render unconditionally — setting isn't checked at the button (consent gate now blocks send, but the toggle is still ignored).
118. 🟡 no audit of fee reversals' reason being required — `deletePayment` reason is optional.
119. 🔵 announcement templates are English-only.
120. 🔵 no "about/version/support" screen; no in-app problem reporting.
121. 🟡 deep-link from notification tap doesn't open the relevant screen (no FCM tap routing).
122. 🔵 `index_building_notice` — ensure it's friendly, not a raw console link.
123. 🔵 consent/todo/reminder banners may stack and crowd small screens.
124. 🟡 admin has two entry points (in-login dialog + admin_login_screen/admin_screen) — maintenance hazard.
125. 🔵 owner cross-school UI may still list data then fail on tap now that rules confine owners to their school.
126. 🔵 no per-school logo/branding — multi-school deployments look identical.
127. 🟡 `share_plus` temp files (new CSV export) — ensure cleanup and not world-readable.
128. 🔵 image upload doesn't enforce the 15 MB cap client-side before a long compress → failed upload after waiting.
129. 🔵 `connectivity_plus` "connected but no internet" (captive portal) may falsely trigger offline-queue sync.
130. 🔵 no test coverage visible for services (only widget_test scaffold).
131. 🟡 phone validation/normalization missing at entry — invalid/short numbers silently produce dead `tel:`/`wa.me` links (country code now added, but length isn't validated).
132. 🔵 `secure_password` symbol set includes `$%^&*` which some email clients mangle in invite display (cosmetic; user resets anyway).
133. 🔵 invite email uses Firebase's generic "reset password" template — guardians get a reset email for an account they never knew existed (confusing onboarding copy).
134. 🔵 forgot-password offers no "didn't get it? check spam / contact admin" guidance.
135. 🔵 phone-OTP — verify resend cooldown and that the OTP is never logged.
136. 🟡 no max-length on most free-text fields except remarks → oversized docs / layout breakage.
137. 🔵 `friendlyAuthError` weak-password message hardcodes "6 characters" though temp passwords are 20.
138. 🔵 no keyboard-type hints on many number/phone fields (137 TextFields) — default keyboard for amounts/phones.
139. 🔵 no "mark all read" persistence across devices (ties to #53).
140. 🔵 no bulk "notify all absentees" — absent WhatsApp is per-student manual taps.

## J. Lower-severity / polish backlog (141–200)

141–157. 🔵 Replace the 157 raw `Color(0x…)` literals with `AppTheme.*` (per the project rule) — one finding per offending file; biggest offenders: dashboards, attendance, guardian_dashboard, fee screens.
158. 🔵 Extract a single `dateKey()` util (≥6 inlined date-key interpolations).
159. 🔵 Single canonical `className` normaliser (see #101).
160. 🔵 Centralize money formatting in one `formatRupees()` (Indian grouping).
161. 🔵 Remove dead FCM wiring or ship a sender (#52).
162. 🔵 Remove `@Deprecated` password method + any dead validateLogin remnants.
163. 🔵 Add `.limit()` + pagination to student/notification/audit lists.
164. 🔵 Add `hasError` branches to the ~12 builders missing them.
165. 🔵 Gate `flutter analyze` (and fix the 2 standing `unnecessary_to_list_in_spreads` lints).
166. 🔵 Add Crashlytics.
167. 🔵 Add App Check.
168. 🔵 Move callable to `asia-south1`.
169. 🔵 Add rules unit tests (emulator).
170. 🔵 Add staging Firebase project.
171. 🔵 Add force-upgrade min-version check.
172. 🔵 Add holiday-calendar awareness to leave + attendance "holiday" state.
173. 🔵 Add "absent in exam" mark state.
174. 🔵 Add maxMarks>0 guard (#36) — quick correctness fix.
175. 🔵 Add over-payment guard (#24).
176. 🔵 Add voided-receipt marker (#26).
177. 🔵 Pre-aggregate fee/attendance summaries (read amplification).
178. 🔵 Add per-student/section/scholarship fee overrides.
179. 🔵 Add data-retention purge jobs (notifications/audit/tombstones).
180. 🔵 Enforce consent before storing a new minor's record (#17).
181. 🔵 Continue i18n rollout (next: guardian_dashboard, home_screen, attendance, fees) (#58).
182. 🔵 Add accessibility semantics pass.
183. 🔵 Add offline indicator banner.
184. 🔵 Add bulk "notify all absentees".
185. 🔵 Add notification deep-link routing.
186. 🔵 Add school logo/branding per tenant.
187. 🔵 Add receipt reprint/share from fee history.
188. 🔵 Add "show reversed payments" toggle.
189. 🔵 Add medical-certificate attachment to leave.
190. 🔵 Add phone-number length/format validation at entry.
191. 🔵 Friendly invite-email copy (not generic reset).
192. 🔵 Add about/version/support screen + in-app problem report.
193. 🔵 Add search/filter to long lists.
194. 🔵 Add PDF progress/cancel.
195. 🔵 Cap homework/announcement/leave body lengths.
196. 🔵 EXIF-strip uploaded images.
197. 🔵 Audit AppLogger for PII in release.
198. 🔵 Confirm no real student PII in `lib/data/` seeds.
199. 🔵 Add biometric/app-lock for staff devices.
200. 🔵 Honour `whatsappEnabled` setting at the button, not just at send.

---

### Top 10 to fix next
1. (#36) Report-card division-by-zero — quick correctness bug.
2. (#71) Crash reporting (Crashlytics) — you're flying blind in prod.
3. (#52) Resolve the half-wired FCM (ship a sender or remove).
4. (#24) Fee over-payment guard.
5. (#34/#35) Attendance lock + transactional student-delete cascade.
6. (#17) Consent as a true processing gate (not just WhatsApp).
7. (#2/#3) App Check + Storage custom-claim tenant scoping.
8. (#58/#59) i18n rollout + kill the 157 raw colors.
9. (#25/#72) Pre-aggregate fee/attendance to stop read storms at scale.
10. (#1) Server-side audit emission.

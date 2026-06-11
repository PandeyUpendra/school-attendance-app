# Feature Roadmap

Master list of candidate features, organized by role. Compiled from a full codebase
review (June 2026). Effort tags: **S** = days, **M** = 1–2 weeks, **L** = multi-week.
**[GAP✓]** = confirmed missing in code (not just assumed). *(infra: …)* = reuses
packages/services already in the app.

---

## Cross-role / Platform

| # | Feature | Effort | Notes |
|---|---------|--------|-------|
| 1 | UPI deep-link fee payment | M | `upi://pay` intent via url_launcher; guardian claims → staff confirms; no gateway fees |
| 2 | Automatic absence alert to guardians | S | Cloud Function on attendance write → FCM topic; feeds existing leave flow |
| 3 | WhatsApp share button on every PDF | S | share_plus already integrated; receipts, report cards, certificates |
| 4 | Admit card / hall ticket + datesheet PDF | S | pdf+printing infra proven by report cards |
| 5 | Bonafide & Transfer Certificate generator | S | same PDF infra; pairs with student-exit workflow |
| 6 | Student ID card generator (batch per class) | S | image_picker + pdf; replaces outside vendors |
| 7 | Merit certificate generator | S | leaderboards + PDF pipeline already exist |
| 8 | Syllabus coverage tracker | M | per class-subject chapter checklist; principal sees % covered |
| 9 | Study materials repository | M | file_picker + Storage + compress already wired |
| 10 | Transport module lite (routes, stops, driver contact) | M | no GPS in v1; tap-to-call driver |
| 11 | Health records + incident log | M | blood group, allergies; incident → guardian push |
| 12 | UDISE+ / govt report CSV export | S | csv package present; enrollment by class/gender/category |
| 13 | Announcement read receipts ("seen by 23/40") | S | tiny `seen` write per open |
| 14 | Gate pass / early pickup with approval + push | M | safety feature; guardian request → teacher approve → gate pass |
| 15 | Parent polls & surveys with live tally | S | reuses announcement + notification plumbing |
| 16 | Per-student performance trend charts | S | fl_chart + marks across exams already stored |
| 17 | Digital class diary (one line per class per day) | S | `diary/{classKey}/{dateKey}`; replaces paper diary |
| 18 | Homework completion tracking (done / photo submit) | M | closes the homework loop; per-assignment teacher view |
| 19 | SMS fallback for non-smartphone guardians | M | critical alerts via SMS gateway when no FCM token |
| 20 | Academic year close / rollover wizard | M | end-of-session: promote, archive, carry dues, reset counters |
| 21 | Online MCQ quizzes (auto-graded) | L | teacher creates, students/guardians answer, auto marks |
| 22 | Library lite (book register, issue/return) | M | simple register, due-date reminders via existing push |
| 23 | Event RSVP (sports day, annual function) | S | announcement + votes sub-map |
| 24 | Regional language expansion beyond EN/HI | M | i18n map pattern in lib/l10n/app_strings.dart scales |

## Owner

| # | Feature | Effort | Notes |
|---|---------|--------|-------|
| 1 | Expense tracking → real P&L | M | income side exists in `fees`; add expenses + monthly P&L PDF. Flagship owner feature |
| 2 | Daily cash reconciliation per collector | S | grouping query over payments + "deposited" confirmation; anti-fraud |
| 3 | Receipt void/edit protection (approval + report) | S | targets the classic cancel-receipt fraud; audit_log exists |
| 4 | Carry-forward dues at promotion **[verify promotion_service]** | S | unpaid dues must follow student into new session |
| 5 | Projected cash flow (30/60/90-day expected collections) | S | derive from instalment due dates already stored |
| 6 | Concession/discount approval workflow + annual report | M | who granted what to whom; second leakage point |
| 7 | Teacher punctuality / accountability card | S | aggregate leaves, substitutions caused, overdue tasks |
| 8 | Enrollment trend + dropout alerts with exit reasons | S | wire deletion flow + fl_chart; "Class 7 lost 5 students" |
| 9 | Parent complaint inbox (assigned → resolved, visible status) | M | reputation management; pattern detection |
| 10 | Owner evening digest push (collection, attendance, admissions) | S | clone principal_digest pattern |
| 11 | Staff attendance + salary slip lite | L | check-in via offline-queue pattern; month-end payslip PDF |
| 12 | Admission inquiry tracker (CRM lite) | M | inquiry → visited → admitted funnel; follow-up dates |
| 13 | Student document vault | M | Storage + DPDP consent infra make it defensible |
| 14 | Inventory / asset register | M | benches, projectors, lab equipment; owner-facing |
| 15 | School data backup/export (full CSV/JSON dump) | S | owner peace-of-mind; vendor-lock-in antidote |

## Principal

| # | Feature | Effort | Notes |
|---|---------|--------|-------|
| 1 | Exam result analytics tab **[GAP✓ — analytics is attendance/fees only]** | M | pass %, subject averages, below-40% counts; 5th tab in analytics_screen |
| 2 | Teacher-wise result comparison | S | join timetable (teacher→class→subject) to marks |
| 3 | At-risk student early warning | M | fuse attendance drop + marks fall + remarks |
| 4 | Classroom observation register (rubric + history) | M | staff_remarks is free-text; appraisal season needs structure |
| 5 | Teacher compliance scorecard (per-teacher green/amber/red) | S | attendance marked? homework posted? marks on time? from existing timestamps |
| 6 | Teacher workload balance report | S | periods/week from timetable + substitution load |
| 7 | Question paper approval workflow | M | submit (file upload) → approve/return → lock; mirrors leave-approval pattern |
| 8 | Staff circular acknowledgment ("12 of 15 acknowledged") | S | read-receipt mechanic on announcements, staff-flavored |
| 9 | Inspection pack (one-tap PDF bundle for DEO/board visits) | M | enrollment, attendance, teacher list, meeting minutes |
| 10 | Lesson plan submission & weekly approval | M | pairs with syllabus tracker |

## Coordinator

| # | Feature | Effort | Notes |
|---|---------|--------|-------|
| 1 | Bulk student import via CSV | S | csv package present; onboarding 400 students by hand is brutal |
| 2 | Exam seating / invigilation roster planner | M | rooms × classes × teachers; outputs printable PDFs |
| 3 | Data-correction approval queue | S | receiving end of guardian correction requests |
| 4 | Document verification queue | S | receiving end of guardian document uploads |
| 5 | Timetable conflict detector | S | teacher double-booked / class with no teacher, flagged on save |

## Teacher

| # | Feature | Effort | Notes |
|---|---------|--------|-------|
| 1 | "My class today" morning card | S | aggregates absentees, birthdays, leave requests, duties, copies due — all existing queries |
| 2 | Live "now teaching" strip (current period + countdown) | S | bell timings + timetable already stored |
| 3 | Leave balance view **[GAP✓ — no balance concept in code]** | S | quotas in settings; ledger from approved leave_applications |
| 4 | Canned one-tap notes to a single guardian | S | "forgot copy", "uniform incomplete" → per-student push |
| 5 | Private student notes (never shown to guardians) | S | distinct from shared student_remarks |
| 6 | Report card comment bank | S | category picker, name auto-fill; saves hours per term |
| 7 | Marks entry speedups (auto-advance, max validation, CSV import) | S | marks deadline week is peak stress |
| 8 | Extend offline queue to marks + homework **[GAP✓ — attendance-only]** | M | generalize enqueue/syncAll pattern; prevents lost-marks disasters |
| 9 | Photo roster for substitutes | S | name + photo + roll for an unknown class; needs student photos |
| 10 | Period swap requests (teacher↔teacher, coordinator notified) | M | rides substitution infrastructure |
| 11 | Homework recycling (repeat last, templates, copy to other class) | S | pure QoL on HomeworkService |
| 12 | "My class" analytics (teacher-scoped charts) | S | filtered reuse of analytics_screen widgets |
| 13 | Voice input / audio attachments for remarks & homework | M | Hindi typing pain; speech-to-text or short audio clips |
| 14 | Printable blank registers & mark sheets | S | pdf + printing + student data |
| 15 | Stationery / resource request to admin | S | chalk, markers, projector booking |

## Guardian

| # | Feature | Effort | Notes |
|---|---------|--------|-------|
| 1 | Downloadable fee receipts **[GAP✓ — receipt numbers exist, no guardian UI]** | S | gapless numbering already in fee_service; 80C tax use case |
| 2 | Holiday calendar view **[GAP✓ — calendar_events exists, no guardian screen]** | S | "is school open tomorrow?" — read-only view of existing data |
| 3 | Data correction requests (name spelling, phone, DOB) | S | DPDP right-to-correction; coordinator approves |
| 4 | Multi-year report card archive **[GAP✓ — no session dimension]** | S | stamp session now or history is lost at promotion |
| 5 | Second guardian access (invite flow) | M | father + mother + grandparent on one child |
| 6 | Urgent alert tier (separate channel, bypasses silent) | S | priority field exists but is text-only; rain-day closures |
| 7 | Exam syllabus per exam ("Ch 1–4") | S | one field on exam model |
| 8 | Class-average context on marks | S | "is 65 good?" — anonymous aggregate per exam-subject |
| 9 | Child's leaderboard standing **[GAP✓ — service exists, no guardian UI]** | S | engagement feature already computed, just unshown |
| 10 | Ask-the-teacher query box (ticket-style, one open per child) | M | structured to protect teacher evenings |
| 11 | Weekly child digest push (attendance, homework, dues) | S | guardian-sized principal_digest |
| 12 | Term-start essentials page (booklist, uniform, stationery) | S | cheapest feature on this list |
| 13 | Guardian-side document upload | S | feeds document vault; saves a school visit |
| 14 | Exam countdown reminders ("Maths in 3 days") | S | scheduled Cloud Function over exam dates |
| 15 | Certificate request flow (bonafide etc., with status) | S | request side of the cert generators |
| 16 | Guardian timetable view (child's subjects per day) | S | "pack the bag"; data in timetable collection |

## Deferred / Phase 2

- **Multi-tenancy / multi-school** — already consciously deferred
- **GPS bus tracking** — phase 2 of transport lite
- **Payment gateway (Razorpay etc.)** — phase 2 of UPI deep-link
- **Student login role** — app currently has no student account; senior classes could use one
- **WhatsApp Business API** — official template messages instead of share-sheet
- **Hostel module** — only if a customer school needs it

---

## Top 10 (desperation ÷ effort, across all roles)

1. **Fee receipts for guardians** — numbering exists, UI missing, yearly 80C demand
2. **Holiday calendar for guardians** — data exists, screen missing
3. **Absence auto-alert** — one Cloud Function, daily value for every parent
4. **Exam result analytics for principal** — confirmed gap, foundation for 3 more features
5. **Teacher "my class today" card + leave balance** — daily teacher retention
6. **Daily cash reconciliation for owner** — anti-fraud, mostly queries
7. **Expense tracking / P&L for owner** — transforms app's value proposition
8. **UPI fee payment** — biggest perceived value, no gateway cost
9. **Offline queue extension to marks** — prevents the app-abandoning disaster
10. **WhatsApp share on PDFs** — trivial, instantly visible to everyone

*Strategic note: features that create a daily reason to open the app (morning card,
diary, digests, alerts) compound — they keep users engaged so every other feature
gets seen. Prioritize at least one per role early.*

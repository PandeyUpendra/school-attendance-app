#!/usr/bin/env python3
"""Generate ISSUES_REPORT.pdf — role-based major-issues analysis of the school app."""
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.platypus import (SimpleDocTemplate, Paragraph, Spacer, Table,
                                TableStyle, PageBreak, KeepTogether)

PRIMARY = colors.HexColor("#6A1B9A")
ACCENT = colors.HexColor("#D81B60")
DANGER = colors.HexColor("#C62828")
WARN = colors.HexColor("#E65100")
MED = colors.HexColor("#F9A825")
LOW = colors.HexColor("#1565C0")
GREY = colors.HexColor("#616161")
LIGHT = colors.HexColor("#F3E5F5")

styles = getSampleStyleSheet()
H1 = ParagraphStyle("H1", parent=styles["Title"], textColor=PRIMARY, fontSize=22, spaceAfter=4)
H2 = ParagraphStyle("H2", parent=styles["Heading1"], textColor=PRIMARY, fontSize=15, spaceBefore=14, spaceAfter=6)
H3 = ParagraphStyle("H3", parent=styles["Heading2"], textColor=ACCENT, fontSize=12, spaceBefore=10, spaceAfter=4)
BODY = ParagraphStyle("BODY", parent=styles["Normal"], fontSize=9.5, leading=13, spaceAfter=4)
SMALL = ParagraphStyle("SMALL", parent=styles["Normal"], fontSize=8.5, leading=11.5, textColor=GREY)
CELL = ParagraphStyle("CELL", parent=styles["Normal"], fontSize=8.8, leading=11.5)
SEV = {"CRITICAL": DANGER, "HIGH": WARN, "MEDIUM": MED, "LOW": LOW}


def sev_para(s):
    return Paragraph(f'<font color="{SEV[s].hexval()}"><b>{s}</b></font>', CELL)


def issue_table(rows):
    data = [[Paragraph("<b>#</b>", CELL), Paragraph("<b>Severity</b>", CELL),
             Paragraph("<b>Issue</b>", CELL)]]
    for i, (sev, title, detail) in enumerate(rows, 1):
        data.append([Paragraph(str(i), CELL), sev_para(sev),
                     Paragraph(f"<b>{title}</b><br/>{detail}", CELL)])
    t = Table(data, colWidths=[9 * mm, 22 * mm, 139 * mm], repeatRows=1)
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), LIGHT),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("GRID", (0, 0), (-1, -1), 0.4, colors.HexColor("#D1C4E9")),
        ("LEFTPADDING", (0, 0), (-1, -1), 4),
        ("RIGHTPADDING", (0, 0), (-1, -1), 4),
        ("TOPPADDING", (0, 0), (-1, -1), 3),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#FAF7FC")]),
    ]))
    return t


story = []
story.append(Paragraph("School App — Major Issues Report", H1))
story.append(Paragraph("Role-based codebase analysis · Owner / Principal / Teacher / Guardian · 11 June 2026", SMALL))
story.append(Spacer(1, 6))
story.append(Paragraph(
    "Scope: full repository on <b>main</b> (~88,000 lines of Dart across 89 screens, 35 services, "
    "Firestore + Storage rules, 12 Cloud Functions). This report lists what is <b>still open</b>. "
    "Findings were verified against the current code, not copied from earlier review documents — "
    "a large number of previously reported issues are confirmed fixed and are summarised first.", BODY))

story.append(Paragraph("Confirmed already resolved (verified in current code)", H2))
story.append(Paragraph(
    "Firebase App Check (Play Integrity / App Attest) · Crashlytics crash reporting · "
    "server-side audit-log writer with client create denied and append-only rules · "
    "fee pre-aggregation (one read per class, not per student) · over-payment cap with explicit override · "
    "atomic gapless receipt numbering · payment reversal kept as void (never hard-deleted) with reconciliation view · "
    "installment-sum-equals-annual-fee validation · attendance lock/cutoff for historical dates · "
    "exam publish gate (guardians see results only after publishedAt) · report-card maxMarks&gt;0 guard · "
    "Storage rules tenant-scoped via schoolId custom claims · friendly auth errors (no raw message leak) · "
    "multi-child guardian switcher · student leave approval auto-marks attendance · "
    "holiday calendar service · i18n on 82 of 89 screens · zero raw Color(0x…) literals · "
    "12 unit-test files + Firestore rules test suites · purgeOldData retention callable · "
    "homework/leave body length caps · WhatsApp-enabled setting honoured at buttons · "
    "password-reuse / email-hijack prevention on user recreation.", BODY))

story.append(Paragraph("How to read this report", H3))
story.append(Paragraph(
    "<b>CRITICAL</b> = fix before relying on the app in production · <b>HIGH</b> = significant money/safety/usability risk · "
    "<b>MEDIUM</b> = real but containable · <b>LOW</b> = polish/backlog. Items marked <i>(verify)</i> could not be fully "
    "confirmed from code alone and need a quick manual check.", SMALL))

# ───────────────────────────── Section A ─────────────────────────────
story.append(Paragraph("A. Platform &amp; operations (affects every role)", H2))
story.append(issue_table([
    ("CRITICAL", "Deployed rules/functions may not match the repository",
     "The hardened firestore.rules, storage.rules and functions/index.js exist locally, but session records indicate they "
     "have not all been deployed to project attendanceapp-e76e1. Until deployed, production runs on the OLD rules — every "
     "security fix in the repo is inert. Storage rules additionally have a hard deploy-order dependency: run the claims "
     "backfill script and deploy syncUserClaims BEFORE the storage rules, or every user is locked out of Storage."),
    ("CRITICAL", "Single Firebase project for development and production",
     "firebase_options.dart points only at attendanceapp-e76e1; no staging project or build flavors. Every test run, rules "
     "experiment and migration rehearses directly against live school data. One bad write or rules deploy hits real "
     "students. Create a separate staging project and a flavor/dart-define switch."),
    ("HIGH", "No CI pipeline",
     "No .github/workflows (or equivalent). flutter analyze, the 12 unit-test files and the Firestore rules test suites all "
     "exist but nothing runs them automatically — a regression reaches main and deploy unchecked. A 30-line GitHub Action "
     "(analyze + test + rules tests) closes this."),
    ("HIGH", "Root-admin trust anchored to two hardcoded Gmail addresses",
     "mandvishal@gmail.com / admin@schoolapp.org are literal strings in auth_service.dart, functions/index.js, "
     "firestore.rules and storage.rules. The app side now has a bootstrap-config fallback, but the rules files still "
     "hardcode them: compromise of either mailbox owns every school, and rotation requires a coordinated 4-file redeploy."),
    ("HIGH", "Notification tap does nothing useful",
     "No onMessageOpenedApp / getInitialMessage handler exists. Push notifications deliver, but tapping one opens the app "
     "at the splash/dashboard root instead of the announcement, leave request or fee reminder it announced. This halves "
     "the value of the entire push pipeline for every role."),
    ("HIGH", "All Cloud Functions in us-central1",
     "Every callable and trigger is pinned to us-central1 while the user base is in India — 250–400 ms extra latency on "
     "every OTP, user-create, audit write and push fan-out. Move to asia-south1 (Mumbai)."),
    ("MEDIUM", "19 silent catch (_) {} blocks remain",
     "Across 9 files including fee_service, push_service, timetable_service, leaderboard_service and 4 screens. A failed "
     "fee-summary update or push-token sync looks identical to success. Each should at least log to Crashlytics."),
    ("MEDIUM", "Two parallel task systems still wired",
     "task_service (class tasks) and staff_task_service coexist with separate screens, rules and inboxes. Staff see two "
     "task lists; every rules/feature change must be done twice. Pick one and migrate."),
    ("MEDIUM", "Notification unread state is per-device",
     "Unread tracking is a SharedPreferences timestamp: reinstalling or switching phones marks everything unread; reading "
     "on one device clears nothing elsewhere. Needs a per-user lastSeen in Firestore."),
    ("MEDIUM", "Stale-session edge cases",
     "(a) Dismissed/suspended staff keep cached offline access for up to 7 days (splash revalidation passes when the "
     "allowed_users read throws offline). (b) The 7-day window trusts the device clock — rolling the clock back defeats "
     "it. (c) Phone-OTP guardians are never revalidated on resume (no email key), so a revoked guardian keeps a broken "
     "dashboard until timeout."),
    ("MEDIUM", "Multi-tenancy fallbacks are landmines",
     "Multi-school support is consciously deferred, but eight call sites still silently fall back to '?? school_1' "
     "(owner_principal_home ×4, auth_service, student_service, push_service, admin_login_screen). The day a second school "
     "onboards, any missed session-restore path quietly writes into school_1's data. Replace fallbacks with a loud throw."),
    ("MEDIUM", "No EXIF stripping on image uploads",
     "Teacher/policy/logo photos are compressed but EXIF (incl. GPS location) is not stripped — location metadata of "
     "whoever took the photo can leak to anyone in the school who can view it."),
    ("MEDIUM", "No biometric / app-lock option",
     "Staff phones holding the PII of hundreds of children rely only on the OS lock screen; no local_auth in pubspec. An "
     "optional PIN/biometric gate on app open is cheap insurance."),
    ("LOW", "No force-upgrade / minimum-version gate",
     "Old builds that pre-date schoolId-filtered rules will hit permission-denied with no explanation once new rules "
     "deploy. A remote min-version check with an upgrade screen prevents support chaos."),
    ("LOW", "No about / version / support screen",
     "No in-app way to see the app version, contact support, or report a problem — every issue becomes a phone call."),
    ("LOW", "Email-keyed accounts cannot change email",
     "allowed_users docs are keyed by lowercased email; a legitimate email change orphans the account (history, role, "
     "classIds) since the doc ID cannot change."),
]))

# ───────────────────────────── Section B ─────────────────────────────
story.append(Paragraph("B. Owner perspective — money, fraud &amp; oversight", H2))
story.append(Paragraph(
    "The owner's core question is \"where is my money and is anyone stealing it?\" The fee module records income well "
    "(integer paise, gapless receipts, reversal audit) but the surrounding controls are missing.", BODY))
story.append(issue_table([
    ("HIGH", "No expense tracking — income-only books",
     "fees captures collections but there is no expense side at all, so no P&amp;L, no monthly net position. The owner "
     "still runs the school's actual finances in a paper ledger or Excel; the app sees half the picture."),
    ("HIGH", "No daily cash reconciliation per collector",
     "Payments record who collected, but there is no end-of-day \"collected vs deposited\" confirmation loop. The classic "
     "school fraud — cash collected, receipt issued, money pocketed for weeks — is invisible. Mostly a grouping query "
     "over data already stored."),
    ("MEDIUM", "No concession / scholarship / sibling-discount support",
     "Fee structure is class-level with only a raw per-student feeAmount override. Discounts are therefore handled "
     "off-book with no record of who granted what to whom — the second classic leakage point after cash handling."),
    ("MEDIUM", "No fee-structure versioning",
     "saveFeeStructure validates installment sums but overwrites in place. A mid-year revision destroys the schedule "
     "that earlier receipts were issued against — an auditor cannot reconstruct what was owed in July."),
    ("MEDIUM", "No dues aging / projected cash-flow view",
     "Installment due dates are stored but never aggregated into \"expected collections next 30/60/90 days\" or an "
     "overdue-aging report. The owner cannot see a cash crunch coming."),
    ("MEDIUM", "Owner screens are the i18n hole",
     "Of the 7 screens still hardcoded English, the owner's are most of them: owner_home, owner_principal_home, "
     "staff_directory_helpers, plus teacher_management and timetable_settings. A Hindi-first owner gets English exactly "
     "where money decisions happen."),
    ("MEDIUM", "No full data export / backup",
     "Beyond per-feature CSVs there is no \"download my school\" dump (students, fees, attendance, marks). Owners fear "
     "vendor lock-in; a JSON/CSV export is also the DPDP-friendly answer to \"give me my data\"."),
    ("LOW", "No staff attendance or payroll trace",
     "Teacher presence is only inferable from leave applications; there is no check-in record, so the owner cannot "
     "verify the punctuality of the people they pay."),
    ("LOW", "No per-school branding",
     "Logo upload exists in Storage paths but receipts/report cards/PDFs render generic branding — matters the moment a "
     "second school onboards."),
]))

# ───────────────────────────── Section C ─────────────────────────────
story.append(Paragraph("C. Principal perspective — academics &amp; staff oversight", H2))
story.append(issue_table([
    ("HIGH", "Analytics has no exam-results dimension",
     "analytics_screen covers attendance and fees only (confirmed gap). Pass percentage, subject averages, below-40% "
     "counts, class comparisons — the principal's core academic questions — are unanswerable in-app even though every "
     "mark is already in Firestore."),
    ("MEDIUM", "No teacher compliance scorecard",
     "\"Did 7-B's teacher mark attendance today? Post homework this week? Enter marks before the deadline?\" Every one "
     "of these is a timestamp already stored, but nothing aggregates them, so the principal still chases teachers "
     "verbally."),
    ("MEDIUM", "No teacher workload / substitution-load report",
     "Periods per week and substitution counts exist in the timetable and substitution history, but no view shows which "
     "teachers are overloaded vs idle — workload disputes are settled by impression."),
    ("MEDIUM", "Single maxMarks per exam, not per subject",
     "Exam.maxMarks is one integer applied to all subjects. An exam where theory is /80 and practical is /20 cannot be "
     "represented; percentages and pass thresholds distort for any non-uniform exam."),
    ("MEDIUM", "Leaderboard is hand-maintained",
     "Leaderboard entries are written manually by management and never recomputed from marks — standings go stale the "
     "moment a new exam is entered, and a wrong rank shown to guardians is a credibility hit."),
    ("LOW", "No staff-circular acknowledgement",
     "Announcements to staff have no read receipt (\"12 of 15 acknowledged\"), so accountability for circulars remains "
     "verbal."),
    ("LOW", "No structured classroom-observation register",
     "staff_remarks is free text; appraisal season needs a rubric with history per teacher."),
    ("LOW", "No inspection pack / statutory registers",
     "DEO/board visits need printable attendance registers, enrollment-by-category and teacher lists as one bundle; "
     "today each is assembled by hand."),
]))

# ───────────────────────────── Section D ─────────────────────────────
story.append(Paragraph("D. Teacher perspective — daily workflow", H2))
story.append(issue_table([
    ("HIGH", "Offline queue covers attendance only",
     "OfflineQueueService queues attendance writes, but marks entry, homework and remarks fail outright on flaky "
     "networks. Losing a class's marks during exam week (typed once, network drop, gone) is the single most "
     "app-abandoning failure mode for teachers. Generalise the enqueue/syncAll pattern."),
    ("MEDIUM", "Offline state is invisible on most screens",
     "Only attendance and the two login screens watch connectivity. Everywhere else a queued/failed save renders exactly "
     "like a successful one — teachers cannot tell if their work is on the server."),
    ("MEDIUM", "No leave-balance concept",
     "Teachers apply for leave with no view of quota vs used, and approvers approve blind. Quota in settings plus a "
     "ledger over approved leave_applications closes it."),
    ("MEDIUM", "Approved leave does not nudge substitution",
     "Approving a teacher's leave and assigning a substitute are deliberately separate steps, but nothing reminds the "
     "coordinator if the second step is forgotten — the failure surfaces as an untaught class at the bell."),
    ("MEDIUM", "Marks entry has no speedups",
     "No auto-advance to next student, no inline max-marks validation while typing, no CSV import. During deadline week "
     "this is the highest-friction screen in the app."),
    ("LOW", "No period-swap workflow",
     "Teacher↔teacher swaps happen via the coordinator off-app; the substitution infrastructure could carry them."),
    ("LOW", "No private student notes",
     "Everything a teacher writes lands in guardian-visible or staff-shared remark streams; there is no \"for my eyes\" "
     "note (e.g. sensitive home-situation context)."),
    ("LOW", "No draft state — edit re-notifies",
     "Homework/announcements post immediately; fixing a typo means delete + repost, which fans out notifications again "
     "and trains guardians to ignore them."),
]))

# ───────────────────────────── Section E ─────────────────────────────
story.append(Paragraph("E. Guardian perspective — the parent experience", H2))
story.append(issue_table([
    ("HIGH", "No downloadable fee receipt",
     "Gapless receipt numbers are generated server-side, but guardians have no UI to view or download a receipt PDF. "
     "Every March (80C tax season) this becomes a front-office queue. The PDF pipeline already exists for report cards."),
    ("HIGH", "No automatic absence alert",
     "When a child is marked absent, the guardian learns of it only if the teacher manually taps the per-student "
     "WhatsApp button. The safety-critical \"your child did not reach school\" push is one small Cloud Function over "
     "attendance writes — the highest-value missing alert in the app."),
    ("MEDIUM", "No holiday calendar view",
     "calendar_events data exists; guardians have no screen for it. \"Is school open tomorrow?\" remains a phone call."),
    ("MEDIUM", "No child timetable view",
     "The timetable collection knows the child's subjects per day, but guardians cannot see it — the daily "
     "\"pack-the-bag\" need."),
    ("MEDIUM", "Roll number still used as child identity in messages",
     "Guardian-facing messages reference the roll number. Rolls get reassigned across years; the stable admissionId "
     "exists but messages have not switched to it — a misdirected fee or absence message names the wrong child."),
    ("MEDIUM", "No second-guardian access",
     "One phone number per child: father OR mother. No invite flow for a second guardian, which in practice means "
     "shared credentials (and OTP lockout when the phone changes hands)."),
    ("MEDIUM", "Guardian correction requests lack a staff signal (verify)",
     "Guardians can submit detail corrections, but no badge/notification appears for staff — submissions sit unseen "
     "until someone happens to open that student's record."),
    ("LOW", "No class-average context on marks",
     "A lone \"65/100\" answers nothing; an anonymous per-exam-subject average gives it meaning at near-zero privacy "
     "cost."),
    ("LOW", "Leaderboard standing computed but never shown",
     "leaderboard_service data exists; no guardian UI surfaces the child's standing."),
    ("LOW", "No exam syllabus or countdown",
     "Exams carry no \"Ch 1–4\" syllabus field and no reminder push as dates approach."),
]))

# ───────────────────────────── Section F ─────────────────────────────
story.append(Paragraph("F. Data quality &amp; compliance (residual)", H2))
story.append(issue_table([
    ("MEDIUM", "Class-name canonicalisation is still heuristic",
     "class_name_utils.dart exists, but spaces↔underscores / split('-') conventions appear across rules and services. "
     "\"Class 9 - A\" vs \"Class 9-A\" vs \"9A\" can mismatch attendance keys, classIds and fee lookups. Audit that every "
     "path routes through the one util (verify)."),
    ("MEDIUM", "Retention exists but is manual",
     "purgeOldData is a callable the owner must remember to invoke. Notifications, audit logs and deleted_students "
     "tombstones (which retain guardian email/phone) grow until then. Schedule it (onSchedule) instead."),
    ("MEDIUM", "Consent gate scope (verify)",
     "Consent infrastructure is substantial (consent_service, consent_gate, parental_consent_flow) and gates WhatsApp "
     "sends. Confirm whether storing/processing a NEW minor's data is also blocked pending consent, as DPDP expects, or "
     "only the messaging path."),
    ("MEDIUM", "Consecutive-absence streak inflates across unmarked days",
     "Unmarked days are skipped rather than breaking the streak, so a streak can span gaps when attendance simply "
     "wasn't taken — the coordinator dashboard then flags the wrong children."),
    ("LOW", "Duplicate-roll guard on student move (verify)",
     "Roll-collision checking is confirmed at add time; verify the edit/move path can't land two students on one roll "
     "in a section."),
    ("LOW", "17 bare int.parse sites remain",
     "Down from 33, but each is a latent crash on malformed Firestore data. Sweep to int.tryParse with defaults."),
    ("LOW", "Attendance date keys not zero-padded",
     "YYYY-M-D keys ('2026-6-4') are internally consistent but break lexicographic ordering in any export or future "
     "query-by-range."),
    ("LOW", "AppLogger PII discipline (verify)",
     "Confirm release builds never log emails/phones/marks — friendlyAuthError now logs e.message via AppLogger; make "
     "sure that channel stays out of release logs or scrubs PII."),
]))

# ───────────────────────────── Section G ─────────────────────────────
story.append(Paragraph("G. Recommended order of attack", H2))
story.append(Paragraph(
    "1. <b>Deploy what you've built</b> — claims backfill → syncUserClaims → storage.rules → firestore.rules → functions; "
    "until then most of your security work is theoretical (A1).<br/>"
    "2. <b>Staging project + CI</b> — stop testing against live data; gate analyze/tests/rules-tests (A2, A3).<br/>"
    "3. <b>Notification tap routing + absence auto-alert</b> — two small changes that multiply the value of the push "
    "pipeline for every role (A5, E2).<br/>"
    "4. <b>Guardian fee receipts</b> — existing PDF + receipt infra, pure UI work, seasonal demand spike (E1).<br/>"
    "5. <b>Extend offline queue to marks</b> — removes the worst teacher data-loss scenario (D1).<br/>"
    "6. <b>Cash reconciliation + expense tracking</b> — turns the fee module into the owner's actual books (B1, B2).<br/>"
    "7. <b>Exam analytics for the principal</b> — confirmed gap, data already stored (C1).<br/>"
    "8. <b>Finish i18n (7 screens) and the catch(_){} sweep</b> — small, mechanical, overdue (A7, B6).", BODY))

story.append(Spacer(1, 10))
story.append(Paragraph(
    "Totals: 59 open issues — 2 critical, 10 high, 29 medium, 18 low. "
    "Generated from static analysis of main @ 9a7b85b; items marked (verify) need a quick manual confirmation.", SMALL))

doc = SimpleDocTemplate("/Users/upendrapandey/school_app/ISSUES_REPORT.pdf", pagesize=A4,
                        leftMargin=18 * mm, rightMargin=18 * mm,
                        topMargin=16 * mm, bottomMargin=16 * mm,
                        title="School App — Major Issues Report",
                        author="Codebase analysis")
doc.build(story)
print("done")

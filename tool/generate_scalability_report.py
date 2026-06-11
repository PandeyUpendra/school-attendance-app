#!/usr/bin/env python3
"""Generates SCALABILITY_REVIEW.pdf — a multi-tenancy & scale architecture audit
of the school_app Flutter codebase. Grounded in actual code (file:line refs)."""

from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_LEFT, TA_CENTER
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak,
    HRFlowable, KeepTogether,
)

# ── Palette (mirrors AppTheme deep-violet brand) ────────────────────────────
PRIMARY   = colors.HexColor("#6A1B9A")
ACCENT    = colors.HexColor("#D81B60")
DANGER    = colors.HexColor("#C62828")
HIGH      = colors.HexColor("#E65100")
MEDIUM    = colors.HexColor("#F9A825")
LOW       = colors.HexColor("#2E7D32")
INK       = colors.HexColor("#1A1A2E")
MUTE      = colors.HexColor("#555566")
LIGHT     = colors.HexColor("#F3EEF8")
RULE      = colors.HexColor("#D8C8E8")

styles = getSampleStyleSheet()

def style(name, **kw):
    styles.add(ParagraphStyle(name, parent=styles['Normal'], **kw))

style('Cover',    fontName='Helvetica-Bold', fontSize=30, textColor=PRIMARY, leading=36)
style('CoverSub', fontName='Helvetica',      fontSize=13, textColor=MUTE,    leading=18)
style('H1',       fontName='Helvetica-Bold', fontSize=17, textColor=PRIMARY, leading=21, spaceBefore=14, spaceAfter=6)
style('H2',       fontName='Helvetica-Bold', fontSize=12.5, textColor=INK,   leading=16, spaceBefore=10, spaceAfter=3)
style('Body',     fontName='Helvetica',      fontSize=9.7,  textColor=INK,   leading=14, spaceAfter=5, alignment=TA_LEFT)
style('BodyMute', fontName='Helvetica',      fontSize=9.2,  textColor=MUTE,  leading=13, spaceAfter=4)
style('CodeBox',  fontName='Courier',        fontSize=8.4,  textColor=colors.HexColor("#3A2A4A"), leading=11, backColor=LIGHT, borderPadding=4, spaceAfter=5)
style('Cell',     fontName='Helvetica',      fontSize=8.6,  textColor=INK,   leading=11)
style('CellB',    fontName='Helvetica-Bold', fontSize=8.6,  textColor=INK,   leading=11)
style('CellHdr',  fontName='Helvetica-Bold', fontSize=8.8,  textColor=colors.white, leading=11)
style('Label',    fontName='Helvetica-Bold', fontSize=8.6,  textColor=PRIMARY, leading=12)
style('Tag',      fontName='Helvetica-Bold', fontSize=8,    textColor=colors.white, leading=10, alignment=TA_CENTER)

def P(t, s='Body'):   return Paragraph(t, styles[s])
def rule(c=RULE, w=0.8): return HRFlowable(width="100%", thickness=w, color=c, spaceBefore=4, spaceAfter=8)

story = []

# ════════════════════════════════════════════════════════════════════ COVER
story += [
    Spacer(1, 60*mm),
    P("Scalability &amp; Multi-Tenancy", 'Cover'),
    P("Architecture Review", 'Cover'),
    Spacer(1, 8*mm),
    P("School App — readiness for multiple schools and lakhs of students", 'CoverSub'),
    Spacer(1, 4*mm),
    rule(PRIMARY, 2),
    Spacer(1, 3*mm),
    P("Flutter + Firebase (Firestore / Auth / Cloud Functions / FCM)", 'CoverSub'),
    P("Firebase project: <b>attendanceapp-e76e1</b>", 'CoverSub'),
    P("Review date: 11 June 2026 &nbsp;·&nbsp; Branch: main", 'CoverSub'),
    Spacer(1, 30*mm),
    P("<b>Verdict:</b> The foundation is multi-tenant and well-secured, but the app "
      "will <b>not</b> handle a large school as-is. Two BLOCKER-level data-loading "
      "limits cap every school at 500 students and make dashboards read the entire "
      "school on every open. Both are fixable without re-architecting. Details inside.", 'BodyMute'),
]
story.append(PageBreak())

# ════════════════════════════════════════════════════════════ HOW TO USE / EXEC
story += [
    P("1 &nbsp; Executive summary", 'H1'),
    rule(),
    P("Your app is already built as a proper multi-tenant system: every business "
      "collection lives under <font face='Courier'>schools/{schoolId}/…</font>, the "
      "Firestore security rules enforce strict per-tenant isolation (\"Phase 3\"), and "
      "expensive operations (cascade delete, promotion, push) are batched correctly. "
      "That is the hard part, and it is done well.", 'Body'),
    P("The problem is <b>read scale</b>. The client was written to load a whole school's "
      "students into memory and compute every total in Dart. That works for a 200-student "
      "demo school; it breaks — silently and then expensively — as you grow toward "
      "thousands of students per school and many schools per project.", 'Body'),
    P("There are <b>12 findings</b> below. The two BLOCKERs must be fixed before you "
      "onboard any school above ~500 students. The HIGH items are needed before you market "
      "to large schools or cross ~5,000 total students. MEDIUM/LOW are hardening for the "
      "lakhs-of-students horizon.", 'Body'),

    Spacer(1, 3*mm),
    P("Severity counts", 'H2'),
]

sev_tbl = Table([
    [P("BLOCKER", 'Tag'), P("HIGH", 'Tag'), P("MEDIUM", 'Tag'), P("LOW", 'Tag')],
    [P("2", 'CellB'),     P("3", 'CellB'),  P("5", 'CellB'),     P("2", 'CellB')],
], colWidths=[42*mm]*4)
sev_tbl.setStyle(TableStyle([
    ('BACKGROUND', (0,0),(0,0), DANGER),
    ('BACKGROUND', (1,0),(1,0), HIGH),
    ('BACKGROUND', (2,0),(2,0), MEDIUM),
    ('BACKGROUND', (3,0),(3,0), LOW),
    ('ALIGN', (0,0),(-1,-1),'CENTER'), ('VALIGN',(0,0),(-1,-1),'MIDDLE'),
    ('TOPPADDING',(0,0),(-1,-1),6),('BOTTOMPADDING',(0,0),(-1,-1),6),
    ('BOX',(0,1),(-1,1),0.5,RULE),('INNERGRID',(0,1),(-1,1),0.5,RULE),
]))
story += [sev_tbl, Spacer(1, 4*mm)]

# Findings index table
story += [P("Findings at a glance", 'H2')]
idx_rows = [[P("ID",'CellHdr'),P("Finding",'CellHdr'),P("Severity",'CellHdr'),P("Effort",'CellHdr')]]
index = [
    ("SCALE-01","500-student hard cap silently truncates every school","BLOCKER","S"),
    ("SCALE-02","Dashboards read the entire school client-side on open","BLOCKER","M"),
    ("SCALE-03","Whole-school real-time listener on dashboards","HIGH","M"),
    ("SCALE-04","No server-side aggregation / rollup counters","HIGH","L"),
    ("SCALE-05","Rules re-read allowed_users instead of using claims","HIGH","M"),
    ("SCALE-06","Client 'school_1' fallbacks are wrong-tenant landmines","MEDIUM","S"),
    ("SCALE-07","No scheduled data retention / archival","MEDIUM","M"),
    ("SCALE-08","Firestore region us-central1 (latency from India)","MEDIUM","L*"),
    ("SCALE-09","Year-rollover promotion is client-driven, sequential","MEDIUM","M"),
    ("SCALE-10","fetchByRolls uses N+1 single-doc reads","LOW","S"),
    ("SCALE-11","allowed_users is one global hot collection","MEDIUM","M"),
    ("SCALE-12","Today-summary fan-out scales with section count","LOW","S"),
]
sevcol = {"BLOCKER":DANGER,"HIGH":HIGH,"MEDIUM":MEDIUM,"LOW":LOW}
for i,(id_,desc,sev,eff) in enumerate(index):
    idx_rows.append([P(id_,'CellB'),P(desc,'Cell'),
                     Paragraph(sev, ParagraphStyle('s',parent=styles['Tag'],backColor=sevcol[sev])),
                     P(eff,'Cell')])
idx = Table(idx_rows, colWidths=[20*mm,98*mm,22*mm,16*mm], repeatRows=1)
sty = [
    ('BACKGROUND',(0,0),(-1,0),PRIMARY),
    ('ROWBACKGROUNDS',(0,1),(-1,-1),[colors.white,LIGHT]),
    ('GRID',(0,0),(-1,-1),0.4,RULE),
    ('VALIGN',(0,0),(-1,-1),'MIDDLE'),
    ('TOPPADDING',(0,0),(-1,-1),4),('BOTTOMPADDING',(0,0),(-1,-1),4),
    ('LEFTPADDING',(0,0),(-1,-1),5),('RIGHTPADDING',(0,0),(-1,-1),5),
]
for r in range(1,len(idx_rows)):
    sty.append(('BACKGROUND',(2,r),(2,r),sevcol[index[r-1][2]]))
    sty.append(('ALIGN',(2,r),(2,r),'CENTER'))
idx.setStyle(TableStyle(sty))
story += [idx, Spacer(1,2*mm),
          P("Effort: S = hours · M = a few days · L = under a day · L* = decision now, cheap if done before launch.", 'BodyMute')]
story.append(PageBreak())

# ════════════════════════════════════════════════════ WHAT'S ALREADY GOOD
story += [
    P("2 &nbsp; What is already done well (do not regress these)", 'H1'),
    rule(),
    P("So a future change does not undo working design, here is what the audit "
      "confirms is solid:", 'Body'),
]
good = [
    ("Tenant data layout","Every business collection is nested under <font face='Courier'>schools/{sid}/…</font> via <font face='Courier'>BaseFirestoreService.schoolCollection()</font>. Schools are fully separated at the data level."),
    ("Strict rule isolation","Firestore rules fail <i>closed</i>: a missing schoolId denies access rather than defaulting to school_1. Only the hardcoded root admin crosses schools (firestore.rules, inSchool())."),
    ("Attendance modelled per day","Attendance is one document per class+section+date (<font face='Courier'>&lt;class&gt;_&lt;section&gt;_&lt;Y-M-D&gt;</font>). This avoids the classic 1&nbsp;MB unbounded-document trap of one-doc-per-class-forever."),
    ("Push via FCM topics","Notifications publish to a topic <font face='Courier'>s_{sid}_{audience}</font> (functions/index.js). One message regardless of device count — no per-device fan-out."),
    ("Batched cascades","Student delete, promotion and purge all chunk writes to stay under Firestore's 500-op batch limit (chunks of 200/400)."),
    ("Short-TTL read cache","Past attendance day-docs are cached 30&nbsp;s and namespaced by school, collapsing repeated dashboard reads (student_service.dart)."),
    ("Custom claims pipeline","<font face='Courier'>syncUserClaims</font> already stamps role + schoolId onto the Auth token on every allowed_users write — the groundwork for cheaper rules is in place (see SCALE-05)."),
]
gd = [[P("Area",'CellHdr'),P("Why it scales",'CellHdr')]]
for a,b in good: gd.append([P(a,'CellB'),P(b,'Cell')])
gt = Table(gd, colWidths=[38*mm,118*mm], repeatRows=1)
gt.setStyle(TableStyle([
    ('BACKGROUND',(0,0),(-1,0),LOW),
    ('ROWBACKGROUNDS',(0,1),(-1,-1),[colors.white,colors.HexColor("#EEF7EE")]),
    ('GRID',(0,0),(-1,-1),0.4,RULE),('VALIGN',(0,0),(-1,-1),'TOP'),
    ('TOPPADDING',(0,0),(-1,-1),5),('BOTTOMPADDING',(0,0),(-1,-1),5),
    ('LEFTPADDING',(0,0),(-1,-1),6),('RIGHTPADDING',(0,0),(-1,-1),6),
]))
story += [gt]
story.append(PageBreak())

# ════════════════════════════════════════════════════════════ FINDINGS
def finding(id_, title, sev, effort, where, what, why, fix, accept):
    col = sevcol[sev]
    head = Table([[
        Paragraph(f"{id_}", ParagraphStyle('fid',parent=styles['CellHdr'],fontSize=11)),
        Paragraph(title, ParagraphStyle('ft',parent=styles['CellHdr'],fontSize=11)),
        Paragraph(f"{sev} · {effort}", ParagraphStyle('fs',parent=styles['Tag'],fontSize=8.5)),
    ]], colWidths=[20*mm,108*mm,28*mm])
    head.setStyle(TableStyle([
        ('BACKGROUND',(0,0),(1,0),PRIMARY),
        ('BACKGROUND',(2,0),(2,0),col),
        ('VALIGN',(0,0),(-1,-1),'MIDDLE'),('ALIGN',(2,0),(2,0),'CENTER'),
        ('TOPPADDING',(0,0),(-1,-1),5),('BOTTOMPADDING',(0,0),(-1,-1),5),
        ('LEFTPADDING',(0,0),(-1,-1),7),
    ]))
    blk = [head, Spacer(1,2*mm)]
    blk += [P("Where", 'Label'), P(where, 'CodeBox')]
    blk += [P("What happens at scale", 'Label'), P(what, 'Body')]
    blk += [P("Why it happens", 'Label'), P(why, 'Body')]
    blk += [P("Fix", 'Label'), P(fix, 'Body')]
    blk += [P("Done when", 'Label'), P(accept, 'BodyMute')]
    blk += [Spacer(1,3*mm), rule(RULE,0.6)]
    story.append(KeepTogether(blk))

story += [P("3 &nbsp; Findings — detail", 'H1'), rule(),
          P("Each finding is self-contained. Hand any subset back to me by ID "
            "(e.g. \"do SCALE-01 and SCALE-02\") and I will have everything I need "
            "to implement it — the location, intent and acceptance test are all here.", 'BodyMute'),
          Spacer(1,3*mm)]

finding(
 "SCALE-01", "500-student hard cap truncates every school", "BLOCKER", "Effort: S",
 "lib/repositories/student_repository.dart:226  → fetchAll():  _students.limit(500).get()\n"
 "lib/repositories/student_repository.dart:432  → watchAll(): _students.limit(500).snapshots()",
 "Every code path that lists \"all students\" stops at 500. A school with 600, 5,000 or "
 "200,000 students will only ever load the first 500 (ordered arbitrarily). Rosters, the "
 "coordinator/principal/owner dashboards, analytics and today's attendance summary all "
 "silently drop the rest. This is data loss, not just slowness — and it fails quietly, "
 "which is worse: nobody sees an error, the numbers are just wrong.",
 "The cap was a stop-gap to bound an unscoped whole-collection read. It is the right "
 "instinct (never read an unbounded collection) but the wrong mechanism — a fixed truncation "
 "instead of pagination or aggregation.",
 "Stop loading whole-school student lists at all for dashboards (see SCALE-02/04). Where a "
 "full list is genuinely needed, switch to <b>cursor pagination</b> — the repository already "
 "has <font face='Courier'>fetchByClassPaginated()</font>; add the same <font face='Courier'>"
 "startAfter</font> loop to <font face='Courier'>fetchAll</font>, or page per class. For "
 "real-time, never <font face='Courier'>watchAll()</font> an unbounded collection; watch per "
 "class/section only.",
 "A school with 1,000+ students shows correct totals and a complete roster; no query in the "
 "app uses a bare <font face='Courier'>.limit(500)</font> on students.",
)
finding(
 "SCALE-02", "Dashboards read the entire school on every open", "BLOCKER", "Effort: M",
 "lib/services/student_service.dart:1196  loadTodayFullSummary()  → _repo.fetchAll()\n"
 "callers: coordinator_dashboard.dart:167 · principal_dashboard.dart:195 ·\n"
 "owner_home.dart:439 · owner_principal_home.dart:267 · analytics_screen.dart:115",
 "Opening a dashboard fetches <i>every student document in the school</i>, groups them in "
 "Dart, then fetches one attendance doc per class-section. For a 5,000-student school that is "
 "5,000+ document reads <b>per dashboard open, per user, per refresh</b>. At lakhs of students "
 "this is both impossibly slow on the client and a serious Firestore bill (reads are billed "
 "per document). Several roles open these screens many times a day.",
 "Totals (present / absent / leave / class strength) are computed by reading raw student and "
 "attendance documents into the client and counting them, rather than reading a small "
 "pre-aggregated summary.",
 "Maintain <b>rollup counter documents</b> updated by Cloud Functions as attendance is marked "
 "and students are added/removed — e.g. <font face='Courier'>schools/{sid}/daily_summaries/"
 "{date}</font> holding per-class present/absent/total. Dashboards then read a handful of "
 "summary docs instead of the whole school. For class strength, also see SCALE-04 "
 "(<font face='Courier'>count()</font> aggregate queries) as a lighter interim step.",
 "Opening any dashboard costs a fixed, small number of reads (tens, not thousands) regardless "
 "of school size; verified with a 5,000-student seed.",
)
finding(
 "SCALE-03", "Whole-school real-time listener on dashboards", "HIGH", "Effort: M",
 "lib/screens/coordinator_dashboard.dart:88  StudentService.instance.watchStudents().listen(...)\n"
 "lib/screens/principal_dashboard.dart:85    StudentService.instance.watchStudents().listen(...)",
 "These screens hold an open real-time listener over the whole-school students collection "
 "(currently capped at 500 by SCALE-01). A snapshot listener re-delivers and re-bills "
 "documents as the collection changes; over a large, busy school it streams far more data than "
 "a dashboard needs and keeps a costly live query open the whole time the screen is mounted.",
 "The dashboards want a live student <i>count</i> / live class strength, but subscribe to the "
 "full document stream to get it.",
 "Replace the whole-school stream with either (a) a listener on the small rollup/summary doc "
 "from SCALE-02, or (b) a periodic <font face='Courier'>count()</font> aggregate. Keep "
 "real-time document streams scoped to a single class/section (<font face='Courier'>"
 "watchStudentsByClass</font>), which is naturally bounded.",
 "No screen subscribes to <font face='Courier'>watchStudents()</font>/<font face='Courier'>"
 "watchAll()</font>; dashboards update from a bounded summary source.",
)
finding(
 "SCALE-04", "No server-side aggregation anywhere", "HIGH", "Effort: L",
 "grep '.count()|AggregateQuery' across lib/  →  0 matches",
 "Firestore has supported server-side <font face='Courier'>count()</font> aggregation for "
 "years, but the app computes every count by downloading documents and counting them in Dart. "
 "This is the root cause shared by SCALE-01/02/03: counts scale with document volume instead "
 "of being O(1).",
 "The codebase predates (or didn't adopt) aggregate queries, so 'how many students / how many "
 "absent' is always answered by reading the underlying documents.",
 "Adopt <font face='Courier'>Query.count()</font> for cheap totals (class strength, students "
 "per section, pending requests) as the quick win, and rollup counters (SCALE-02) for hot, "
 "frequently-read aggregates like daily attendance. As a rule: a screen that only needs a "
 "<i>number</i> must never download the <i>rows</i>.",
 "Class-strength and 'how many' figures come from <font face='Courier'>count()</font> or a "
 "counter doc, with zero per-row reads.",
)
finding(
 "SCALE-05", "Security rules re-read allowed_users instead of using claims", "HIGH", "Effort: M",
 "firestore.rules  getUserData() → get(/allowed_users/{email})  (called by every rule)\n"
 "functions/index.js:31 syncUserClaims  → already sets {role, schoolId} custom claims",
 "Every rule evaluation calls <font face='Courier'>getUserData()</font>, which does a "
 "document <font face='Courier'>get()</font> of <font face='Courier'>allowed_users</font>. "
 "Rules are also bumping against Firestore's 1000-expression-per-request ceiling — the file is "
 "full of comments about teacher writes being denied because identity helpers re-derive "
 "<font face='Courier'>getUserData()</font> too many times. At lakhs of attendance writes a "
 "day this adds latency, fragility and a billed read to <i>every</i> protected operation.",
 "Identity (role, schoolId) is resolved by reading a Firestore document inside the rule, even "
 "though the same values are already minted onto the Auth token by "
 "<font face='Courier'>syncUserClaims</font> and ignored by the rules.",
 "Read identity from <font face='Courier'>request.auth.token.role</font> / "
 "<font face='Courier'>.schoolId</font> (custom claims) instead of <font face='Courier'>"
 "get()</font>. This removes a document read and most of the expression-count pressure from "
 "every rule. Keep the <font face='Courier'>get()</font> only as a fallback for accounts whose "
 "claims haven't propagated yet, and force a token refresh after provisioning.",
 "Hot-path rules (attendance write, student read) evaluate with no <font face='Courier'>get()"
 "</font>; rule unit tests still pass; the 1000-expression comments become obsolete.",
)
finding(
 "SCALE-06", "Client 'school_1' fallbacks are wrong-tenant landmines", "MEDIUM", "Effort: S",
 "auth_service.dart:121 return 'school_1' · student_service.dart:582 ?? 'school_1'\n"
 "push_service.dart:73 ?? 'school_1' · owner_principal_home.dart:289/659/822/846 ?? 'school_1'\n"
 "admin_login_screen.dart:76 currentSchoolId = 'school_1'",
 "If <font face='Courier'>currentSchoolId</font> is ever null at the moment a query runs "
 "(session restore race, logout/login overlap), the client silently targets the literal tenant "
 "<font face='Courier'>school_1</font>. With the new fail-closed rules this no longer leaks "
 "data, but it produces confusing silent permission-denials and, in the worst timing, writes "
 "aimed at the wrong school. As you add real schools, <font face='Courier'>school_1</font> "
 "becomes just another tenant and these defaults become genuinely dangerous.",
 "A historical single-tenant default ('school_1') was left as a fallback in client code paths "
 "that should now require an explicit, resolved schoolId.",
 "Replace every <font face='Courier'>?? 'school_1'</font> / hardcoded assignment with a hard "
 "failure (throw / guard that blocks the action and surfaces 'no active school') when "
 "schoolId is null. Fail loud, never default. The notifier in "
 "<font face='Courier'>BaseFirestoreService</font> already lets screens wait for a real value.",
 "No occurrence of the string <font face='Courier'>'school_1'</font> as a fallback remains in "
 "lib/; a null schoolId blocks the operation with a clear message.",
)
finding(
 "SCALE-07", "No scheduled data retention / archival", "MEDIUM", "Effort: M",
 "functions/index.js:650 purgeOldData  → onCall (manual only, not scheduled)",
 "Attendance, notifications, audit_logs and deleted-student tombstones grow forever, per "
 "school. A purge function exists but must be invoked by hand. At lakhs of students × daily "
 "writes, these collections balloon, slowing range queries and inflating storage. Old data is "
 "rarely read but never aged out.",
 "Retention was implemented as an on-demand admin action rather than an automatic policy.",
 "Convert retention to a <font face='Courier'>onSchedule</font> (Cloud Scheduler) function "
 "that runs nightly per school, archiving or deleting beyond a retention window (e.g. keep "
 "raw attendance 18 months, summaries forever). Pair with the rollup docs from SCALE-02 so "
 "history survives as cheap aggregates after raw docs are aged out.",
 "A scheduled job ages out data automatically; collection sizes stay bounded by the retention "
 "window in a load test.",
)
finding(
 "SCALE-08", "Firestore region us-central1 adds latency from India", "MEDIUM", "Effort: L* (decision now)",
 "functions/index.js  region: 'us-central1' (all triggers) · Firestore DB location fixed at "
 "project creation",
 "Because the client does many sequential round-trips (read students, then per-class "
 "attendance, then counts), latency multiplies. A US region adds ~200–300&nbsp;ms per round "
 "trip for Indian users; ten chained reads becomes seconds of perceived lag. Firestore's "
 "location is chosen <b>once, at project creation, and cannot be changed</b> — so this is a "
 "now-or-never call.",
 "The Firebase project defaulted to a US multi-region; for an India-focused school business "
 "the data lives far from its users.",
 "If you are early enough to recreate the project, provision Firestore in "
 "<font face='Courier'>asia-south1</font> (Mumbai) or <font face='Courier'>asia-south2</font> "
 "(Delhi) and deploy functions to the matching region. If the project already holds real "
 "data, treat this as a documented trade-off and lean harder on SCALE-02/04 to cut round-trip "
 "count instead. Decide deliberately before launch.",
 "A conscious, recorded decision: either Firestore is in an India region, or the latency is "
 "accepted and mitigated by fewer round-trips.",
)
finding(
 "SCALE-09", "Year-rollover promotion is client-driven and sequential", "MEDIUM", "Effort: M",
 "lib/repositories/student_repository.dart  promoteStudentsAtomic()  → chunks of 200, awaited "
 "one batch at a time on the client",
 "Promotion is correctly chunked (200 students/batch, 2 ops each), but it runs on the "
 "client, one batch after another. Promoting a whole large school (thousands of students) "
 "means dozens-to-hundreds of sequential committed batches while the app stays open — slow, "
 "interruptible (backgrounding, network drop), and it cannot atomically span the whole school.",
 "Annual promotion is a bulk back-office operation implemented as a foreground client loop.",
 "Move whole-school promotion to a Cloud Function (callable or scheduled) using the Admin SDK "
 "and a <font face='Courier'>BulkWriter</font>, so it runs server-side reliably and resumably, "
 "independent of the client staying open. Keep the client path for small single-class "
 "promotions.",
 "Promoting a 5,000-student school completes server-side without the app open and is "
 "resumable on failure.",
)
finding(
 "SCALE-10", "fetchByRolls uses N+1 single-document reads", "LOW", "Effort: S",
 "lib/repositories/student_repository.dart:264 fetchByRolls → Future.wait(rolls.map(fetchByRoll))",
 "Each roll is fetched with its own <font face='Courier'>get()</font>. Fine for one class "
 "(~40 students), but it is an O(n) read pattern that will be reused in larger contexts and "
 "bills one read per roll.",
 "Convenience implementation that loops single-document reads instead of a batched query.",
 "Use <font face='Courier'>whereIn</font> on the roll/doc-id (batched in groups of 30, "
 "Firestore's whereIn limit) to fetch a class's rolls in 1–2 queries. Low priority, but a "
 "trivial efficiency win when touched.",
 "Fetching N rolls costs ceil(N/30) queries, not N reads.",
)
finding(
 "SCALE-11", "allowed_users is one global hot collection", "MEDIUM", "Effort: M",
 "Root collection allowed_users/{email}  — not school-scoped; read by every auth resolution "
 "and (today) every security-rule evaluation",
 "All users of all tenants share one flat root collection, and it is read on every login and "
 "(until SCALE-05) every rule check. Firestore handles large flat collections fine for "
 "key-lookups, so this is not urgent — but it is a cross-tenant hot path and a single blast "
 "radius if any code ever lists it unscoped.",
 "Identity was intentionally kept global (email is globally unique, and rules resolve identity "
 "by email) — a reasonable choice that just needs guarding as volume grows.",
 "Primarily mitigated by SCALE-05 (claims remove the per-rule read). Additionally: never run "
 "an unbounded list query on <font face='Courier'>allowed_users</font>; always look up by "
 "email key. Optionally store a <font face='Courier'>schoolId</font> field (already present) "
 "and index it for the rare admin 'list users in my school' view, scoped per tenant.",
 "No unscoped list of allowed_users exists; rule evaluations no longer read it on the hot path.",
)
finding(
 "SCALE-12", "Today-summary fan-out scales with section count", "LOW", "Effort: S",
 "lib/services/student_service.dart:1233  Future.wait(allKeys.map((k) => _attendance.doc(k).get()))",
 "<font face='Courier'>loadTodayFullSummary</font> issues one attendance-doc read per "
 "class-section for today. A large school with many sections (e.g. 60) does 60 reads just for "
 "today's summary, on top of the whole-student fetch from SCALE-02. Bounded by section count, "
 "so it is LOW on its own — but it compounds SCALE-02.",
 "Today's totals are assembled by reading each section's live attendance doc directly.",
 "Subsumed by the SCALE-02 rollup: a single <font face='Courier'>daily_summaries/{date}</font> "
 "doc per school removes this fan-out entirely. Until then, it is acceptable.",
 "Today's summary reads one (or a few) rollup docs, not one-per-section.",
)

story.append(PageBreak())

# ════════════════════════════════════════════════════════════ ROADMAP
story += [P("4 &nbsp; Suggested order of work", 'H1'), rule(),
          P("You do not have to do all of this at once. Each phase unlocks the next "
            "tier of school size. Hand me a phase (or individual IDs) and I will implement it.", 'Body')]

phases = [
    ("Phase A — Unblock growth past 500 students", DANGER,
     "SCALE-01, SCALE-02, SCALE-04",
     "Kills the silent 500-cap and stops dashboards reading whole schools. Adopt count() "
     "aggregates and a daily rollup doc. After this you can safely onboard schools of a few "
     "thousand students. This is the minimum to call the app 'scalable'."),
    ("Phase B — Cut cost & latency at the read layer", HIGH,
     "SCALE-03, SCALE-05, SCALE-12",
     "Remove the whole-school live listener, move rule identity onto custom claims (the "
     "pipeline already exists), and fold the today fan-out into the rollup. Big drop in "
     "Firestore reads/bill and rule fragility."),
    ("Phase C — Operational hardening for the long haul", MEDIUM,
     "SCALE-06, SCALE-07, SCALE-09, SCALE-11",
     "Remove school_1 fallbacks, schedule retention, move year-rollover to a server job, "
     "and guard the global identity collection. These keep a multi-school system healthy "
     "over years of data growth."),
    ("Phase D — Strategic / one-time decisions", LOW,
     "SCALE-08, SCALE-10",
     "Decide the Firestore region deliberately (now-or-never) and tidy the N+1 read when "
     "convenient. Low urgency, but SCALE-08 must be a conscious choice before real data lands."),
]
for title,col,ids,desc in phases:
    h = Table([[P(title,'CellHdr'), P(ids,'Tag')]], colWidths=[120*mm,36*mm])
    h.setStyle(TableStyle([
        ('BACKGROUND',(0,0),(0,0),PRIMARY),('BACKGROUND',(1,0),(1,0),col),
        ('VALIGN',(0,0),(-1,-1),'MIDDLE'),('ALIGN',(1,0),(1,0),'CENTER'),
        ('TOPPADDING',(0,0),(-1,-1),5),('BOTTOMPADDING',(0,0),(-1,-1),5),
        ('LEFTPADDING',(0,0),(-1,-1),7),
    ]))
    story += [h, Spacer(1,1.5*mm), P(desc,'Body'), Spacer(1,3*mm)]

# ════════════════════════════════════════════════════════════ HANDBACK
story += [Spacer(1,4*mm), P("5 &nbsp; How to hand this back to me", 'H1'), rule(),
    P("This report is built so you can return it to me and I will know exactly what to do. "
      "Any of these work:", 'Body'),
    P("•&nbsp; <b>By ID</b> — \"Implement SCALE-01 and SCALE-02.\" Each finding above carries "
      "its location, intent, fix and a 'Done when' acceptance test, so I have full context.", 'Body'),
    P("•&nbsp; <b>By phase</b> — \"Do Phase A.\" I will work the listed IDs in order and verify "
      "each against its acceptance criterion.", 'Body'),
    P("•&nbsp; <b>By goal</b> — \"Make it handle 10,000 students per school.\" I will map that to "
      "Phases A–B and confirm scope before starting.", 'Body'),
    Spacer(1,2*mm),
    P("Before implementing, I will restate the finding, propose the concrete code change "
      "(files + approach), and — for anything that touches rules, functions or data shape — "
      "outline how to verify it with a seeded large-school test before you ship.", 'BodyMute'),
    Spacer(1,4*mm), rule(PRIMARY,1.2),
    P("<b>Bottom line:</b> the architecture is sound and genuinely multi-tenant — you are not "
      "facing a rewrite. The blockers are a 500-row truncation and a read-the-whole-school "
      "dashboard pattern, both fixable with pagination, aggregate queries and rollup counters. "
      "Fix Phase A and you can confidently sell to multi-thousand-student schools; complete "
      "B–D and the lakhs-of-students, many-schools future is well within reach.", 'Body'),
]

# ── Page furniture ──────────────────────────────────────────────────────────
def furniture(canvas, doc):
    canvas.saveState()
    w,h = A4
    if doc.page > 1:
        canvas.setFillColor(PRIMARY)
        canvas.rect(0, h-12*mm, w, 12*mm, fill=1, stroke=0)
        canvas.setFillColor(colors.white)
        canvas.setFont('Helvetica-Bold', 8.5)
        canvas.drawString(18*mm, h-8*mm, "School App · Scalability & Multi-Tenancy Review")
        canvas.setFillColor(MUTE)
        canvas.setFont('Helvetica', 8)
        canvas.drawRightString(w-18*mm, 10*mm, f"Page {doc.page}")
        canvas.drawString(18*mm, 10*mm, "Confidential · architecture audit · 11 Jun 2026")
        canvas.setStrokeColor(RULE)
        canvas.line(18*mm, 13*mm, w-18*mm, 13*mm)
    canvas.restoreState()

doc = SimpleDocTemplate(
    "/Users/upendrapandey/school_app/SCALABILITY_REVIEW.pdf",
    pagesize=A4, topMargin=20*mm, bottomMargin=18*mm,
    leftMargin=18*mm, rightMargin=18*mm,
    title="School App — Scalability & Multi-Tenancy Review",
    author="Architecture audit",
)
doc.build(story, onFirstPage=furniture, onLaterPages=furniture)
print("OK wrote SCALABILITY_REVIEW.pdf")

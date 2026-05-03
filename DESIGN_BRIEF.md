# School App — Design Brief for Claude Design

## App Overview
A school management app for Indian schools. Used daily by Teachers, Coordinators (vice-principal), Principals, and Guardians (parents). Built with Flutter. Target device: Android phones (small-to-mid size screens).

---

## Brand & Design System

### Colors
| Token | Hex | Usage |
|-------|-----|-------|
| Primary | #1565C0 | AppBars, buttons, icons, active states |
| Primary Dark | #0D47A1 | Gradient start, pressed states |
| Primary Mid | #1976D2 | Gradient end, secondary elements |
| Background | #F7F8FC | All page backgrounds |
| Surface | #FFFFFF | Cards, tiles, bottom sheets |
| Success | #2E7D32 | Present, paid, saved |
| Warning | #F57F17 | Leave, pending, offline |
| Danger | #C62828 | Absent, error, delete |
| Text Primary | #212121 | Main text |
| Text Secondary | #757575 | Subtitles, labels |
| Divider | #E0E0E0 | Between tiles |

### Typography
- App title: 18sp Bold, white
- Screen subtitle: 11sp, white70
- Section header: 12sp, Bold, #9E9E9E, UPPERCASE, letter-spacing 0.8
- Tile title: 15sp, SemiBold (#212121)
- Tile subtitle: 12sp, Regular (#757575)
- Card label: 11sp, Medium (#757575)
- Card value: 20sp, Bold (colored)

### Component Patterns
- **AppBar**: Primary blue (#1565C0), white text, elevation 0, two-line title (name + role/date)
- **Feature Tile**: White bg, 44×44 icon box (primary.withOpacity(0.10), radius 12), title + subtitle, chevron right. Divider between tiles in same section.
- **Section Header**: 12sp grey uppercase label, padding top 20dp
- **Card**: White, radius 14, border grey.shade200, padding 16
- **Status Chip**: Pill shape, radius 20, colored text + 10% opacity bg
- **Bottom Sheet**: radius 24 top corners, white, handle bar at top
- **FAB**: Primary blue, extended with icon + label
- **Save Button**: Full-width, radius 14, 52dp height, floating above list
- **Search Bar**: White, radius 12, grey border, search icon prefix

---

## Screens to Design

---

### 1. ROLE SELECTION (Login)
**Purpose**: First screen. User picks their role and logs in.

**Layout**:
- White background
- Top: School icon (blue, 48dp) + "School App" title (28sp Bold) + "Who are you?" subtitle
- 5 role cards stacked vertically with 12dp gap:
  - Admin (manage_accounts icon)
  - Coordinator (admin_panel_settings icon)
  - Teacher (person icon)
  - Principal (business icon)
  - Guardian (family_restroom icon)

**Role Card**:
- Blue (#1565C0) tinted bg (5% opacity), blue border (20% opacity), radius 14
- Left: icon box (blue, 10% opacity bg, radius 10)
- Middle: role name (15sp Bold blue) + subtitle (12sp grey)
- Right: arrow_forward_ios icon
- On tap: shows email + password dialog

**Login Dialog**:
- Rounded corners (16dp)
- Title: role icon + "Sign in as [Role]"
- Email field + Password field (with show/hide toggle)
- Cancel + Continue (blue) buttons

---

### 2. TEACHER HOME
**Purpose**: Main screen for class teachers and regular teachers.

**AppBar**: Blue, teacher's name (bold 18sp) + "Class Teacher • Class 6" (12sp white70). Notification bell icon (with red dot badge) + logout icon.

**Body**: Scrollable list of sections. Each section = grey uppercase header + white tiles.

**Sections for Class Teacher**:
- ACADEMICS: Take Attendance, My Timetable, My Substitution Duties
- STUDENTS: Student List, Attendance History
- CALLS: Daily Calls
- LEAVE: Apply for Leave
- COPY CHECKING: Copy Checking
- HOMEWORK: Homework
- EXAMS & MARKS: Exams & Marks
- ANNOUNCEMENTS: Notice Board

All tiles use the standard Feature Tile pattern (blue icon box, title, subtitle, chevron).

---

### 3. COORDINATOR DASHBOARD
**Purpose**: Management hub for coordinator/vice-principal.

**AppBar**: Blue, "School App" + "Coordinator" subtitle. Notification bell + logout.

**Body**: Sections list + attendance cards at bottom.

**Sections**:
- ANNOUNCEMENTS: Notice Board
- FEE MANAGEMENT: Fee Structure, Fee Collection (green icon — money semantic)
- EXAMS & MARKS: Exam Management
- COPY CHECKING: Copy Checking Overview
- HOMEWORK: Homework Overview
- TIMETABLE: Timetable & Settings, School Timetable (PDF), Assign Duties
- STAFF: Manage Teachers
- STUDENTS: Student Details
- FREE BELLS: Teacher's Free Bells (amber icon — warning semantic)
- LEAVE REQUESTS: Leave Requests tile (shows pending count badge in orange)
- ANALYTICS: Analytics Dashboard
- REPORTS: Attendance Reports
- TODAY'S ATTENDANCE: Live attendance cards per class

**Attendance Card** (per class):
- White bg, left side: 44×44 icon box (colored by attendance status)
- Class name (15sp Bold) + "Present 28/32 · Absent 3 · Leave 1" (12sp grey)
- Tap to drill down to class detail
- Classes not yet marked show "Not marked yet" in italic grey

---

### 4. PRINCIPAL DASHBOARD
**Purpose**: Read-only school overview for principal.

**AppBar**: Blue, "Principal" + "School-wide overview".

**Hero Card** (top, full width):
- Blue gradient (#0D47A1 → #1976D2), radius 16, padding 18
- "TODAY" label + "X / Y classes marked" pill badge
- Large "87.5% Present" (40sp Bold white)
- Row of 4 stats: Present | Absent | Leave | Total (all white)

**Mini Stat Cards** (2 per row below hero):
- White cards with icon box: "3 Teachers on leave today" | "2 Pending leave requests"

**Sections below**:
- TODAY'S ATTENDANCE BY CLASS: same attendance tiles as coordinator
- ANALYTICS, TOOLS (Announcements, Leave Requests, Attendance Reports, School Timetable)

---

### 5. GUARDIAN DASHBOARD
**Purpose**: Parent view — child's attendance, fees, homework.

**AppBar**: Blue, "Guardian Portal" + "Your child's school activity". Notification + logout.

**Content** (scrollable cards):

1. **Student Card**: White, radius 14. Circle avatar (blue initial letter) + name (17sp Bold) + "Roll 5 • Class 6" + father name.

2. **Today's Status Banner**: Colored banner (green=Present / red=Absent / amber=Leave / grey=Not marked). Icon + title + subtitle message. Soft bg, colored border.

3. **Month Summary Card**: White card. Month nav (< April 2026 >). Stat row: Days | Present | Absent | Leave (colored numbers). Progress bar showing attendance %. Low attendance (<75%) shows red.

4. **Calendar Card**: White card. 7-column grid for the month. Each day cell: colored bg (green/red/amber) with P/A/L letter. Future dates: light grey.

5. **Fee Status Card**: White card. Wallet icon + "Fee Status" title + "Fully Paid/Pending" pill. Progress bar (green=paid, orange=due). Paid/Due/Total amounts row.

6. **Homework Section**: White card. List of latest 5 assignments. Each: subject + title + due date + status chip (Reviewed/Overdue/Due in N days).

7. **Action Buttons** (outlined, full width, stacked): Attendance Certificate | School Announcements | Contact School

---

### 6. ATTENDANCE SCREEN
**Purpose**: Class teacher marks attendance for each student.

**AppBar**: Blue. "Class 6" (17sp Bold) + "Thu, 24 Apr 2026 · 32 students" (11sp white60). "All ✓" text button on right.

**Offline Banner** (if no internet): Orange strip below AppBar. Cloud-off icon + "No internet — saved locally".

**Sync Banner** (if pending records): Blue strip. Sync icon + "2 offline records — Tap to sync".

**Search Bar**: White rounded field, appears when >10 students.

**Student List**: Each row:
- 4dp colored left border (red/amber/green)
- Circle avatar with status-colored ring
- Name (14.5sp SemiBold) + "Roll 3 · Father name" (11.5sp grey)
- A | L | P toggle: 3-segment control (Absent=red, Leave=amber, Present=green). Selected = filled color. Unselected = outline.
- Subtle divider between rows

**Floating Save Button**: Full-width, radius 14, 52dp. Green when online ("Save Attendance"), Orange when offline ("Save Offline"). Amber dot indicator when unsaved changes exist.

---

### 7. ANALYTICS DASHBOARD
**Purpose**: Visual charts for attendance trends, absence leaders, fee progress.

**AppBar**: Blue, "Analytics" title. 4 tabs below AppBar.

**Tab 1 — Overview**:
- Stats row: Present% | Absent% | Leave% (colored chips)
- BarChart: class-wise attendance comparison (x=class names, y=0-100%)
- Per-class progress tiles with LinearProgressIndicator

**Tab 2 — Attendance Trend**:
- Class picker chips at top
- LineChart: daily attendance % over current month, with 75% dashed threshold line in red
- Day summary row: working days, present, absent, leave counts

**Tab 3 — Absence Leaderboard**:
- Class picker chips
- Sorted list: student name + "X days absent in 30 days"
- 🥇🥈🥉 rank badges for top 3
- Colored progress bar per student

**Tab 4 — Fee Progress**:
- Summary stats: Total collected | Outstanding | Schools %
- BarChart: collected vs outstanding per class
- Per-class detail tiles

---

### 8. HOMEWORK SCREEN (Teacher)
**Purpose**: Teacher posts and manages homework assignments.

**AppBar**: Blue, "Homework" + teacher's subject.

**Filter Chips**: Horizontal scrollable row of class chips (Class 6, Class 7, etc.) + "All" chip.

**Homework Cards**:
- White card, radius 12
- Header: subject chip (blue pill) + class chip + status badge (Reviewed green / Pending amber / Overdue red)
- Title (15sp Bold) + description (13sp grey, 2 lines max)
- Due date row: calendar icon + date
- Delete button (red, teacher's own posts only)

**FAB**: Blue extended "+Post Homework" button.

**Post Sheet** (bottom sheet, radius 24):
- Class selector chips
- Subject dropdown
- Title text field
- Description multiline field
- Due date picker row
- "Post Homework" blue button full width

---

### 9. STUDENT LIST SCREEN
**Purpose**: View and manage students in a class.

**AppBar**: Blue, class name + "X students".

**Search Bar**: Below AppBar.

**Student Tiles**:
- White bg, left: circle avatar (blue initial)
- Name + "Roll X · Father: Name · Phone: 9999999999"
- Chevron right
- Tap: opens student detail bottom sheet

**Student Detail**:
- Large avatar, name, class, roll
- Info rows: Father, Mother, Phone, Address
- DOCUMENTS section: "Generate Attendance Certificate" outlined button
- Delete button (red, class teacher only)

**FAB**: "+ Add Student" blue button.

---

### 10. FEE COLLECTION SCREEN
**Purpose**: Record fee payments, view dues per student.

**AppBar**: Blue, "Fee Collection".

**Class Selector**: Horizontal chips.

**Summary Hero**: Blue gradient card showing total collected / outstanding / % paid.

**Student Fee Tiles**:
- Name + roll
- "₹12,000 paid · ₹3,000 due" 
- Green "Paid" or orange "Pending" pill badge
- Tap: opens payment recording sheet

---

### 11. LEAVE APPLICATION SCREEN (Teacher)
**AppBar**: Blue, "Apply for Leave".

**Teacher Card**: White card with avatar (blue initial) + name + subject.

**Form**:
- Submit to: Coordinator / Principal (toggle chips)
- Start date picker row (calendar icon + date)
- Number of days stepper (− 3 + )
- End date: auto-calculated, shown as grey label
- Reason dropdown (Medical, Family, Emergency, etc.)
- Blue "Submit Application" button full width

---

### 12. LEAVE REQUESTS SCREEN (Coordinator/Principal)
**AppBar**: Blue, "Leave Requests" + pending count badge.

**Filter Chips**: All | Pending | Approved | Rejected

**Request Cards**:
- Teacher name + subject
- Date range + days
- Reason label
- Status chip: orange=Pending, green=Approved, red=Rejected
- Pending cards: Approve (green) + Reject (red) action buttons

---

### 13. DAILY CALLS SCREEN
**Purpose**: Track which absent/leave students' parents have been called.

**AppBar**: Blue, "Daily Calls" + 2 tabs (Today | History).

**Today Tab**:
- Summary bar: X absent, Y called, Z pending
- Student tiles: name + status chip (Absent/Leave) + "Called / Not Called" toggle button
- Called: green check button. Not called: grey phone button.
- Tap "not called" → opens reason dialog

**History Tab**:
- Date-grouped list of past call records

---

### 14. ADMIN SCREEN
**Purpose**: Register new users with email+password+role.

**AppBar**: Blue, "Admin Panel" + "Manage login access".

**Form** (inside blue header area below AppBar):
- Role dropdown
- Email field
- Password field + show/hide
- "Add" white button with blue text

**Users List**:
- Each tile: email + role chip (colored) + delete icon
- Section header: "REGISTERED USERS (12)"

---

### 15. TIMETABLE SETTINGS SCREEN
**AppBar**: Blue, "Timetable & Settings".

**Tabs**: Bell Schedule | Classes | Teachers

**Bell Schedule Tab**:
- List of bells: "Bell 1 — 08:00 AM — 08:45 AM" 
- Edit/delete per bell
- "+ Add Bell" FAB (blue)

**Classes Tab**:
- Class chips grid (Class 6, Class 7...)
- "+ Add Class" button

**Teachers Tab**:
- Teacher tiles: name + subject + class teacher badge
- Assign/edit timetable per teacher

---

## Design Goals & Quality Bar

1. **Pixel-perfect Material Design 2** — not Material 3 (no dynamic color, no rounded mega-shapes)
2. **WhatsApp-level simplicity** — every user can use it without training
3. **Information density** — show maximum useful info per tile without crowding
4. **Consistent spacing** — 16dp horizontal padding, 12dp vertical tile padding, 20dp section header top
5. **One-hand usability** — important actions reachable with thumb (FAB bottom-right, save button bottom center)
6. **Status clarity** — color + icon + text for every status (never color alone)
7. **Loading states** — shimmer or centered CircularProgressIndicator (primary blue)
8. **Empty states** — centered icon + message + CTA button

---

## What to Design

Please create high-fidelity mobile UI mockups (393dp width, Android style) for ALL 15 screens above. Use:
- Realistic data (student names, class names, numbers)
- The exact color tokens specified
- The exact component patterns specified
- Consistent spacing and typography

For each screen, show the primary/default state. For attendance screen also show the offline state.

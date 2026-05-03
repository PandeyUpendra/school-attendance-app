# DONE — Features Already Built

## Role Selection
- [x] Role selection screen on launch: **Coordinator** or **Teacher**
- [x] Teacher role: pick a saved teacher from list → lands on Teacher Home
- [x] Coordinator role: lands on Coordinator Dashboard directly
- [x] Switch Role button available on every home screen (AppBar)

---

## Coordinator Dashboard
- [x] Grid of feature tiles: Teacher Management, Bell & Class Settings, Timetable Editor, Student Details, Assign Duties
- [x] Navigation to all coordinator sections

---

## Teacher Management (Coordinator only)
- [x] List all teachers with name, subject, class-teacher badge
- [x] Add teacher dialog:
  - Name, Subject, Email, Phone
  - Section field gated behind "Class Teacher" toggle
  - Class picker appears only when Class Teacher is ON
- [x] Edit teacher (same dialog, pre-filled)
- [x] Delete teacher (with confirmation + removes from timetable)
- [x] Teachers stored in SharedPreferences (`tt_teachers`)

---

## Bell & Class Settings (Coordinator only)
- [x] Configure number of bells (drag-to-reorder list)
- [x] Per-bell duration (minutes) — editing Bell 1 propagates to all non-lunch bells
- [x] First bell start time (12-hour picker, stored as 24-hour HH:MM)
- [x] Absolute start times cascade automatically from Bell 1 time + durations
- [x] Display times in 12-hour AM/PM format
- [x] Single insertable **Lunch Bell** (via "Lunch" header button); hidden once one exists
- [x] Lunch bell has its own duration; is skipped in bell numbering (Bell 4 → Lunch → Bell 5)
- [x] Class list management: add / rename / delete class names
- [x] Settings stored in SharedPreferences (`tt_settings`)

---

## Timetable Editor (Coordinator only)
- [x] Grid: rows = classes, columns = bells
- [x] Aggregated view (no day selector) — each cell shows the teacher assigned across days
- [x] Cell shows: teacher avatar, full name, subject, day-dot indicators (Mo/Tu/We…)
- [x] Tap cell → `_CellPickerSheet` bottom sheet:
  - Multi-day selection chips (Mon–Sat, tap to toggle)
  - Teacher list with color avatar
  - Optional custom subject field (auto-filled from teacher's default)
  - "Assign" button (enabled when teacher + at least one day selected)
  - "Clear All" removes teacher from every day for that slot
- [x] Clash detection: same teacher cannot be in two classes at the same bell on the same day
- [x] Timetable stored in SharedPreferences (`tt_data`), shape: `className → day → bell → TimetableEntry`
- [x] Backward-compatible loader handles pre-day and pre-TimetableEntry formats

---

## My Timetable (Teacher view — read-only)
- [x] Day selector row (Mon–Sat pill buttons)
- [x] Grid: rows = classes, columns = bells
- [x] Each cell shows teacher avatar, full name, subject
- [x] Info strip: total classes, bells/day

---

## Attendance Screen
- [x] Reached directly (class teacher) or via ClassPickerScreen (regular teacher/coordinator)
- [x] **Mark All Present** button (AppBar `done_all` icon)
- [x] **Save Attendance** button (AppBar check icon)
- [x] Student photo shown in list (falls back to roll-number avatar)
- [x] **3-state toggle per student**: P (Present, green) | L (Leave, amber) | A (Absent, red)
- [x] Summary strip: Total / Present / Leave / Absent counts
- [x] Save confirmation dialog with Present / Leave / Absent breakdown
- [x] Swipe-to-remove student (with confirmation)
- [x] Attendance stored per class per day in SharedPreferences
- [x] Backward-compatible loader: old `bool` values migrate to `'Present'`/`'Absent'`

---

## Student Management
- [x] **Add Student** form (class teacher only, via FAB in Student List):
  - Roll number (unique per class), Full name, Father's name, Mother's name (optional)
  - Phone number, Fee status (Paid / Pending / Partial)
  - Photo: camera or gallery via `image_picker`
- [x] **Edit Student** (pencil icon in Student Profile page, class teacher only)
- [x] **Delete Student** (bin icon in Student Profile page, class teacher only)

---

## Student List Screen
- [x] Search bar (name, roll, father's name, phone)
- [x] Student cards: photo avatar, name, roll, father, phone, fee badge
- [x] Tap card → **Student Profile page**
- [x] FAB "Add Student" shown only for class teachers

---

## Student Profile Page
- [x] Teal header: large photo/avatar, name, roll chip, class chip
- [x] Contact section: phone number + **Call** button (opens dialer) + **WhatsApp** button (opens wa.me)
- [x] Family section: father's name, mother's name
- [x] Fee status badge with colour and icon
- [x] Edit & Delete actions in AppBar (class teacher only)

---

## Home Screens

### Teacher Home (class teacher)
- [x] ACADEMICS section: Take Attendance → directly to their class (no class picker)
- [x] STUDENTS section: Student List → directly to their class with edit rights

### Teacher Home (non-class teacher)
- [x] Take Attendance → ClassPickerScreen → AttendanceScreen
- [x] My Timetable
- [x] Student List → ClassPickerScreen → StudentListScreen (read-only)

---

## Data Storage
- [x] All data via `SharedPreferences` (local, offline)
- [x] Singleton service pattern: `TimetableService`, `StudentService`, `AuthService`
- [x] Teachers: `tt_teachers` (JSON array)
- [x] Settings: `tt_settings` (JSON object)
- [x] Timetable: `tt_data` (nested JSON)
- [x] Students: `students_list` (JSON array)
- [x] Attendance: `attendance_<className>_<YYYY-M-D>` (JSON object)

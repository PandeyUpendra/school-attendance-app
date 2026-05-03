# PROJECT_CONTEXT.md
> Complete technical reference for the School App codebase.
> **For AI models:** Read this file first before answering any question or suggesting any change. All architectural decisions, naming conventions, and business rules are documented here.

---

## 1. PROJECT OVERVIEW

**App Name:** School App (`school_app`)  
**Platform:** Flutter — runs on Android, iOS, macOS, Windows, Web  
**Firebase Project:** `attendanceapp-e76e1`  
**Current Version:** 1.0.0+1  

### Purpose
A multi-role school management application for a single school. It digitises daily school operations: attendance marking, timetable management, teacher leave, exam marks, fee collection, homework tracking, copy-checking, announcements, and a photo gallery.

### Target Users (4 roles)
| Role | Who | What they do |
|---|---|---|
| **Teacher** | Subject/class teachers | Mark attendance, post homework, check copies, apply for leave |
| **Coordinator** | School admin/head teacher | Oversee all classes, manage timetable, fees, exams, substitutions |
| **Principal** | School principal | School-wide attendance view, leave approvals, announcements |
| **Guardian** | Parent/guardian | Track their child's attendance, fees, homework, exam results |

### Problem It Solves
Replaces paper registers and WhatsApp groups with a structured system where: class teachers mark daily attendance, guardians receive real-time absence alerts, coordinators manage staff leave and substitutions, and exam results + fee payments are tracked digitally.

---

## 2. TECH STACK

### Language & Framework
- **Dart 3.3.4+** — primary language
- **Flutter** (Material Design, `useMaterial3: false`) — UI framework

### Backend & Database
- **Cloud Firestore** — primary database (NoSQL, document/collection model)
- **Firebase Storage** — used exclusively by GalleryService for photo uploads
- **No Firebase Auth** — login is custom: email+password checked against the `allowed_users` Firestore collection

### Local Storage
- **SharedPreferences** — session persistence (who is logged in), offline attendance queue, notification unread markers

### Key Packages
| Package | Version | Purpose |
|---|---|---|
| `firebase_core` | ^2.27.0 | Firebase initialization |
| `cloud_firestore` | ^4.17.0 | All Firestore read/write operations |
| `firebase_storage` | ^11.7.0 | Gallery photo upload/download |
| `shared_preferences` | ^2.2.2 | Local session & offline queue |
| `fl_chart` | ^0.68.0 | Analytics bar/line charts |
| `pdf` + `printing` | ^3.10.8 / ^5.12.0 | Timetable & attendance certificate PDF export |
| `flutter_image_compress` | ^2.1.0 | Compress photos before gallery upload |
| `image` | ^4.1.3 | Watermark rendering on gallery photos |
| `cached_network_image` | ^3.3.1 | Gallery photo display with caching |
| `shimmer` | ^3.0.0 | Loading skeleton animations |
| `url_launcher` | ^6.3.0 | Phone calls from guardian portal |
| `image_picker` | ^1.1.2 | Photo selection for gallery |
| `file_picker` | ^8.0.5 | File selection |
| `csv` | ^6.0.0 | CSV data export |
| `share_plus` | ^7.2.1 | Share PDFs/certificates |
| `connectivity_plus` | ^6.0.3 | Network status detection |
| `font_awesome_flutter` | 10.6.0 | Icon set extension |
| `google_sign_in` | ^6.2.1 | **In pubspec but appears unused** (see Known Issues) |

---

## 3. FOLDER STRUCTURE

```
school_app/
├── lib/
│   ├── main.dart                    ★ Entry point, _SplashGate router
│   ├── theme.dart                   ★ AppTheme — single source of all colours
│   ├── firebase_options.dart        Auto-generated Firebase config (do not edit)
│   │
│   ├── models/                      ★ Plain Dart data classes (no code generation)
│   │   ├── student.dart             Student fields + toJson/fromJson
│   │   ├── teacher.dart             Teacher fields
│   │   ├── timetable_entry.dart     Single timetable slot (teacherId + subject)
│   │   ├── announcement.dart        School announcement
│   │   ├── homework.dart            Homework assignment
│   │   ├── exam.dart                Exam + ExamResult (marks per student)
│   │   ├── fee.dart                 FeeStructure + FeeComponent + Payment
│   │   ├── copy_check.dart          CopyCheck session + CopyStatus per student
│   │   ├── gallery_album.dart       Album metadata
│   │   ├── gallery_photo.dart       Photo metadata + 3 Storage URLs
│   │   └── substitution_record.dart Historical substitution event
│   │
│   ├── services/                    ★ All Firestore I/O — singletons
│   │   ├── auth_service.dart        SharedPreferences session (login/logout)
│   │   ├── timetable_service.dart   Teachers, settings, timetable, duties,
│   │   │                            allowed_users, substitutions, leave_applications
│   │   ├── student_service.dart     Students + attendance (all date-keyed reads)
│   │   ├── notification_service.dart notifications collection + unread tracking
│   │   ├── announcement_service.dart announcements collection
│   │   ├── homework_service.dart    homework collection
│   │   ├── exam_service.dart        exams + exam_results sub-collection
│   │   ├── fee_service.dart         fee_structures + fee_payments nested sub-collection
│   │   ├── copy_check_service.dart  copy_checks + statuses sub-collection
│   │   ├── gallery_service.dart     ★ Only service using Firebase Storage
│   │   ├── substitution_history_service.dart  substitution_history collection
│   │   └── offline_queue_service.dart  SharedPreferences attendance queue
│   │
│   └── screens/                     All UI screens
│       ├── role_selection_screen.dart   Login screen (email+password)
│       ├── home_screen.dart             ★ Teacher dashboard
│       ├── coordinator_dashboard.dart   ★ Coordinator dashboard
│       ├── principal_dashboard.dart     ★ Principal dashboard
│       ├── guardian_dashboard.dart      ★ Guardian portal (single student view)
│       ├── admin_screen.dart            User management (add/remove allowed_users)
│       │
│       ├── attendance_screen.dart       Mark today's attendance
│       ├── attendance_history_screen.dart  Monthly attendance grid/reports
│       ├── attendance_class_detail_screen.dart  Per-date detail
│       ├── student_list_screen.dart     List students in a class
│       ├── add_student_screen.dart      Add/edit a student
│       ├── student_details_screen.dart  Coordinator student overview
│       ├── class_picker_screen.dart     Shared class-selection dialog
│       │
│       ├── timetable_settings_screen.dart  Bell schedule + class config
│       ├── my_timetable_screen.dart        Personal/school timetable + PDF export
│       ├── assign_duties_screen.dart       Daily assembly/gate duties
│       ├── free_bells_screen.dart          Free bells + assign substitutions
│       ├── substitution_history_screen.dart  Teacher's sub duty history
│       │
│       ├── leave_application_screen.dart  Teacher submits leave
│       ├── leave_requests_screen.dart     Coordinator/principal approves leave
│       │
│       ├── exam_management_screen.dart    Create exams, enter marks
│       ├── report_card_screen.dart        Per-student report card
│       ├── homework_screen.dart           Teacher posts homework
│       ├── homework_overview_screen.dart  Coordinator views all homework
│       ├── copy_checking_screen.dart      Teacher marks copy status
│       ├── copy_check_overview_screen.dart  Coordinator overview
│       │
│       ├── announcements_screen.dart      Post/view announcements
│       ├── notifications_screen.dart      Notification inbox
│       ├── teacher_management_screen.dart  Add/remove teachers
│       ├── teacher_profile_screen.dart     Teacher profile view
│       │
│       ├── fee_structure_screen.dart      Set class fee structure
│       ├── fee_collection_screen.dart     Record & view payments
│       │
│       ├── analytics_screen.dart          Charts: attendance trends, absences
│       ├── daily_calls_screen.dart        Track guardian calls for absent students
│       ├── attendance_certificate_screen.dart  Generate attendance PDF certificate
│       │
│       └── gallery/
│           ├── gallery_home_screen.dart       Album list
│           ├── album_detail_screen.dart        Photos in an album
│           ├── create_album_screen.dart        Create new album
│           └── fullscreen_photo_viewer.dart    Fullscreen photo with zoom
│
├── CLAUDE.md            Project instructions for Claude Code
├── PROJECT_CONTEXT.md   ← this file
├── pubspec.yaml         Dependencies
└── firebase.json        Firebase config
```

**Most important directories:**
- `lib/services/` — all database access lives here; never write Firestore calls in screens
- `lib/models/` — canonical data shapes; always use these for Firestore serialisation
- `lib/theme.dart` — all colours; never use raw `Color(0x...)` literals in screens

---

## 4. DATABASE SCHEMA

### Firestore Collections

---

#### `students/{className_section_roll}` ★ CORE SCHEMA
**Doc ID format:** `{className}_{section}_{roll}` — spaces replaced with underscores  
Examples: `Class_6_A_12`, `Class_10_32`

```
roll          : int           ★ primary student identifier within a class
name          : String
className     : String        e.g. "Class 6"
section       : String        e.g. "A" (empty string if no section)
fatherName    : String
motherName    : String?
phone         : String        guardian contact number
photoPath     : String?       optional photo URL/path
feeStatus     : String        'Paid' | 'Pending' | 'Partial'
teacherId     : String?       ID of class teacher who owns this record (null on legacy docs)
```

**Relationships:**
- `teacherId` → `teachers/{teacherId}`
- `className + roll` → `attendance/{className_YYYY-M-D}` (rolls sub-map key)
- `className + roll` → `exam_results/{examId}/students/{roll}`
- `className + roll` → `fee_payments/{className}/students/{roll}/payments/`

---

#### `attendance/{className_YYYY-M-D}`
**Doc ID format:** `Class_6_2026-5-3` (no zero-padding on month/day)

```
rolls         : Map<String, String>   key=roll as string, value='Present'|'Absent'|'Leave'
reasons       : Map<String, String>?  key=roll as string, value=reason text
called        : Map<String, bool>?    key=roll as string, value=whether teacher called
updatedAt     : Timestamp
```

**Note:** Legacy docs may have `rolls` values as `bool` (true=Present, false=Absent). All read methods auto-migrate this.

---

#### `teachers/{teacherId}`
**Doc ID:** manually set teacher ID (not an auto-generated Firestore ID)

```
id            : String        same as doc ID
name          : String
subject       : String
email         : String
section       : String        section this teacher is responsible for
isClassTeacher: bool
classTeacherOf: String?       class name e.g. "Class 6" (null if not a class teacher)
```

---

#### `settings/main`
Single document — school-wide configuration

```
numberOfBells : int           derived from bells array length
classes       : String[]      e.g. ["Class 6", "Class 7", "Class 8", "Class 9", "Class 10"]
firstBellTime : String        "HH:MM" 24-hour format, e.g. "08:00"
bells         : Array<{
  duration    : int           minutes
  isLunch     : bool          whether this slot is a lunch break
}>
```

---

#### `timetable/{className}`
**Doc ID:** class name (e.g. "Class 6")

```
data: {
  "Monday": {
    "1": { teacherId: String|null, subject: String|null },
    "2": { teacherId: String|null, subject: String|null },
    ...N (N = numberOfBells)
  },
  "Tuesday": { ... },
  "Wednesday": { ... },
  "Thursday": { ... },
  "Friday": { ... },
  "Saturday": { ... }
}
```

**Relationships:** `teacherId` → `teachers/{teacherId}`

---

#### `duties/{YYYY-M-D}`
Daily teacher duty assignments (assembly, gate, lunch, etc.)

```
assignments   : Map<String, String>   teacherId → duty description string
updatedAt     : Timestamp
```

---

#### `substitutions/{YYYY-M-D}`
Daily substitution assignments for free bells

```
"{className}_{bell}" : String   value = substituteTeacherId
updatedAt            : Timestamp
```

Example key: `"Class 6_3"` means bell 3 of Class 6.

---

#### `substitution_history/{autoId}`
Permanent log of every substitution event

```
dateKey               : String    'YYYY-M-D'
date                  : Timestamp
className             : String
bell                  : int
substituteTeacherId   : String
substituteTeacherName : String    ← denormalised copy at write time
originalTeacherId     : String
originalTeacherName   : String    ← denormalised copy at write time
subject               : String
createdAt             : Timestamp
```

---

#### `allowed_users/{email}`
**Doc ID:** lowercased email — the user registry / login table

```
email           : String
password        : String        ⚠ PLAINTEXT — no hashing
role            : String        'teacher' | 'coordinator' | 'principal' | 'guardian'
studentClass    : String?       guardians only — linked student's class
studentRoll     : int?          guardians only — linked student's roll
assignedClasses : String[]?     coordinator/principal only — classes they oversee
```

**Relationships:**
- For teachers: after login the app fetches teacher record from `teachers/` by email
- For guardians: `studentClass + studentRoll` → `students/{id}`

---

#### `leave_applications/{autoId}`

```
teacherId      : String
teacherName    : String         ← denormalised
teacherEmail   : String
toRole         : String         'coordinator' | 'principal'
startDate      : String         ISO date string e.g. "2026-05-03"
numberOfDays   : int
reason         : String
status         : String         'pending' | 'approved' | 'rejected'
coordinatorNote: String?        added when resolved
createdAt      : Timestamp
```

---

#### `notifications/{autoId}`
Server-side notification fan-out (no push server — clients poll Firestore)

```
type      : String    'absent' | 'leave_submitted' | 'leave_resolved' | 'announcement' | 'gallery'
title     : String
body      : String
audience  : String    'all' | 'teachers' | 'guardians' | 'coordinator' | 'principal'
                      | 'teacher:{teacherId}' | 'guardian:{className}:{roll}'
createdAt : Timestamp
```

Clients filter in-memory by `audience`. Records older than 30 days are ignored on read.

---

#### `announcements/{autoId}`

```
title        : String
body         : String
postedBy     : String    poster's email/name
postedByRole : String    'coordinator' | 'principal'
audience     : String    'all' | 'teachers' | 'guardians'
isPinned     : bool
postedAt     : Timestamp
```

---

#### `homework/{autoId}`

```
teacherId   : String
teacherName : String    ← denormalised
className   : String
subject     : String
title       : String
description : String
dueDate     : Timestamp
postedAt    : Timestamp
isReviewed  : bool      teacher marks reviewed after checking copies
```

---

#### `exams/{examId}`

```
name      : String    e.g. "Unit Test 1", "Half Yearly"
className : String
subjects  : String[]
maxMarks  : int       per subject
examDate  : Timestamp
createdBy : String    coordinator email
```

**Sub-collection:** `exam_results/{examId}/students/{roll}`

```
roll        : int
studentName : String    ← denormalised
className   : String    ← denormalised
examId      : String    ← redundant with parent doc ID
examName    : String    ← denormalised
marks       : Map<String, double?>    subject → marks (null = absent/not entered)
maxMarks    : int
enteredBy   : String    teacher email
```

---

#### `fee_structures/{className}`
**Doc ID:** class name with spaces → underscores

```
className      : String
totalAnnualFee : double
components     : Array<{
  name         : String    e.g. "Tuition", "Transport", "Exam Fee"
  amount       : double
}>
```

---

#### `fee_payments/{className}/students/{roll}/payments/{autoId}`
4-level deep nested path.

```
amount    : double
paidOn    : Timestamp
mode      : String    'Cash' | 'UPI' | 'Bank' | 'Cheque'
receiptNo : String    format: RCP-{3chars}-{roll}-{timestamp}
note      : String?
```

---

#### `copy_checks/{checkId}`
One session = one teacher checking one class's copies on one day

```
teacherId   : String
teacherName : String    ← denormalised
className   : String
subject     : String
checkDate   : Timestamp
createdAt   : Timestamp
```

**Sub-collection:** `copy_checks/{checkId}/statuses/{roll}`

```
roll          : int
studentName   : String    ← denormalised from Student
guardianPhone : String    ← denormalised from Student
status        : String    'checked' | 'incomplete' | 'not_done'
remarks       : String?
```

---

#### `schools/school_1/albums/{albumId}`
School ID is hardcoded as `'school_1'` in GalleryService.

```
title         : String
description   : String
eventDate     : Timestamp
coverPhotoUrl : String    URL of the compressed variant of the first photo
createdBy     : String    uploader's email
createdAt     : Timestamp
photoCount    : int       maintained by increment/decrement on upload/delete
isPublished   : bool
```

#### `schools/school_1/photos/{photoId}`

```
albumId        : String    → schools/school_1/albums/{albumId}
originalUrl    : String    Firebase Storage download URL
compressedUrl  : String    resized to 1080px, 70% quality
watermarkedUrl : String    compressed + school name watermark bottom-right
uploadedBy     : String
uploadedAt     : Timestamp
fileName       : String
```

---

### Firebase Storage Paths

```
schools/school_1/gallery/{albumId}/original/{photoId}.jpg
schools/school_1/gallery/{albumId}/compressed/{photoId}.jpg
schools/school_1/gallery/{albumId}/watermarked/{photoId}.jpg
```

---

### SharedPreferences (device-local — not synced)

| Key | Type | Purpose |
|---|---|---|
| `auth_email` | String | Logged-in user email |
| `auth_role` | String | User role |
| `auth_teacher_id` | String | Teacher's ID (from `teachers/` collection) |
| `auth_student_class` | String | Guardian: linked student's class |
| `auth_student_roll` | int | Guardian: linked student's roll |
| `auth_assigned_classes` | String | Comma-delimited assigned classes (coordinator/principal) |
| `notif_last_seen_ms` | int | Milliseconds timestamp: last time notifications were opened |
| `notif_ann_last_seen_ms` | int | Milliseconds timestamp: last time announcements were opened |
| `attendance_offline_queue` | JSON String | Array of pending attendance writes queued while offline |

---

### Cross-Collection Relationships Summary

```
allowed_users/{email}
  └── role='teacher' → teachers/{teacherId}   (fetched by email match after login)
  └── role='guardian' → students/{id}          (via studentClass + studentRoll)

teachers/{teacherId}
  └── classTeacherOf → timetable/{className}
  └── id → timetable/{className}.data.*.*.teacherId
  └── id → substitutions/{date}.*
  └── id → leave_applications.teacherId
  └── id → copy_checks.teacherId
  └── id → homework.teacherId
  └── id → substitution_history.substituteTeacherId / originalTeacherId

students/{id}
  └── className + roll → attendance/{className_date}
  └── className + roll → exam_results/{examId}/students/{roll}
  └── className + roll → fee_payments/{className}/students/{roll}/
  └── teacherId → teachers/{teacherId}

exams/{examId}
  └── examId → exam_results/{examId}/students/{roll}

copy_checks/{checkId}
  └── checkId → copy_checks/{checkId}/statuses/{roll}
```

---

## 5. APP MODULES

### Module 1: Authentication & Session
**What it does:** No Firebase Auth. Custom login — email+password validated against `allowed_users` Firestore collection. Session persisted in SharedPreferences. `_SplashGate` in `main.dart` auto-routes returning users to their dashboard.

**Files:** `lib/main.dart`, `lib/screens/role_selection_screen.dart`, `lib/services/auth_service.dart`  
**Collections:** `allowed_users`  
**Roles:** All

---

### Module 2: Attendance
**What it does:** Class teachers mark each student as Present/Absent/Leave. Stores one Firestore doc per class per day. Supports offline queueing when no internet. Coordinators/principals see today's full summary across all classes with consecutive-absence streaks.

**Files:**
- `lib/screens/attendance_screen.dart` — take today's attendance
- `lib/screens/attendance_history_screen.dart` — monthly grid view
- `lib/screens/attendance_class_detail_screen.dart` — per-date drill-down
- `lib/services/student_service.dart` — all attendance read/write methods
- `lib/services/offline_queue_service.dart` — offline write queue

**Collections:** `attendance`, `students`  
**Roles:** Teacher (mark), Coordinator/Principal (view summaries), Guardian (view own child)

---

### Module 3: Student Management
**What it does:** Class teachers add/edit/remove students in their assigned class. Coordinator can view all students across all classes. Removing a student cascade-deletes their attendance roll entries.

**Files:** `lib/screens/student_list_screen.dart`, `lib/screens/add_student_screen.dart`, `lib/screens/student_details_screen.dart`, `lib/services/student_service.dart`, `lib/models/student.dart`  
**Collections:** `students`, `attendance` (cascade delete)  
**Roles:** Teacher (own class), Coordinator (all classes)

---

### Module 4: Timetable
**What it does:** Coordinator configures school bell schedule and class list in `settings/main`. Assigns teachers to class+day+bell slots in `timetable/{className}`. Teachers view their personal timetable. All users can export as PDF.

**Files:** `lib/screens/timetable_settings_screen.dart`, `lib/screens/my_timetable_screen.dart`, `lib/services/timetable_service.dart`, `lib/models/timetable_entry.dart`  
**Collections:** `timetable`, `settings`  
**Roles:** Coordinator (manage), Teacher/Principal/Guardian (view)

---

### Module 5: Leave Management
**What it does:** Teachers submit leave applications to coordinator or principal. Coordinator/principal approves or rejects. Approved leave feeds into the substitution module to identify absent teachers.

**Files:** `lib/screens/leave_application_screen.dart`, `lib/screens/leave_requests_screen.dart`, `lib/services/timetable_service.dart`  
**Collections:** `leave_applications`, `notifications`  
**Roles:** Teacher (submit), Coordinator/Principal (review)

---

### Module 6: Substitutions & Duties
**What it does:** Daily duty assignments (assembly, gate). Free bells screen shows which bells are uncovered because a teacher is on leave. Coordinator assigns substitute teachers. Every assignment is logged to `substitution_history`. Auto-suggests teachers with fewer recent substitutions.

**Files:** `lib/screens/assign_duties_screen.dart`, `lib/screens/free_bells_screen.dart`, `lib/screens/substitution_history_screen.dart`, `lib/services/timetable_service.dart`, `lib/services/substitution_history_service.dart`  
**Collections:** `duties`, `substitutions`, `substitution_history`, `timetable`, `leave_applications`  
**Roles:** Coordinator (manage), Teacher (view own history)

---

### Module 7: Notifications
**What it does:** Serverless notification system. When events occur (absent mark, leave submitted/approved, announcement), a document is written to `notifications`. Clients fetch and filter by `audience` field. Unread state is local (SharedPreferences timestamp). No push notifications.

**Files:** `lib/screens/notifications_screen.dart`, `lib/services/notification_service.dart`  
**Collections:** `notifications`  
**Roles:** All (each role sees their audience-filtered subset)

---

### Module 8: Announcements
**What it does:** Coordinator/principal post notices to all, teachers only, or guardians only. Announcements can be pinned (shown first). Teachers and guardians see a notice board.

**Files:** `lib/screens/announcements_screen.dart`, `lib/services/announcement_service.dart`, `lib/models/announcement.dart`  
**Collections:** `announcements`, `notifications` (notification written on post)  
**Roles:** Coordinator/Principal (post), Teacher/Guardian (view)

---

### Module 9: Exams & Marks
**What it does:** Coordinator creates exams (name, class, subjects, maxMarks, date). Teachers enter marks per student (null = absent). Per-student report cards show grade, %, progress bar. Guardians see all their child's results.

**Files:** `lib/screens/exam_management_screen.dart`, `lib/screens/report_card_screen.dart`, `lib/services/exam_service.dart`, `lib/models/exam.dart`  
**Collections:** `exams`, `exam_results/{examId}/students`  
**Roles:** Coordinator (create exams), Teacher (enter marks), Guardian (view results)

---

### Module 10: Fee Management
**What it does:** Coordinator defines fee structure per class (components + total). Records individual payments per student. Tracks paid vs. outstanding. Guardian portal shows fee status summary for their child.

**Files:** `lib/screens/fee_structure_screen.dart`, `lib/screens/fee_collection_screen.dart`, `lib/services/fee_service.dart`, `lib/models/fee.dart`  
**Collections:** `fee_structures`, `fee_payments`  
**Roles:** Coordinator (manage), Guardian (view)

---

### Module 11: Homework
**What it does:** Teachers post assignments (subject, title, description, due date) for their classes. Teachers can mark as reviewed. Coordinator sees all homework across classes. Guardian sees their child's class homework.

**Files:** `lib/screens/homework_screen.dart`, `lib/screens/homework_overview_screen.dart`, `lib/services/homework_service.dart`, `lib/models/homework.dart`  
**Collections:** `homework`  
**Roles:** Teacher (post/review), Coordinator (overview), Guardian (view)

---

### Module 12: Copy Checking
**What it does:** Teachers create a checking session for a class. Mark each student's copy as `checked`, `incomplete`, or `not_done`. Coordinator sees an overview per class. Teacher can add remarks per student.

**Files:** `lib/screens/copy_checking_screen.dart`, `lib/screens/copy_check_overview_screen.dart`, `lib/services/copy_check_service.dart`, `lib/models/copy_check.dart`  
**Collections:** `copy_checks`, `copy_checks/{id}/statuses`  
**Roles:** Teacher (mark), Coordinator (view)

---

### Module 13: Gallery
**What it does:** Coordinator/principal upload event photos organised into albums. Photos are compressed (1080px, 70% quality), watermarked with "Our School" text, and stored in Firebase Storage in 3 variants. Albums can be published/unpublished. All roles view published albums.

**Files:** `lib/screens/gallery/gallery_home_screen.dart`, `lib/screens/gallery/album_detail_screen.dart`, `lib/screens/gallery/create_album_screen.dart`, `lib/screens/gallery/fullscreen_photo_viewer.dart`, `lib/services/gallery_service.dart`, `lib/models/gallery_album.dart`, `lib/models/gallery_photo.dart`  
**Collections:** `schools/school_1/albums`, `schools/school_1/photos`, `notifications`  
**Storage:** `schools/school_1/gallery/{albumId}/{variant}/{photoId}.jpg`  
**Roles:** Coordinator/Principal (upload/manage), Teacher/Guardian (view)

---

### Module 14: Analytics
**What it does:** Charts for attendance trends (line chart), top absentees (bar chart), class-wise attendance comparison. Uses `fl_chart`. Data is computed from raw attendance reads.

**Files:** `lib/screens/analytics_screen.dart`  
**Collections:** `attendance`, `students`  
**Roles:** Coordinator, Principal

---

### Module 15: Daily Calls
**What it does:** After attendance is marked, class teacher sees absent/leave students with guardian phone numbers. Can track which guardians have been called with a checkmark.

**Files:** `lib/screens/daily_calls_screen.dart`, `lib/services/student_service.dart` (`saveCalled`, `loadTodayCalled`)  
**Collections:** `attendance` (`called` sub-map field)  
**Roles:** Teacher (class teacher only)

---

### Module 16: Admin (User Management)
**What it does:** Manage the `allowed_users` list — add/edit/remove user accounts, assign roles, link guardians to student records, assign classes to coordinators.

**Files:** `lib/screens/admin_screen.dart`, `lib/services/timetable_service.dart` (user CRUD methods)  
**Collections:** `allowed_users`  
**Roles:** Coordinator (primary admin)

---

### Module 17: Attendance Certificate
**What it does:** Generate a formal PDF attendance certificate for a student, with date range selector. Uses `pdf` + `printing` packages for export/share.

**Files:** `lib/screens/attendance_certificate_screen.dart`  
**Collections:** `attendance`  
**Roles:** Guardian (for own child), Coordinator

---

## 6. DATA FLOW

### Pattern: UI → Service → Firestore → UI

All services are singletons accessed via factory constructor: `StudentService()`, `TimetableService()`, etc. Screens call service methods directly — there is no BLoC, Provider, Riverpod, or other state management layer.

```
Widget (StatefulWidget)
  └── initState() → calls service.getData()
       └── Service.getData()
            └── FirebaseFirestore.instance.collection('x').get()
                 └── .then() / await → parses into Model
                      └── setState(() => _data = model)
                           └── build() re-renders
```

### Real-time vs. One-shot

Most screens use **one-shot futures** (fetch once on load, refresh on pull-to-refresh). Only a few use streams:
- `StudentService.watchStudents()` — used by Coordinator/Principal dashboards to react to roster changes
- `StudentService.watchStudentsByClass()` — used by attendance screen
- `AnnouncementService.watchAnnouncements()` — for badge counts
- `GalleryService.getAlbums()` / `getPhotos()` — real-time photo streams

### How Student Data Flows

1. **Adding a student:** `AddStudentScreen` → `StudentService.addStudent()` → writes to `students/{id}` with doc ID `{className}_{section}_{roll}`
2. **Marking attendance:** `AttendanceScreen` fetches student list via `StudentService.getStudentsByClass()`, then writes attendance map to `attendance/{className_date}` via `StudentService.saveAttendance()`
3. **Guardian viewing child:** `GuardianDashboard` receives `studentClass` + `studentRoll` from session, calls `StudentService.getStudentByRoll()` to get profile, then independently loads attendance, fees, homework, exams in parallel with `Future.wait()`
4. **Coordinator summary:** `StudentService.loadTodayFullSummary()` fires 1 all-students query + N attendance doc reads in parallel, groups in-memory — optimised to avoid N+1 Firestore reads

### Offline Attendance Flow

```
AttendanceScreen marks attendance
  ↓ connectivity_plus: is online?
  ├── YES → StudentService.saveAttendance() → Firestore directly
  └── NO  → OfflineQueueService.enqueue()  → SharedPreferences
                ↓ when back online
              OfflineQueueService.syncAll() → StudentService.saveAttendanceForDate()
```

### Notification Fan-out Flow

```
Event occurs (e.g. student marked Absent)
  ↓
Service writes to `notifications/{autoId}` with audience='guardian:Class6:12'
  ↓
Guardian opens app → NotificationService.getFor() fetches all notifications
  → filters client-side by audience string matching
  → sorts newest first, drops records > 30 days old
  ↓
Unread count = count of items with createdAt > prefs.getInt('notif_last_seen_ms')
```

---

## 7. CURRENT KNOWN ISSUES

### Security
1. **Passwords stored as plaintext in Firestore.** `allowed_users.password` is a raw string. Anyone with Firestore read access (or a leaked service account) can read all passwords. The app has no Firebase Auth, no hashing, no salting. This is an architectural decision but a significant security risk for production.

2. **No Firestore Security Rules verified.** `storage.rules` exists but Firestore rules are not visible in the codebase — verify that `allowed_users` is not publicly readable.

3. **`google_sign_in` package is in `pubspec.yaml` but there is no implementation in any screen or service.** This is dead code that unnecessarily increases app size.

### Data Integrity
4. **Student name is denormalised into multiple collections.** `ExamResult`, `CopyStatus`, `SubstitutionRecord`, and `Homework` all store teacher/student names as strings at write time. If a name is corrected in `students/` or `teachers/`, these historical records are not updated.

5. **`feeStatus` field on Student is not computed.** It is a manually set string (`'Paid'|'Pending'|'Partial'`) on the student doc, but the actual payment truth lives in `fee_payments/`. These two can diverge — there is no code that auto-updates `feeStatus` when a payment is recorded.

6. **`attendance` date key uses no zero-padding** (`2026-5-3` not `2026-05-03`). This prevents lexicographic Firestore range queries on date ranges across months/years if ever needed.

7. **Cascade delete is incomplete.** `StudentService.removeStudent()` deletes the student doc and removes their roll from `attendance` docs, but does NOT clean up `exam_results`, `fee_payments`, or `copy_checks/statuses` for that student.

### Architecture
8. **`_WaveClipper` class is duplicated verbatim** in `home_screen.dart`, `coordinator_dashboard.dart`, `guardian_dashboard.dart`, and `principal_dashboard.dart`. Should be extracted to a shared widget.

9. **`TimetableService._settingsCache` is process-local.** If the coordinator updates settings on one device, other connected devices in the same session will read stale cached settings until they restart.

10. **No offline support outside attendance.** All other modules (exams, homework, fees, leave applications) will throw/silently fail if Firestore is unreachable. Only `OfflineQueueService` handles offline state.

11. **`fee_payments` 4-level nesting** makes it impossible to query all payments across students/classes in a single Firestore query. Reporting across the whole school requires N×M reads.

12. **Guardian `_callSchool()` dials `student.phone`** — but that field is the guardian's own phone number, not a school number. The button label says "Contact School" but it calls the guardian's stored number. This appears to be a bug.

13. **`notifications` collection grows unboundedly.** There is no TTL, no Cloud Function cleanup, no delete-on-read. Only a 30-day client-side filter prevents displaying old records, but they accumulate in Firestore.

14. **Teacher's `section` field** — the `Teacher` model has a `section` field, but it is separate from `classTeacherOf`. The meaning is ambiguous: it could be the section of their own class, but it is not consistently used.

---

## 8. BUSINESS RULES

The following rules are enforced in the app and must be preserved in any changes:

1. **A student belongs to exactly one class+section.** Doc ID `{className}_{section}_{roll}` is the unique identifier. A student cannot exist in two classes simultaneously.

2. **Roll numbers are unique within a class+section.** `StudentService.addStudent()` checks for duplicates and returns an error string if the roll already exists.

3. **Attendance is per-class per-day.** One Firestore doc covers the entire class for one day. Partial saves (one student at a time) are not supported — the whole class map is written.

4. **Attendance statuses are exactly:** `'Present'`, `'Absent'`, `'Leave'`. Legacy bool values (pre-redesign) are auto-migrated on read.

5. **Low attendance threshold is 75%.** Flagged in Guardian dashboard and AttendanceHistory screen. This is hardcoded, not a configurable setting.

6. **Grading scale** (computed from `ExamResult.percentage`):
   - A+ ≥ 90% | A ≥ 80% | B+ ≥ 70% | B ≥ 60% | C ≥ 50% | D ≥ 33% | F < 33%
   - Pass threshold: 33%

7. **Only class teachers can take attendance.** `HomeScreen` gates the "Take Attendance" tile behind `teacher.isClassTeacher == true && teacher.classTeacherOf != null`.

8. **Coordinator can be scoped to a subset of classes.** `assignedClasses` in `allowed_users` limits which classes a coordinator sees. If empty/null, they see all classes.

9. **Timetable clash detection:** `TimetableService.findClash()` prevents assigning the same teacher to two different classes at the same bell on the same day.

10. **Leave applications are directed to a role, not a person.** `toRole` is `'coordinator'` or `'principal'` — any user with that role can approve/reject.

11. **Gallery photos are stored in 3 variants:** `original` (unmodified), `compressed` (1080px, 70% quality), `watermarked` (compressed + "Our School" text bottom-right). The `compressedUrl` is used as the album cover.

12. **School ID is hardcoded as `'school_1'`** in `GalleryService`. Multi-school support is not implemented.

13. **Notification unread count is per-device.** The SharedPreferences timestamp means if a user logs in on a second device, all notifications appear unread on that device.

14. **Substitution auto-suggest** ranks teachers by fewest substitutions in the last 30 days (lower count = better candidate). This is advisory only — coordinator can assign anyone.

15. **Offline queue is last-write-wins.** If the same class's attendance is queued twice for the same day (e.g. marked, edited, network restored), only the last entry is kept.

---

## 9. HOW TO USE THIS FILE

**Instructions for any AI model receiving this document:**

When a developer asks you a question about this project or asks you to modify it, follow these rules:

1. **Read this document first.** All architectural decisions, naming conventions, and data relationships are here. Do not make assumptions that contradict what is documented.

2. **Respect the service layer.** All Firestore reads and writes go through `lib/services/`. Never suggest writing Firestore calls directly inside a screen widget.

3. **Use AppTheme constants.** All colours must reference `AppTheme.*` from `lib/theme.dart`. Never suggest raw `Color(0x...)` literals.

4. **Doc ID conventions matter.** Student doc IDs use `{className}_{section}_{roll}` with spaces replaced by underscores. Attendance doc IDs use `{className}_YYYY-M-D` with NO zero-padding. Timetable bell numbers are 1-indexed integers stored as string keys in the map.

5. **All services are singletons.** Always access them via factory: `StudentService()`, not `StudentService.instance`. Never instantiate with `new`.

6. **No state management library.** The app uses plain `StatefulWidget` + `setState`. Do not suggest adding Provider, Riverpod, BLoC, etc. unless the developer explicitly requests it.

7. **Before suggesting schema changes**, check the Known Issues section. Many inconsistencies are already documented — do not re-create existing problems.

8. **Password handling is intentionally plaintext** (see Known Issues §1). Do not add hashing without explicit instruction — it would break existing user logins without a migration.

9. **The 4-role system is fixed.** Roles are: `teacher`, `coordinator`, `principal`, `guardian`. No other roles exist.

10. **When modifying models**, remember that `toJson()` / `fromJson()` are the serialisation contract with Firestore. Adding a new field requires updating both methods and providing a default in `fromJson()` for backward compatibility with existing Firestore documents.

11. **The `students` + `attendance` separation is intentional.** Student profiles live in `students/`, daily status in `attendance/`. Never combine them.

12. **Date keys in attendance are non-padded** (`2026-5-3`). Any new code reading or writing attendance must use this exact format (see `StudentService._todayKey()`).

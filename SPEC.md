# School App — Current State SPEC
Generated: 2026-05-11 from Android Studio / Gemini-built codebase.

---

## User Roles & Entry Points

| Role | Entry Screen | Notes |
|------|-------------|-------|
| `teacher` / `subjectTeacher` | `HomeScreen(teacher)` | Class teacher or subject teacher |
| `coordinator` | `CoordinatorDashboard` | Manages teachers, substitutions, announcements |
| `principal` | `PrincipalDashboard` | Oversight, analytics, staff tasks, digest |
| `owner` | `OwnerHome` | School owner — accounts, school settings |
| `ownerPrincipal` | `OwnerPrincipalHome` | Combined owner + principal |
| `guardian` | `GuardianDashboard(studentClass, studentRoll, studentSection)` | Parent portal |

Auth: **Firebase Auth** — email/password sign-in (`LoginScreen`), phone OTP for guardians (`GuardianLoginScreen` → `PhoneOtpScreen`), and password reset (`forgot_password_screen.dart`). Role/identifier metadata lives in `allowed_users/{uid}` keyed by the Firebase Auth UID (fields: `role`, `schoolId`, `classIds[]`, `studentIds[]`, …). Session is also persisted to `SharedPreferences` via `AuthService` for fast routing; `clearSession()` signs out of Firebase Auth.

---

## All Screens

### Teacher Screens
| File | Purpose |
|------|---------|
| `home_screen.dart` | Teacher dashboard home |
| `attendance_screen.dart` | Mark daily attendance (present/absent/leave) |
| `attendance_history_screen.dart` | Calendar view of past attendance |
| `homework_screen.dart` | Post & manage homework assignments |
| `homework_overview_screen.dart` | Overview of all posted homework |
| `copy_checking_screen.dart` | Log copy-checking sessions per student |
| `leave_application_screen.dart` | Submit leave request to coordinator |
| `my_timetable_screen.dart` | View personal timetable |
| `marks_entry_screen.dart` | Enter exam marks for students |
| `test_marking_screen.dart` | Enter test marks |
| `task_marking_screen.dart` | Mark task completion |
| `task_status_screen.dart` | View task status |
| `daily_calls_screen.dart` | Track parent phone calls (class teacher) |
| `staff_tasks_screen.dart` | View tasks assigned by principal |
| `meeting/teacher_meeting_tasks_screen.dart` | View tasks assigned from a meeting |
| `student_list_screen.dart` | View students in assigned class |
| `student_details_screen.dart` | View/edit single student detail |
| `student_remarks_screen.dart` | Add/view remarks for a student |
| `student_selection_screen.dart` | Pick a student |
| `notifications_screen.dart` | In-app notification feed |

### Coordinator Screens
| File | Purpose |
|------|---------|
| `coordinator_dashboard.dart` | Coordinator home dashboard |
| `substitution_plan_screen.dart` | Auto-suggest + assign substitutions |
| `substitution_history_screen.dart` | Log of past substitutions |
| `coordinator/absent_teachers_screen.dart` | Today's absent teachers |
| `leave_requests_screen.dart` | Approve / reject teacher leave |
| `student_leave_requests_screen.dart` | Review student leave requests |
| `assign_duties_screen.dart` | Assign duty roster |
| `free_bells_screen.dart` | See unassigned bell slots |
| `teacher_management_screen.dart` | Add/edit/remove teachers |
| `timetable_settings_screen.dart` | Configure bells and class list |
| `announcements_screen.dart` | Post announcements (teachers/guardians) |
| `class_picker_screen.dart` | Utility: pick a class+section |
| `exam_management_screen.dart` | Create / manage exams |
| `copy_check_overview_screen.dart` | See copy-checking status across classes |
| `coordinator/report_card_template_editor.dart` | Edit report-card templates |
| `analytics_screen.dart` | Charts: attendance trends, absence leaders |
| `attendance_certificate_screen.dart` | Generate attendance certificate PDF |
| `fee_collection_screen.dart` | Record fee payments |
| `fee_structure_screen.dart` | Set fee structure per class |
| `fee_overview_screen.dart` | Fee overview |
| `coordinator_staff_tasks_screen.dart` | Coordinator's assigned tasks |
| `meeting/coordinator_meeting_records_screen.dart` | Coordinator meeting records |
| `todo_list_screen.dart` | Coordinator to-do list |
| `add_student_screen.dart` | Add new student |

### Principal Screens
| File | Purpose |
|------|---------|
| `principal_dashboard.dart` | Principal home dashboard |
| `principal_digest_screen.dart` | End-of-day summary + PDF export |
| `staff_task_management_screen.dart` | Create & assign tasks to staff |
| `tasks/create_staff_task_screen.dart` | Create a staff task |
| `tasks/staff_task_detail_screen.dart` | Staff task detail |
| `tasks/staff_task_analytics_view.dart` | Staff task analytics |
| `meeting/principal_meeting_records_screen.dart` | Principal meeting records |
| `meeting/meeting_detail_screen.dart` | Single meeting detail |
| `student_deletion_requests_screen.dart` | Review student-deletion requests |
| `admin_screen.dart` | Admin utilities (delete data, manage users) |
| `admin/audit_log_screen.dart` | View immutable audit log |
| `report_card_screen.dart` | Report card with rank/grade/PDF |

### Guardian Screens
| File | Purpose |
|------|---------|
| `guardian_dashboard.dart` | Guardian home dashboard |
| `guardian_login_screen.dart` | Guardian login (email or phone OTP) |
| `phone_otp_screen.dart` | Phone OTP verification |
| `guardian_student_details_screen.dart` | View child's details |
| `guardian_leave_application_screen.dart` | Submit child's leave request |
| `consent/parental_consent_flow.dart` | Parental consent capture |
| `birthdays/birthdays_screen.dart` | Student/staff birthdays |

### Shared / Utility Screens
| File | Purpose |
|------|---------|
| `login_screen.dart` | Primary login UI (Firebase Auth email/password) |
| `forgot_password_screen.dart` | Password reset via Firebase Auth |
| `role_selection_screen.dart` | Role-based login UI (legacy; boot path uses `LoginScreen`) |
| `notifications_screen.dart` | Notification list |

### Owner / Onboarding Screens
| File | Purpose |
|------|---------|
| `owner/owner_home.dart` | Owner dashboard |
| `owner/owner_principal_home.dart` | Combined owner + principal home |
| `owner/edit_school_settings_screen.dart` | Edit school config / branding |
| `onboarding/school_onboarding_screen.dart` + `step1…step6` | 6-step school setup wizard |

### Gallery Screens (`lib/screens/gallery/`)
| File | Purpose |
|------|---------|
| `gallery_home_screen.dart` | Album grid, publish/unpublish |
| `album_detail_screen.dart` | Photos in an album, upload |
| `create_album_screen.dart` | Create album form |
| `fullscreen_photo_viewer.dart` | Full-screen photo swipe viewer |

---

## All Services

| Service | Firestore Collections / Storage | Key Methods |
|---------|--------------------------------|-------------|
| `AuthService` | `allowed_users` | `saveSession`, `getSession`, `clearSession` |
| `TimetableService` | `teachers`, `timetable`, `settings/main`, `duties`, `substitutions`, `leave_applications` | CRUD for teachers, timetable, settings, leave |
| `StudentService` | `students`, `attendance` | `getStudents`, `getStudentsByClass`, attendance read/write, remarks |
| `NotificationService` | `notifications` | `addAbsenceNotice`, `addLeaveSubmitted`, `addLeaveResolved`, `addSubstitutionAssigned`, `addAnnouncementNotice` |
| `AnnouncementService` | `announcements` | `getAnnouncements`, `postAnnouncement`, `watchAnnouncements`, pin/unpin |
| `HomeworkService` | `homework` | `postHomework`, `getHomeworkForTeacher`, `getHomeworkForClass`, `markReviewed` |
| `ExamService` | `exams`, `exam_results` | CRUD exams + results, `getStudentResults` |
| `FeeService` | `fees`, `fee_payments` | `getFeeStructure`, `saveFeeStructure`, `addPayment`, `getClassFeeOverview` |
| `CopyCheckService` | `copy_checks`, subcollection `statuses` | `createCheck`, `saveStatuses`, `getAllChecks` |
| `GalleryService` | `schools/school_1/albums`, `schools/school_1/photos` + Firebase Storage | `createAlbum`, `getAlbums`, `uploadPhoto` (3 variants), `publishAlbum` |
| `OfflineQueueService` | SharedPreferences only | `enqueue`, `syncAll`, `getCachedAttendance` |
| `SubstitutionHistoryService` | `substitution_history` | `logSubstitution`, `getHistory`, `getSubstituteCounts` |
| `SubstitutionSuggesterService` | (reads via TimetableService + SubstitutionHistoryService) | `buildPlan` — ranks candidate teachers by workload |
| `PrincipalDigestService` ★ NEW | (reads from students, teachers via StudentService/TimetableService/CopyCheckService) | `buildTodayDigest` → `DigestSnapshot` |
| `StaffTaskService` ★ NEW | `staff_tasks` | `createTask`, `getAllTasks`, `getTasksForTeacher`, `getTasksForCoordinator`, `updateStatus` |
| `AttendanceService` | `attendance` | Attendance writes (also handled in StudentService) |
| `ExportService` | — | CSV/PDF export utilities |
| `FirestoreService` | — | Generic Firestore helper |
| `UserService` | `allowed_users` | User management |

---

## All Models

| Model | Key Fields |
|-------|-----------|
| `Student` | roll, name, className, section, fatherName, motherName, phone, photoPath, feeStatus, teacherId |
| `Teacher` | id, name, subject, email, section, isClassTeacher, classTeacherOf |
| `TimetableEntry` | teacherId, subject (null = teacher default) |
| `Announcement` | id, title, body, postedBy, postedByRole, audience (`all`/`teachers`/`guardians`), isPinned, postedAt |
| `AttendanceStatus` | enum: present/absent/leave with codes P/A/L and colors |
| `Homework` | id, teacherId, teacherName, className, subject, title, description, dueDate, isReviewed |
| `Exam` | id, name, className, subjects[], maxMarks, examDate, createdBy |
| `ExamResult` | roll, studentName, examId, marks Map\<subject→double?\>, grade, percentage, isPassed |
| `FeeStructure` | className, totalAnnualFee, components[] |
| `FeeComponent` | name, amount |
| `Payment` | id, amount, paidOn, mode, receiptNo |
| `CopyCheck` | id, teacherId, teacherName, className, subject, checkDate |
| `CopyStatus` | roll, studentName, status (`checked`/`incomplete`/`not_done`), remarks |
| `SubstitutionRecord` | id, dateKey, className, bell, substituteTeacherId, originalTeacherId, subject |
| `GalleryAlbum` | id, title, description, eventDate, coverPhotoUrl, photoCount, isPublished |
| `GalleryPhoto` | id, albumId, originalUrl, compressedUrl, watermarkedUrl, uploadedBy |
| `StaffTask` ★ NEW | id, title, description, assignedToType, assignedTeacherIds[], assignedCoordinatorEmails[], status (pending/inProgress/done) |
| `StudentRemark` ★ NEW | id, createdBy, role, remark, timestamp, teacherId |
| `AppUser` | uid, name, email, role (UserRole enum), schoolId, classIds[] |
| `StudentProfileData` types | FeesStatus, TestResult, BehaviorTag, BehaviorNote, Complaint |

---

## All Packages (pubspec.yaml)

| Package | Version | Use |
|---------|---------|-----|
| `shared_preferences` | ^2.2.2 | Session storage, offline queue, digest cache |
| `google_sign_in` | ^6.2.1 | (installed but unused; auth is Firebase Auth — email/password + guardian phone OTP) |
| `image_picker` | ^1.1.2 | Photo uploads for gallery |
| `url_launcher` | ^6.3.0 | Phone call links in daily calls screen |
| `font_awesome_flutter` | 10.6.0 | Icons |
| `pdf` + `printing` | ^3.10.8 / ^5.12.0 | Report cards, attendance certificates, digest PDFs |
| `firebase_core` | ^2.27.0 | Firebase init |
| `cloud_firestore` | ^4.17.0 | All data storage |
| `firebase_storage` | ^11.7.0 | Gallery photo uploads |
| `fl_chart` | ^0.68.0 | Analytics bar/line charts |
| `connectivity_plus` | ^6.0.3 | Offline detection |
| `file_picker` | ^8.0.5 | File import (CSV?) |
| `csv` | ^6.0.0 | CSV export/import |
| `flutter_image_compress` | ^2.1.0 | Gallery photo compression |
| `image` | ^4.1.3 | Image processing (watermarking) |
| `image_gallery_saver` | ^2.0.3 | Save photos to device gallery |
| `share_plus` | ^7.2.1 | Share reports/PDFs |
| `cached_network_image` | ^3.3.1 | Gallery photo caching |
| `shimmer` | ^3.0.0 | Loading skeleton animations |

---

## Firestore Collections

| Collection | Purpose |
|-----------|---------|
| `allowed_users` | Login credentials (email+password+role) |
| `teachers` | Teacher documents |
| `students` | Student documents (ID: `{className}_{section}_{roll}`) |
| `attendance/{className}` | Daily attendance (date key `YYYY-M-D`, rolls sub-map) |
| `timetable` | Class timetables |
| `settings/main` | School settings (bells, classes) |
| `duties` | Duty roster |
| `substitutions` | Active substitution plans |
| `leave_applications` | Teacher leave requests |
| `notifications` | In-app notifications (filtered by `audience` field) |
| `announcements` | School announcements |
| `homework` | Homework assignments |
| `exams` | Exam metadata |
| `exam_results/{examId}/students/{roll}` | Per-student exam results |
| `fees` | Fee structures per class |
| `fee_payments` | Payment records |
| `copy_checks` | Copy-checking sessions |
| `schools/school_1/albums` | Gallery albums |
| `schools/school_1/photos` | Gallery photo metadata |
| `substitution_history` | Log of all past substitutions |
| `staff_tasks` ★ NEW | Tasks assigned by principal to staff |

**Firebase Storage:** `schools/school_1/gallery/{albumId}/{original|compressed|watermarked}/{photoId}.jpg`

---

## New Features Added by Android Studio / Gemini

1. **Gallery Module** — `GalleryService` + 4 screens + `GalleryAlbum`/`GalleryPhoto` models. Photos stored in Firebase Storage with 3 variants (original, compressed, watermarked). Albums can be published/unpublished.

2. **Principal Digest** — `PrincipalDigestService.buildTodayDigest()` aggregates attendance, copy-checking, and teacher stats into a `DigestSnapshot`. `PrincipalDigestScreen` shows it with PDF export and tracks whether viewed today via SharedPreferences.

3. **Staff Task Management** — `StaffTaskService` + `StaffTask` model. Principal creates tasks (from presets or custom) and assigns them to `all_teachers`, `all_coordinators`, or specific individuals. Staff see tasks in `StaffTasksScreen` and can update status (pending → inProgress → done).

4. **Student Remarks** — `StudentRemark` model + `student_remarks_widget.dart`. Any role (teacher/coordinator/principal/guardian) can log timestamped remarks for a student. Stored at `students/{id}/remarks` subcollection.

5. **Daily Calls Screen** — Class teacher tracks parent phone calls with student list, call log, and PDF export. Uses `url_launcher` for direct dial.

6. **Report Card Screen** — Shows all students' results for one exam with class rank, percentage, grade (A+/A/B+/B/C/D/F) and printable PDF.

7. **Fee Structure Screen** — Coordinator configures fee components per class (Tuition, Transport, Exam, etc.) with totals.

8. **SubstitutionSuggesterService** — Smart substitution ranking: considers teacher workload (substitution count), free bell slots, and subject match to suggest best candidates automatically.

---

## Known Issues / Incomplete Code

1. ✅ **MERGE CONFLICTS RESOLVED:** The previously-flagged unresolved merge conflicts in `lib/screens/coordinator_dashboard.dart` and `lib/screens/home_screen.dart` have since been resolved — no `<<<<<<<` markers remain and both files are in normal compile-shape.

2. `google_sign_in` package is installed but not actually used (the guardian login path uses email/password + phone OTP via Firebase Auth; `AuthService.signInWithGoogle()` is a `null` stub).

3. `firestore_service.dart` is legacy/likely-unused: it uses a different attendance schema (`schools/{sid}/classes/{classId}/attendance`) than the live path, and carries dead FCM-token code with no messaging package behind it. Reconcile or remove. (`attendance_service.dart` no longer exists.)

4. Multi-tenancy is scaffolded but not fully wired: several services and the owner screens still hardcode `schoolId = 'school_1'` despite the school-scoped (`schools/{sid}/…`) schema and the onboarding wizard.

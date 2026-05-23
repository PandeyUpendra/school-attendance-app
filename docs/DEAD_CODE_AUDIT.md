# Dead Code Audit — school_app
Generated: 2026-05-23 · Total dart files: 184 · `flutter analyze` issues: 36 warnings, 0 errors

---

## Methodology

1. All 184 `.dart` files under `lib/` were enumerated.
2. For each file, **inbound import count** was computed: how many other files `import` or `part` it.
3. Files with zero inbound imports were further checked by **class-name cross-reference** (Navigator pushes, constructor calls anywhere in the codebase).
4. Duplicate-looking screens were identified by name-token overlap and inspected for AppBar titles.
5. `flutter analyze` warnings were collated (unused fields, unused elements, unused imports).

---

## 1 — Files with Zero Inbound Imports

> **Legend:**  
> 💀 **DEAD** — zero inbound imports AND class name never referenced anywhere else  
> ⚠️ **ORPHAN** — zero inbound imports but class IS referenced (via Navigator push without import, or dynamic routing)  
> ✅ **ENTRY_POINT** — expected to have zero inbound imports  

### 1a — Confirmed Entry Points (keep, no action)

| File | Reason |
|------|--------|
| `lib/main.dart` | App entry point |
| `lib/scripts/migrate_users.dart` | CLI migration script — run standalone |

---

### 1b — Confirmed Dead Files (safe to delete after review)

| File | Class | Notes |
|------|-------|-------|
| `lib/providers/theme_provider.dart` | `ThemeProvider` | ThemeProvider never referenced anywhere; app uses `AppTheme` constants directly from `lib/theme.dart` |
| `lib/screens/attendance_class_detail_screen.dart` | `AttendanceClassDetailScreen` | Zero refs; superseded by inline class-detail in `attendance_screen.dart` |
| `lib/screens/attendance_report_screen.dart` | `AttendanceReportScreen` | Zero refs; reporting now in `analytics_screen.dart` |
| `lib/screens/bell_settings_screen.dart` | `BellSettingsScreen` | Zero refs; bell configuration merged into `timetable_settings_screen.dart` |
| `lib/screens/calendar_screen.dart` | `CalendarScreen` | Zero refs; calendar integrated into dashboards |
| `lib/screens/class_setup_screen.dart` | `ClassSetupScreen` | Zero refs; replaced by onboarding flow |
| `lib/screens/coordinator/fee_defaulters_screen.dart` | `FeeDefaultersScreen` | Zero refs; fee defaulters shown inline in `fee_overview_screen.dart` |
| `lib/screens/coordinator_staff_tasks_screen.dart` | `CoordinatorStaffTasksScreen` | Zero refs; duplicates `tasks/staff_task_management_screen.dart` (see §3) |
| `lib/screens/create_account_sheet.dart` | `_CreateAccountSheet` (private) | Zero refs; account creation moved to `admin_screen.dart` |
| `lib/screens/create_task_screen.dart` | `CreateTaskScreen` | Zero refs; task creation is inside `tasks/create_staff_task_screen.dart` |
| `lib/screens/gallery/gallery_home_screen.dart` | `GalleryHomeScreen` | Zero refs; `gallery_home_screen.dart` under `gallery/` is the canonical entry; check if they differ |
| `lib/screens/guardian_details_list_screen.dart` | `GuardianDetailsListScreen` | Zero refs; guardian list view is inside `guardian_dashboard.dart` |
| `lib/screens/history_screen.dart` | `HistoryScreen` | Zero refs; **duplicate of `attendance_history_screen.dart`** (see §3) |
| `lib/screens/leaderboard_screen.dart` | `LeaderboardScreen` | Zero refs; leaderboard removed from nav |
| `lib/screens/principal_home.dart` | `PrincipalHome` | Zero refs; **duplicate of `principal_dashboard.dart`** (see §3) |
| `lib/screens/school_contacts_screen.dart` | `SchoolContactsScreen` | Zero refs; contacts shown in `home_screen.dart` card |
| `lib/screens/school_policy_screen.dart` | `SchoolPolicyScreen` | Zero refs; policy text unused |
| `lib/screens/school_registration_screen.dart` | `SchoolRegistrationScreen` | Zero refs; replaced by `onboarding/school_onboarding_screen.dart` |
| `lib/screens/set_password_screen.dart` | `SetPasswordScreen` | Zero refs; no password-reset flow in app (Firestore auth only) |
| `lib/screens/student_profile_screen.dart` | `StudentProfileScreen` | Zero refs; profile shown inline in student list |
| `lib/screens/task_status_screen.dart` | `TaskStatusScreen` | Zero refs; status shown in `tasks/staff_task_detail_screen.dart` |
| `lib/screens/teacher_profile_screen.dart` | `TeacherProfileScreen` | Zero refs; profile in `teacher_management_screen.dart` |
| `lib/screens/teacher_tasks_screen.dart` | `TeacherTasksScreen` | Zero refs; teacher task view is `tasks/unified_staff_task_screen.dart` |
| `lib/screens/test_creation_screen.dart` | `TestCreationScreen` | Zero refs; exam creation inside `exam_management_screen.dart` |
| `lib/screens/timetable_editor_screen.dart` | `TimetableEditorScreen` | Zero refs; timetable editing is in `timetable_settings_screen.dart` |
| `lib/screens/timetable_screen.dart` | `TimetableScreen` | Zero refs; **duplicate of `my_timetable_screen.dart`** (see §3) |
| `lib/services/attendance_service.dart` | `AttendanceService` | Zero refs; attendance logic lives in `timetable_service.dart` + `StudentService` |
| `lib/services/dashboard_service.dart` | `DashboardSummary` | Zero refs; dashboard data fetched inline in dashboard screens |
| `lib/services/export_service.dart` | `ExportService` | Zero refs; export not wired to any UI |
| `lib/services/user_service.dart` | `UserService` | Zero refs; user management uses `AuthService` directly |
| `lib/widgets/student_remarks_widget.dart` | `StudentRemarksWidget` | Zero refs; remarks shown in student list via inline widget |

**Total confirmed-dead files: 31**

---

### 1c — Orphan Files (zero inbound imports but class IS referenced — investigate before deleting)

| File | Class | Referenced By | Action |
|------|-------|---------------|--------|
| `lib/screens/staff_task_management_screen.dart` | `StaffTaskManagementScreen` | `tasks/staff_task_management_screen.dart` (same class name — conflict!) | **Merge or rename** (see §3) |
| `lib/screens/tasks/staff_task_management_screen.dart` | `StaffTaskManagementScreen` | `staff_task_management_screen.dart` (circular reference) | **Merge or rename** (see §3) |
| `lib/repositories/student_repository_fake.dart` | `FakeStudentRepository` | `student_repository.dart`, `student_service.dart` | Keep — used for testing/dependency injection |

---

## 2 — Symbols Defined But Never Referenced Elsewhere

| Symbol | File | Type | Verdict |
|--------|------|------|---------|
| `privacyNoticeTitle` | `lib/utils/privacy_notice.dart` | top-level `String` | Dead — never displayed |
| `UserService` | `lib/services/user_service.dart` | class | Dead — file is dead (see §1b) |
| `ExportService` | `lib/services/export_service.dart` | class | Dead — file is dead (see §1b) |

### Unused elements inside live files (from `flutter analyze`)

| Symbol | File | Type |
|--------|------|------|
| `_sectionHeader` | `attendance_class_detail_screen.dart` | private function |
| `_toggleSound`, `_toggleVibration`, `_refresh`, `_markAll`, `_removeStudent`, `_accentColor`, `_rowBg`, `_buildStatsCard`, `_WaveClipper`, `_SaveButton`, `_statusColor`, `_VerticalProgressBar` | `attendance_screen.dart` | private elements (12 total) |
| `_getIconForType` | `calendar_screen.dart` | private function (file is dead) |
| `_SectionHeader` | `school_policy_screen.dart` | private class (file is dead) |
| `_fmtDate` | `staff_tasks_screen.dart` | private function |
| `shade800` | `student_leave_requests_screen.dart` | private getter |
| `_shortName` | `timetable_settings_screen.dart` | private function |

### Unused imports (from `flutter analyze`)

| Unused Import | In File |
|---------------|---------|
| `base_firestore_service.dart` | `assign_duties_screen.dart` |
| `fee_collection_screen.dart` | `coordinator_dashboard.dart` |
| `base_firestore_service.dart` | `student_list_screen.dart` |
| `../../theme.dart` | `tasks/staff_task_analytics_view.dart` |
| `role_permission_service.dart` | `principal_home.dart` (file is dead) |
| duplicate `import` | `auth_service.dart` |

---

## 3 — Duplicate / Overlapping Screens

### 3a — Definite Duplicates (same purpose, both exist)

| Pair | A | B | Recommendation |
|------|---|---|----------------|
| **Staff task management** | `screens/staff_task_management_screen.dart` → `Scaffold > AppBar('All Staff Tasks')` | `screens/tasks/staff_task_management_screen.dart` → `Scaffold > AppBar('Task Management')` | Both define `StaffTaskManagementScreen` — **class name collision**. Delete `screens/staff_task_management_screen.dart`; canonical is under `tasks/`. |
| **Principal home** | `screens/principal_home.dart` → no distinct AppBar | `screens/principal_dashboard.dart` → full dashboard with cards | `principal_home.dart` is the dead older version. Keep `principal_dashboard.dart`. |
| **Attendance history** | `screens/history_screen.dart` → `AppBar('History — ${className}')` | `screens/attendance_history_screen.dart` → modern attendance history | `history_screen.dart` is the dead older version. Keep `attendance_history_screen.dart`. |
| **Timetable view** | `screens/timetable_screen.dart` → `AppBar('Timetable — ${className}')` | `screens/my_timetable_screen.dart` → personal timetable view | Different angles: `timetable_screen` shows a class's full timetable; `my_timetable_screen` shows teacher's own. **Keep both** but document distinction. `timetable_screen.dart` is dead (zero refs) — wire it or delete it. |

### 3b — Pairs With Distinct Purposes (keep both, just name clarification)

| Pair | A Purpose | B Purpose |
|------|-----------|-----------|
| `login_screen.dart` vs `role_selection_screen.dart` | Admin-only login (`AppBar('Admin Access')`) | Role picker → routes to teacher / coordinator / guardian login | Distinct — keep both |
| `guardian_login_screen.dart` vs `role_selection_screen.dart` | Guardian-specific login form | Entry point before login | Distinct — keep both |
| `coordinator_dashboard.dart` vs `coordinator_management_screen.dart` | Coordinator's main dashboard | Manage coordinator accounts (`AppBar('Manage Coordinators')`) | Distinct — keep both |
| `homework_screen.dart` vs `homework_overview_screen.dart` | Homework entry/editing (teacher) | Overview / list view | Distinct — keep both; rename for clarity |
| `copy_check_overview_screen.dart` vs `copy_checking_screen.dart` | Overview list of copy-checks | Active checking workflow | Distinct — keep both |
| `fee_collection_screen.dart` vs `fee_overview_screen.dart` | Collect fees per student | Overview of fee status | Distinct — keep both |
| `marks_entry_screen.dart` vs `test_marking_screen.dart` | Enter marks after exam | Mark individual copies | Similar but `marks_entry` is for bulk result entry; `test_marking` is per-paper. Keep both; verify. |
| `exam_management_screen.dart` vs `test_creation_screen.dart` | Manage exams list | Create single test (dead) | `test_creation_screen.dart` is dead (zero refs). Delete it. |

---

## 4 — Data / Script Files (special cases)

| File | Status | Notes |
|------|--------|-------|
| `lib/data/student_data.dart` | ⚠️ Check | Seed data — may be used in onboarding or tests only |
| `lib/data/template_seeds.dart` | ⚠️ Check | Template seed data — used by `report_card_template_service.dart`? |
| `lib/scripts/migrate_users.dart` | ✅ Keep | One-off migration script, not imported |

---

## 5 — Summary & Recommended Actions

### Phase 1a — Delete without hesitation (31 files)
All files in §1b above. These have **zero inbound imports AND zero class-name references**. No navigator push or constructor call anywhere in the codebase touches them.

**Estimated line reduction: ~6,000–8,000 lines**

### Phase 1b — Merge / resolve conflicts
- `screens/staff_task_management_screen.dart` → delete; keep `tasks/staff_task_management_screen.dart`

### Phase 1c — Fix analyze warnings in live files
- Remove 12 unused private elements from `attendance_screen.dart`
- Remove unused imports in 5 live files  
- Fix duplicate import in `auth_service.dart`

### Phase 1d — Keep but document
- `lib/repositories/student_repository_fake.dart` — test double, intentionally kept
- `lib/screens/my_timetable_screen.dart` vs `timetable_screen.dart` — decide one canonical timetable screen

---

## 6 — Next: Phase 2 Feature Folder Reorganisation

After dead files are removed, the target structure is:

```
lib/
  features/
    auth/           # role_selection, login_screen, guardian_login, forgot_password
    attendance/     # attendance_screen, history, certificate, daily_calls, report
    students/       # student_list, add_student, student_leave, student_profile_data
    teachers/       # teacher_management, teacher_profile
    timetable/      # my_timetable, timetable_settings, bell_settings, assign_duties
    substitution/   # substitution_plan, history, free_bells
    exams/          # exam_management, marks_entry, test_marking, report_card
    fees/           # fee_collection, fee_overview, fee_structure
    copy_check/     # copy_check_overview, copy_checking
    announcements/  # announcements_screen
    homework/       # homework_screen, homework_overview
    gallery/        # album_detail, create_album, fullscreen_photo_viewer
    analytics/      # analytics_screen
    dashboards/     # coordinator_dashboard, principal_dashboard, guardian_dashboard, home_screen, admin_screen
    leave/          # leave_application, leave_requests, guardian_leave
    tasks/          # create_staff_task, staff_task_management, unified_staff_task, staff_task_detail, staff_task_analytics
    digest/         # principal_digest (if screen exists)
  shared/
    widgets/        # consent_pending_banner, task_badge_widgets, todo_reminder_banner
    utils/          # privacy_notice, report_card_pdf_builder, role_guard
  models/           # (unchanged)
  services/         # (unchanged)
  repositories/     # (unchanged)
```

**Proceed only after §5 deletions are confirmed and committed.**

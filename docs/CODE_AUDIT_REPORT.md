# Code Audit Report — Phase 1 Cleanup Executed
Generated: 2026-05-24 · Branch: `claude/angry-nash-cf956e`

## Summary

| Metric | Before | After | Delta |
|---|---|---|---|
| Dart files in `lib/` | 184 | **154** | −30 (−16.3%) |
| `flutter analyze` total issues | 643 | **611** | −32 |
| Errors | 6 (pre-existing in `test_marking_screen.dart`) | **0** | −6 ✅ |
| Warnings | 36 | **13** | −23 (−64%) |
| Lines removed (net) | — | **12,564** | (12,566 deleted, 2 added) |

## What was done

### A. Deleted 29 dead files (~12,300 lines)
All verified zero inbound imports **and** zero class-name references in `lib/`. The Phase-1 audit also listed 3 false-positives (still live) — these were **kept**:
- `coordinator_staff_tasks_screen.dart` — used by `coordinator_dashboard.dart:257`
- `create_task_screen.dart` — used by `principal_dashboard.dart:294`
- `task_status_screen.dart` — used by `principal_dashboard.dart:283`

For the `StaffTaskManagementScreen` duplicate, the audit said the `tasks/` version was canonical. Reality: `principal_dashboard.dart:275` imports the older `screens/` version (862 lines, AppBar "All Staff Tasks") rather than the simpler `tasks/` version (352 lines, "Task Management"). Deleted `tasks/staff_task_management_screen.dart` instead to preserve the live richer view.

Deleted files (29):
```
lib/providers/theme_provider.dart
lib/screens/attendance_class_detail_screen.dart
lib/screens/attendance_report_screen.dart
lib/screens/bell_settings_screen.dart
lib/screens/calendar_screen.dart
lib/screens/class_setup_screen.dart
lib/screens/coordinator/fee_defaulters_screen.dart
lib/screens/create_account_sheet.dart
lib/screens/gallery/gallery_home_screen.dart
lib/screens/guardian_details_list_screen.dart
lib/screens/history_screen.dart
lib/screens/leaderboard_screen.dart
lib/screens/principal_home.dart
lib/screens/school_contacts_screen.dart
lib/screens/school_policy_screen.dart
lib/screens/school_registration_screen.dart
lib/screens/set_password_screen.dart
lib/screens/student_profile_screen.dart
lib/screens/tasks/staff_task_management_screen.dart
lib/screens/teacher_profile_screen.dart
lib/screens/teacher_tasks_screen.dart
lib/screens/test_creation_screen.dart
lib/screens/timetable_editor_screen.dart
lib/screens/timetable_screen.dart
lib/services/attendance_service.dart
lib/services/dashboard_service.dart
lib/services/export_service.dart
lib/services/user_service.dart
lib/widgets/student_remarks_widget.dart
```

### B. Removed 13 unused private elements from `attendance_screen.dart`
`_schoolId`, `_toggleSound`, `_toggleVibration`, `_refresh`, `_markAll`, `_removeStudent`, `_accentColor`, `_rowBg`, `_buildStatsCard`, `_WaveClipper`, `_SaveButton`, `_statusColor`, `_VerticalProgressBar` — ~260 dead lines in the largest screen file.

### C. Removed other dead private symbols in live files
- `_fmtDate` in `staff_tasks_screen.dart` (duplicate — `_fmtDateFull` remains)
- `shade800` extension getter in `student_leave_requests_screen.dart`
- `_shortName` in `timetable_settings_screen.dart`
- `privacyNoticeTitle` top-level fn in `utils/privacy_notice.dart`

### D. Removed 4 unused imports
- `base_firestore_service.dart` from `assign_duties_screen.dart`
- `fee_collection_screen.dart` from `coordinator_dashboard.dart`
- `base_firestore_service.dart` from `student_list_screen.dart`
- `../../theme.dart` from `tasks/staff_task_analytics_view.dart`
- (`base_firestore_service.dart` from `attendance_screen.dart` — new orphan after `_schoolId` removal)

### E. Fixed 6 pre-existing compile errors in `test_marking_screen.dart`
Bug: `const AppTheme.primary` — `AppTheme.primary` is a static `Color` field, not a const constructor. Removed the spurious `const` at lines 179 and 408. Code now compiles cleanly.

## Remaining 13 warnings (intentionally not touched)

Mostly unused fields in screens that look like scaffolding for in-progress work (`_studentService`, `_feeService` in `analytics_screen.dart`; `_savedResults` in `marks_entry_screen.dart`; `_schoolName` in owner dashboards). Leaving these for the owner to decide — removing them silently could orphan plumbing meant for upcoming features.

The 598 `info` items are mostly `deprecated_member_use` for `withOpacity` (Flutter wants `.withValues()`) — purely stylistic, no behavior change.

## Verification

```
flutter analyze
# 611 issues found (0 errors, 13 warnings, 598 info)
```

Worktree is clean of errors. No tests were run — see [TESTING_GAP](#testing-gap) in MISSING_FEATURES.

## Suggested next phases (not done here)

1. **Phase 1c (deferred):** decide whether to wire `timetable_screen.dart` (class-view timetable) somewhere or delete it — it's still present after this pass.
2. **Phase 2:** feature-folder reorganization (`lib/features/...`) as outlined in `docs/DEAD_CODE_AUDIT.md` §6.
3. **withOpacity migration:** bulk codemod from `.withOpacity(x)` to `.withValues(alpha: x)` — affects ~150 sites.
4. **Owner-screen unused fields:** revisit after deciding if multi-school owner mode is shipping or being deferred.

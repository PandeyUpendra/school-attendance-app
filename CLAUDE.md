# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run on a connected device / emulator
flutter run

# Run on a specific platform
flutter run -d macos
flutter run -d chrome

# Build
flutter build apk
flutter build ios --no-codesign

# Analyze (lint)
flutter analyze

# Tests
flutter test
flutter test test/widget_test.dart   # single file
```

## Architecture

### Entry point & session routing

`lib/main.dart` initialises Firebase then renders `_SplashGate`, which reads the saved session from `AuthService` and pushes the correct dashboard — no login screen is shown for returning users.

```
_SplashGate
  ├── teacher   → HomeScreen(teacher)
  ├── coordinator → CoordinatorDashboard
  ├── principal   → PrincipalDashboard
  ├── guardian    → GuardianDashboard(studentClass, studentRoll)
  └── (none)    → RoleSelectionScreen
```

### Authentication

There is **no Firebase Auth**. Login is purely Firestore-based: `RoleSelectionScreen` prompts for email + password and checks against the `allowed_users` collection. On success, `AuthService.saveSession()` persists the role and identifiers to `SharedPreferences`. All services are singletons — construct via the factory `ServiceName()`.

### Theme

`lib/theme.dart` → `AppTheme` is the **single source of truth** for all colours. Always use `AppTheme.*` constants in screen code — never raw `Color(0x...)` literals. Key colours:
- `AppTheme.primary` — Deep Violet `#6A1B9A`
- `AppTheme.accent` — Magenta `#D81B60` (badges, pending indicators)
- `AppTheme.background` — Light lavender page background
- `AppTheme.success/warning/danger` — semantic data colours (Present/Leave/Absent)

### Services layer (`lib/services/`)

All services are singletons wrapping Firestore collections directly — no repository abstraction layer.

| Service | Firestore collections |
|---|---|
| `TimetableService` | `teachers`, `settings/main`, `timetable`, `duties`, `allowed_users`, `substitutions`, `leave_applications` |
| `StudentService` | `students`, `attendance` |
| `NotificationService` | `notifications` |
| `AnnouncementService` | `announcements` |
| `HomeworkService` | `homework` |
| `ExamService` | `exams` |
| `FeeService` | `fees` |
| `CopyCheckService` | `copy_checks` |
| `GalleryService` | `schools/school_1/albums`, `schools/school_1/photos` (Firebase Storage) |
| `OfflineQueueService` | SharedPreferences only — no Firestore |

`TimetableService._settingsCache` is an in-memory cache invalidated on `saveSettings()` — only one round-trip per app session for school settings (bells, classes).

### Offline attendance

`OfflineQueueService` queues attendance writes to SharedPreferences (`attendance_offline_queue`) when offline. Call `syncAll()` when connectivity returns. Duplicate entries for the same `className + dateKey` are replaced (last write wins).

### Notifications

No push notification server. `NotificationService` writes documents to the `notifications` collection when events occur (absent mark, leave submitted/resolved, announcement). Clients filter by `audience` field (`guardian:{class}:{roll}`, `coordinator`, `teacher:{teacherId}`, etc.). Unread state is tracked locally via a SharedPreferences timestamp.

### Data models (`lib/models/`)

Plain Dart classes with `toJson()` / `fromJson()` — no code generation. Student document IDs follow `{className}_{section}_{roll}` (spaces → underscores). Attendance documents live at `attendance/{className}` with date keys in `YYYY-M-D` format and `rolls` sub-map of `roll → status`.

### Gallery

`GalleryService` is the only service that uses Firebase Storage. Firestore paths are namespaced under `schools/school_1/`. Storage paths follow `schools/school_1/gallery/{albumId}/{original|compressed|watermarked}/{photoId}.jpg`. The school ID constant is hardcoded as `'school_1'` in `GalleryService`.

### Firebase project

Firebase project: `attendanceapp-e76e1`. Config lives in `lib/firebase_options.dart` (generated) and `android/app/google-services.json`.

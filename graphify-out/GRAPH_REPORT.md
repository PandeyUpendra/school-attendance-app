# Graph Report - .  (2026-04-26)

## Corpus Check
- 134 files · ~155,813 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1291 nodes · 1579 edges · 54 communities detected
- Extraction: 97% EXTRACTED · 3% INFERRED · 0% AMBIGUOUS · INFERRED: 50 edges (avg confidence: 0.86)
- Token cost: 2,360 input · 5,170 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Screen Hub & Shared Imports|Screen Hub & Shared Imports]]
- [[_COMMUNITY_Core Dashboards & Firebase|Core Dashboards & Firebase]]
- [[_COMMUNITY_Student & Certificate Screens|Student & Certificate Screens]]
- [[_COMMUNITY_Attendance Certificate Screen|Attendance Certificate Screen]]
- [[_COMMUNITY_Guardian Dashboard|Guardian Dashboard]]
- [[_COMMUNITY_Data Models|Data Models]]
- [[_COMMUNITY_Timetable Settings Screen|Timetable Settings Screen]]
- [[_COMMUNITY_Attendance Screen|Attendance Screen]]
- [[_COMMUNITY_Fee Collection Screen|Fee Collection Screen]]
- [[_COMMUNITY_Free Bells Screen|Free Bells Screen]]
- [[_COMMUNITY_Copy Checking Screen|Copy Checking Screen]]
- [[_COMMUNITY_Copy Check Overview|Copy Check Overview]]
- [[_COMMUNITY_macOS App Icons|macOS App Icons]]
- [[_COMMUNITY_Knowledge Graph Report|Knowledge Graph Report]]
- [[_COMMUNITY_Analytics Screen|Analytics Screen]]
- [[_COMMUNITY_Windows Native Runner|Windows Native Runner]]
- [[_COMMUNITY_Teacher Management Screen|Teacher Management Screen]]
- [[_COMMUNITY_Leave Application Screen|Leave Application Screen]]
- [[_COMMUNITY_Attendance History Screen|Attendance History Screen]]
- [[_COMMUNITY_Leave Requests Screen|Leave Requests Screen]]
- [[_COMMUNITY_My Timetable Screen|My Timetable Screen]]
- [[_COMMUNITY_Timetable Editor Screen|Timetable Editor Screen]]
- [[_COMMUNITY_Exam Management Screen|Exam Management Screen]]
- [[_COMMUNITY_Admin Screen|Admin Screen]]
- [[_COMMUNITY_Announcements Screen|Announcements Screen]]
- [[_COMMUNITY_Class Attendance Detail|Class Attendance Detail]]
- [[_COMMUNITY_iOS App Icons|iOS App Icons]]
- [[_COMMUNITY_Android Launcher Icons|Android Launcher Icons]]
- [[_COMMUNITY_Web & Splash Assets|Web & Splash Assets]]
- [[_COMMUNITY_macOS Plugin Registration|macOS Plugin Registration]]
- [[_COMMUNITY_iOS App Delegate|iOS App Delegate]]
- [[_COMMUNITY_Platform Test Suites|Platform Test Suites]]
- [[_COMMUNITY_Android Plugin Registrant|Android Plugin Registrant]]
- [[_COMMUNITY_Widget Tests|Widget Tests]]
- [[_COMMUNITY_Teacher Model|Teacher Model]]
- [[_COMMUNITY_Student Model|Student Model]]
- [[_COMMUNITY_Android Main Activity|Android Main Activity]]
- [[_COMMUNITY_Timetable Entry Model|Timetable Entry Model]]
- [[_COMMUNITY_iOS Bridging Header|iOS Bridging Header]]
- [[_COMMUNITY_iOS Plugin Header|iOS Plugin Header]]
- [[_COMMUNITY_Linux App Header|Linux App Header]]
- [[_COMMUNITY_Linux Plugin Header|Linux Plugin Header]]
- [[_COMMUNITY_Windows Utils Header|Windows Utils Header]]
- [[_COMMUNITY_Windows Window Header|Windows Window Header]]
- [[_COMMUNITY_Windows Resource Header|Windows Resource Header]]
- [[_COMMUNITY_Windows Plugin Header|Windows Plugin Header]]
- [[_COMMUNITY_Linux CMake Build|Linux CMake Build]]
- [[_COMMUNITY_Windows Runner|Windows Runner]]
- [[_COMMUNITY_App Icons Report Node|App Icons Report Node]]
- [[_COMMUNITY_macOS Runner Report Node|macOS Runner Report Node]]
- [[_COMMUNITY_macOS Delegate Report Node|macOS Delegate Report Node]]
- [[_COMMUNITY_Platform Tests Report Node|Platform Tests Report Node]]
- [[_COMMUNITY_Android Plugin Report Node|Android Plugin Report Node]]
- [[_COMMUNITY_Widget Tests Report Node|Widget Tests Report Node]]

## God Nodes (most connected - your core abstractions)
1. `package:flutter/material.dart` - 41 edges
2. `../theme.dart` - 40 edges
3. `../services/timetable_service.dart` - 27 edges
4. `package:flutter/material.dart` - 24 edges
5. `../theme.dart` - 24 edges
6. `package:cloud_firestore/cloud_firestore.dart` - 16 edges
7. `../services/student_service.dart` - 16 edges
8. `../models/teacher.dart` - 16 edges
9. `../models/student.dart` - 14 edges
10. `Flutter Logo App Icon` - 14 edges

## Surprising Connections (you probably didn't know these)
- `Flutter Logo Icon Design` --is_placeholder_icon_for--> `school_app`  [INFERRED]
  macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png → README.md
- `Flutter Logo App Icon` --represents--> `Flutter Framework`  [EXTRACTED]
  ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png → README.md
- `school_app` --conceptually_related_to--> `iOS Launch Screen Assets`  [INFERRED]
  README.md → ios/Runner/Assets.xcassets/LaunchImage.imageset/README.md
- `flutter_wrapper_plugin (Windows Static Library)` --conceptually_related_to--> `Flutter Framework`  [INFERRED]
  windows/flutter/CMakeLists.txt → README.md
- `my_application_dispose()` --calls--> `dispose`  [INFERRED]
  linux/my_application.cc → lib/screens/copy_checking_screen.dart

## Communities

### Community 0 - "Screen Hub & Shared Imports"
Cohesion: 0.02
Nodes (106): analytics_screen.dart, announcements_screen.dart, assign_duties_screen.dart, attendance_class_detail_screen.dart, attendance_history_screen.dart, attendance_screen.dart, class_picker_screen.dart, copy_check_overview_screen.dart (+98 more)

### Community 1 - "Core Dashboards & Firebase"
Cohesion: 0.02
Nodes (86): admin_screen.dart, coordinator_dashboard.dart, firebase_options.dart, guardian_dashboard.dart, home_screen.dart, DefaultFirebaseOptions, UnsupportedError, build (+78 more)

### Community 2 - "Student & Certificate Screens"
Cohesion: 0.02
Nodes (83): add_student_screen.dart, attendance_certificate_screen.dart, dart:io, AddStudentScreen, _AddStudentScreenState, build, dispose, _Field (+75 more)

### Community 3 - "Attendance Certificate Screen"
Cohesion: 0.03
Nodes (64): AttendanceCertificateScreen, _AttendanceCertificateScreenState, build, _DateButton, Divider, _fmtDate, initState, _previewRow (+56 more)

### Community 4 - "Guardian Dashboard"
Cohesion: 0.03
Nodes (62): AnnouncementsScreen, AuthService, _bellTime, build, _CalendarCard, Center, ClipPath, Column (+54 more)

### Community 5 - "Data Models"
Cohesion: 0.03
Nodes (51): dart:convert, Announcement, CopyCheck, CopyStatus, copyWith, Exam, ExamResult, FeeComponent (+43 more)

### Community 6 - "Timetable Settings Screen"
Cohesion: 0.03
Nodes (60): _addBell, _addClass, AlertDialog, _Bell, _bellDisplayNumber, _bellHdrCell, _bellRow, build (+52 more)

### Community 7 - "Attendance Screen"
Cohesion: 0.04
Nodes (53): dart:async, _accentColor, AnimatedContainer, AppBar, _AttendanceHeroCard, AttendanceScreen, _AttendanceScreenState, _Avatar (+45 more)

### Community 8 - "Fee Collection Screen"
Cohesion: 0.04
Nodes (50): AlwaysScrollableScrollPhysics, build, ChoiceChip, _ClassFeeSummary, Container, Divider, FeeCollectionScreen, _FeeCollectionScreenState (+42 more)

### Community 9 - "Free Bells Screen"
Cohesion: 0.04
Nodes (43): build, _buildBellCard, _buildClassRow, Container, Divider, _emptyState, Flexible, FreeBellsScreen (+35 more)

### Community 10 - "Copy Checking Screen"
Cohesion: 0.04
Nodes (37): fl_register_plugins(), _AllStudentsTab, AlwaysScrollableScrollPhysics, BoxConstraints, build, Center, _CheckSessionScreen, _CheckSessionScreenState (+29 more)

### Community 11 - "Copy Check Overview"
Cohesion: 0.04
Nodes (43): AlwaysScrollableScrollPhysics, build, Center, _colorFor, Container, _CoordCheckDetailScreen, _CoordCheckDetailScreenState, CopyCheckOverviewScreen (+35 more)

### Community 12 - "macOS App Icons"
Cohesion: 0.07
Nodes (43): AOT Library (libapp.so / app.so), App Icon 128x128, App Icon 16x16, App Icon 256x256, App Icon 32x32, App Icon 512x512, App Icon 64x64, AppIcon Appiconset (macOS) (+35 more)

### Community 13 - "Knowledge Graph Report"
Cohesion: 0.08
Nodes (41): School App Graph Visualization (HTML), AuthService, package:cloud_firestore/cloud_firestore.dart, Community: Admin Panel, Community: Analytics Module, Community: Announcements, Community: Attendance Certificate, Community: Attendance Class Detail (+33 more)

### Community 14 - "Analytics Screen"
Cohesion: 0.06
Nodes (34): _AbsenceEntry, _AbsenceLeaderboardTab, _AbsenceLeaderboardTabState, AnalyticsScreen, _AnalyticsScreenState, _AttendanceTrendTab, _AttendanceTrendTabState, BarChartGroupData (+26 more)

### Community 15 - "Windows Native Runner"
Cohesion: 0.09
Nodes (25): FlutterWindow(), OnCreate(), RegisterPlugins(), wWinMain(), CreateAndAttachConsole(), GetCommandLineArguments(), Utf8FromUtf16(), Create() (+17 more)

### Community 16 - "Teacher Management Screen"
Cohesion: 0.06
Nodes (30): AlertDialog, build, Center, _confirmRemove, Container, _currentDay, dispose, Divider (+22 more)

### Community 17 - "Leave Application Screen"
Cohesion: 0.07
Nodes (28): build, _card, Container, _dateLabel, dispose, _endDateLabel, Expanded, GestureDetector (+20 more)

### Community 18 - "Attendance History Screen"
Cohesion: 0.07
Nodes (28): AlwaysScrollableScrollPhysics, AttendanceHistoryScreen, _AttendanceHistoryScreenState, build, _CalStat, Card, Container, _emptyState (+20 more)

### Community 19 - "Leave Requests Screen"
Cohesion: 0.07
Nodes (27): free_bells_screen.dart, build, _buildList, capitalize, Center, _chip, Container, _detailRow (+19 more)

### Community 20 - "My Timetable Screen"
Cohesion: 0.08
Nodes (25): _Badge, build, _buildFullGrid, _buildPersonalView, Column, Container, _daySelector, Divider (+17 more)

### Community 21 - "Timetable Editor Screen"
Cohesion: 0.08
Nodes (23): build, _buildCell, _buildGrid, _buildLegend, Center, Chip, _colorFor, Container (+15 more)

### Community 22 - "Exam Management Screen"
Cohesion: 0.08
Nodes (22): AlwaysScrollableScrollPhysics, BorderSide, BoxConstraints, build, Container, Divider, _ExamCard, ExamManagementScreen (+14 more)

### Community 23 - "Admin Screen"
Cohesion: 0.1
Nodes (20): AdminScreen, _AdminScreenState, AlwaysScrollableScrollPhysics, build, Container, dispose, Divider, GestureDetector (+12 more)

### Community 24 - "Announcements Screen"
Cohesion: 0.1
Nodes (19): AnnouncementsScreen, _AnnouncementsScreenState, _audienceColor, BoxConstraints, build, _Card, Container, _fmtDate (+11 more)

### Community 25 - "Class Attendance Detail"
Cohesion: 0.11
Nodes (17): AttendanceClassDetailScreen, _AttendanceClassDetailScreenState, build, Container, Divider, Expanded, initState, launchUrl (+9 more)

### Community 26 - "iOS App Icons"
Cohesion: 0.23
Nodes (16): App Icon 20x20 @1x, App Icon 20x20 @2x, App Icon 20x20 @3x, App Icon 29x29 @1x, App Icon 29x29 @2x, App Icon 29x29 @3x, App Icon 40x40 @1x, App Icon 40x40 @2x (+8 more)

### Community 27 - "Android Launcher Icons"
Cohesion: 0.23
Nodes (16): Android Launcher Icon hdpi (72px), Android Launcher Icon mdpi (48px), Android Launcher Icon xhdpi (96px), Android Launcher Icon xxhdpi (144px), Android Launcher Icon xxxhdpi (192px), Android Mipmap Launcher Icon Assets, Flutter Logo App Icon, iOS AppIcon Asset Catalog (+8 more)

### Community 28 - "Web & Splash Assets"
Cohesion: 0.4
Nodes (10): macOS App Icon 1024x1024 - Flutter logo on white rounded-rectangle background with subtle shadow, light blue and dark navy blue chevrons, macOS style, Web Favicon - Flutter logo icon (tiny, ~16x16 equivalent), light blue chevron on transparent background, Flutter Framework Logo - iconic angled chevron/arrow shapes forming the letter F, using light sky-blue and dark navy-blue colors, Web PWA Icon 192x192 - Flutter logo, light blue and dark navy blue angled chevrons on white background, Web PWA Icon 512x512 - Flutter logo, light blue and dark navy blue chevrons on white background, large format standard icon, Web PWA Maskable Icon 192x192 - Flutter logo, light blue and dark navy blue chevrons on white background, safe-zone padded for maskable use, Web PWA Maskable Icon 512x512 - Flutter logo, light blue and dark navy blue chevrons on white background, large format maskable icon with safe-zone padding, macOS App Icon Asset - platform-specific icon in Xcode xcassets bundle for macOS Runner target (+2 more)

### Community 29 - "macOS Plugin Registration"
Cohesion: 0.33
Nodes (3): RegisterGeneratedPlugins(), MainFlutterWindow, NSWindow

### Community 30 - "iOS App Delegate"
Cohesion: 0.33
Nodes (2): AppDelegate, FlutterAppDelegate

### Community 31 - "Platform Test Suites"
Cohesion: 0.4
Nodes (2): RunnerTests, XCTestCase

### Community 32 - "Android Plugin Registrant"
Cohesion: 0.4
Nodes (2): GeneratedPluginRegistrant, -registerWithRegistry

### Community 33 - "Widget Tests"
Cohesion: 0.5
Nodes (3): package:flutter_test/flutter_test.dart, package:school_app/main.dart, main

### Community 34 - "Teacher Model"
Cohesion: 0.67
Nodes (2): copyWith, Teacher

### Community 35 - "Student Model"
Cohesion: 0.67
Nodes (2): copyWith, Student

### Community 36 - "Android Main Activity"
Cohesion: 1.0
Nodes (1): MainActivity

### Community 37 - "Timetable Entry Model"
Cohesion: 1.0
Nodes (1): TimetableEntry

### Community 38 - "iOS Bridging Header"
Cohesion: 1.0
Nodes (0): 

### Community 39 - "iOS Plugin Header"
Cohesion: 1.0
Nodes (0): 

### Community 40 - "Linux App Header"
Cohesion: 1.0
Nodes (0): 

### Community 41 - "Linux Plugin Header"
Cohesion: 1.0
Nodes (0): 

### Community 42 - "Windows Utils Header"
Cohesion: 1.0
Nodes (0): 

### Community 43 - "Windows Window Header"
Cohesion: 1.0
Nodes (0): 

### Community 44 - "Windows Resource Header"
Cohesion: 1.0
Nodes (0): 

### Community 45 - "Windows Plugin Header"
Cohesion: 1.0
Nodes (0): 

### Community 46 - "Linux CMake Build"
Cohesion: 1.0
Nodes (1): Linux CMakeLists.txt (Top-Level)

### Community 47 - "Windows Runner"
Cohesion: 1.0
Nodes (1): Community: Windows Native Runner

### Community 48 - "App Icons Report Node"
Cohesion: 1.0
Nodes (1): Community: App Icons & Web Assets

### Community 49 - "macOS Runner Report Node"
Cohesion: 1.0
Nodes (1): Community: macOS Native Runner

### Community 50 - "macOS Delegate Report Node"
Cohesion: 1.0
Nodes (1): Community: macOS App Delegate

### Community 51 - "Platform Tests Report Node"
Cohesion: 1.0
Nodes (1): Community: Platform Test Suites

### Community 52 - "Android Plugin Report Node"
Cohesion: 1.0
Nodes (1): Community: Android Plugin Registrant

### Community 53 - "Widget Tests Report Node"
Cohesion: 1.0
Nodes (1): Community: Widget Tests

## Knowledge Gaps
- **1003 isolated node(s):** `main`, `package:flutter_test/flutter_test.dart`, `package:school_app/main.dart`, `-registerWithRegistry`, `MainActivity` (+998 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Android Main Activity`** (2 nodes): `MainActivity.kt`, `MainActivity`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Timetable Entry Model`** (2 nodes): `timetable_entry.dart`, `TimetableEntry`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `iOS Bridging Header`** (1 nodes): `Runner-Bridging-Header.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `iOS Plugin Header`** (1 nodes): `GeneratedPluginRegistrant.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Linux App Header`** (1 nodes): `my_application.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Linux Plugin Header`** (1 nodes): `generated_plugin_registrant.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Windows Utils Header`** (1 nodes): `utils.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Windows Window Header`** (1 nodes): `win32_window.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Windows Resource Header`** (1 nodes): `resource.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Windows Plugin Header`** (1 nodes): `generated_plugin_registrant.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Linux CMake Build`** (1 nodes): `Linux CMakeLists.txt (Top-Level)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Windows Runner`** (1 nodes): `Community: Windows Native Runner`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `App Icons Report Node`** (1 nodes): `Community: App Icons & Web Assets`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `macOS Runner Report Node`** (1 nodes): `Community: macOS Native Runner`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `macOS Delegate Report Node`** (1 nodes): `Community: macOS App Delegate`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Platform Tests Report Node`** (1 nodes): `Community: Platform Test Suites`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Android Plugin Report Node`** (1 nodes): `Community: Android Plugin Registrant`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Widget Tests Report Node`** (1 nodes): `Community: Widget Tests`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `package:flutter/material.dart` connect `Core Dashboards & Firebase` to `Screen Hub & Shared Imports`, `Student & Certificate Screens`, `Attendance Certificate Screen`, `Guardian Dashboard`, `Data Models`, `Timetable Settings Screen`, `Attendance Screen`, `Fee Collection Screen`, `Free Bells Screen`, `Copy Checking Screen`, `Copy Check Overview`, `Analytics Screen`, `Teacher Management Screen`, `Leave Application Screen`, `Attendance History Screen`, `Leave Requests Screen`, `My Timetable Screen`, `Timetable Editor Screen`, `Exam Management Screen`, `Admin Screen`, `Announcements Screen`, `Class Attendance Detail`?**
  _High betweenness centrality (0.256) - this node is a cross-community bridge._
- **Why does `../theme.dart` connect `Core Dashboards & Firebase` to `Screen Hub & Shared Imports`, `Student & Certificate Screens`, `Attendance Certificate Screen`, `Guardian Dashboard`, `Data Models`, `Timetable Settings Screen`, `Attendance Screen`, `Fee Collection Screen`, `Free Bells Screen`, `Copy Checking Screen`, `Copy Check Overview`, `Analytics Screen`, `Teacher Management Screen`, `Leave Application Screen`, `Attendance History Screen`, `Leave Requests Screen`, `My Timetable Screen`, `Timetable Editor Screen`, `Exam Management Screen`, `Admin Screen`, `Announcements Screen`, `Class Attendance Detail`?**
  _High betweenness centrality (0.254) - this node is a cross-community bridge._
- **What connects `main`, `package:flutter_test/flutter_test.dart`, `package:school_app/main.dart` to the rest of the system?**
  _1003 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Screen Hub & Shared Imports` be split into smaller, more focused modules?**
  _Cohesion score 0.02 - nodes in this community are weakly interconnected._
- **Should `Core Dashboards & Firebase` be split into smaller, more focused modules?**
  _Cohesion score 0.02 - nodes in this community are weakly interconnected._
- **Should `Student & Certificate Screens` be split into smaller, more focused modules?**
  _Cohesion score 0.02 - nodes in this community are weakly interconnected._
- **Should `Attendance Certificate Screen` be split into smaller, more focused modules?**
  _Cohesion score 0.03 - nodes in this community are weakly interconnected._
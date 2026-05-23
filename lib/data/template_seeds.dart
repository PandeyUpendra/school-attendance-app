/// Seed data for the three default system report card templates.
/// [headerText] is left empty here and filled at seed time from
/// schools/{sid}.brandName so the school's chosen branding always appears —
/// never a hardcoded institution name.
const List<Map<String, dynamic>> kTemplateSeedData = [
  // ── CBSE Scholastic ────────────────────────────────────────────────────────
  {
    'name': 'CBSE Scholastic',
    'board': 'cbse',
    'headerLogo': '',
    'headerText': '', // filled from brandName at seed time
    'subjects': <Map<String, dynamic>>[],
    'showRank': true,
    'showAttendance': true,
    'showCoCurricular': false,
    'gradeScheme': [
      {'minPercent': 91.0, 'maxPercent': 100.0, 'grade': 'A1', 'gpa': 10.0},
      {'minPercent': 81.0, 'maxPercent': 90.0,  'grade': 'A2', 'gpa': 9.0},
      {'minPercent': 71.0, 'maxPercent': 80.0,  'grade': 'B1', 'gpa': 8.0},
      {'minPercent': 61.0, 'maxPercent': 70.0,  'grade': 'B2', 'gpa': 7.0},
      {'minPercent': 51.0, 'maxPercent': 60.0,  'grade': 'C1', 'gpa': 6.0},
      {'minPercent': 41.0, 'maxPercent': 50.0,  'grade': 'C2', 'gpa': 5.0},
      {'minPercent': 33.0, 'maxPercent': 40.0,  'grade': 'D',  'gpa': 4.0},
      {'minPercent': 0.0,  'maxPercent': 32.9,  'grade': 'E',  'gpa': 0.0},
    ],
    'footerText':
        'Class Teacher: _______________________    '
        'Principal: _______________________',
    'pageSize': 'A4',
    'orientation': 'portrait',
    'isSystemPreset': true,
  },

  // ── ICSE Standard ──────────────────────────────────────────────────────────
  {
    'name': 'ICSE Standard',
    'board': 'icse',
    'headerLogo': '',
    'headerText': '',
    'subjects': <Map<String, dynamic>>[],
    'showRank': true,
    'showAttendance': true,
    'showCoCurricular': true,
    'gradeScheme': [
      {'minPercent': 90.0, 'maxPercent': 100.0, 'grade': 'A+', 'gpa': 4.0},
      {'minPercent': 80.0, 'maxPercent': 89.9,  'grade': 'A',  'gpa': 4.0},
      {'minPercent': 70.0, 'maxPercent': 79.9,  'grade': 'B+', 'gpa': 3.5},
      {'minPercent': 60.0, 'maxPercent': 69.9,  'grade': 'B',  'gpa': 3.0},
      {'minPercent': 50.0, 'maxPercent': 59.9,  'grade': 'C+', 'gpa': 2.5},
      {'minPercent': 40.0, 'maxPercent': 49.9,  'grade': 'C',  'gpa': 2.0},
      {'minPercent': 35.0, 'maxPercent': 39.9,  'grade': 'D',  'gpa': 1.0},
      {'minPercent': 0.0,  'maxPercent': 34.9,  'grade': 'F',  'gpa': 0.0},
    ],
    'footerText':
        'Examined By: _______________________    '
        'Head of Institution: _______________________',
    'pageSize': 'A4',
    'orientation': 'portrait',
    'isSystemPreset': true,
  },

  // ── Custom Blank ───────────────────────────────────────────────────────────
  {
    'name': 'Custom Blank',
    'board': 'custom',
    'headerLogo': '',
    'headerText': '',
    'subjects': <Map<String, dynamic>>[],
    'showRank': false,
    'showAttendance': false,
    'showCoCurricular': false,
    'gradeScheme': [
      {'minPercent': 90.0, 'maxPercent': 100.0, 'grade': 'A+', 'gpa': 4.0},
      {'minPercent': 80.0, 'maxPercent': 89.9,  'grade': 'A',  'gpa': 3.7},
      {'minPercent': 70.0, 'maxPercent': 79.9,  'grade': 'B+', 'gpa': 3.3},
      {'minPercent': 60.0, 'maxPercent': 69.9,  'grade': 'B',  'gpa': 3.0},
      {'minPercent': 50.0, 'maxPercent': 59.9,  'grade': 'C',  'gpa': 2.0},
      {'minPercent': 33.0, 'maxPercent': 49.9,  'grade': 'D',  'gpa': 1.0},
      {'minPercent': 0.0,  'maxPercent': 32.9,  'grade': 'F',  'gpa': 0.0},
    ],
    'footerText': 'Signature: _______________________',
    'pageSize': 'A4',
    'orientation': 'portrait',
    'isSystemPreset': true,
  },
];

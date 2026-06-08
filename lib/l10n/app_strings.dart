import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../providers/locale_provider.dart';

/// Lightweight, map-based translations. Each key maps to per-language strings.
/// Hindi (`hi`) uses simple everyday wording. To translate more of the app,
/// add keys here and replace literals with `context.tr('key')`.
///
/// This intentionally avoids ARB / codegen so strings can be added incrementally
/// without a build step. English is always the fallback.
class AppStrings {
  static const Map<String, Map<String, String>> _values = {
    // ── Profile ──────────────────────────────────────────────────────────
    'myProfile':       {'en': 'My Profile',        'hi': 'मेरी प्रोफ़ाइल'},
    'account':         {'en': 'ACCOUNT',           'hi': 'खाता'},
    'email':           {'en': 'Email',             'hi': 'ईमेल'},
    'phone':           {'en': 'Phone',             'hi': 'फ़ोन'},
    'school':          {'en': 'School',            'hi': 'स्कूल'},
    'status':          {'en': 'Status',            'hi': 'स्थिति'},
    'assignedClasses': {'en': 'ASSIGNED CLASSES',  'hi': 'दी गई कक्षाएँ'},
    'children':        {'en': 'CHILDREN',          'hi': 'बच्चे'},
    'statusActive':    {'en': 'Active',            'hi': 'सक्रिय'},
    'statusPending':   {'en': 'Pending',           'hi': 'लंबित'},

    // ── Language ─────────────────────────────────────────────────────────
    'language':        {'en': 'Language',          'hi': 'भाषा'},
    'chooseLanguage':  {'en': 'Choose language',   'hi': 'भाषा चुनें'},
    'preferences':     {'en': 'PREFERENCES',       'hi': 'पसंद'},

    // ── Common actions ───────────────────────────────────────────────────
    'save':            {'en': 'Save',              'hi': 'सेव करें'},
    'cancel':          {'en': 'Cancel',            'hi': 'रद्द करें'},
    'logout':          {'en': 'Logout',            'hi': 'लॉग आउट'},

    // ── Login ────────────────────────────────────────────────────────────
    'signInSubtitle':  {'en': 'Sign in to your account', 'hi': 'अपने खाते में साइन इन करें'},
    'emailAddress':    {'en': 'Email Address',     'hi': 'ईमेल पता'},
    'password':        {'en': 'Password',          'hi': 'पासवर्ड'},
    'forgotPassword':  {'en': 'Forgot Password?',  'hi': 'पासवर्ड भूल गए?'},
    'signIn':          {'en': 'Sign In',           'hi': 'साइन इन करें'},

    // ── Forgot password ──────────────────────────────────────────────────
    'resetPassword':       {'en': 'Reset Password',       'hi': 'पासवर्ड रीसेट करें'},
    'forgotPasswordTitle': {'en': 'Forgot Your Password?', 'hi': 'अपना पासवर्ड भूल गए?'},
    'checkYourEmail':      {'en': 'Check Your Email',     'hi': 'अपना ईमेल देखें'},
    'forgotPasswordDesc':  {
      'en': "Enter the email address registered with your school account and we'll send you a secure link to reset your password.",
      'hi': 'अपने स्कूल खाते से जुड़ा ईमेल पता डालें, हम आपको पासवर्ड रीसेट करने के लिए एक सुरक्षित लिंक भेजेंगे।'
    },
    'resetSentDesc':       {
      'en': "If an account exists for that email, we've sent a password reset link. Check your inbox (and spam folder).",
      'hi': 'यदि उस ईमेल के लिए कोई खाता मौजूद है, तो हमने पासवर्ड रीसेट लिंक भेज दिया है। अपना इनबॉक्स (और स्पैम फ़ोल्डर) देखें।'
    },
    'sendResetLink':       {'en': 'Send Reset Link',     'hi': 'रीसेट लिंक भेजें'},
    'tryDifferentEmail':   {'en': 'Try a different email', 'hi': 'दूसरा ईमेल आज़माएँ'},
    'backToSignIn':        {'en': 'Back to Sign In',     'hi': 'साइन इन पर वापस जाएँ'},

    // ── Guardian login / phone OTP ───────────────────────────────────────
    'guardianSignInSubtitle': {'en': "Sign in to view your child's progress", 'hi': 'अपने बच्चे की प्रगति देखने के लिए साइन इन करें'},
    'signInWithPhone':  {'en': 'Sign In with Phone', 'hi': 'फ़ोन से साइन इन करें'},
    'phoneNumber':      {'en': 'Phone Number',     'hi': 'फ़ोन नंबर'},
    'sendOtp':          {'en': 'Send OTP',         'hi': 'OTP भेजें'},
    'sixDigitCode':     {'en': '6-digit code',     'hi': '6 अंकों का कोड'},
    'verify':           {'en': 'Verify',           'hi': 'सत्यापित करें'},
    'resendOtp':        {'en': 'Resend OTP',       'hi': 'OTP दोबारा भेजें'},

    // ── Notifications ────────────────────────────────────────────────────
    'notifications':         {'en': 'Notifications',          'hi': 'सूचनाएँ'},
    'markAllRead':           {'en': 'Mark all read',          'hi': 'सभी पढ़ा हुआ चिह्नित करें'},
    'clearAll':              {'en': 'Clear All',              'hi': 'सभी हटाएँ'},
    'clearAllNotifications': {'en': 'Clear All Notifications', 'hi': 'सभी सूचनाएँ हटाएँ'},
    'noNotificationsYet':    {'en': 'No notifications yet',   'hi': 'अभी कोई सूचना नहीं'},
    'delete':                {'en': 'Delete',                 'hi': 'हटाएँ'},
    'selectAll':             {'en': 'Select all',             'hi': 'सभी चुनें'},
    'deselectAll':           {'en': 'Deselect all',           'hi': 'चयन हटाएँ'},

    // ── Teacher home: section headers ────────────────────────────────────
    'secAcademics':        {'en': 'ACADEMICS',      'hi': 'शैक्षणिक'},
    'secStudents':         {'en': 'STUDENTS',       'hi': 'छात्र'},
    'secCalls':            {'en': 'CALLS',          'hi': 'कॉल'},
    'secLeave':            {'en': 'LEAVE',          'hi': 'अवकाश'},
    'secCopyChecking':     {'en': 'COPY CHECKING',  'hi': 'कॉपी जाँच'},
    'secHomework':         {'en': 'HOMEWORK',       'hi': 'गृहकार्य'},
    'secExamsMarks':       {'en': 'EXAMS & MARKS',  'hi': 'परीक्षा और अंक'},
    'secRemarks':          {'en': 'REMARKS',        'hi': 'टिप्पणियाँ'},
    'secMyTasks':          {'en': 'MY TASKS',       'hi': 'मेरे कार्य'},
    'secAnnouncements':    {'en': 'ANNOUNCEMENTS',  'hi': 'घोषणाएँ'},
    'secBirthdays':        {'en': 'BIRTHDAYS',      'hi': 'जन्मदिन'},
    'secMyTodoList':       {'en': 'MY TO-DO LIST',  'hi': 'मेरी टू-डू सूची'},
    'secSubstituteDutyToday': {'en': 'SUBSTITUTE DUTY TODAY', 'hi': 'आज की स्थानापन्न ड्यूटी'},

    // ── Teacher home: tile titles ────────────────────────────────────────
    'takeAttendance':      {'en': 'Take Attendance',        'hi': 'उपस्थिति लें'},
    'substituteDutyToday': {'en': 'Substitute Duty Today',  'hi': 'आज की स्थानापन्न ड्यूटी'},
    'myTimetable':         {'en': 'My Timetable',           'hi': 'मेरी समय-सारिणी'},
    'mySubstitutionDuties':{'en': 'My Substitution Duties', 'hi': 'मेरी स्थानापन्न ड्यूटी'},
    'studentList':         {'en': 'Student List',           'hi': 'छात्र सूची'},
    'attendanceHistory':   {'en': 'Attendance History',     'hi': 'उपस्थिति इतिहास'},
    'deletedStudents':     {'en': 'Deleted Students',       'hi': 'हटाए गए छात्र'},
    'studentRemarks':      {'en': 'Student Remarks',        'hi': 'छात्र टिप्पणियाँ'},
    'dailyCalls':          {'en': 'Daily Calls',            'hi': 'दैनिक कॉल'},
    'applyForLeave':       {'en': 'Apply for Leave',        'hi': 'अवकाश के लिए आवेदन'},
    'studentLeaveRequests':{'en': 'Student Leave Requests', 'hi': 'छात्र अवकाश अनुरोध'},
    'copyChecking':        {'en': 'Copy Checking',          'hi': 'कॉपी जाँच'},
    'homework':            {'en': 'Homework',               'hi': 'गृहकार्य'},
    'examsMarks':          {'en': 'Exams & Marks',          'hi': 'परीक्षा और अंक'},
    'myRemarks':           {'en': 'My Remarks',             'hi': 'मेरी टिप्पणियाँ'},
    'myTasks':             {'en': 'My Tasks',               'hi': 'मेरे कार्य'},
    'meetingTasks':        {'en': 'Meeting Tasks',          'hi': 'बैठक कार्य'},
    'noticeBoard':         {'en': 'Notice Board',           'hi': 'सूचना पट्ट'},
    'birthdays':           {'en': 'Birthdays',              'hi': 'जन्मदिन'},

    // ── Teacher home: tile subtitles ─────────────────────────────────────
    'subSubDutiesDesc':       {'en': 'Classes I have covered as substitute', 'hi': 'जिन कक्षाओं में मैंने स्थानापन्न के रूप में पढ़ाया'},
    'subExamsDesc':           {'en': 'Enter marks and view report cards', 'hi': 'अंक दर्ज करें और रिपोर्ट कार्ड देखें'},
    'subMyRemarksDesc':       {'en': 'Feedback from your coordinator and principal', 'hi': 'आपके समन्वयक और प्रधानाचार्य से प्रतिक्रिया'},
    'subCopyCheckDesc':       {'en': 'Mark student copies for your classes', 'hi': 'अपनी कक्षाओं के लिए छात्र कॉपियाँ जाँचें'},
    'subTodoDesc':            {'en': 'Personal tasks with reminders and due dates', 'hi': 'अनुस्मारक और नियत तिथि के साथ निजी कार्य'},
    'subHomeworkDesc':        {'en': 'Post and manage assignments for your classes', 'hi': 'अपनी कक्षाओं के लिए असाइनमेंट पोस्ट और प्रबंधित करें'},
    'subAnnouncementsDesc':   {'en': 'Post and view school announcements', 'hi': 'स्कूल घोषणाएँ पोस्ट करें और देखें'},
    'subStudentRemarksDesc':  {'en': 'Record observations and feedback for students', 'hi': 'छात्रों के लिए अवलोकन और प्रतिक्रिया दर्ज करें'},
    'subStudentRemarksDesc2': {'en': 'Record observations and feedback for your students', 'hi': 'अपने छात्रों के लिए अवलोकन और प्रतिक्रिया दर्ज करें'},
    'subStudentLeaveDesc':    {'en': 'Review leave applications submitted by guardians', 'hi': 'अभिभावकों द्वारा प्रस्तुत अवकाश आवेदनों की समीक्षा करें'},
    'subBirthdaysDesc':       {'en': 'Staff and student birthday wishes', 'hi': 'स्टाफ और छात्र जन्मदिन शुभकामनाएँ'},
    'subApplyLeaveDesc':      {'en': 'Submit a leave application to coordinator or principal', 'hi': 'समन्वयक या प्रधानाचार्य को अवकाश आवेदन भेजें'},
    'subMeetingTasksDesc':    {'en': 'Tasks assigned to you from staff meetings', 'hi': 'स्टाफ बैठकों से आपको सौंपे गए कार्य'},
    'subStudentListDesc':     {'en': 'View student records by class', 'hi': 'कक्षावार छात्र रिकॉर्ड देखें'},
    'subMyTasksDesc':         {'en': 'View tasks assigned to you', 'hi': 'आपको सौंपे गए कार्य देखें'},
    'subTimetableAllDesc':    {'en': 'View your bell schedule for all classes', 'hi': 'सभी कक्षाओं के लिए अपनी घंटी समय-सारिणी देखें'},
    'subTimetablePersonalDesc': {'en': 'View your personal bell schedule', 'hi': 'अपनी निजी घंटी समय-सारिणी देखें'},

    // ── Coordinator / Principal dashboards: section headers ──────────────
    'secAnalytics':      {'en': 'ANALYTICS',                 'hi': 'विश्लेषण'},
    'secFeeManagement':  {'en': 'FEE MANAGEMENT',            'hi': 'शुल्क प्रबंधन'},
    'secFreeBells':      {'en': 'FREE BELLS & SUBSTITUTION', 'hi': 'खाली घंटी और स्थानापन्न'},
    'secLeaveRequests':  {'en': 'LEAVE REQUESTS',            'hi': 'अवकाश अनुरोध'},
    'secReports':        {'en': 'REPORTS',                   'hi': 'रिपोर्ट'},
    'secStaffTasks':     {'en': 'STAFF TASKS',               'hi': 'स्टाफ कार्य'},
    'secStaff':          {'en': 'STAFF',                     'hi': 'स्टाफ'},
    'secTimetable':      {'en': 'TIMETABLE',                 'hi': 'समय-सारिणी'},

    // ── Coordinator / Principal dashboards: tile titles ──────────────────
    'staffTasks':           {'en': 'Staff Tasks',           'hi': 'स्टाफ कार्य'},
    'meetingRecords':       {'en': 'Meeting Records',        'hi': 'बैठक रिकॉर्ड'},
    'staffRemarks':         {'en': 'Staff Remarks',          'hi': 'स्टाफ टिप्पणियाँ'},
    'manageTeachers':       {'en': 'Manage Teachers',        'hi': 'शिक्षक प्रबंधन'},
    'absentTeachersToday':  {'en': 'Absent Teachers Today',  'hi': 'आज अनुपस्थित शिक्षक'},
    'studentDetails':       {'en': 'Student Details',        'hi': 'छात्र विवरण'},
    'promoteClass':         {'en': 'Promote Class',          'hi': 'कक्षा पदोन्नति'},
    'analyticsDashboard':   {'en': 'Analytics Dashboard',    'hi': 'विश्लेषण डैशबोर्ड'},
    'attendanceReports':    {'en': 'Attendance Reports',     'hi': 'उपस्थिति रिपोर्ट'},
    'feeCollection':        {'en': 'Fee Collection',         'hi': 'शुल्क संग्रह'},
    'feeStructure':         {'en': 'Fee Structure',          'hi': 'शुल्क संरचना'},
    'examManagement':       {'en': 'Exam Management',         'hi': 'परीक्षा प्रबंधन'},
    'reportCardTemplates':  {'en': 'Report Card Templates',  'hi': 'रिपोर्ट कार्ड टेम्पलेट'},
    'copyCheckingOverview': {'en': 'Copy Checking Overview', 'hi': 'कॉपी जाँच अवलोकन'},
    'homeworkOverview':     {'en': 'Homework Overview',      'hi': 'गृहकार्य अवलोकन'},
    'timetableSettings':    {'en': 'Timetable & Settings',   'hi': 'समय-सारिणी और सेटिंग्स'},
    'substitutionBells':    {'en': 'Substitution Bells',     'hi': 'स्थानापन्न घंटियाँ'},
    'leaveRequests':        {'en': 'Leave Requests',         'hi': 'अवकाश अनुरोध'},
    'assignDuties':         {'en': 'Assign Duties',          'hi': 'ड्यूटी सौंपें'},
    'myTodoList':           {'en': 'My To-Do List',          'hi': 'मेरी टू-डू सूची'},

    // ── Principal dashboard: section headers ─────────────────────────────
    'secActiveTasks':      {'en': 'ACTIVE TASKS',      'hi': 'सक्रिय कार्य'},
    'secFinance':          {'en': 'FINANCE',           'hi': 'वित्त'},
    'secTools':            {'en': 'TOOLS',             'hi': 'उपकरण'},
    'secCoordinatorTools': {'en': 'COORDINATOR TOOLS', 'hi': 'समन्वयक उपकरण'},

    // ── Principal dashboard: tile titles ─────────────────────────────────
    'manageCoordinators':      {'en': 'Manage Coordinators',        'hi': 'समन्वयक प्रबंधन'},
    'schoolSettings':          {'en': 'School Settings',            'hi': 'स्कूल सेटिंग्स'},
    'announcements':           {'en': 'Announcements',              'hi': 'घोषणाएँ'},
    'teacherDeletionRequests': {'en': 'Teacher Deletion Requests',  'hi': 'शिक्षक हटाने के अनुरोध'},
    'studentDeletionRequests': {'en': 'Student Deletion Requests',  'hi': 'छात्र हटाने के अनुरोध'},
    'schoolTimetable':         {'en': 'School Timetable',           'hi': 'स्कूल समय-सारिणी'},
    'studentRecords':          {'en': 'Student Records',            'hi': 'छात्र रिकॉर्ड'},
    'auditLog':                {'en': 'Audit Log',                  'hi': 'ऑडिट लॉग'},
    'coordinatorTools':        {'en': 'Coordinator Tools',          'hi': 'समन्वयक उपकरण'},
    'principalDigest':         {'en': 'Principal Digest',           'hi': 'प्रधानाचार्य सारांश'},

    // ── Principal dashboard: tile subtitles ──────────────────────────────
    'subManageCoordinatorsDesc':     {'en': 'Add, edit or remove coordinator accounts & class assignments', 'hi': 'समन्वयक खाते और कक्षा नियुक्तियाँ जोड़ें, संपादित करें या हटाएँ'},
    'subMeetingRecordsPrincipalDesc':{'en': 'View all meeting records, tasks and PDFs', 'hi': 'सभी बैठक रिकॉर्ड, कार्य और PDF देखें'},
    'subSchoolSettingsDesc':         {'en': 'Edit school info, academic, fees & communication', 'hi': 'स्कूल जानकारी, शैक्षणिक, शुल्क और संचार संपादित करें'},
    'subStaffTasksUnifiedDesc':      {'en': 'Create, assign and track task completion in one place', 'hi': 'एक ही स्थान पर कार्य बनाएँ, सौंपें और ट्रैक करें'},
    'subStaffRemarksPrincipalDesc':  {'en': 'Give feedback to teachers and coordinators', 'hi': 'शिक्षकों और समन्वयकों को प्रतिक्रिया दें'},
    'subPrincipalDigestDesc':        {'en': 'EOD summary · attendance, leaves, fees, copy-check', 'hi': 'दिन-अंत सारांश · उपस्थिति, अवकाश, शुल्क, कॉपी-जाँच'},
    'subAnnouncementsPrincipalDesc': {'en': 'Post and view school notices', 'hi': 'स्कूल सूचनाएँ पोस्ट करें और देखें'},
    'subLeaveApproveDesc':           {'en': 'Review & approve pending applications from teachers', 'hi': 'शिक्षकों के लंबित आवेदनों की समीक्षा और स्वीकृति'},
    'subTeacherDeletionDesc':        {'en': 'Review & approve coordinator requests to remove teachers', 'hi': 'शिक्षक हटाने के समन्वयक अनुरोधों की समीक्षा और स्वीकृति'},
    'subAttendanceReportsDesc':      {'en': 'Monthly history, % per student & low-attendance flags', 'hi': 'मासिक इतिहास, प्रति छात्र % और कम-उपस्थिति फ़्लैग'},
    'subStudentRecordsDesc':         {'en': 'View student details and contact info by class', 'hi': 'कक्षावार छात्र विवरण और संपर्क जानकारी देखें'},
    'subAuditLogDesc':               {'en': 'View all create/update/delete actions with before/after diff', 'hi': 'सभी क्रियाओं को पहले/बाद के अंतर के साथ देखें'},
    'subCoordinatorToolsDesc':       {'en': 'Access timetable, substitutions, leave management & more', 'hi': 'समय-सारिणी, स्थानापन्न, अवकाश प्रबंधन और अधिक'},

    // ── Guardian dashboard: section headers ──────────────────────────────
    'secAttendance':     {'en': 'ATTENDANCE',           'hi': 'उपस्थिति'},
    'secFees':           {'en': 'FEES',                 'hi': 'शुल्क'},
    'secLeaveRemarks':   {'en': 'LEAVE & REMARKS',      'hi': 'अवकाश और टिप्पणियाँ'},
    'secSchoolProfile':  {'en': 'SCHOOL & PROFILE',     'hi': 'स्कूल और प्रोफ़ाइल'},
    'secFeeBreakdown':   {'en': 'FEE BREAKDOWN',        'hi': 'शुल्क विवरण'},
    'secInstallments':   {'en': 'INSTALLMENTS SCHEDULE','hi': 'किस्त अनुसूची'},

    // ── Guardian dashboard: tile titles ──────────────────────────────────
    'subjectTeachers':       {'en': 'Subject Teachers',       'hi': 'विषय शिक्षक'},
    'examResults':           {'en': 'Exam Results',           'hi': 'परीक्षा परिणाम'},
    'attendanceCertificate': {'en': 'Attendance Certificate', 'hi': 'उपस्थिति प्रमाणपत्र'},
    'feeStatus':             {'en': 'Fee Status',             'hi': 'शुल्क स्थिति'},
    'feeDetails':            {'en': 'Fee Details',            'hi': 'शुल्क विवरण'},
    'schoolInfo':            {'en': 'School Info',            'hi': 'स्कूल जानकारी'},
    'mySchool':              {'en': 'My School',              'hi': 'मेरा स्कूल'},
    'parentalConsent':       {'en': 'Parental Consent',       'hi': 'अभिभावक सहमति'},

    // ── Guardian dashboard: tile subtitles ───────────────────────────────
    'subViewBellSchedule':   {'en': 'View class bell schedule',        'hi': 'कक्षा की घंटी समय-सारिणी देखें'},
    'subTeachersThisClass':  {'en': 'Teachers teaching this class',    'hi': 'इस कक्षा को पढ़ाने वाले शिक्षक'},
    'subViewHomework':       {'en': 'View homework assignments',       'hi': 'गृहकार्य असाइनमेंट देखें'},
    'subViewReportCards':    {'en': 'View report cards and marks',     'hi': 'रिपोर्ट कार्ड और अंक देखें'},
    'subMonthlyReports':     {'en': 'Monthly reports and calendar',    'hi': 'मासिक रिपोर्ट और कैलेंडर'},
    'subDownloadCertificate':{'en': 'Download certificate',            'hi': 'प्रमाणपत्र डाउनलोड करें'},
    'subSubmitLeave':        {'en': 'Submit leave application',        'hi': 'अवकाश आवेदन भेजें'},
    'subViewObservations':   {'en': 'View class teacher observations', 'hi': 'कक्षा शिक्षक की टिप्पणियाँ देखें'},
    'subViewProfile':        {'en': 'View student profile details',    'hi': 'छात्र प्रोफ़ाइल विवरण देखें'},
    'subViewAnnouncements':  {'en': 'View school announcements',       'hi': 'स्कूल घोषणाएँ देखें'},
    'subViewSchoolContact':  {'en': 'View school contact and details', 'hi': 'स्कूल संपर्क और विवरण देखें'},
    'subManagePermissions':  {'en': 'Manage permissions and privacy settings', 'hi': 'अनुमतियाँ और गोपनीयता सेटिंग्स प्रबंधित करें'},

    // ── My Timetable screen ──────────────────────────────────────────────
    'sharePdf':               {'en': 'Share PDF',         'hi': 'PDF साझा करें'},
    'downloadSharePdf':       {'en': 'Download / Share PDF', 'hi': 'PDF डाउनलोड / साझा करें'},
    'timetableNotSetUp':      {'en': 'Timetable not set up yet', 'hi': 'समय-सारिणी अभी सेट नहीं है'},
    'askCoordinatorConfigure':{'en': 'Ask the coordinator to configure it', 'hi': 'इसे सेट करने के लिए समन्वयक से कहें'},
    'classesLabel':           {'en': 'Classes',           'hi': 'कक्षाएँ'},
    'bellsPerDay':            {'en': 'Bells/Day',          'hi': 'घंटियाँ/दिन'},
    'classLabel':             {'en': 'Class',             'hi': 'कक्षा'},
    'lunch':                  {'en': 'Lunch',             'hi': 'लंच'},

    // ── Leave application screen ──────────────────────────────────────────
    'ok':                  {'en': 'OK',                  'hi': 'ठीक है'},
    'selectLeaveStartDate':{'en': 'Select Leave Start Date', 'hi': 'अवकाश आरंभ तिथि चुनें'},
    'pleaseSpecifyReason': {'en': 'Please specify a reason', 'hi': 'कृपया कारण बताएँ'},
    'reasonMin10':         {'en': 'Reason must be at least 10 characters', 'hi': 'कारण कम से कम 10 अक्षरों का होना चाहिए'},
    'leaveAlreadyApplied': {'en': 'Leave Already Applied', 'hi': 'अवकाश पहले से लागू'},
    'leaveOverlapFull':    {'en': 'You already have a Pending or Approved leave on these dates.\n\nPlease check your leave history or choose different dates.', 'hi': 'इन तिथियों पर आपका पहले से लंबित या स्वीकृत अवकाश है।\n\nकृपया अपना अवकाश इतिहास जाँचें या अलग तिथियाँ चुनें।'},
    'leaveSubmitted':      {'en': 'Leave application submitted successfully ✓', 'hi': 'अवकाश आवेदन सफलतापूर्वक भेजा गया ✓'},
    'sendApplicationTo':   {'en': 'Send Application To',  'hi': 'आवेदन यहाँ भेजें'},
    'leaveDuration':       {'en': 'Leave Duration',       'hi': 'अवकाश अवधि'},
    'startDate':           {'en': 'Start Date',           'hi': 'आरंभ तिथि'},
    'numberOfDays':        {'en': 'Number of Days',       'hi': 'दिनों की संख्या'},
    'reasonForLeave':      {'en': 'Reason for Leave',     'hi': 'अवकाश का कारण'},
    'describeReasonHint':  {'en': 'Describe your reason (min 10 characters)…', 'hi': 'अपना कारण लिखें (कम से कम 10 अक्षर)…'},
    'submitting':          {'en': 'Submitting…',          'hi': 'भेजा जा रहा है…'},
    'submitApplication':   {'en': 'Submit Application',   'hi': 'आवेदन भेजें'},
    'myLeaveHistory':      {'en': 'MY LEAVE HISTORY',     'hi': 'मेरा अवकाश इतिहास'},
    'noLeaveApplications': {'en': 'No leave applications yet.', 'hi': 'अभी कोई अवकाश आवेदन नहीं।'},
    'statusApproved':      {'en': 'Approved',             'hi': 'स्वीकृत'},
    'statusRejected':      {'en': 'Rejected',             'hi': 'अस्वीकृत'},

    // ── Announcements screen ─────────────────────────────────────────────
    'selectTitle':           {'en': 'Select Title',              'hi': 'शीर्षक चुनें'},
    'chooseAnnouncementType':{'en': 'Choose an announcement type','hi': 'घोषणा का प्रकार चुनें'},
    'customTitle':           {'en': 'Custom Title',              'hi': 'कस्टम शीर्षक'},
    'bodyLabel':             {'en': 'Body',                      'hi': 'विवरण'},
    'audience':              {'en': 'Audience',                  'hi': 'किसके लिए'},
    'pinAnnouncement':       {'en': 'Pin this announcement',     'hi': 'इस घोषणा को पिन करें'},
    'deleteAnnouncementQ':   {'en': 'Delete Announcement?',      'hi': 'घोषणा हटाएँ?'},
    'deleteSelectedQ':       {'en': 'Delete Selected?',          'hi': 'चयनित हटाएँ?'},
    'deleteAll':             {'en': 'Delete All',                'hi': 'सभी हटाएँ'},
    'retry':                 {'en': 'Retry',                     'hi': 'पुनः प्रयास'},
    'schoolNoticeBoard':     {'en': 'School notice board',       'hi': 'स्कूल सूचना पट्ट'},
    'newLabel':              {'en': 'New',                       'hi': 'नया'},
    'edit':                  {'en': 'Edit',                      'hi': 'संपादित करें'},

    // ── Fee overview screen ──────────────────────────────────────────────
    'feeCollectionOverviewSub': {'en': 'Class-wise collection overview', 'hi': 'कक्षावार संग्रह अवलोकन'},
    'exportToCsv':           {'en': 'Export to CSV',     'hi': 'CSV में निर्यात करें'},
    'refresh':               {'en': 'Refresh',           'hi': 'रिफ़्रेश'},
    'noClassesConfigured':   {'en': 'No classes configured yet.', 'hi': 'अभी कोई कक्षा सेट नहीं है।'},
    'secSchoolWideCollection':{'en': 'SCHOOL-WIDE COLLECTION', 'hi': 'विद्यालय-व्यापी संग्रह'},
    'collected':             {'en': 'Collected',         'hi': 'एकत्रित'},
    'pendingLabel':          {'en': 'Pending',           'hi': 'बकाया'},
    'fullyPaidLabel':        {'en': 'Fully Paid',        'hi': 'पूर्ण भुगतान'},
    'noFeeStructures':       {'en': 'No fee structures configured', 'hi': 'कोई शुल्क संरचना सेट नहीं'},

    // ── Fee collection screen ────────────────────────────────────────────
    'tapStudentRecordPayment':{'en': 'Tap a student to record payment', 'hi': 'भुगतान दर्ज करने के लिए छात्र पर टैप करें'},
    'noClassesConfiguredShort':{'en': 'No classes configured.', 'hi': 'कोई कक्षा सेट नहीं है।'},
    'noStudentsInClass':     {'en': 'No students in this class.', 'hi': 'इस कक्षा में कोई छात्र नहीं।'},
    'paidLabel':             {'en': 'Paid',               'hi': 'भुगतान'},
    'partialLabel':          {'en': 'Partial',            'hi': 'आंशिक'},
    'dueLabel':              {'en': 'Due',                'hi': 'बकाया'},
    'recordPayment':         {'en': 'Record Payment',     'hi': 'भुगतान दर्ज करें'},
    'instalmentOptional':    {'en': 'Instalment (optional)', 'hi': 'किस्त (वैकल्पिक)'},
    'noSpecificInstalment':  {'en': 'No specific instalment', 'hi': 'कोई विशेष किस्त नहीं'},
    'paymentMode':           {'en': 'Payment Mode',       'hi': 'भुगतान का तरीका'},
    'noteOptional':          {'en': 'Note (optional)',    'hi': 'टिप्पणी (वैकल्पिक)'},
    'savePayment':           {'en': 'Save Payment',       'hi': 'भुगतान सहेजें'},
    'secInstalmentsShort':   {'en': 'INSTALMENTS',        'hi': 'किस्तें'},
    'secPaymentHistory':     {'en': 'PAYMENT HISTORY',    'hi': 'भुगतान इतिहास'},
    'noPaymentsYet':         {'en': 'No payments recorded yet.', 'hi': 'अभी कोई भुगतान दर्ज नहीं।'},
    'printReceipt':          {'en': 'Print Receipt',      'hi': 'रसीद प्रिंट करें'},

    // ── Homework overview screen ─────────────────────────────────────────
    'subHomeworkOverviewAll':{'en': 'All assignments across classes', 'hi': 'सभी कक्षाओं के असाइनमेंट'},
    'deleteHomeworkQ':       {'en': 'Delete Homework?',   'hi': 'गृहकार्य हटाएँ?'},

    // ── Exam management screen ───────────────────────────────────────────
    'manageExamsResults':    {'en': 'Manage exams and results', 'hi': 'परीक्षाएँ और परिणाम प्रबंधित करें'},
    'newExam':               {'en': 'New Exam',           'hi': 'नई परीक्षा'},
    'deleteExamQ':           {'en': 'Delete Exam?',       'hi': 'परीक्षा हटाएँ?'},
    'enterMarks':            {'en': 'Enter Marks',        'hi': 'अंक दर्ज करें'},
    'reportCard':            {'en': 'Report Card',        'hi': 'रिपोर्ट कार्ड'},
    'subjectsLabel':         {'en': 'Subjects',           'hi': 'विषय'},
    'addLabel':              {'en': 'Add',                'hi': 'जोड़ें'},
    'examName':              {'en': 'Exam Name (e.g. Unit Test 1)', 'hi': 'परीक्षा का नाम (जैसे यूनिट टेस्ट 1)'},
    'maxMarksPerSubject':    {'en': 'Max Marks per Subject', 'hi': 'प्रति विषय अधिकतम अंक'},
    'examDate':              {'en': 'Exam Date',          'hi': 'परीक्षा तिथि'},

    // ── Attendance screen ────────────────────────────────────────────────
    'attendanceSaved':       {'en': 'Attendance Saved',   'hi': 'उपस्थिति सहेजी गई'},
    'notifyViaWhatsapp':     {'en': 'Notify via WhatsApp', 'hi': 'WhatsApp से सूचित करें'},
    'done':                  {'en': 'Done',               'hi': 'हो गया'},
    'savedOffline':          {'en': 'Saved Offline',      'hi': 'ऑफ़लाइन सहेजा गया'},
    'savedLocally':          {'en': 'Saved Locally',      'hi': 'स्थानीय रूप से सहेजा गया'},
    'searchByRoll':          {'en': 'Search by Roll No.', 'hi': 'रोल नंबर से खोजें'},
    'goToRollNumber':        {'en': 'Go to Roll Number',  'hi': 'रोल नंबर पर जाएँ'},
    'rollNotFound':          {'en': 'Roll number not found', 'hi': 'रोल नंबर नहीं मिला'},
    'go':                    {'en': 'Go',                 'hi': 'जाएँ'},
    'offlineAttendanceMsg':  {'en': 'Offline — attendance will be saved locally', 'hi': 'ऑफ़लाइन — उपस्थिति स्थानीय रूप से सहेजी जाएगी'},
    'editAttendance':        {'en': 'Edit Attendance',    'hi': 'उपस्थिति संपादित करें'},
    'notifyGuardiansWhatsapp':{'en': 'Notify Guardians via WhatsApp', 'hi': 'अभिभावकों को WhatsApp से सूचित करें'},
    'noClassAssigned':       {'en': 'No class assigned to you yet', 'hi': 'आपको अभी कोई कक्षा नहीं सौंपी गई'},
    'askCoordinatorAssign':  {'en': 'Ask the coordinator to assign your class and section', 'hi': 'समन्वयक से अपनी कक्षा और सेक्शन सौंपने को कहें'},
    'addStudentsFirst':      {'en': 'Add students via Student List first', 'hi': 'पहले छात्र सूची से छात्र जोड़ें'},
    'secRemarksComplaints':  {'en': 'REMARKS / COMPLAINTS', 'hi': 'टिप्पणियाँ / शिकायतें'},
    'noActiveRemarks':       {'en': 'No active remarks.',  'hi': 'कोई सक्रिय टिप्पणी नहीं।'},
    'attendanceDone':        {'en': 'ATTENDANCE DONE',    'hi': 'उपस्थिति पूर्ण'},
    'saveAttendance':        {'en': 'SAVE ATTENDANCE',    'hi': 'उपस्थिति सहेजें'},
    'whatsappAbsenceNotice': {'en': 'WHATSAPP ABSENCE NOTICE', 'hi': 'WhatsApp अनुपस्थिति सूचना'},

    // ── Daily calls screen ───────────────────────────────────────────────
    'dailyCallsSub':         {'en': 'Guardian follow-up & history', 'hi': 'अभिभावक फ़ॉलो-अप और इतिहास'},
    'reasonForAbsence':      {'en': 'Reason for absence:', 'hi': 'अनुपस्थिति का कारण:'},
    'exportPdf':             {'en': 'Export PDF',         'hi': 'PDF निर्यात करें'},
    'calledLabel':           {'en': 'Called',             'hi': 'कॉल किया'},
    'noHistoryFound':        {'en': 'No history found',   'hi': 'कोई इतिहास नहीं मिला'},
    'pastCallRecords':       {'en': 'Past call records will appear here', 'hi': 'पिछले कॉल रिकॉर्ड यहाँ दिखेंगे'},

    // ── Student details / shared ─────────────────────────────────────────
    'selectSection':         {'en': 'Select Section',     'hi': 'सेक्शन चुनें'},
    'noClassTeachersAssigned':{'en': 'No class teachers assigned', 'hi': 'कोई कक्षा शिक्षक नियुक्त नहीं'},
    'assignClassTeachersHint':{'en': 'Assign class teachers in Teacher Management', 'hi': 'शिक्षक प्रबंधन में कक्षा शिक्षक नियुक्त करें'},

    // ── Staff tasks screen ───────────────────────────────────────────────
    'deleteTaskTitle':       {'en': 'Delete Task',        'hi': 'कार्य हटाएँ'},
    'deleteTaskPermanently': {'en': 'Delete this task permanently?', 'hi': 'इस कार्य को स्थायी रूप से हटाएँ?'},
    'noDueDate':             {'en': 'No due date',        'hi': 'कोई नियत तिथि नहीं'},
    'noTasksAssigned':       {'en': 'No tasks assigned',  'hi': 'कोई कार्य नहीं सौंपा गया'},
    'allCaughtUp':           {'en': 'You are all caught up!', 'hi': 'आपका सब कुछ पूरा है!'},

    // ── To-do list screen ────────────────────────────────────────────────
    'addTask':               {'en': 'Add Task',           'hi': 'कार्य जोड़ें'},
    'addTodoTask':           {'en': 'Add To-Do Task',     'hi': 'टू-डू कार्य जोड़ें'},
    'dailyReminder':         {'en': 'Daily reminder',     'hi': 'दैनिक अनुस्मारक'},
    'dueDate':               {'en': 'Due date',           'hi': 'नियत तिथि'},
    'overdue':               {'en': 'OVERDUE',            'hi': 'अतिदेय'},
    'selectTask':            {'en': 'Select task',        'hi': 'कार्य चुनें'},
    'customTaskTitle':       {'en': 'Custom task title',  'hi': 'कस्टम कार्य शीर्षक'},

    // ── Coordinator / Principal dashboards: tile subtitles ───────────────
    'subStaffTasksDesc':         {'en': 'Assign tasks to teachers and track progress', 'hi': 'शिक्षकों को कार्य सौंपें और प्रगति ट्रैक करें'},
    'subMeetingRecordsDesc':     {'en': 'Manage meetings, agenda points and teacher task assignments', 'hi': 'बैठकें, एजेंडा और शिक्षक कार्य प्रबंधित करें'},
    'subStaffRemarksDesc':       {'en': 'Give feedback to teachers and view remarks from the principal', 'hi': 'शिक्षकों को प्रतिक्रिया दें और प्रधानाचार्य की टिप्पणियाँ देखें'},
    'subManageTeachersDesc':     {'en': 'Add or remove teachers from the school', 'hi': 'स्कूल में शिक्षक जोड़ें या हटाएँ'},
    'subStudentDetailsDesc':     {'en': 'View and manage student records by class', 'hi': 'कक्षावार छात्र रिकॉर्ड देखें और प्रबंधित करें'},
    'subStudentRemarksCoordDesc':{'en': 'Add and view observations for any student', 'hi': 'किसी भी छात्र के लिए अवलोकन जोड़ें और देखें'},
    'subDeletedStudentsDesc':    {'en': 'Read-only history of removed students, class-wise', 'hi': 'हटाए गए छात्रों का कक्षावार रिकॉर्ड (केवल पढ़ने योग्य)'},
    'subPromoteClassDesc':       {'en': 'Move a class up for the new academic year', 'hi': 'नए शैक्षणिक वर्ष के लिए कक्षा को आगे बढ़ाएँ'},
    'subAnnouncementsManageDesc':{'en': 'Post and manage school announcements', 'hi': 'स्कूल घोषणाएँ पोस्ट और प्रबंधित करें'},
    'subAnalyticsDesc':          {'en': 'Attendance trends, absences, fee progress & charts', 'hi': 'उपस्थिति रुझान, अनुपस्थिति, शुल्क प्रगति और चार्ट'},
    'subFeeCollectionDesc':      {'en': 'Class-wise collection, instalments & payment history', 'hi': 'कक्षावार संग्रह, किस्तें और भुगतान इतिहास'},
    'subFeeStructureDesc':       {'en': 'Set annual fee and components per class', 'hi': 'प्रति कक्षा वार्षिक शुल्क और घटक निर्धारित करें'},
    'subExamMgmtDesc':           {'en': 'Create exams, enter marks and view report cards', 'hi': 'परीक्षाएँ बनाएँ, अंक दर्ज करें और रिपोर्ट कार्ड देखें'},
    'subReportTemplatesDesc':    {'en': 'Design and manage PDF report card layouts', 'hi': 'PDF रिपोर्ट कार्ड लेआउट डिज़ाइन और प्रबंधित करें'},
    'subCopyCheckOverviewDesc':  {'en': 'View copy-checking status across all classes', 'hi': 'सभी कक्षाओं में कॉपी जाँच स्थिति देखें'},
    'subHomeworkOverviewDesc':   {'en': 'View all assignments posted across classes', 'hi': 'सभी कक्षाओं में पोस्ट किए गए असाइनमेंट देखें'},
    'subTimetableSettingsDesc':  {'en': 'Bell schedule, classes and teacher assignments', 'hi': 'घंटी समय, कक्षाएँ और शिक्षक नियुक्तियाँ'},
    'subSubstitutionBellsDesc':  {'en': 'View free periods & assign substitutions', 'hi': 'खाली पीरियड देखें और स्थानापन्न सौंपें'},
    'subSubstitutionHistoryDesc':{'en': 'View all substitution assignments & leaderboard', 'hi': 'सभी स्थानापन्न नियुक्तियाँ और लीडरबोर्ड देखें'},
    'subAssignDutiesDesc':       {'en': 'Assembly, lunch duty, gate duty and more', 'hi': 'सभा, लंच ड्यूटी, गेट ड्यूटी और अधिक'},
    'subViewTimetablesDesc':     {'en': 'View & share class timetables as PDF', 'hi': 'कक्षा समय-सारिणी PDF के रूप में देखें और साझा करें'},

    // ── Role selection ───────────────────────────────────────────────────
    'chooseHowToSignIn':   {'en': 'Choose how to sign in', 'hi': 'साइन इन का तरीका चुनें'},
    'staffLogin':          {'en': 'Staff Login',         'hi': 'स्टाफ़ लॉगिन'},
    'staffLoginSubtitle':  {'en': 'Teacher, Coordinator, Principal, Owner', 'hi': 'शिक्षक, समन्वयक, प्रधानाचार्य, मालिक'},
    'guardianSubtitle':    {'en': "View your child's attendance & progress", 'hi': 'अपने बच्चे की उपस्थिति और प्रगति देखें'},
    'adminSubtitle':       {'en': 'Manage registered users & login access', 'hi': 'पंजीकृत उपयोगकर्ता और लॉगिन प्रबंधित करें'},

    // ── Guardian ─────────────────────────────────────────────────────────
    'viewing':         {'en': 'VIEWING',           'hi': 'देख रहे हैं'},

    // ── Role names ───────────────────────────────────────────────────────
    'role_owner':       {'en': 'Owner',       'hi': 'मालिक'},
    'role_principal':   {'en': 'Principal',   'hi': 'प्रधानाचार्य'},
    'role_coordinator': {'en': 'Coordinator', 'hi': 'समन्वयक'},
    'role_teacher':     {'en': 'Teacher',     'hi': 'शिक्षक'},
    'role_guardian':    {'en': 'Guardian',    'hi': 'अभिभावक'},
    'role_admin':       {'en': 'Admin',       'hi': 'एडमिन'},
  };

  /// Returns the translation for [key] in [code], falling back to English then
  /// the key itself (so a missing translation is visible but never crashes).
  static String get(String code, String key) {
    final entry = _values[key];
    if (entry == null) return key;
    return entry[code] ?? entry['en'] ?? key;
  }

  /// Localised label for a role id (e.g. 'coordinator' → 'समन्वयक').
  static String role(String code, String roleId) => get(code, 'role_$roleId');
}

/// `context.tr('key')` — resolves a translation for the current language and
/// rebuilds the widget when the language changes.
extension L10nExtension on BuildContext {
  String tr(String key) =>
      AppStrings.get(Provider.of<LocaleProvider>(this).code, key);

  String trRole(String roleId) =>
      AppStrings.role(Provider.of<LocaleProvider>(this).code, roleId);
}

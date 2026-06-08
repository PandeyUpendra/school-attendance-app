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

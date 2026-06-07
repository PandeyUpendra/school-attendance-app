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

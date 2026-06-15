import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/base_firestore_service.dart';
import '../../services/school_settings_service.dart';

class SchoolSettingsProvider extends ChangeNotifier {
  final _svc = SchoolSettingsService();

  Map<String, dynamic> _school = {};
  Map<String, dynamic> _academic = {};
  Map<String, dynamic> _fees = {};
  Map<String, dynamic> _comm = {};
  bool _loaded = false;

  /// School id the live streams are currently bound to. Tracked so we only
  /// rebind when the active school actually changes.
  String? _boundSchoolId;

  StreamSubscription? _schoolSub;
  StreamSubscription? _academicSub;
  StreamSubscription? _feesSub;
  StreamSubscription? _commSub;

  SchoolSettingsProvider() {
    _bind();
    // Rebind whenever the signed-in school changes (login / session restore /
    // logout). Without this the provider stays locked to the school that was
    // active when it was first created — so owner edits saved under the real
    // school never surface for the principal/guardian reading afterwards.
    BaseFirestoreService.schoolIdNotifier.addListener(_onActiveSchoolChanged);
  }

  void _onActiveSchoolChanged() {
    try {
      if (AuthService.currentSchoolId == _boundSchoolId) return;
      _bind();
    } catch (_) {
      // Catch initialization errors during early startup
    }
  }

  bool _notifyPending = false;

  void _notifyDebounced() {
    if (_notifyPending) return;
    _notifyPending = true;
    scheduleMicrotask(() {
      _notifyPending = false;
      notifyListeners();
    });
  }

  /// (Re)subscribes the live streams to the currently active school, clearing
  /// any data carried over from a previously bound school.
  void _bind() {
    String? schoolId;
    try {
      schoolId = AuthService.currentSchoolId;
    } catch (_) {
      // Early startup: user is signed in but session not yet restored.
      // Do not listen to any streams yet; wait for _onActiveSchoolChanged to re-bind.
      _boundSchoolId = null;
      _schoolSub?.cancel(); _schoolSub = null;
      _academicSub?.cancel(); _academicSub = null;
      _feesSub?.cancel(); _feesSub = null;
      _commSub?.cancel(); _commSub = null;
      _school = {}; _academic = {}; _fees = {}; _comm = {};
      _loaded = false;
      return;
    }

    _boundSchoolId = schoolId;
    _schoolSub?.cancel();
    _schoolSub = null;
    _academicSub?.cancel();
    _academicSub = null;
    _feesSub?.cancel();
    _feesSub = null;
    _commSub?.cancel();
    _commSub = null;
    _school = {};
    _academic = {};
    _fees = {};
    _comm = {};
    _loaded = false;
    _init();
  }

  void _init() {
    _schoolSub = _svc.getSchoolSettings().listen((data) {
      _school = data;
      _loaded = true;
      _notifyDebounced();
    });
    _academicSub = _svc.getAcademicSettings().listen((data) {
      _academic = data;
      _loaded = true;
      _notifyDebounced();
    });
    _feesSub = _svc.getFeeSettings().listen((data) {
      _fees = data;
      _notifyDebounced();
    });
    _commSub = _svc.getCommSettings().listen((data) {
      _comm = data;
      _notifyDebounced();
    });
  }

  @override
  void dispose() {
    BaseFirestoreService.schoolIdNotifier.removeListener(_onActiveSchoolChanged);
    _schoolSub?.cancel();
    _academicSub?.cancel();
    _feesSub?.cancel();
    _commSub?.cancel();
    super.dispose();
  }

  bool get isLoaded => _loaded;

  // ── School ────────────────────────────────────────────────────────────────
  String get schoolName => _school['schoolName'] as String? ?? 'My School';
  String get schoolLogo => _school['logoUrl'] as String? ?? '';
  String get schoolPhone => _school['phone'] as String? ?? '';
  String get schoolEmail => _school['email'] as String? ?? '';
  String get schoolAddress => _school['address'] as String? ?? '';
  String get schoolCity => _school['city'] as String? ?? '';
  String get schoolState => _school['state'] as String? ?? '';
  String get schoolPinCode => _school['pinCode'] as String? ?? '';
  String get board => _school['board'] as String? ?? '';
  String get schoolType => _school['schoolType'] as String? ?? '';
  String get principalName => _school['principalName'] as String? ?? '';
  String get schoolTagline => _school['tagline'] as String? ?? '';
  String get schoolWebsite => _school['website'] as String? ?? '';
  String get establishedYear => _school['establishedYear'] as String? ?? '';
  String get subscriptionPlan => _school['subscriptionPlan'] as String? ?? 'free';

  // ── Social Media ──────────────────────────────────────────────────────────
  String get facebookUrl => _school['facebookUrl'] as String? ?? '';
  String get instagramUrl => _school['instagramUrl'] as String? ?? '';
  String get twitterUrl => _school['twitterUrl'] as String? ?? '';
  String get youtubeUrl => _school['youtubeUrl'] as String? ?? '';
  String get linkedinUrl => _school['linkedinUrl'] as String? ?? '';

  // ── Academic ─────────────────────────────────────────────────────────────
  int get classesFrom => _academic['classesFrom'] as int? ?? 6;
  int get classesTo => _academic['classesTo'] as int? ?? 10;
  /// Label-based getters (new format, added for pre-primary support).
  /// Falls back to constructing a label from the old integer fields.
  String get classesFromLabel =>
      _academic['classesFromLabel'] as String? ??
      'Class ${_academic['classesFrom'] ?? 1}';
  String get classesToLabel =>
      _academic['classesToLabel'] as String? ??
      'Class ${_academic['classesTo'] ?? 10}';
  List<String> get sections =>
      ((_academic['sections'] as List?) ?? ['A']).map((e) => e.toString()).toList();
  List<String> get classList =>
      ((_academic['classList'] as List?) ??
          ['6-A', '7-A', '8-A', '9-A', '10-A']).map((e) => e.toString()).toList();
  String get academicYearStart =>
      _academic['academicYearStart'] as String? ?? 'April';
  String get workingDays => _academic['workingDays'] as String? ?? 'Mon-Sat';
  int get periodsPerDay => _academic['periodsPerDay'] as int? ?? 8;
  int get periodDuration => _academic['periodDuration'] as int? ?? 45;
  int get lunchAfterPeriod => _academic['lunchAfterPeriod'] as int? ?? 4;

  List<String> get workingDaysList => workingDays == 'Mon-Fri'
      ? ['Mon', 'Tue', 'Wed', 'Thu', 'Fri']
      : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  // ── Fees ──────────────────────────────────────────────────────────────────
  String get feeFrequency => _fees['feeFrequency'] as String? ?? 'Monthly';
  int get feeDueDate => _fees['feeDueDate'] as int? ?? 10;
  bool get lateFeeEnabled => _fees['lateFeeEnabled'] as bool? ?? false;
  int get lateFeePerDay {
    final val = _fees['lateFeePerDay'] as int? ?? 0;
    return val < 0 ? 0 : val;
  }
  int get reminderDaysBefore => _fees['reminderDaysBefore'] as int? ?? 7;

  // ── Communication ─────────────────────────────────────────────────────────
  bool get whatsappEnabled => _comm['whatsappEnabled'] as bool? ?? false;
  String get schoolWhatsapp => _comm['schoolWhatsapp'] as String? ?? '';
  String get preferredLanguage =>
      _comm['preferredLanguage'] as String? ?? 'English';
  bool get busServiceAvailable =>
      _comm['busServiceAvailable'] as bool? ?? false;
  int get busRouteCount => _comm['busRouteCount'] as int? ?? 0;

  // ── Raw maps for settings editor ──────────────────────────────────────────
  Map<String, dynamic> get rawSchool => Map.from(_school);
  Map<String, dynamic> get rawAcademic => Map.from(_academic);
  Map<String, dynamic> get rawFees => Map.from(_fees);
  Map<String, dynamic> get rawComm => Map.from(_comm);

  // ── Update helpers ────────────────────────────────────────────────────────
  Future<void> updateSchoolSettings(Map<String, dynamic> data) =>
      _svc.updateSchoolSettings(data);
  Future<void> updateAcademicSettings(Map<String, dynamic> data) =>
      _svc.updateAcademicSettings(data);
  Future<void> updateFeeSettings(Map<String, dynamic> data) {
    if (data['lateFeePerDay'] != null) {
      final val = data['lateFeePerDay'] as int;
      if (val < 0) {
        throw ArgumentError('lateFeePerDay cannot be negative');
      }
    }
    return _svc.updateFeeSettings(data);
  }
  Future<void> updateCommSettings(Map<String, dynamic> data) =>
      _svc.updateCommSettings(data);
  Future<void> logChange(String f, String o, String n, String uid) =>
      _svc.logChange(f, o, n, uid);
  Stream<List<Map<String, dynamic>>> watchChangeLog() =>
      _svc.watchChangeLog();
}

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/school_settings_service.dart';

class SchoolSettingsProvider extends ChangeNotifier {
  final _svc = SchoolSettingsService();

  Map<String, dynamic> _school = {};
  Map<String, dynamic> _academic = {};
  Map<String, dynamic> _fees = {};
  Map<String, dynamic> _comm = {};
  bool _loaded = false;

  StreamSubscription? _schoolSub;
  StreamSubscription? _academicSub;
  StreamSubscription? _feesSub;
  StreamSubscription? _commSub;

  SchoolSettingsProvider() {
    _init();
  }

  void _init() {
    _schoolSub = _svc.getSchoolSettings().listen((data) {
      _school = data;
      _loaded = true;
      notifyListeners();
    });
    _academicSub = _svc.getAcademicSettings().listen((data) {
      _academic = data;
      _loaded = true;
      notifyListeners();
    });
    _feesSub = _svc.getFeeSettings().listen((data) {
      _fees = data;
      notifyListeners();
    });
    _commSub = _svc.getCommSettings().listen((data) {
      _comm = data;
      notifyListeners();
    });
  }

  @override
  void dispose() {
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

  // ── Academic ─────────────────────────────────────────────────────────────
  int get classesFrom => _academic['classesFrom'] as int? ?? 6;
  int get classesTo => _academic['classesTo'] as int? ?? 10;
  List<String> get sections =>
      List<String>.from(_academic['sections'] as List? ?? ['A']);
  List<String> get classList =>
      List<String>.from(_academic['classList'] as List? ??
          ['6-A', '7-A', '8-A', '9-A', '10-A']);
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
  int get lateFeePerDay => _fees['lateFeePerDay'] as int? ?? 0;
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
  Future<void> updateFeeSettings(Map<String, dynamic> data) =>
      _svc.updateFeeSettings(data);
  Future<void> updateCommSettings(Map<String, dynamic> data) =>
      _svc.updateCommSettings(data);
  Future<void> logChange(String f, String o, String n, String uid) =>
      _svc.logChange(f, o, n, uid);
  Stream<List<Map<String, dynamic>>> watchChangeLog() =>
      _svc.watchChangeLog();
}

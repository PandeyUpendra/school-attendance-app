import 'package:flutter/material.dart';
import '../theme.dart';

enum AttendanceStatus {
  present,
  absent,
  leave;

  /// Single-letter code stored in Firestore / local storage.
  String get code {
    switch (this) {
      case AttendanceStatus.present:
        return 'P';
      case AttendanceStatus.absent:
        return 'A';
      case AttendanceStatus.leave:
        return 'L';
    }
  }

  String get label {
    switch (this) {
      case AttendanceStatus.present:
        return 'Present';
      case AttendanceStatus.absent:
        return 'Absent';
      case AttendanceStatus.leave:
        return 'On Leave';
    }
  }

  Color get color {
    switch (this) {
      case AttendanceStatus.present:
        return AppTheme.success;
      case AttendanceStatus.absent:
        return AppTheme.danger;
      case AttendanceStatus.leave:
        return AppTheme.warning;
    }
  }

  Color get lightColor {
    switch (this) {
      case AttendanceStatus.present:
        return AppTheme.successLight;
      case AttendanceStatus.absent:
        return AppTheme.dangerLight;
      case AttendanceStatus.leave:
        return AppTheme.warningLight;
    }
  }

  bool get isPresent => this == AttendanceStatus.present;
  bool get isAbsent => this == AttendanceStatus.absent;
  bool get isLeave => this == AttendanceStatus.leave;

  /// Parses both legacy bool values and new string codes.
  static AttendanceStatus fromValue(dynamic v) {
    if (v == true || v == 'P') return AttendanceStatus.present;
    if (v == 'L') return AttendanceStatus.leave;
    return AttendanceStatus.absent; // false, 'A', or anything else
  }
}

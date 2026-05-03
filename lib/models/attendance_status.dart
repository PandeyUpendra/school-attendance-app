import 'package:flutter/material.dart';

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
        return const Color(0xFF2E7D32); // green
      case AttendanceStatus.absent:
        return const Color(0xFFC62828); // red
      case AttendanceStatus.leave:
        return const Color(0xFF1565C0); // blue
    }
  }

  Color get lightColor {
    switch (this) {
      case AttendanceStatus.present:
        return const Color(0xFFE8F5E9);
      case AttendanceStatus.absent:
        return const Color(0xFFFFEBEE);
      case AttendanceStatus.leave:
        return const Color(0xFFE3F2FD);
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

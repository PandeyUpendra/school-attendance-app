import 'package:cloud_firestore/cloud_firestore.dart';

// ── Fees Status ──────────────────────────────────────────────────────────────

enum FeesStatus {
  paid, pending, overdue;

  String get label {
    switch (this) {
      case FeesStatus.paid:    return 'Paid';
      case FeesStatus.pending: return 'Pending';
      case FeesStatus.overdue: return 'Overdue';
    }
  }

  static FeesStatus fromString(String? v) {
    switch (v) {
      case 'paid':    return FeesStatus.paid;
      case 'overdue': return FeesStatus.overdue;
      default:        return FeesStatus.pending;
    }
  }
}

// ── Test Result ──────────────────────────────────────────────────────────────

class TestResult {
  final String name;
  final String subject;
  final int marksObtained;
  final int totalMarks;
  final DateTime date;

  const TestResult({
    required this.name,
    required this.subject,
    required this.marksObtained,
    required this.totalMarks,
    required this.date,
  });

  Map<String, dynamic> toMap() => {
    'name': name,
    'subject': subject,
    'marksObtained': marksObtained,
    'totalMarks': totalMarks,
    'date': Timestamp.fromDate(date),
  };

  factory TestResult.fromMap(Map<String, dynamic> m) => TestResult(
    name: m['name'] as String? ?? '',
    subject: m['subject'] as String? ?? '',
    marksObtained: (m['marksObtained'] as num?)?.toInt() ?? 0,
    totalMarks: (m['totalMarks'] as num?)?.toInt() ?? 100,
    date: (m['date'] is Timestamp)
        ? (m['date'] as Timestamp).toDate()
        : DateTime.now(),
  );
}

// ── Behavior Tag & Note ──────────────────────────────────────────────────────

enum BehaviorTag {
  positive, neutral, concern;

  String get label {
    switch (this) {
      case BehaviorTag.positive: return 'Positive';
      case BehaviorTag.neutral:  return 'Neutral';
      case BehaviorTag.concern:  return 'Concern';
    }
  }

  static BehaviorTag fromString(String? v) {
    switch (v) {
      case 'positive': return BehaviorTag.positive;
      case 'concern':  return BehaviorTag.concern;
      default:         return BehaviorTag.neutral;
    }
  }
}

class BehaviorNote {
  final String text;
  final BehaviorTag tag;
  final DateTime date;
  final String addedBy;

  const BehaviorNote({
    required this.text,
    required this.tag,
    required this.date,
    required this.addedBy,
  });

  Map<String, dynamic> toMap() => {
    'text': text,
    'tag': tag.name,
    'date': Timestamp.fromDate(date),
    'addedBy': addedBy,
  };

  factory BehaviorNote.fromMap(Map<String, dynamic> m) => BehaviorNote(
    text: m['text'] as String? ?? '',
    tag: BehaviorTag.fromString(m['tag'] as String?),
    date: (m['date'] is Timestamp)
        ? (m['date'] as Timestamp).toDate()
        : DateTime.now(),
    addedBy: m['addedBy'] as String? ?? '',
  );
}

// ── Complaint ────────────────────────────────────────────────────────────────

class Complaint {
  final String text;
  final String subject;
  final DateTime date;
  final String addedBy;

  const Complaint({
    required this.text,
    required this.subject,
    required this.date,
    required this.addedBy,
  });

  Map<String, dynamic> toMap() => {
    'text': text,
    'subject': subject,
    'date': Timestamp.fromDate(date),
    'addedBy': addedBy,
  };

  factory Complaint.fromMap(Map<String, dynamic> m) => Complaint(
    text: m['text'] as String? ?? '',
    subject: m['subject'] as String? ?? '',
    date: (m['date'] is Timestamp)
        ? (m['date'] as Timestamp).toDate()
        : DateTime.now(),
    addedBy: m['addedBy'] as String? ?? '',
  );
}

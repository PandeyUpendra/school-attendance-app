import 'package:cloud_firestore/cloud_firestore.dart';

class SyllabusChapter {
  final String id;
  final String name;
  final List<String> topics;

  SyllabusChapter({
    required this.id,
    required this.name,
    required this.topics,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'topics': topics,
      };

  factory SyllabusChapter.fromJson(Map<String, dynamic> json) {
    return SyllabusChapter(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      topics: List<String>.from(json['topics'] as List? ?? []),
    );
  }
}

class SyllabusTemplate {
  final String id;
  final String className;
  final String subject;
  final List<SyllabusChapter> chapters;

  SyllabusTemplate({
    required this.id,
    required this.className,
    required this.subject,
    required this.chapters,
  });

  Map<String, dynamic> toJson() => {
        'className': className,
        'subject': subject,
        'chapters': chapters.map((c) => c.toJson()).toList(),
      };

  factory SyllabusTemplate.fromDoc(String id, Map<String, dynamic> data) {
    final list = data['chapters'] as List? ?? [];
    return SyllabusTemplate(
      id: id,
      className: (data['className'] as String?) ?? '',
      subject: (data['subject'] as String?) ?? '',
      chapters: list.map((c) => SyllabusChapter.fromJson(Map<String, dynamic>.from(c as Map))).toList(),
    );
  }
}

class SyllabusCoverage {
  final String id;
  final String className;
  final String subject;
  final List<String> completedChapterIds;
  final DateTime? lastUpdated;
  final String lastUpdatedBy;

  SyllabusCoverage({
    required this.id,
    required this.className,
    required this.subject,
    required this.completedChapterIds,
    this.lastUpdated,
    required this.lastUpdatedBy,
  });

  double getProgressPercent(int totalChapters) {
    if (totalChapters == 0) return 0.0;
    return (completedChapterIds.length / totalChapters).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
        'className': className,
        'subject': subject,
        'completedChapterIds': completedChapterIds,
        'lastUpdated': lastUpdated != null ? Timestamp.fromDate(lastUpdated!) : FieldValue.serverTimestamp(),
        'lastUpdatedBy': lastUpdatedBy,
      };

  factory SyllabusCoverage.fromDoc(String id, Map<String, dynamic> data) {
    final ts = data['lastUpdated'];
    return SyllabusCoverage(
      id: id,
      className: (data['className'] as String?) ?? '',
      subject: (data['subject'] as String?) ?? '',
      completedChapterIds: List<String>.from(data['completedChapterIds'] as List? ?? []),
      lastUpdated: ts is Timestamp ? ts.toDate() : null,
      lastUpdatedBy: (data['lastUpdatedBy'] as String?) ?? '',
    );
  }
}

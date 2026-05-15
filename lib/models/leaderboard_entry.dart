class LeaderboardEntry {
  final String studentId;
  final String studentName;
  final int    roll;
  final String classId;
  final double score;
  final int    rank;
  final String badge; // "gold" | "silver" | "bronze" | "none"

  const LeaderboardEntry({
    required this.studentId,
    required this.studentName,
    required this.roll,
    required this.classId,
    required this.score,
    required this.rank,
    required this.badge,
  });

  Map<String, dynamic> toJson() => {
    'studentId':   studentId,
    'studentName': studentName,
    'roll':        roll,
    'classId':     classId,
    'score':       score,
    'rank':        rank,
    'badge':       badge,
  };

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) =>
      LeaderboardEntry(
        studentId:   json['studentId']   as String? ?? '',
        studentName: json['studentName'] as String? ?? '',
        roll:        (json['roll']       as num?)?.toInt()    ?? 0,
        classId:     json['classId']     as String? ?? '',
        score:       (json['score']      as num?)?.toDouble() ?? 0.0,
        rank:        (json['rank']       as num?)?.toInt()    ?? 0,
        badge:       json['badge']       as String? ?? 'none',
      );

  LeaderboardEntry copyWith({
    String? studentId,
    String? studentName,
    int?    roll,
    String? classId,
    double? score,
    int?    rank,
    String? badge,
  }) => LeaderboardEntry(
    studentId:   studentId   ?? this.studentId,
    studentName: studentName ?? this.studentName,
    roll:        roll        ?? this.roll,
    classId:     classId     ?? this.classId,
    score:       score       ?? this.score,
    rank:        rank        ?? this.rank,
    badge:       badge       ?? this.badge,
  );
}

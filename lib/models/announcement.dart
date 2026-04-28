import 'package:cloud_firestore/cloud_firestore.dart';

/// A school announcement / notice.
/// Audience can be 'all', 'teachers', or 'guardians'.
class Announcement {
  final String   id;
  final String   title;
  final String   body;
  final String   postedBy;        // email / name of poster
  final String   postedByRole;    // coordinator | principal
  final String   audience;        // all | teachers | guardians
  final bool     isPinned;
  final DateTime? postedAt;

  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.postedBy,
    required this.postedByRole,
    required this.audience,
    required this.isPinned,
    this.postedAt,
  });

  Map<String, dynamic> toJson() => {
        'title':       title,
        'body':        body,
        'postedBy':    postedBy,
        'postedByRole': postedByRole,
        'audience':    audience,
        'isPinned':    isPinned,
        'postedAt':    FieldValue.serverTimestamp(),
      };

  factory Announcement.fromDoc(String id, Map<String, dynamic> data) {
    final ts = data['postedAt'];
    return Announcement(
      id:           id,
      title:        (data['title']        as String?) ?? '',
      body:         (data['body']         as String?) ?? '',
      postedBy:     (data['postedBy']     as String?) ?? '',
      postedByRole: (data['postedByRole'] as String?) ?? 'coordinator',
      audience:     (data['audience']     as String?) ?? 'all',
      isPinned:     (data['isPinned']     as bool?)   ?? false,
      postedAt:     ts is Timestamp ? ts.toDate() : null,
    );
  }
}

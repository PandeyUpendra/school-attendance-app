import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/announcement.dart';

class AnnouncementService {
  static final _db    = FirebaseFirestore.instance;
  static final _coll  = _db.collection('announcements');

  static final AnnouncementService _instance = AnnouncementService._();
  AnnouncementService._();
  factory AnnouncementService() => _instance;

  /// Fetches announcements visible to the given audience.
  /// Returns pinned first, then newest first.
  Future<List<Announcement>> getAnnouncements({String? audience}) async {
    final snap = await _coll.get();
    final list = snap.docs
        .map((d) => Announcement.fromDoc(d.id, d.data()))
        .where((a) =>
            audience == null ||
            a.audience == 'all' ||
            a.audience == audience)
        .toList();
    // Pinned first, then newest posted
    list.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      final ta = a.postedAt;
      final tb = b.postedAt;
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return tb.compareTo(ta);
    });
    return list;
  }

  /// Real-time stream of announcements (for notification badges).
  Stream<List<Announcement>> watchAnnouncements({String? audience}) {
    return _coll.snapshots().map((snap) {
      final list = snap.docs
          .map((d) => Announcement.fromDoc(d.id, d.data()))
          .where((a) =>
              audience == null ||
              a.audience == 'all' ||
              a.audience == audience)
          .toList();
      list.sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        final ta = a.postedAt;
        final tb = b.postedAt;
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });
      return list;
    });
  }

  Future<String> postAnnouncement(Announcement ann) async {
    final ref = await _coll.add(ann.toJson());
    return ref.id;
  }

  Future<void> deleteAnnouncement(String id) async {
    await _coll.doc(id).delete();
  }

  Future<void> setPinned(String id, bool pinned) async {
    await _coll.doc(id).update({'isPinned': pinned});
  }

  /// Fetches all announcements posted by a specific role (e.g. 'principal'),
  /// sorted newest first. Used for the Principal's notification log.
  Future<List<Announcement>> getAnnouncementsByRole(String role) async {
    final snap = await _coll.get();
    final list = snap.docs
        .map((d) => Announcement.fromDoc(d.id, d.data()))
        .where((a) => a.postedByRole == role)
        .toList();
    list.sort((a, b) {
      final ta = a.postedAt;
      final tb = b.postedAt;
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return tb.compareTo(ta);
    });
    return list;
  }
}

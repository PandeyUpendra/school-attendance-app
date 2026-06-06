import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/announcement.dart';
import 'auth_service.dart';

class AnnouncementService {
  final _db = FirebaseFirestore.instance;

  /// School-scoped announcements collection: schools/{sid}/announcements.
  /// schoolId is read lazily so it always reflects the active session.
  CollectionReference<Map<String, dynamic>> get _coll =>
      _db.collection('schools').doc(AuthService.currentSchoolId)
         .collection('announcements');

  static final AnnouncementService _instance = AnnouncementService._();
  AnnouncementService._();
  factory AnnouncementService() => _instance;

  /// Builds the set of `audience` values visible to this viewer so the filter
  /// runs server-side (`whereIn`) instead of fetching the whole collection.
  List<String> _audiencesFor(String? audience, String? viewerClass) {
    final audiences = <String>{'all'};
    if (audience != null) audiences.add(audience);
    if (viewerClass != null) audiences.add('class:$viewerClass');
    return audiences.toList();
  }

  /// Pinned first, then newest posted. Sorting stays client-side (Firestore
  /// can't order by isPinned+postedAt without a composite index).
  void _sortPinnedThenNewest(List<Announcement> list) {
    list.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      final ta = a.postedAt;
      final tb = b.postedAt;
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return tb.compareTo(ta);
    });
  }

  /// Fetches announcements visible to the given audience.
  /// Returns pinned first, then newest first.
  Future<List<Announcement>> getAnnouncements(
      {String? audience, String? viewerClass}) async {
    final snap = await _coll
        .where('audience', whereIn: _audiencesFor(audience, viewerClass))
        .get();
    final list = snap.docs
        .map((d) => Announcement.fromDoc(d.id, d.data()))
        .toList();
    _sortPinnedThenNewest(list);
    return list;
  }

  /// Real-time stream of announcements (for notification badges).
  Stream<List<Announcement>> watchAnnouncements(
      {String? audience, String? viewerClass}) {
    return _coll
        .where('audience', whereIn: _audiencesFor(audience, viewerClass))
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => Announcement.fromDoc(d.id, d.data()))
          .toList();
      _sortPinnedThenNewest(list);
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

  /// Fetches all announcements posted by a specific role, sorted newest first.
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

  /// Fetches all announcements posted by a specific user (by posterName/email),
  /// sorted newest first. Used for "My Log" tab.
  Future<List<Announcement>> getAnnouncementsByPoster(String posterName) async {
    final snap = await _coll.get();
    final list = snap.docs
        .map((d) => Announcement.fromDoc(d.id, d.data()))
        .where((a) => a.postedBy == posterName)
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

  /// Batch-deletes multiple announcements by ID.
  Future<void> deleteAnnouncements(List<String> ids) async {
    final batch = _db.batch();
    for (final id in ids) {
      batch.delete(_coll.doc(id));
    }
    await batch.commit();
  }

  // ── Custom announcement titles ────────────────────────────────────────────
  // Staff-saved titles that show up in the title dropdown alongside the
  // built-in presets. School-scoped so the whole school shares them.

  CollectionReference<Map<String, dynamic>> get _templatesColl =>
      _db.collection('schools').doc(AuthService.currentSchoolId)
         .collection('announcement_templates');

  /// All custom titles saved for reuse, as title → default message.
  Future<Map<String, String>> getCustomTemplates() async {
    final snap = await _templatesColl.get();
    final map = <String, String>{};
    for (final d in snap.docs) {
      final t = (d.data()['title'] as String?)?.trim();
      if (t != null && t.isNotEmpty) {
        map[t] = (d.data()['message'] as String?) ?? '';
      }
    }
    return map;
  }

  /// Saves (or updates) a custom announcement title and its default message so
  /// it appears in the title dropdown next time. The doc id is derived from the
  /// title, so re-saving the same title overwrites instead of duplicating.
  Future<void> saveCustomTemplate(String title, String message) async {
    final t = title.trim();
    if (t.isEmpty) return;
    var id = t.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    if (id.replaceAll('_', '').isEmpty) id = 't_${t.hashCode}';
    await _templatesColl.doc(id).set({'title': t, 'message': message});
  }
}

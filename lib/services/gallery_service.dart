import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import '../models/gallery_album.dart';
import '../models/gallery_photo.dart';

/// Gallery service — Firestore + Firebase Storage backend.
///
/// Firestore paths:
///   schools/{schoolId}/albums/{albumId}
///   schools/{schoolId}/photos/{photoId}
///
/// Storage paths:
///   schools/{schoolId}/gallery/{albumId}/original/{photoId}.jpg
///   schools/{schoolId}/gallery/{albumId}/compressed/{photoId}.jpg
///   schools/{schoolId}/gallery/{albumId}/watermarked/{photoId}.jpg
class GalleryService {
  static const _schoolId  = 'school_1';
  static const _schoolName = 'Our School';
  static const _pageSize  = 20;
  static const _albumPage = 10;

  static final _db      = FirebaseFirestore.instance;
  static final _storage = FirebaseStorage.instance;

  static CollectionReference get _albumsColl =>
      _db.collection('schools').doc(_schoolId).collection('albums');

  static CollectionReference get _photosColl =>
      _db.collection('schools').doc(_schoolId).collection('photos');

  static CollectionReference get _notifColl =>
      _db.collection('notifications');

  static final GalleryService _instance = GalleryService._();
  GalleryService._();
  factory GalleryService() => _instance;

  // ── Albums ─────────────────────────────────────────────────────────────────

  /// Creates a new album document; returns the albumId.
  Future<String> createAlbum({
    required String   title,
    required String   description,
    required DateTime eventDate,
    required String   createdBy,
  }) async {
    final ref = await _albumsColl.add({
      'title':         title,
      'description':   description,
      'eventDate':     Timestamp.fromDate(eventDate),
      'coverPhotoUrl': '',
      'createdBy':     createdBy,
      'createdAt':     FieldValue.serverTimestamp(),
      'photoCount':    0,
      'isPublished':   true,
    });
    return ref.id;
  }

  /// Real-time stream of all albums (newest event first).
  /// Filters published/draft client-side to avoid a composite Firestore index.
  Stream<List<GalleryAlbum>> getAlbums({
    DocumentSnapshot? lastDoc,
    bool adminView = false,
  }) {
    Query q = _albumsColl.orderBy('eventDate', descending: true);
    if (lastDoc != null) q = q.startAfterDocument(lastDoc);
    q = q.limit(_albumPage * 3); // fetch extra to absorb client-side filtering
    return q.snapshots().map((snap) {
      final albums = snap.docs.map(GalleryAlbum.fromFirestore).toList();
      if (!adminView) return albums.where((a) => a.isPublished).take(_albumPage).toList();
      return albums.take(_albumPage).toList();
    });
  }

  /// One-time fetch of albums; filters published/draft client-side.
  Future<List<GalleryAlbum>> fetchAlbums({
    DocumentSnapshot? lastDoc,
    bool adminView = false,
  }) async {
    Query q = _albumsColl.orderBy('eventDate', descending: true);
    if (lastDoc != null) q = q.startAfterDocument(lastDoc);
    q = q.limit(_albumPage * 3); // fetch extra to absorb client-side filtering
    final snap = await q.get();
    final albums = snap.docs.map(GalleryAlbum.fromFirestore).toList();
    if (!adminView) return albums.where((a) => a.isPublished).take(_albumPage).toList();
    return albums.take(_albumPage).toList();
  }

  Future<void> updateAlbum(
    String albumId, {
    String?   title,
    String?   description,
    DateTime? eventDate,
  }) async {
    final data = <String, dynamic>{};
    if (title       != null) data['title']       = title;
    if (description != null) data['description'] = description;
    if (eventDate   != null) data['eventDate']   = Timestamp.fromDate(eventDate);
    if (data.isNotEmpty) await _albumsColl.doc(albumId).update(data);
  }

  Future<void> publishAlbum(String albumId, String albumTitle) async {
    await _albumsColl.doc(albumId).update({'isPublished': true});
    // Notify all roles that can view the gallery
    await _notifColl.add({
      'type':      'gallery',
      'title':     'New Photos Added \u{1F4F8}',
      'body':      '$albumTitle photos are now available in the gallery.',
      'audience':  'all',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> unpublishAlbum(String albumId) async {
    await _albumsColl.doc(albumId).update({'isPublished': false});
  }

  /// Deletes an album and all its photos (Firestore + Storage).
  Future<void> deleteAlbum(String albumId) async {
    // Delete all photos in this album
    final photosSnap = await _photosColl
        .where('albumId', isEqualTo: albumId)
        .get();
    for (final doc in photosSnap.docs) {
      await _deletePhotoDoc(doc.id, albumId);
    }
    await _albumsColl.doc(albumId).delete();
  }

  // ── Photos ─────────────────────────────────────────────────────────────────

  /// Real-time stream of photos for an album (newest first).
  /// Sort is done client-side to avoid a composite Firestore index.
  Stream<List<GalleryPhoto>> getPhotos(String albumId) {
    return _photosColl
        .where('albumId', isEqualTo: albumId)
        .limit(_pageSize)
        .snapshots()
        .map((snap) {
          final photos = snap.docs.map(GalleryPhoto.fromFirestore).toList();
          photos.sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
          return photos;
        });
  }

  /// Paginated fetch of photos; sort client-side to avoid composite index.
  Future<List<GalleryPhoto>> fetchPhotos(
    String albumId, {
    DocumentSnapshot? lastDoc,
  }) async {
    Query q = _photosColl
        .where('albumId', isEqualTo: albumId)
        .limit(_pageSize);
    if (lastDoc != null) q = q.startAfterDocument(lastDoc);
    final snap = await q.get();
    final photos = snap.docs.map(GalleryPhoto.fromFirestore).toList();
    photos.sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
    return photos;
  }

  /// Returns raw [QueryDocumentSnapshot] for pagination cursors.
  Future<List<QueryDocumentSnapshot>> fetchPhotosDocs(
    String albumId, {
    DocumentSnapshot? lastDoc,
  }) async {
    Query q = _photosColl
        .where('albumId', isEqualTo: albumId)
        .limit(_pageSize);
    if (lastDoc != null) q = q.startAfterDocument(lastDoc);
    final snap = await q.get();
    return snap.docs;
  }

  /// Deletes a single photo (Firestore + Storage).
  Future<void> deletePhoto(String photoId, String albumId) async {
    await _deletePhotoDoc(photoId, albumId);
    // Decrement album photo count
    await _albumsColl.doc(albumId).update({
      'photoCount': FieldValue.increment(-1),
    });
  }

  Future<void> _deletePhotoDoc(String photoId, String albumId) async {
    // Delete storage files (best effort)
    for (final variant in ['original', 'compressed', 'watermarked']) {
      try {
        await _storage
            .ref('schools/$_schoolId/gallery/$albumId/$variant/$photoId.jpg')
            .delete();
      } catch (_) {}
    }
    await _photosColl.doc(photoId).delete();
  }

  /// Uploads [files] to [albumId], processing each:
  /// compress → watermark → upload all 3 variants.
  ///
  /// [onProgress] is called after each photo finishes: (done, total).
  /// [onCoverSet] fires when the first photo becomes the album cover.
  Future<void> uploadPhotos(
    String      albumId,
    List<File>  files,
    String      uploadedBy, {
    void Function(int done, int total)? onProgress,
  }) async {
    for (var i = 0; i < files.length; i++) {
      await _uploadSinglePhoto(albumId, files[i], uploadedBy);
      onProgress?.call(i + 1, files.length);
    }
  }

  Future<void> _uploadSinglePhoto(
    String albumId,
    File   file,
    String uploadedBy,
  ) async {
    final photoId   = _photosColl.doc().id;
    final fileName  = file.path.split('/').last;
    final origBytes = await file.readAsBytes();

    // 1. Compress
    final compressedBytes = await FlutterImageCompress.compressWithList(
      origBytes,
      minWidth:  1080,
      minHeight: 1080,
      quality:   70,
    );

    // 2. Watermark (applied to the compressed version)
    final watermarkedBytes = await _addWatermark(compressedBytes);

    // 3. Upload all 3 variants
    final basePath = 'schools/$_schoolId/gallery/$albumId';
    final origUrl  = await _uploadBytes(
        '$basePath/original/$photoId.jpg',     origBytes);
    final compUrl  = await _uploadBytes(
        '$basePath/compressed/$photoId.jpg',   Uint8List.fromList(compressedBytes));
    final wmUrl    = await _uploadBytes(
        '$basePath/watermarked/$photoId.jpg',  Uint8List.fromList(watermarkedBytes));

    // 4. Save to Firestore
    await _photosColl.doc(photoId).set({
      'albumId':        albumId,
      'originalUrl':    origUrl,
      'compressedUrl':  compUrl,
      'watermarkedUrl': wmUrl,
      'uploadedBy':     uploadedBy,
      'uploadedAt':     FieldValue.serverTimestamp(),
      'fileName':       fileName,
    });

    // 5. Increment album photoCount; set cover if first photo
    final albumDoc  = await _albumsColl.doc(albumId).get();
    final albumData = albumDoc.data() as Map<String, dynamic>?;
    final count     = (albumData?['photoCount'] as int?) ?? 0;
    final updates   = <String, dynamic>{'photoCount': FieldValue.increment(1)};
    if (count == 0 || ((albumData?['coverPhotoUrl'] as String?) ?? '').isEmpty) {
      updates['coverPhotoUrl'] = compUrl;
    }
    await _albumsColl.doc(albumId).update(updates);
  }

  Future<String> _uploadBytes(String path, Uint8List bytes) async {
    final ref  = _storage.ref(path);
    final task = await ref.putData(
      bytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return await task.ref.getDownloadURL();
  }

  /// Adds a semi-transparent school-name watermark to the bottom-right corner.
  Future<List<int>> _addWatermark(List<int> bytes) async {
    final decoded = img.decodeImage(Uint8List.fromList(bytes));
    if (decoded == null) return bytes;

    const text      = _schoolName;
    final font      = img.arial14;
    const padding   = 10;
    const bgPadding = 6;

    // Approximate text dimensions (arial14 chars ~8×16px)
    const textW = _schoolName.length * 8;
    const textH  = 16;
    final x      = decoded.width  - textW - padding - bgPadding;
    final y      = decoded.height - textH - padding - bgPadding;

    // Semi-transparent background rect
    img.fillRect(
      decoded,
      x1: x - bgPadding,
      y1: y - bgPadding,
      x2: x + textW + bgPadding,
      y2: y + textH + bgPadding,
      color: img.ColorRgba8(0, 0, 0, 150),
    );

    // White text
    img.drawString(
      decoded,
      text,
      font:  font,
      x:     x,
      y:     y,
      color: img.ColorRgba8(255, 255, 255, 230),
    );

    return img.encodeJpg(decoded, quality: 90);
  }

  /// Updates the album cover photo URL.
  Future<void> setCover(String albumId, String photoUrl) async {
    await _albumsColl.doc(albumId).update({'coverPhotoUrl': photoUrl});
  }

  /// Downloads image bytes from a network URL using dart:io.
  Future<Uint8List> downloadBytes(String url) async {
    final client   = HttpClient();
    final request  = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    final builder  = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    client.close();
    return builder.toBytes();
  }
}

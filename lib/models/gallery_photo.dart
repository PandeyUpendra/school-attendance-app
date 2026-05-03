import 'package:cloud_firestore/cloud_firestore.dart';

class GalleryPhoto {
  final String   id;
  final String   albumId;
  final String   originalUrl;
  final String   compressedUrl;
  final String   watermarkedUrl;
  final String   uploadedBy;
  final DateTime uploadedAt;
  final String   fileName;

  const GalleryPhoto({
    required this.id,
    required this.albumId,
    required this.originalUrl,
    required this.compressedUrl,
    required this.watermarkedUrl,
    required this.uploadedBy,
    required this.uploadedAt,
    required this.fileName,
  });

  factory GalleryPhoto.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return GalleryPhoto(
      id:             doc.id,
      albumId:        (d['albumId']        as String?)    ?? '',
      originalUrl:    (d['originalUrl']    as String?)    ?? '',
      compressedUrl:  (d['compressedUrl']  as String?)    ?? '',
      watermarkedUrl: (d['watermarkedUrl'] as String?)    ?? '',
      uploadedBy:     (d['uploadedBy']     as String?)    ?? '',
      uploadedAt:     (d['uploadedAt']     as Timestamp?) ?.toDate() ?? DateTime.now(),
      fileName:       (d['fileName']       as String?)    ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'albumId':        albumId,
    'originalUrl':    originalUrl,
    'compressedUrl':  compressedUrl,
    'watermarkedUrl': watermarkedUrl,
    'uploadedBy':     uploadedBy,
    'uploadedAt':     FieldValue.serverTimestamp(),
    'fileName':       fileName,
  };
}

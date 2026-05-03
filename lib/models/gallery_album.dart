import 'package:cloud_firestore/cloud_firestore.dart';

class GalleryAlbum {
  final String   id;
  final String   title;
  final String   description;
  final DateTime eventDate;
  final String   coverPhotoUrl;
  final String   createdBy;
  final DateTime createdAt;
  final int      photoCount;
  final bool     isPublished;

  const GalleryAlbum({
    required this.id,
    required this.title,
    required this.description,
    required this.eventDate,
    required this.coverPhotoUrl,
    required this.createdBy,
    required this.createdAt,
    required this.photoCount,
    required this.isPublished,
  });

  factory GalleryAlbum.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return GalleryAlbum(
      id:            doc.id,
      title:         (d['title']         as String?)    ?? '',
      description:   (d['description']   as String?)    ?? '',
      eventDate:     (d['eventDate']      as Timestamp?) ?.toDate() ?? DateTime.now(),
      coverPhotoUrl: (d['coverPhotoUrl']  as String?)    ?? '',
      createdBy:     (d['createdBy']      as String?)    ?? '',
      createdAt:     (d['createdAt']      as Timestamp?) ?.toDate() ?? DateTime.now(),
      photoCount:    (d['photoCount']     as int?)       ?? 0,
      isPublished:   (d['isPublished']    as bool?)      ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'title':         title,
    'description':   description,
    'eventDate':     Timestamp.fromDate(eventDate),
    'coverPhotoUrl': coverPhotoUrl,
    'createdBy':     createdBy,
    'createdAt':     FieldValue.serverTimestamp(),
    'photoCount':    photoCount,
    'isPublished':   isPublished,
  };

  GalleryAlbum copyWith({
    String?   title,
    String?   description,
    DateTime? eventDate,
    String?   coverPhotoUrl,
    int?      photoCount,
    bool?     isPublished,
  }) => GalleryAlbum(
    id:            id,
    title:         title         ?? this.title,
    description:   description   ?? this.description,
    eventDate:     eventDate     ?? this.eventDate,
    coverPhotoUrl: coverPhotoUrl ?? this.coverPhotoUrl,
    createdBy:     createdBy,
    createdAt:     createdAt,
    photoCount:    photoCount    ?? this.photoCount,
    isPublished:   isPublished   ?? this.isPublished,
  );
}

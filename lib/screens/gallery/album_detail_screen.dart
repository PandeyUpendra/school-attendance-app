import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme.dart';
import '../../models/gallery_album.dart';
import '../../models/gallery_photo.dart';
import '../../services/gallery_service.dart';
import 'create_album_screen.dart';
import 'fullscreen_photo_viewer.dart';

const _writeRoles = {'principal', 'coordinator', 'admin'};

class AlbumDetailScreen extends StatefulWidget {
  final GalleryAlbum album;
  final String       role;
  final String       userEmail;
  final bool         startEditing;

  const AlbumDetailScreen({
    super.key,
    required this.album,
    required this.role,
    required this.userEmail,
    this.startEditing = false,
  });

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  final _service    = GalleryService();
  final _picker     = ImagePicker();
  final _scrollCtrl = ScrollController();

  late GalleryAlbum          _album;
  List<GalleryPhoto>         _photos      = [];
  QueryDocumentSnapshot?     _lastDoc;
  bool                       _loading     = true;
  bool                       _loadingMore = false;
  bool                       _hasMore     = true;
  String?                    _error;

  // Upload state
  bool   _uploading      = false;
  int    _uploadDone     = 0;
  int    _uploadTotal    = 0;
  bool   _pickerActive   = false;

  bool get _canWrite => _writeRoles.contains(widget.role);

  @override
  void initState() {
    super.initState();
    _album = widget.album;
    _scrollCtrl.addListener(_onScroll);
    _loadPhotos();
    if (widget.startEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _editAlbum());
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
            _scrollCtrl.position.maxScrollExtent - 200 &&
        !_loadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _loadPhotos() async {
    setState(() { _loading = true; _error = null; _photos = []; _lastDoc = null; _hasMore = true; });
    try {
      final docs = await _service.fetchPhotosDocs(_album.id);
      if (!mounted) return;
      setState(() {
        _photos   = docs.map((d) => GalleryPhoto.fromFirestore(d)).toList();
        _lastDoc  = docs.isNotEmpty ? docs.last : null;
        _hasMore  = docs.length == 20;
        _loading  = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _lastDoc == null) return;
    setState(() => _loadingMore = true);
    try {
      final docs = await _service.fetchPhotosDocs(
        _album.id, lastDoc: _lastDoc);
      if (!mounted) return;
      setState(() {
        _photos.addAll(docs.map(GalleryPhoto.fromFirestore));
        _lastDoc     = docs.isNotEmpty ? docs.last : _lastDoc;
        _hasMore     = docs.length == 20;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _addPhotos() async {
    if (_pickerActive) return;
    _pickerActive = true;
    List<XFile> xfiles;
    try {
      xfiles = await _picker.pickMultiImage(limit: 20);
    } finally {
      _pickerActive = false;
    }
    if (xfiles.isEmpty || !mounted) return;

    final files = xfiles.map((x) => File(x.path)).toList();
    final count = files.length;
    setState(() {
      _uploading   = true;
      _uploadDone  = 0;
      _uploadTotal = count;
    });

    String? errorMsg;
    try {
      await _service.uploadPhotos(
        _album.id,
        files,
        widget.userEmail,
        onProgress: (done, total) {
          if (mounted) setState(() { _uploadDone = done; _uploadTotal = total; });
        },
      );
    } catch (e) {
      errorMsg = e.toString();
    } finally {
      if (mounted) setState(() => _uploading = false);
    }

    if (!mounted) return;
    if (errorMsg != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $errorMsg')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$count photo(s) uploaded!')),
      );
      await _loadPhotos();
    }
  }

  Future<void> _deletePhoto(GalleryPhoto photo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title:   const Text('Delete Photo'),
        content: const Text('Delete this photo? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.deletePhoto(photo.id, _album.id);
      setState(() => _photos.removeWhere((p) => p.id == photo.id));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _editAlbum() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateAlbumScreen(
          userEmail: widget.userEmail,
          editAlbum: _album,
        ),
      ),
    );
    if (result == null) {
      // Reload album data from Firestore after edit
      _loadPhotos();
    }
  }

  Future<void> _deleteAlbum() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title:   const Text('Delete Album'),
        content: Text('Delete "${_album.title}" and all its photos? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.deleteAlbum(_album.id);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _togglePublish() async {
    final wasPublished = _album.isPublished;
    String? errorMsg;
    try {
      if (wasPublished) {
        await _service.unpublishAlbum(_album.id);
        if (mounted) setState(() => _album = _album.copyWith(isPublished: false));
      } else {
        await _service.publishAlbum(_album.id, _album.title);
        if (mounted) setState(() => _album = _album.copyWith(isPublished: true));
      }
    } catch (e) {
      errorMsg = e.toString();
    }
    if (!mounted) return;
    if (errorMsg != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $errorMsg')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(wasPublished
            ? 'Album hidden — no longer visible to others'
            : 'Album is now visible to coordinators, teachers & guardians'),
      ));
    }
  }

  void _openPhoto(int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullscreenPhotoViewer(
          photos:       _photos,
          initialIndex: index,
        ),
      ),
    );
  }

  String _fmtDate(DateTime dt) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun',
                'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${dt.day} ${m[dt.month - 1]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(_album.title, overflow: TextOverflow.ellipsis),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: _canWrite
            ? [
                IconButton(
                  icon: Icon(_album.isPublished
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined),
                  tooltip: _album.isPublished ? 'Hide from others' : 'Make visible to all',
                  onPressed: _togglePublish,
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit')   _editAlbum();
                    if (v == 'delete') _deleteAlbum();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit',
                        child: ListTile(
                          leading: Icon(Icons.edit_outlined),
                          title:   Text('Edit Album'),
                          contentPadding: EdgeInsets.zero,
                        )),
                    const PopupMenuItem(value: 'delete',
                        child: ListTile(
                          leading: Icon(Icons.delete_outline, color: Colors.red),
                          title:   Text('Delete Album', style: TextStyle(color: Colors.red)),
                          contentPadding: EdgeInsets.zero,
                        )),
                  ],
                ),
              ]
            : null,
      ),
      floatingActionButton: _canWrite
          ? FloatingActionButton.extended(
              onPressed: _uploading ? null : _addPhotos,
              backgroundColor: _uploading ? Colors.grey : AppTheme.primary,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Add Photos'),
            )
          : null,
      body: Column(
        children: [
          // Upload progress bar
          if (_uploading)
            _UploadProgressBar(done: _uploadDone, total: _uploadTotal),

          // Album info banner
          _AlbumBanner(album: _album, fmtDate: _fmtDate),

          // Photos grid
          Expanded(child: _buildGrid()),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    if (_loading) {
      return GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(3),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount:  3,
          mainAxisSpacing: 3,
          crossAxisSpacing: 3,
        ),
        itemCount: 9,
        itemBuilder: (_, __) => Shimmer.fromColors(
          baseColor:      Colors.grey.shade300,
          highlightColor: Colors.grey.shade100,
          child: Container(color: Colors.white),
        ),
      );
    }

    if (_error != null) {
      return LayoutBuilder(builder: (context, constraints) {
        return RefreshIndicator(
          onRefresh: _loadPhotos,
          color: AppTheme.primary,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: constraints.maxHeight,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: Colors.grey.shade600)),
                    const SizedBox(height: 16),
                    ElevatedButton(onPressed: _loadPhotos, child: const Text('Retry')),
                  ],
                ),
              ),
            ),
          ),
        );
      });
    }

    if (_photos.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadPhotos,
        color: AppTheme.primary,
        child: ListView(children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.25),
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.photo_outlined, size: 72, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              Text('No photos yet',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
              if (_canWrite) ...[
                const SizedBox(height: 8),
                Text('Tap "Add Photos" to upload',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
              ],
            ]),
          ),
        ]),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPhotos,
      color: AppTheme.primary,
      child: GridView.builder(
        controller:  _scrollCtrl,
        physics:     const AlwaysScrollableScrollPhysics(),
        padding:     const EdgeInsets.fromLTRB(3, 3, 3, 100),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount:   3,
          mainAxisSpacing:  3,
          crossAxisSpacing: 3,
        ),
        itemCount: _photos.length + (_loadingMore ? 3 : 0),
        itemBuilder: (_, i) {
          if (i >= _photos.length) {
            return Shimmer.fromColors(
              baseColor:      Colors.grey.shade300,
              highlightColor: Colors.grey.shade100,
              child: Container(color: Colors.white),
            );
          }
          final photo = _photos[i];
          return GestureDetector(
            onTap:      () => _openPhoto(i),
            onLongPress: _canWrite ? () => _confirmDelete(photo) : null,
            child: CachedNetworkImage(
              imageUrl:    photo.compressedUrl.isNotEmpty
                  ? photo.compressedUrl
                  : photo.originalUrl,
              fit:         BoxFit.cover,
              placeholder: (_, __) => Shimmer.fromColors(
                baseColor:      Colors.grey.shade300,
                highlightColor: Colors.grey.shade100,
                child: Container(color: Colors.white),
              ),
              errorWidget: (_, __, ___) => Container(
                color: Colors.grey.shade200,
                child: Icon(Icons.broken_image_outlined,
                    color: Colors.grey.shade400),
              ),
            ),
          );
        },
      ),
    );
  }

  void _confirmDelete(GalleryPhoto photo) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title:   const Text('Delete Photo', style: TextStyle(color: Colors.red)),
              onTap:   () { Navigator.pop(context); _deletePhoto(photo); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ─── Upload progress bar ──────────────────────────────────────────────────────

class _UploadProgressBar extends StatelessWidget {
  final int done, total;
  const _UploadProgressBar({required this.done, required this.total});

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Uploading $done/$total…',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value:           total > 0 ? done / total : 0,
            minHeight:       6,
            backgroundColor: Colors.grey.shade200,
            valueColor:      const AlwaysStoppedAnimation(AppTheme.primary),
          ),
        ),
      ],
    ),
  );
}

// ─── Album info banner ────────────────────────────────────────────────────────

class _AlbumBanner extends StatelessWidget {
  final GalleryAlbum album;
  final String Function(DateTime) fmtDate;
  const _AlbumBanner({required this.album, required this.fmtDate});

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
    child: Row(children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              album.title,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 3),
            Row(children: [
              Icon(Icons.event_outlined,
                  size: 13, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text(
                fmtDate(album.eventDate),
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(width: 12),
              Icon(Icons.photo_outlined,
                  size: 13, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text(
                '${album.photoCount} photo${album.photoCount == 1 ? '' : 's'}',
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade600),
              ),
            ]),
            if (album.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                album.description,
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade700),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
      if (!album.isPublished)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color:        Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20),
            border:       Border.all(color: Colors.grey.shade400),
          ),
          child: Text(
            'Hidden',
            style: TextStyle(
                fontSize: 11,
                color:      Colors.grey.shade700,
                fontWeight: FontWeight.bold),
          ),
        ),
    ]),
  );
}

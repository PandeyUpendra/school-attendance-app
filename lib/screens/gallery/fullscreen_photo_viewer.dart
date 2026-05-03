import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import '../../models/gallery_photo.dart';
import '../../services/gallery_service.dart';

class FullscreenPhotoViewer extends StatefulWidget {
  final List<GalleryPhoto> photos;
  final int                initialIndex;

  const FullscreenPhotoViewer({
    super.key,
    required this.photos,
    required this.initialIndex,
  });

  @override
  State<FullscreenPhotoViewer> createState() => _FullscreenPhotoViewerState();
}

class _FullscreenPhotoViewerState extends State<FullscreenPhotoViewer> {
  late PageController _pageCtrl;
  late int            _currentIndex;
  final _service = GalleryService();

  bool _barsVisible = true;
  bool _actionBusy  = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageCtrl     = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  GalleryPhoto get _current => widget.photos[_currentIndex];

  void _toggleBars() => setState(() => _barsVisible = !_barsVisible);

  Future<void> _download() async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      final url = _current.watermarkedUrl.isNotEmpty
          ? _current.watermarkedUrl
          : _current.compressedUrl;
      if (url.isEmpty) {
        _showSnack('No photo URL available');
        return;
      }
      final bytes = await _service.downloadBytes(url);
      final name  = 'school_gallery_${DateTime.now().millisecondsSinceEpoch}';
      final result = await ImageGallerySaver.saveImage(bytes, name: name);
      _showSnack(result != null ? 'Saved to gallery!' : 'Could not save photo');
    } catch (e) {
      _showSnack('Download failed: $e');
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _share() async {
    if (_actionBusy) return;
    await _shareInternal(openWhatsApp: false);
  }

  Future<void> _shareWhatsApp() async {
    if (_actionBusy) return;
    await _shareInternal(openWhatsApp: true);
  }

  Future<void> _shareInternal({required bool openWhatsApp}) async {
    setState(() => _actionBusy = true);
    try {
      final url = _current.watermarkedUrl.isNotEmpty
          ? _current.watermarkedUrl
          : _current.compressedUrl;
      if (url.isEmpty) {
        _showSnack('No photo URL available');
        return;
      }
      final bytes = await _service.downloadBytes(url);
      // Write to temp file
      final tmpDir  = Directory.systemTemp;
      final tmpFile = File(
          '${tmpDir.path}/school_gallery_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tmpFile.writeAsBytes(bytes);

      const subject = 'School Gallery Photo';
      final text    = openWhatsApp
          ? 'Check out this photo from our school gallery!'
          : null;

      await Share.shareXFiles(
        [XFile(tmpFile.path)],
        subject: subject,
        text:    text,
      );

      // Clean up temp file after share dialog dismisses
      Future.delayed(const Duration(seconds: 30), () {
        if (tmpFile.existsSync()) tmpFile.deleteSync();
      });
    } catch (e) {
      _showSnack('Share failed: $e');
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Photo PageView ─────────────────────────────────────────────────
          PageView.builder(
            controller:  _pageCtrl,
            itemCount:   widget.photos.length,
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemBuilder: (_, i) {
              final photo = widget.photos[i];
              final url   = photo.originalUrl.isNotEmpty
                  ? photo.originalUrl
                  : photo.compressedUrl;
              return GestureDetector(
                onTap: _toggleBars,
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 5.0,
                  child: CachedNetworkImage(
                    imageUrl:    url,
                    fit:         BoxFit.contain,
                    placeholder: (_, __) => Shimmer.fromColors(
                      baseColor:      Colors.grey.shade800,
                      highlightColor: Colors.grey.shade600,
                      child: Container(color: Colors.grey.shade900),
                    ),
                    errorWidget: (_, __, ___) => Center(
                      child: Icon(Icons.broken_image_outlined,
                          size: 64, color: Colors.grey.shade600),
                    ),
                  ),
                ),
              );
            },
          ),

          // ── Top bar (counter + back) ───────────────────────────────────────
          AnimatedOpacity(
            opacity:  _barsVisible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(children: [
                  IconButton(
                    icon:  const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color:        Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_currentIndex + 1} of ${widget.photos.length}',
                      style: const TextStyle(
                          color:      Colors.white,
                          fontSize:   13,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                ]),
              ),
            ),
          ),

          // ── Bottom action bar ──────────────────────────────────────────────
          AnimatedOpacity(
            opacity:  _barsVisible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                top: false,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  decoration: BoxDecoration(
                    color:        Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _ActionButton(
                        icon:    Icons.download_outlined,
                        label:   'Download',
                        busy:    _actionBusy,
                        onTap:   _download,
                      ),
                      _ActionButton(
                        icon:    Icons.chat_outlined,
                        label:   'WhatsApp',
                        busy:    _actionBusy,
                        onTap:   _shareWhatsApp,
                      ),
                      _ActionButton(
                        icon:    Icons.share_outlined,
                        label:   'Share',
                        busy:    _actionBusy,
                        onTap:   _share,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Action button ────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final IconData    icon;
  final String      label;
  final bool        busy;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: busy ? null : onTap,
    child: Opacity(
      opacity: busy ? 0.5 : 1.0,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color:  Colors.white.withOpacity(0.15),
            shape:  BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
              color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
        ),
      ]),
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../../theme.dart';
import '../../models/gallery_album.dart';
import '../../services/gallery_service.dart';
import 'create_album_screen.dart';
import 'album_detail_screen.dart';

/// Role constants that have write access to the gallery.
const _writeRoles = {'principal', 'coordinator', 'admin'};

class GalleryHomeScreen extends StatefulWidget {
  final String role;
  final String userEmail;

  const GalleryHomeScreen({
    super.key,
    required this.role,
    required this.userEmail,
  });

  @override
  State<GalleryHomeScreen> createState() => _GalleryHomeScreenState();
}

class _GalleryHomeScreenState extends State<GalleryHomeScreen> {
  final _service = GalleryService();

  List<GalleryAlbum> _albums        = [];
  List<GalleryAlbum> _filtered      = [];
  bool               _loading       = true;
  String?            _error;
  String             _searchQuery   = '';
  String             _dateFilter    = 'All';   // 'All' | 'This Month' | 'This Year'
  bool               _searchVisible = false;
  final _searchCtrl  = TextEditingController();

  bool get _canWrite => _writeRoles.contains(widget.role);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final albums = await _service.fetchAlbums(adminView: _canWrite);
      if (!mounted) return;
      setState(() {
        _albums  = albums;
        _loading = false;
      });
      _applyFilters();
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _applyFilters() {
    final now = DateTime.now();
    setState(() {
      _filtered = _albums.where((a) {
        // Search filter
        if (_searchQuery.isNotEmpty &&
            !a.title.toLowerCase().contains(_searchQuery.toLowerCase())) {
          return false;
        }
        // Date filter
        if (_dateFilter == 'This Month') {
          return a.eventDate.year == now.year &&
              a.eventDate.month == now.month;
        }
        if (_dateFilter == 'This Year') {
          return a.eventDate.year == now.year;
        }
        return true;
      }).toList();
    });
  }

  void _onSearch(String v) {
    _searchQuery = v;
    _applyFilters();
  }

  void _onDateFilter(String v) {
    setState(() => _dateFilter = v);
    _applyFilters();
  }

  Future<void> _createAlbum() async {
    final result = await Navigator.push<GalleryAlbum>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateAlbumScreen(userEmail: widget.userEmail),
      ),
    );
    if (result != null && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AlbumDetailScreen(
            album:     result,
            role:      widget.role,
            userEmail: widget.userEmail,
          ),
        ),
      );
      _load();
    }
  }

  Future<void> _openAlbum(GalleryAlbum album) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AlbumDetailScreen(
          album:     album,
          role:      widget.role,
          userEmail: widget.userEmail,
        ),
      ),
    );
    _load();
  }

  Future<void> _deleteAlbum(GalleryAlbum album) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Album'),
        content: Text('Delete "${album.title}" and all its photos? This cannot be undone.'),
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
      await _service.deleteAlbum(album.id);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _editAlbum(GalleryAlbum album) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AlbumDetailScreen(
          album:     album,
          role:      widget.role,
          userEmail: widget.userEmail,
          startEditing: true,
        ),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: _searchVisible
            ? TextField(
                controller: _searchCtrl,
                autofocus:  true,
                style: const TextStyle(color: Colors.white),
                cursorColor: Colors.white70,
                decoration: const InputDecoration(
                  hintText:  'Search events…',
                  hintStyle: TextStyle(color: Colors.white54),
                  border:    InputBorder.none,
                ),
                onChanged: _onSearch,
              )
            : const Text('Event Gallery'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_searchVisible ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _searchVisible = !_searchVisible;
                if (!_searchVisible) {
                  _searchCtrl.clear();
                  _searchQuery = '';
                  _applyFilters();
                }
              });
            },
          ),
        ],
      ),
      floatingActionButton: _canWrite
          ? FloatingActionButton.extended(
              onPressed: _createAlbum,
              backgroundColor: AppTheme.primary,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('New Album'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppTheme.primary,
        child: Column(
          children: [
            _buildFilterChips(),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: ['All', 'This Month', 'This Year'].map((label) {
          final selected = _dateFilter == label;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(label),
              selected: selected,
              onSelected: (_) => _onDateFilter(label),
              selectedColor: AppTheme.primary.withOpacity(0.15),
              checkmarkColor: AppTheme.primary,
              labelStyle: TextStyle(
                color:      selected ? AppTheme.primary : Colors.grey.shade700,
                fontWeight: selected ? FontWeight.w600  : FontWeight.normal,
                fontSize:   12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: selected ? AppTheme.primary : Colors.grey.shade300,
                ),
              ),
              backgroundColor: Colors.transparent,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount:   2,
          mainAxisSpacing:  12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.82,
        ),
        itemCount: 6,
        itemBuilder: (_, __) => _ShimmerAlbumCard(),
      );
    }

    if (_error != null) {
      return LayoutBuilder(builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: constraints.maxHeight,
            child: _ErrorState(error: _error!, onRetry: _load),
          ),
        );
      });
    }

    if (_filtered.isEmpty) {
      return LayoutBuilder(builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: constraints.maxHeight,
            child: _EmptyState(
              message: _searchQuery.isNotEmpty || _dateFilter != 'All'
                  ? 'No events match your filter'
                  : 'No events yet',
            ),
          ),
        );
      });
    }

    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount:   2,
        mainAxisSpacing:  12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.82,
      ),
      itemCount: _filtered.length,
      itemBuilder: (_, i) => _AlbumCard(
        album:    _filtered[i],
        canWrite: _canWrite,
        onTap:    () => _openAlbum(_filtered[i]),
        onEdit:   () => _editAlbum(_filtered[i]),
        onDelete: () => _deleteAlbum(_filtered[i]),
      ),
    );
  }
}

// ─── Album card ───────────────────────────────────────────────────────────────

class _AlbumCard extends StatelessWidget {
  final GalleryAlbum album;
  final bool         canWrite;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AlbumCard({
    required this.album,
    required this.canWrite,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  String _fmtDate(DateTime dt) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun',
                'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${dt.day} ${m[dt.month - 1]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: canWrite
          ? () => _showOptions(context)
          : null,
      child: Container(
        decoration: BoxDecoration(
          color:        Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color:       Colors.black.withOpacity(0.08),
              blurRadius:  8,
              offset:      const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover photo
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  album.coverPhotoUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl:     album.coverPhotoUrl,
                          fit:          BoxFit.cover,
                          placeholder:  (_, __) => _shimmerBox(),
                          errorWidget:  (_, __, ___) => _placeholderBox(),
                        )
                      : _placeholderBox(),
                  // Gradient overlay
                  Positioned(
                    left: 0, right: 0, bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin:  Alignment.bottomCenter,
                          end:    Alignment.topCenter,
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                      child: Text(
                        album.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color:      Colors.white,
                          fontSize:   13,
                          fontWeight: FontWeight.bold,
                          height:     1.2,
                        ),
                      ),
                    ),
                  ),
                  // Photo count badge
                  if (album.photoCount > 0)
                    Positioned(
                      top: 6, right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color:        Colors.black54,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.photo_library_outlined,
                              color: Colors.white, size: 10),
                          const SizedBox(width: 3),
                          Text(
                            '${album.photoCount}',
                            style: const TextStyle(
                              color:      Colors.white,
                              fontSize:   10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ]),
                      ),
                    ),
                  // Draft badge
                  if (!album.isPublished)
                    Positioned(
                      top: 6, left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color:        Colors.grey.shade700,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text('Hidden',
                            style: TextStyle(
                              color:      Colors.white,
                              fontSize:   9,
                              fontWeight: FontWeight.bold,
                            )),
                      ),
                    ),
                ],
              ),
            ),
            // Date row
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Row(children: [
                Icon(Icons.event_outlined, size: 12, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _fmtDate(album.eventDate),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  void _showOptions(BuildContext context) {
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
              leading:  const Icon(Icons.edit_outlined),
              title:    const Text('Edit Album'),
              onTap: () { Navigator.pop(context); onEdit(); },
            ),
            ListTile(
              leading:  const Icon(Icons.delete_outline, color: Colors.red),
              title:    const Text('Delete Album', style: TextStyle(color: Colors.red)),
              onTap: () { Navigator.pop(context); onDelete(); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _shimmerBox() => Shimmer.fromColors(
    baseColor:      Colors.grey.shade300,
    highlightColor: Colors.grey.shade100,
    child: Container(color: Colors.white),
  );

  Widget _placeholderBox() => Container(
    color: Colors.grey.shade200,
    child: Center(
      child: Icon(Icons.photo_library_outlined,
          size: 40, color: Colors.grey.shade400),
    ),
  );
}

// ─── Shimmer card placeholder ─────────────────────────────────────────────────

class _ShimmerAlbumCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Shimmer.fromColors(
    baseColor:      Colors.grey.shade300,
    highlightColor: Colors.grey.shade100,
    child: Container(
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
    ),
  );
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.photo_album_outlined, size: 72, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        Text(
          message,
          style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 8),
        Text(
          'Pull down to refresh',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
        ),
      ],
    ),
  );
}

// ─── Error state ──────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final String       error;
  final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.wifi_off_outlined, size: 64, color: Colors.grey.shade400),
        const SizedBox(height: 16),
        const Text('Could not load gallery',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(error,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Try Again'),
        ),
      ],
    ),
  );
}

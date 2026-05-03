import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/announcement.dart';
import '../services/announcement_service.dart';
import '../services/notification_service.dart';
import '../theme.dart';

/// Announcements / Notice Board.
/// - Everyone can view (filtered by audience).
/// - Coordinator & Principal can post, pin, edit, and delete.
/// - Coordinator & Principal also see a "Principal's Log" tab with a full
///   audit trail of every announcement the Principal has sent.
class AnnouncementsScreen extends StatefulWidget {
  /// 'coordinator' | 'principal' | 'teacher' | 'guardian'
  final String viewerRole;

  /// Optional display name/email for "posted by" on new announcements.
  final String? posterName;

  const AnnouncementsScreen({
    super.key,
    required this.viewerRole,
    this.posterName,
  });

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen>
    with SingleTickerProviderStateMixin {
  final _service = AnnouncementService();

  bool _loading = true;
  List<Announcement> _items = [];

  bool _logLoading = false;
  List<Announcement> _principalLog = [];

  TabController? _tabController;

  // Audience filter for viewers — teachers/guardians only see their own + 'all'.
  String? get _filterAudience {
    if (widget.viewerRole == 'teacher')  return 'teachers';
    if (widget.viewerRole == 'guardian') return 'guardians';
    return null; // coordinator/principal → see all
  }

  bool get _canPost =>
      widget.viewerRole == 'coordinator' ||
      widget.viewerRole == 'principal';

  @override
  void initState() {
    super.initState();
    if (_canPost) {
      _tabController = TabController(length: 2, vsync: this);
    }
    _load();
    NotificationService().markAnnouncementsSeen();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await _service.getAnnouncements(audience: _filterAudience);
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
    if (_canPost) _loadPrincipalLog();
  }

  Future<void> _loadPrincipalLog() async {
    setState(() => _logLoading = true);
    final items = await _service.getAnnouncementsByRole('principal');
    if (!mounted) return;
    setState(() {
      _principalLog = items;
      _logLoading = false;
    });
  }

  Future<void> _openComposer({Announcement? editing}) async {
    final formKey   = GlobalKey<FormState>();
    final titleCtrl = TextEditingController(text: editing?.title ?? '');
    final bodyCtrl  = TextEditingController(text: editing?.body ?? '');
    String audience = editing?.audience ?? 'all';
    bool   pinned   = editing?.isPinned ?? false;
    bool   saving   = false;

    final posted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(
            left: 18, right: 18, top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 18,
          ),
          child: Form(
            key: formKey,
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(editing == null ? 'New Announcement' : 'Edit Announcement',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              TextFormField(
                controller: titleCtrl,
                maxLength: 80,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                decoration: InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  counterText: '',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Title is required' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: bodyCtrl,
                maxLines: 5,
                maxLength: 1000,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                decoration: InputDecoration(
                  labelText: 'Body',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Body is required';
                  if (v.trim().length < 10) return 'At least 10 characters';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              const Text('Audience',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final opt in const [
                    {'val': 'all',       'label': 'Everyone'},
                    {'val': 'teachers',  'label': 'Teachers'},
                    {'val': 'guardians', 'label': 'Guardians'},
                  ])
                    ChoiceChip(
                      label: Text(opt['label']!),
                      selected: audience == opt['val'],
                      onSelected: (_) =>
                          setS(() => audience = opt['val']!),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Pin this announcement',
                    style: TextStyle(fontSize: 13)),
                value: pinned,
                onChanged: (v) => setS(() => pinned = v),
              ),
              const SizedBox(height: 12),
              Row(children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          final title = titleCtrl.text.trim();
                          final body  = bodyCtrl.text.trim();
                          setS(() => saving = true);
                          final ann = Announcement(
                            id:           editing?.id ?? '',
                            title:        title,
                            body:         body,
                            postedBy:     widget.posterName ?? 'School',
                            postedByRole: widget.viewerRole,
                            audience:     audience,
                            isPinned:     pinned,
                          );
                          if (editing == null) {
                            await _service.postAnnouncement(ann);
                            await NotificationService().addAnnouncementNotice(
                              title: title,
                              body:  body,
                              audience: audience,
                            );
                          } else {
                            await _service.deleteAnnouncement(editing.id);
                            await _service.postAnnouncement(ann);
                          }
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        },
                  icon: const Icon(Icons.send_outlined, size: 18),
                  label: Text(editing == null ? 'Post' : 'Save'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ]),
            ],
            ),
          ),
        ),
      ),
    );

    if (posted == true) _load();
  }

  Future<void> _confirmDelete(Announcement a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
        title: const Text('Delete Announcement?'),
        content: Text('Permanently delete "${a.title}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _service.deleteAnnouncement(a.id);
    _load();
  }

  Future<void> _togglePin(Announcement a) async {
    await _service.setPinned(a.id, !a.isPinned);
    _load();
  }

  // ── Notice board list ──────────────────────────────────────────────────────

  Widget _buildNoticeBoard() {
    return RefreshIndicator(
      onRefresh: _load,
      color: Colors.deepOrange,
      child: _loading
          ? ListView(children: const [
              SizedBox(height: 120),
              Center(child: CircularProgressIndicator()),
            ])
          : _items.isEmpty
              ? ListView(children: [
                  const SizedBox(height: 100),
                  Icon(Icons.campaign_outlined,
                      size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      _canPost
                          ? 'No announcements yet.\nTap + to post one.'
                          : 'No announcements yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 14, color: Colors.grey.shade500),
                    ),
                  ),
                ])
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(12),
                  itemCount: _items.length,
                  itemBuilder: (_, i) => _Card(
                    announcement: _items[i],
                    canManage: _canPost,
                    onPin:    () => _togglePin(_items[i]),
                    onEdit:   () => _openComposer(editing: _items[i]),
                    onDelete: () => _confirmDelete(_items[i]),
                  ),
                ),
    );
  }

  // ── Principal's log ────────────────────────────────────────────────────────

  Widget _buildPrincipalLog() {
    return RefreshIndicator(
      onRefresh: () async => _loadPrincipalLog(),
      color: AppTheme.primary,
      child: _logLoading
          ? ListView(children: const [
              SizedBox(height: 120),
              Center(child: CircularProgressIndicator()),
            ])
          : _principalLog.isEmpty
              ? ListView(children: [
                  const SizedBox(height: 100),
                  Icon(Icons.history, size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      'No notifications sent by the Principal yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 14, color: Colors.grey.shade500),
                    ),
                  ),
                ])
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(12),
                  itemCount: _principalLog.length,
                  itemBuilder: (_, i) => _LogCard(
                    announcement: _principalLog[i],
                    canManage: _canPost,
                    onEdit:   () => _openComposer(editing: _principalLog[i]),
                    onDelete: () => _confirmDelete(_principalLog[i]),
                  ),
                ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appBar = AppBar(
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Announcements',
              style:
                  TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          Text('School notice board',
              style: TextStyle(fontSize: 12, color: Colors.white70)),
        ],
      ),
      bottom: _canPost
          ? TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              tabs: const [
                Tab(text: 'Notice Board'),
                Tab(text: "Principal's Log"),
              ],
            )
          : null,
    );

    final fab = _canPost
        ? FloatingActionButton.extended(
            onPressed: () => _openComposer(),
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add),
            label: const Text('New'),
          )
        : null;

    if (_canPost) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: appBar,
        floatingActionButton: fab,
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildNoticeBoard(),
            _buildPrincipalLog(),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: appBar,
      body: _buildNoticeBoard(),
    );
  }
}

// ─── Notice Board card ────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Announcement announcement;
  final bool         canManage;
  final VoidCallback onPin, onEdit, onDelete;

  const _Card({
    required this.announcement,
    required this.canManage,
    required this.onPin,
    required this.onEdit,
    required this.onDelete,
  });

  String _fmtDate(DateTime? d) {
    if (d == null) return '';
    final now  = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours   < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays    < 1) return '${diff.inHours}h ago';
    if (diff.inDays    < 7) return '${diff.inDays}d ago';
    return '${d.day}/${d.month}/${d.year}';
  }

  Color _audienceColor(String a) {
    switch (a) {
      case 'teachers':  return Colors.red;
      case 'guardians': return Colors.purple;
      default:          return AppTheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final a        = announcement;
    final audColor = _audienceColor(a.audience);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: a.isPinned ? Colors.deepOrange.shade200 : Colors.grey.shade200,
          width: a.isPinned ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            if (a.isPinned) ...[
              const Icon(Icons.push_pin, color: Colors.deepOrange, size: 16),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(a.title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold)),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: audColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                a.audience == 'all'
                    ? 'Everyone'
                    : '${a.audience[0].toUpperCase()}${a.audience.substring(1)}',
                style: TextStyle(
                    fontSize: 10,
                    color: audColor,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(a.body,
              style: TextStyle(
                  fontSize: 13, height: 1.4, color: Colors.grey.shade800)),
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.person_outline,
                size: 14, color: Colors.grey.shade500),
            const SizedBox(width: 4),
            Flexible(
              child: Text(a.postedBy,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade600)),
            ),
            const SizedBox(width: 10),
            Icon(Icons.access_time,
                size: 13, color: Colors.grey.shade400),
            const SizedBox(width: 3),
            Text(_fmtDate(a.postedAt),
                style: TextStyle(
                    fontSize: 11, color: Colors.grey.shade500)),
            const Spacer(),
            if (canManage) ...[
              IconButton(
                icon: Icon(
                    a.isPinned
                        ? Icons.push_pin
                        : Icons.push_pin_outlined,
                    size: 18,
                    color: a.isPinned ? Colors.deepOrange : Colors.grey),
                onPressed: onPin,
                tooltip: a.isPinned ? 'Unpin' : 'Pin',
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined,
                    size: 18, color: Colors.grey),
                onPressed: onEdit,
                tooltip: 'Edit',
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: Colors.redAccent),
                onPressed: onDelete,
                tooltip: 'Delete',
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ]),
        ],
      ),
    );
  }
}

// ─── Principal's Log card ─────────────────────────────────────────────────────

class _LogCard extends StatelessWidget {
  final Announcement announcement;
  final bool         canManage;
  final VoidCallback onEdit, onDelete;

  const _LogCard({
    required this.announcement,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
  });

  String _fullDate(DateTime? d) {
    if (d == null) return '—';
    final hour   = d.hour.toString().padLeft(2, '0');
    final minute = d.minute.toString().padLeft(2, '0');
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month]} ${d.year}  $hour:$minute';
  }

  Color _audienceColor(String a) {
    switch (a) {
      case 'teachers':  return Colors.red;
      case 'guardians': return Colors.purple;
      default:          return AppTheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final a        = announcement;
    final audColor = _audienceColor(a.audience);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row — timestamp + audience badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.06),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(children: [
              Icon(Icons.history, size: 14, color: AppTheme.primary),
              const SizedBox(width: 6),
              Text(_fullDate(a.postedAt),
                  style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: audColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  a.audience == 'all'
                      ? 'Everyone'
                      : '${a.audience[0].toUpperCase()}${a.audience.substring(1)}',
                  style: TextStyle(
                      fontSize: 10,
                      color: audColor,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  if (a.isPinned) ...[
                    const Icon(Icons.push_pin,
                        color: Colors.deepOrange, size: 14),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(a.title,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(a.body,
                    style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: Colors.grey.shade700)),
              ],
            ),
          ),
          // Footer — poster name + actions
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 6, 6),
            child: Row(children: [
              Icon(Icons.person_outline,
                  size: 13, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Flexible(
                child: Text(a.postedBy,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade600)),
              ),
              const Spacer(),
              if (canManage) ...[
                IconButton(
                  icon: const Icon(Icons.edit_outlined,
                      size: 17, color: Colors.grey),
                  onPressed: onEdit,
                  tooltip: 'Edit',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 17, color: Colors.redAccent),
                  onPressed: onDelete,
                  tooltip: 'Delete',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ]),
          ),
        ],
      ),
    );
  }
}

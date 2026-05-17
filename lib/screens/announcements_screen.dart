import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/announcement.dart';
import '../services/announcement_service.dart';
import '../services/notification_service.dart';
import '../theme.dart';

/// Announcements / Notice Board.
/// - Everyone except guardians can post.
/// - All non-guardian roles see a "My Log" tab with their own past announcements.
/// - My Log supports edit, delete, and multi-select delete.
/// - Each notice shows the role of the sender (Principal, Coordinator, etc.).
class AnnouncementsScreen extends StatefulWidget {
  /// 'coordinator' | 'principal' | 'teacher' | 'class_teacher' | 'guardian'
  final String viewerRole;

  /// Email / display name used as postedBy and for My Log filtering.
  final String? posterName;

  /// The class name (e.g. "10th-A") if the viewer is a teacher or guardian.
  final String? viewerClass;

  const AnnouncementsScreen({
    super.key,
    required this.viewerRole,
    this.posterName,
    this.viewerClass,
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
  List<Announcement> _myLog = [];

  // Multi-select state for My Log
  bool _logSelectMode = false;
  final Set<String> _selectedLogIds = {};

  TabController? _tabController;

  String? get _filterAudience {
    if (widget.viewerRole == 'teacher' || widget.viewerRole == 'class_teacher') {
      return 'teachers';
    }
    if (widget.viewerRole == 'guardian') return 'guardians';
    return null;
  }

  bool get _canPost => widget.viewerRole != 'guardian';

  bool _canManageItem(Announcement a) {
    if (widget.viewerRole == 'principal' || widget.viewerRole == 'coordinator' ||
        widget.viewerRole == 'owner') {
      return true;
    }
    return a.postedBy == (widget.posterName ?? '__none__');
  }

  @override
  void initState() {
    super.initState();
    if (_canPost) {
      _tabController = TabController(length: 2, vsync: this);
    }
    _load();
    // markAnnouncementsSeen removed — method no longer in NotificationService
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await _service.getAnnouncements(
      audience: _filterAudience,
      viewerClass: widget.viewerClass,
    );
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
    if (_canPost) _loadMyLog();
  }

  Future<void> _loadMyLog() async {
    setState(() => _logLoading = true);
    final items = (widget.posterName?.isNotEmpty == true)
        ? await _service.getAnnouncementsByPoster(widget.posterName!)
        : await _service.getAnnouncementsByRole(widget.viewerRole);
    if (!mounted) return;
    setState(() {
      _myLog = items;
      _logLoading = false;
    });
  }

  // ── Announcement title → body template map ───────────────────────────────────

  static const Map<String, String> _titleTemplates = {
    'Parent-Teacher Meeting':
        'Dear Parents,\n\nYou are cordially invited to attend the Parent-Teacher Meeting scheduled on [Date] at [Time].\n\nPlease make it a point to attend and discuss your child\'s academic progress with the respective teachers.\n\nFor any queries, contact the school office.\n\nRegards,\nSchool Management',

    'Holiday Notice':
        'Dear Students and Parents,\n\nThis is to inform you that the school will remain closed on [Date] on account of [Holiday Name].\n\nClasses will resume as usual from [Resumption Date].\n\nThank you.',

    'Exam Schedule':
        'Dear Students and Parents,\n\nThe [Term] examinations are scheduled from [Start Date] to [End Date].\n\nThe detailed timetable is available on the school notice board. Students are advised to prepare well and maintain regular attendance.\n\nBest wishes,\nExam Committee',

    'Fee Reminder':
        'Dear Parents,\n\nThis is a gentle reminder that school fees for [Term / Month] are due by [Due Date].\n\nKindly clear all pending dues at the earliest to avoid late charges. Payments can be made at the school office during working hours (9 AM – 2 PM).\n\nRegards,\nAccounts Department',

    'Sports Day':
        'Dear All,\n\nWe are pleased to announce our Annual Sports Day on [Date] at [Time] on the school grounds.\n\nAll students are encouraged to participate enthusiastically. Parents are cordially invited to witness and cheer for their children.\n\nThe event will include athletic competitions and a prize distribution ceremony.\n\nSee you there!',

    'Annual Function':
        'Dear All,\n\nWe are delighted to invite you to our Annual Prize Distribution and Cultural Function on [Date] at [Time] at [Venue].\n\nThe programme will feature performances by students, prize distribution, and a special address.\n\nPlease be seated by [Reporting Time].\n\nWarm regards,\nSchool Management',

    'School Reopening':
        'Dear Students and Parents,\n\nThe school will reopen on [Date] after the [Vacation Name] vacation.\n\nAll students are expected to report in proper school uniform. Pending assignments and projects must be completed before reporting.\n\nWe look forward to seeing you!\n\nRegards,\nSchool Management',

    'School Trip / Excursion':
        'Dear Parents,\n\nThe school has organised an educational excursion to [Place] on [Date].\n\nStudents of [Classes] are invited to participate. Reporting time: [Time] at the school gate. Return by [Return Time].\n\nKindly submit the signed consent slip with the excursion fee of ₹[Amount] by [Last Date].\n\nRegards,\nSchool Management',

    'Result Declaration':
        'Dear Students and Parents,\n\nThe results of [Exam Name] will be declared on [Date] at [Time].\n\nParents are requested to collect the report cards in person from the class teacher between [Time Slot]. A valid ID proof is required.\n\nRegards,\nAcademic Department',

    'Staff Meeting':
        'Dear Staff Members,\n\nA staff meeting has been scheduled on [Date] at [Time] in [Venue].\n\nAttendance of all teaching and non-teaching staff is mandatory. Please be punctual.\n\nAgenda: [Topics to be discussed]\n\nRegards,\nSchool Administration',

    'Vaccination / Health Drive':
        'Dear Parents,\n\nA health and vaccination drive is being organised at the school on [Date] in collaboration with [Health Authority].\n\nVaccinations / Services available: [Details]\n\nKindly provide written consent for your ward by submitting the form available at the school office by [Date].\n\nRegards,\nSchool Health Committee',

    'General Notice':
        'Dear All,\n\n[Write your announcement here. Replace this text with the actual notice content.]\n\nFor any queries or further information, please contact the school office.\n\nRegards,\nSchool Management',
  };

  Future<void> _openComposer({Announcement? editing}) async {
    final formKey = GlobalKey<FormState>();

    final presetTitles = _titleTemplates.keys.toList();
    const customKey = 'Custom...';

    // Determine initial selected title
    String? selectedTitle;
    if (editing != null) {
      selectedTitle = presetTitles.contains(editing.title)
          ? editing.title
          : customKey;
    }

    final customTitleCtrl = TextEditingController(
      text: (editing != null && selectedTitle == customKey) ? editing.title : '',
    );
    final bodyCtrl = TextEditingController(text: editing?.body ?? '');

    // Default audience based on role
    String audience = editing?.audience ??
        ((widget.viewerRole == 'teacher' ||
                    widget.viewerRole == 'class_teacher') &&
                widget.viewerClass != null
            ? 'class:${widget.viewerClass}'
            : 'all');
    bool pinned = editing?.isPinned ?? false;
    bool saving = false;

    final posted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final allOptions = [...presetTitles, customKey];

          return SingleChildScrollView(
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
                  Text(
                    editing == null ? 'New Announcement' : 'Edit Announcement',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 14),

                  // ── Title dropdown ──────────────────────────────────────
                  DropdownButtonFormField<String>(
                    value: selectedTitle,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Select Title',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                    ),
                    hint: const Text('Choose an announcement type'),
                    items: allOptions.map((t) {
                      final isCustom = t == customKey;
                      return DropdownMenuItem<String>(
                        value: t,
                        child: Text(
                          t,
                          style: TextStyle(
                            fontSize: 14,
                            color: isCustom
                                ? Colors.grey.shade600
                                : Colors.black87,
                            fontStyle: isCustom
                                ? FontStyle.italic
                                : FontStyle.normal,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val == null) return;
                      setS(() {
                        selectedTitle = val;
                        if (val != customKey) {
                          // Auto-fill body with template
                          bodyCtrl.text = _titleTemplates[val] ?? '';
                        } else {
                          // Custom: clear body only if it was a template
                          if (_titleTemplates.containsValue(bodyCtrl.text)) {
                            bodyCtrl.text = '';
                          }
                        }
                      });
                    },
                    validator: (_) => selectedTitle == null
                        ? 'Please select a title'
                        : null,
                  ),

                  // ── Custom title field (shown only when "Custom..." picked) ──
                  if (selectedTitle == customKey) ...[
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: customTitleCtrl,
                      maxLength: 80,
                      maxLengthEnforcement: MaxLengthEnforcement.enforced,
                      decoration: InputDecoration(
                        labelText: 'Custom Title',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        counterText: '',
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty)
                              ? 'Title is required'
                              : null,
                    ),
                  ],

                  const SizedBox(height: 10),

                  // ── Body ───────────────────────────────────────────────
                  TextFormField(
                    controller: bodyCtrl,
                    maxLines: 7,
                    maxLength: 1000,
                    maxLengthEnforcement: MaxLengthEnforcement.enforced,
                    decoration: InputDecoration(
                      labelText: 'Body',
                      alignLabelWithHint: true,
                      helperText: selectedTitle != null && selectedTitle != customKey
                          ? 'Template pre-filled — edit as needed'
                          : null,
                      helperStyle: TextStyle(
                          fontSize: 11, color: Colors.grey.shade500),
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
                      if (widget.viewerRole == 'principal' ||
                          widget.viewerRole == 'coordinator') ...[
                        for (final opt in const [
                          {'val': 'all', 'label': 'Everyone'},
                          {'val': 'teachers', 'label': 'Teachers'},
                          {'val': 'guardians', 'label': 'Guardians'},
                        ])
                          ChoiceChip(
                            label: Text(opt['label']!),
                            selected: audience == opt['val'],
                            onSelected: (_) =>
                                setS(() => audience = opt['val']!),
                          ),
                      ],
                      if ((widget.viewerRole == 'teacher' ||
                              widget.viewerRole == 'class_teacher') &&
                          widget.viewerClass != null)
                        ChoiceChip(
                          label: Text('My Class (${widget.viewerClass})'),
                          selected: audience == 'class:${widget.viewerClass}',
                          onSelected: (_) => setS(
                              () => audience = 'class:${widget.viewerClass}'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (widget.viewerRole == 'principal' ||
                      widget.viewerRole == 'coordinator')
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
                              final title = selectedTitle == customKey
                                  ? customTitleCtrl.text.trim()
                                  : selectedTitle!;
                              final body = bodyCtrl.text.trim();
                              setS(() => saving = true);
                              final ann = Announcement(
                                id: editing?.id ?? '',
                                title: title,
                                body: body,
                                postedBy: widget.posterName ?? 'School',
                                postedByRole: widget.viewerRole,
                                audience: audience,
                                isPinned: pinned,
                              );
                              if (editing == null) {
                                await _service.postAnnouncement(ann);
                                await NotificationService()
                                    .addAnnouncementNotice(
                                  title: title,
                                  body: body,
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
          );
        },
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

  Future<void> _deleteSelected() async {
    if (_selectedLogIds.isEmpty) return;
    final count = _selectedLogIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
        title: const Text('Delete Selected?'),
        content: Text(
            'Permanently delete $count announcement${count > 1 ? 's' : ''}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _service.deleteAnnouncements(_selectedLogIds.toList());
    if (!mounted) return;
    setState(() {
      _logSelectMode = false;
      _selectedLogIds.clear();
    });
    _load();
  }

  Future<void> _togglePin(Announcement a) async {
    await _service.setPinned(a.id, !a.isPinned);
    _load();
  }

  // ── Notice board ──────────────────────────────────────────────────────────────

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
                    canManage: _canManageItem(_items[i]),
                    canPin: widget.viewerRole == 'principal' ||
                        widget.viewerRole == 'coordinator' ||
                        widget.viewerRole == 'owner',
                    onPin:    () => _togglePin(_items[i]),
                    onEdit:   () => _openComposer(editing: _items[i]),
                    onDelete: () => _confirmDelete(_items[i]),
                  ),
                ),
    );
  }

  // ── My Log ────────────────────────────────────────────────────────────────────

  Widget _buildMyLog() {
    if (_logLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        if (_logSelectMode)
          Container(
            color: AppTheme.primary.withOpacity(0.07),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              Text(
                '${_selectedLogIds.length} selected',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                    fontSize: 13),
              ),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Delete'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: _selectedLogIds.isEmpty ? null : _deleteSelected,
              ),
              TextButton(
                onPressed: () => setState(() {
                  _logSelectMode = false;
                  _selectedLogIds.clear();
                }),
                child: const Text('Cancel'),
              ),
            ]),
          ),
        Expanded(
          child: _myLog.isEmpty
              ? ListView(children: [
                  const SizedBox(height: 100),
                  Icon(Icons.history, size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      "You haven't sent any announcements yet.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 14, color: Colors.grey.shade500),
                    ),
                  ),
                ])
              : RefreshIndicator(
                  onRefresh: () async => _loadMyLog(),
                  color: AppTheme.primary,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(12),
                    itemCount: _myLog.length,
                    itemBuilder: (_, i) {
                      final a          = _myLog[i];
                      final isSelected = _selectedLogIds.contains(a.id);
                      return GestureDetector(
                        onLongPress: () {
                          if (!_logSelectMode) {
                            setState(() {
                              _logSelectMode = true;
                              _selectedLogIds.add(a.id);
                            });
                          }
                        },
                        onTap: _logSelectMode
                            ? () => setState(() {
                                  if (isSelected) {
                                    _selectedLogIds.remove(a.id);
                                    if (_selectedLogIds.isEmpty) {
                                      _logSelectMode = false;
                                    }
                                  } else {
                                    _selectedLogIds.add(a.id);
                                  }
                                })
                            : null,
                        child: _LogCard(
                          announcement: a,
                          isSelected:    isSelected,
                          selectionMode: _logSelectMode,
                          onEdit:   _logSelectMode
                              ? null
                              : () => _openComposer(editing: a),
                          onDelete: _logSelectMode
                              ? null
                              : () => _confirmDelete(a),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
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
                Tab(text: 'My Log'),
              ],
            )
          : null,
    );

    final fab = _canPost
        ? FloatingActionButton.extended(
            onPressed: _logSelectMode ? null : () => _openComposer(),
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
          controller: _tabController!,
          children: [
            _buildNoticeBoard(),
            _buildMyLog(),
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

// ── Helpers ───────────────────────────────────────────────────────────────────

(Color, String) _roleInfo(String role) {
  switch (role) {
    case 'principal':     return (AppTheme.primary, 'Principal');
    case 'coordinator':   return (Colors.blue.shade700, 'Coordinator');
    case 'class_teacher': return (Colors.green.shade700, 'Class Teacher');
    case 'teacher':       return (Colors.teal.shade700, 'Teacher');
    default:              return (Colors.grey.shade600, role);
  }
}

String _fmtDateRelative(DateTime? d) {
  if (d == null) return '';
  final now  = DateTime.now();
  final diff = now.difference(d);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours   < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays    < 1) return '${diff.inHours}h ago';
  if (diff.inDays    < 7) return '${diff.inDays}d ago';
  return '${d.day}/${d.month}/${d.year}';
}

String _fmtDateFull(DateTime? d) {
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
    case 'guardians': return AppTheme.primaryMid;
    default:          return AppTheme.primary;
  }
}

String _audienceLabel(String a) {
  if (a == 'all') return 'Everyone';
  if (a.startsWith('class:')) return 'Class ${a.substring(6)}';
  return '${a[0].toUpperCase()}${a.substring(1)}';
}

// ─── Notice Board card ────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Announcement announcement;
  final bool         canManage;
  final bool         canPin;
  final VoidCallback onPin, onEdit, onDelete;

  const _Card({
    required this.announcement,
    required this.canManage,
    required this.canPin,
    required this.onPin,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final a        = announcement;
    final audColor = _audienceColor(a.audience);
    final (roleColor, roleLabel) = _roleInfo(a.postedByRole);

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
                _audienceLabel(a.audience),
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
            // Role badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: roleColor.withOpacity(0.10),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(roleLabel,
                  style: TextStyle(
                      fontSize: 10,
                      color: roleColor,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 6),
            Icon(Icons.person_outline,
                size: 13, color: Colors.grey.shade500),
            const SizedBox(width: 3),
            Flexible(
              child: Text(a.postedBy,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade600)),
            ),
            const SizedBox(width: 8),
            Icon(Icons.access_time,
                size: 13, color: Colors.grey.shade400),
            const SizedBox(width: 3),
            Text(_fmtDateRelative(a.postedAt),
                style: TextStyle(
                    fontSize: 11, color: Colors.grey.shade500)),
            const Spacer(),
            if (canManage) ...[
              if (canPin)
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

// ─── My Log card ──────────────────────────────────────────────────────────────

class _LogCard extends StatelessWidget {
  final Announcement  announcement;
  final bool          isSelected;
  final bool          selectionMode;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _LogCard({
    required this.announcement,
    required this.isSelected,
    required this.selectionMode,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final a        = announcement;
    final audColor = _audienceColor(a.audience);
    final (roleColor, roleLabel) = _roleInfo(a.postedByRole);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isSelected
            ? AppTheme.primary.withOpacity(0.06)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? AppTheme.primary.withOpacity(0.5)
              : Colors.grey.shade200,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row — timestamp + audience badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.primary.withOpacity(0.08)
                  : AppTheme.primary.withOpacity(0.05),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(children: [
              if (selectionMode) ...[
                Icon(
                  isSelected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: isSelected ? AppTheme.primary : Colors.grey.shade400,
                ),
                const SizedBox(width: 8),
              ] else ...[
                Icon(Icons.history, size: 14, color: AppTheme.primary),
                const SizedBox(width: 6),
              ],
              Text(_fmtDateFull(a.postedAt),
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
                  _audienceLabel(a.audience),
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
          // Footer — role badge + poster name + actions
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 6, 8),
            child: Row(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: roleColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(roleLabel,
                    style: TextStyle(
                        fontSize: 10,
                        color: roleColor,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 6),
              Icon(Icons.person_outline,
                  size: 13, color: Colors.grey.shade500),
              const SizedBox(width: 3),
              Flexible(
                child: Text(a.postedBy,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade600)),
              ),
              const Spacer(),
              if (!selectionMode && onEdit != null) ...[
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

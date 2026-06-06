import 'package:flutter/material.dart';

import '../models/announcement.dart';
import '../services/announcement_service.dart';
import '../theme.dart';
import '../utils/announcement_templates.dart';

/// New-announcement form shared by the owner / owner-principal home screens.
///
/// The title is a single dropdown that lists the built-in preset titles plus
/// any custom titles staff have saved, ending with a "Write a custom title…"
/// option. Picking a known title also fills the message with its default
/// (editable) text; choosing custom reveals a free-text title field with a
/// "save this title for later" checkbox so it joins the dropdown next time.
class AnnouncementComposer extends StatefulWidget {
  final String email;
  final String role;

  /// Called after an announcement is posted, so the host can refresh its
  /// "recent announcements" list.
  final VoidCallback? onSent;

  const AnnouncementComposer({
    super.key,
    required this.email,
    required this.role,
    this.onSent,
  });

  @override
  State<AnnouncementComposer> createState() => _AnnouncementComposerState();
}

class _AnnouncementComposerState extends State<AnnouncementComposer> {
  /// Sentinel dropdown value for the "write a custom title" option.
  static const _kCustom = '__custom_title__';

  final _titleCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  String _target = 'All Staff';
  bool _sending = false;

  /// Currently selected dropdown value: a known title, [_kCustom], or null.
  String? _selection;

  /// Whether the custom-title text field is showing.
  bool get _isCustom => _selection == _kCustom;

  /// Whether to persist the typed custom title for reuse.
  bool _saveForLater = false;

  /// Saved custom titles → default message, loaded from Firestore.
  Map<String, String> _customTemplates = {};

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    try {
      final custom = await AnnouncementService().getCustomTemplates();
      if (mounted) setState(() => _customTemplates = custom);
    } catch (_) {/* presets still work without custom titles */}
  }

  /// Preset titles first, then saved custom titles not already in the presets.
  List<String> get _knownTitles {
    final titles = <String>[...kAnnouncementTemplates.keys];
    for (final t in _customTemplates.keys) {
      if (!titles.contains(t)) titles.add(t);
    }
    return titles;
  }

  void _onTitleSelected(String? value) {
    setState(() {
      _selection = value;
      if (value == null) return;
      if (value == _kCustom) {
        _saveForLater = false;
        _titleCtrl.clear();
        return;
      }
      // Known title — fill title + default message (both stay editable).
      _titleCtrl.text = value;
      final msg = kAnnouncementTemplates[value] ?? _customTemplates[value] ?? '';
      if (msg.isNotEmpty) _msgCtrl.text = msg;
    });
  }

  Future<void> _send() async {
    final title = _titleCtrl.text.trim();
    final body = _msgCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) {
      _snack('Enter title and message');
      return;
    }
    setState(() => _sending = true);
    try {
      await AnnouncementService().postAnnouncement(Announcement(
        id: '',
        title: title,
        body: body,
        postedBy: widget.email,
        postedByRole: widget.role,
        audience: _target,
        isPinned: false,
      ));
      // Persist the custom title (with its message) for reuse if requested.
      if (_isCustom && _saveForLater) {
        await AnnouncementService().saveCustomTemplate(title, body);
        await _loadTemplates();
      }
      _titleCtrl.clear();
      _msgCtrl.clear();
      if (mounted) {
        setState(() {
          _selection = null;
          _saveForLater = false;
        });
        _snack('Announcement sent', success: true);
        widget.onSent?.call();
      }
    } catch (e) {
      _snack('Error: $e');
    }
    if (mounted) setState(() => _sending = false);
  }

  void _snack(String msg, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? AppTheme.success : null,
    ));
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        isDense: true,
      );

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Announcement title: presets + saved + custom ───────────────────
      DropdownButtonFormField<String>(
        value: _selection,
        isExpanded: true,
        decoration: _dec('Announcement Title', Icons.title_outlined),
        hint: const Text('Choose or write a title'),
        items: [
          ..._knownTitles.map(
              (t) => DropdownMenuItem(value: t, child: Text(t))),
          const DropdownMenuItem(
            value: _kCustom,
            child: Row(children: [
              Icon(Icons.edit_outlined, size: 18, color: AppTheme.accent),
              SizedBox(width: 8),
              Text('Write a custom title…'),
            ]),
          ),
        ],
        onChanged: _onTitleSelected,
      ),

      // ── Custom-title field + save-for-later ─────────────────────────────
      if (_isCustom) ...[
        const SizedBox(height: 10),
        TextField(
          controller: _titleCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: _dec('Custom title', Icons.drive_file_rename_outline),
        ),
        CheckboxListTile(
          value: _saveForLater,
          onChanged: (v) => setState(() => _saveForLater = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
          activeColor: AppTheme.accent,
          title: const Text('Save this title for later use',
              style: TextStyle(fontSize: 13)),
        ),
      ],

      const SizedBox(height: 10),
      TextField(
        controller: _msgCtrl,
        maxLines: 3,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: 'Message',
          prefixIcon: const Padding(
            padding: EdgeInsets.only(bottom: 48),
            child: Icon(Icons.message_outlined),
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          isDense: true,
        ),
      ),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        value: _target,
        decoration: const InputDecoration(
          labelText: 'Target Audience',
          prefixIcon: Icon(Icons.group_outlined),
          isDense: true,
        ),
        items: ['All Staff', 'All Guardians', 'Everyone']
            .map((t) => DropdownMenuItem(value: t, child: Text(t)))
            .toList(),
        onChanged: (v) {
          if (v != null) setState(() => _target = v);
        },
      ),
      const SizedBox(height: 14),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          icon: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.send_outlined),
          label: Text(_sending ? 'Sending…' : 'Send Announcement'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.accent,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _sending ? null : _send,
        ),
      ),
    ]);
  }
}

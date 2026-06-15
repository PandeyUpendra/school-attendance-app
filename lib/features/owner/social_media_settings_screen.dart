import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../shared/providers/school_settings_provider.dart';
import '../../services/auth_service.dart';
import '../../l10n/app_strings.dart';
import '../../theme.dart';

class SocialMediaSettingsScreen extends StatefulWidget {
  const SocialMediaSettingsScreen({super.key});

  @override
  State<SocialMediaSettingsScreen> createState() => _SocialMediaSettingsScreenState();
}

class _SocialMediaSettingsScreenState extends State<SocialMediaSettingsScreen> {
  bool _editing = false;
  bool _saving = false;
  bool _init = false;

  late TextEditingController _facebookCtrl;
  late TextEditingController _instagramCtrl;
  late TextEditingController _twitterCtrl;
  late TextEditingController _youtubeCtrl;
  late TextEditingController _linkedinCtrl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_init) {
      final p = context.read<SchoolSettingsProvider>();
      _facebookCtrl = TextEditingController(text: p.facebookUrl);
      _instagramCtrl = TextEditingController(text: p.instagramUrl);
      _twitterCtrl = TextEditingController(text: p.twitterUrl);
      _youtubeCtrl = TextEditingController(text: p.youtubeUrl);
      _linkedinCtrl = TextEditingController(text: p.linkedinUrl);
      _init = true;
    }
  }

  @override
  void dispose() {
    _facebookCtrl.dispose();
    _instagramCtrl.dispose();
    _twitterCtrl.dispose();
    _youtubeCtrl.dispose();
    _linkedinCtrl.dispose();
    super.dispose();
  }

  bool _isValidUrl(String value) {
    if (value.isEmpty) return true;
    final uri = Uri.tryParse(value);
    return uri != null && (uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https'));
  }

  Future<void> _save() async {
    // Validate URLs
    if (!_isValidUrl(_facebookCtrl.text.trim()) ||
        !_isValidUrl(_instagramCtrl.text.trim()) ||
        !_isValidUrl(_twitterCtrl.text.trim()) ||
        !_isValidUrl(_youtubeCtrl.text.trim()) ||
        !_isValidUrl(_linkedinCtrl.text.trim())) {
      _snack('Please enter valid URLs starting with http:// or https://');
      return;
    }

    setState(() => _saving = true);
    try {
      final p = context.read<SchoolSettingsProvider>();
      final old = p.rawSchool;
      final data = {
        'facebookUrl': _facebookCtrl.text.trim(),
        'instagramUrl': _instagramCtrl.text.trim(),
        'twitterUrl': _twitterCtrl.text.trim(),
        'youtubeUrl': _youtubeCtrl.text.trim(),
        'linkedinUrl': _linkedinCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await p.updateSchoolSettings(data);
      final uid = (await AuthService().getSession())?['email'] as String? ?? 'owner';
      for (final k in data.keys) {
        if (k == 'updatedAt') continue;
        final oldVal = old[k]?.toString() ?? '';
        final newVal = data[k]?.toString() ?? '';
        if (oldVal != newVal) await p.logChange(k, oldVal, newVal, uid);
      }
      if (mounted) {
        _snack(context.tr('settingsUpdated'), success: true);
        setState(() => _editing = false);
      }
    } catch (e) {
      if (mounted) _snack('Error: $e');
    }
    if (mounted) setState(() => _saving = false);
  }

  void _snack(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? AppTheme.success : AppTheme.danger,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(context.tr('socialMediaLinksTitle')),
        actions: [
          if (!_editing)
            TextButton.icon(
              icon: const Icon(Icons.edit_outlined, color: Colors.white, size: 18),
              label: Text(
                context.tr('edit'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
              onPressed: () => setState(() => _editing = true),
            )
          else
            TextButton.icon(
              icon: const Icon(Icons.close, color: Colors.white, size: 18),
              label: Text(context.tr('cancel'), style: const TextStyle(color: Colors.white)),
              onPressed: () {
                // Reset fields and cancel edit mode
                final p = context.read<SchoolSettingsProvider>();
                _facebookCtrl.text = p.facebookUrl;
                _instagramCtrl.text = p.instagramUrl;
                _twitterCtrl.text = p.twitterUrl;
                _youtubeCtrl.text = p.youtubeUrl;
                _linkedinCtrl.text = p.linkedinUrl;
                setState(() => _editing = false);
              },
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          if (!_editing)
            Container(
              color: AppTheme.warning.withValues(alpha: 0.12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                const Icon(Icons.lock_outline, size: 16, color: AppTheme.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr('viewOnlyWarning'),
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.warning,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ]),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    elevation: 0,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: AppTheme.border),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: AppTheme.primary, size: 24),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              context.tr('socialMediaSubtitle'),
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppTheme.textPrimary,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _socialField(
                    controller: _facebookCtrl,
                    label: context.tr('facebookLabel'),
                    icon: FontAwesomeIcons.facebook,
                    iconColor: const Color(0xFF1877F2),
                    readOnly: !_editing,
                  ),
                  const SizedBox(height: 16),
                  _socialField(
                    controller: _instagramCtrl,
                    label: context.tr('instagramLabel'),
                    icon: FontAwesomeIcons.instagram,
                    iconColor: const Color(0xFFE4405F),
                    readOnly: !_editing,
                  ),
                  const SizedBox(height: 16),
                  _socialField(
                    controller: _twitterCtrl,
                    label: context.tr('twitterLabel'),
                    icon: FontAwesomeIcons.twitter,
                    iconColor: const Color(0xFF1DA1F2),
                    readOnly: !_editing,
                  ),
                  const SizedBox(height: 16),
                  _socialField(
                    controller: _youtubeCtrl,
                    label: context.tr('youtubeLabel'),
                    icon: FontAwesomeIcons.youtube,
                    iconColor: const Color(0xFFFF0000),
                    readOnly: !_editing,
                  ),
                  const SizedBox(height: 16),
                  _socialField(
                    controller: _linkedinCtrl,
                    label: context.tr('linkedinLabel'),
                    icon: FontAwesomeIcons.linkedin,
                    iconColor: const Color(0xFF0A66C2),
                    readOnly: !_editing,
                  ),
                  const SizedBox(height: 32),
                  if (_editing)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.save_outlined),
                        label: Text(_saving ? context.tr('savingLabel') : context.tr('saveSettingsLabel')),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _saving ? null : _save,
                      ),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _socialField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required Color iconColor,
    required bool readOnly,
  }) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: TextInputType.url,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 12, right: 10, top: 10, bottom: 10),
          child: FaIcon(icon, color: iconColor, size: 20),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        isDense: true,
      ),
    );
  }
}

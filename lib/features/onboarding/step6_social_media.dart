import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../l10n/app_strings.dart';
import '../../models/school_onboarding.dart';
import '../../theme.dart';

class Step6SocialMedia extends StatefulWidget {
  final SchoolOnboarding initial;
  final void Function(SchoolOnboarding) onChanged;

  const Step6SocialMedia({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  @override
  State<Step6SocialMedia> createState() => Step6SocialMediaState();
}

class Step6SocialMediaState extends State<Step6SocialMedia> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _facebookCtrl;
  late final TextEditingController _instagramCtrl;
  late final TextEditingController _twitterCtrl;
  late final TextEditingController _youtubeCtrl;
  late final TextEditingController _linkedinCtrl;

  @override
  void initState() {
    super.initState();
    final d = widget.initial;
    _facebookCtrl = TextEditingController(text: d.facebookUrl);
    _instagramCtrl = TextEditingController(text: d.instagramUrl);
    _twitterCtrl = TextEditingController(text: d.twitterUrl);
    _youtubeCtrl = TextEditingController(text: d.youtubeUrl);
    _linkedinCtrl = TextEditingController(text: d.linkedinUrl);
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

  void _notify() {
    widget.onChanged(widget.initial.copyWith(
      facebookUrl: _facebookCtrl.text.trim(),
      instagramUrl: _instagramCtrl.text.trim(),
      twitterUrl: _twitterCtrl.text.trim(),
      youtubeUrl: _youtubeCtrl.text.trim(),
      linkedinUrl: _linkedinCtrl.text.trim(),
    ));
  }

  bool validate() => _formKey.currentState?.validate() ?? true;

  String? _validateUrl(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return null; // All social links are optional
    final uri = Uri.tryParse(v);
    if (uri == null || !uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return 'Please enter a valid URL (https://...)';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Info card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: AppTheme.primary, size: 22),
                const SizedBox(width: 12),
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
          const SizedBox(height: 24),
          _socialField(
            controller: _facebookCtrl,
            label: context.tr('facebookLabel'),
            icon: FontAwesomeIcons.facebook,
            iconColor: const Color(0xFF1877F2),
          ),
          const SizedBox(height: 16),
          _socialField(
            controller: _instagramCtrl,
            label: context.tr('instagramLabel'),
            icon: FontAwesomeIcons.instagram,
            iconColor: const Color(0xFFE4405F),
          ),
          const SizedBox(height: 16),
          _socialField(
            controller: _twitterCtrl,
            label: context.tr('twitterLabel'),
            icon: FontAwesomeIcons.twitter,
            iconColor: const Color(0xFF1DA1F2),
          ),
          const SizedBox(height: 16),
          _socialField(
            controller: _youtubeCtrl,
            label: context.tr('youtubeLabel'),
            icon: FontAwesomeIcons.youtube,
            iconColor: const Color(0xFFFF0000),
          ),
          const SizedBox(height: 16),
          _socialField(
            controller: _linkedinCtrl,
            label: context.tr('linkedinLabel'),
            icon: FontAwesomeIcons.linkedin,
            iconColor: const Color(0xFF0A66C2),
          ),
          const SizedBox(height: 12),
          Text(
            'All social media links are optional. You can add them later from School Settings.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade500,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _socialField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required Color iconColor,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.url,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'https://',
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 12, right: 10, top: 10, bottom: 10),
          child: FaIcon(icon, color: iconColor, size: 20),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        isDense: true,
      ),
      onChanged: (_) => _notify(),
      validator: _validateUrl,
    );
  }
}

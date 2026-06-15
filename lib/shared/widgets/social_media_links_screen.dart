import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../shared/providers/school_settings_provider.dart';
import '../../l10n/app_strings.dart';
import '../../theme.dart';

/// Read-only screen to display school social media links.
/// Used by principal, coordinator, teacher & guardian dashboards.
class SocialMediaLinksScreen extends StatelessWidget {
  const SocialMediaLinksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SchoolSettingsProvider>();

    final links = <_SocialLink>[
      _SocialLink(context.tr('facebookLabel'), p.facebookUrl, FontAwesomeIcons.facebook, const Color(0xFF1877F2)),
      _SocialLink(context.tr('instagramLabel'), p.instagramUrl, FontAwesomeIcons.instagram, const Color(0xFFE4405F)),
      _SocialLink(context.tr('twitterLabel'), p.twitterUrl, FontAwesomeIcons.twitter, const Color(0xFF1DA1F2)),
      _SocialLink(context.tr('youtubeLabel'), p.youtubeUrl, FontAwesomeIcons.youtube, const Color(0xFFFF0000)),
      _SocialLink(context.tr('linkedinLabel'), p.linkedinUrl, FontAwesomeIcons.linkedin, const Color(0xFF0A66C2)),
    ];

    final hasAny = links.any((l) => l.url.isNotEmpty);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(context.tr('socialMediaLinksTitle')),
      ),
      body: SingleChildScrollView(
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
            if (!hasAny)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      Icon(Icons.link_off_outlined, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text(
                        context.tr('noSocialMediaLinks'),
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...links.where((l) => l.url.isNotEmpty).map((l) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: const BorderSide(color: AppTheme.border),
                  ),
                  child: InkWell(
                    onTap: () => _openUrl(context, l.url),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: l.color.withValues(alpha: 0.12),
                            child: FaIcon(l.icon, color: l.color, size: 18),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l.label.replaceAll(' URL', ''),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  l.url,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.open_in_new, color: l.color, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
              )),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _openUrl(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open this link'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }
}

class _SocialLink {
  final String label;
  final String url;
  final IconData icon;
  final Color color;
  const _SocialLink(this.label, this.url, this.icon, this.color);
}

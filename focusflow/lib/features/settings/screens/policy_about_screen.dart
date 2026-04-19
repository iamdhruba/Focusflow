import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:focusflow/core/theme/app_theme.dart';
import 'package:focusflow/shared/widgets/glass_card.dart';
import 'package:url_launcher/url_launcher.dart';
import 'policy_content_screen.dart';

String? encodeQueryParameters(Map<String, String> params) {
  return params.entries
      .map((MapEntry<String, String> e) =>
          '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
      .join('&');
}

/// Screen 9: Policy & About
class PolicyAboutScreen extends StatelessWidget {
  const PolicyAboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('About & Policy'),
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.pop()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          // App branding
          Center(
            child: Column(
              children: [
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    boxShadow: AppColors.ambientShadow,
                  ),
                  child: const Icon(Icons.self_improvement_rounded, color: Colors.white, size: 38),
                ),
                const SizedBox(height: AppSpacing.md),
                Text('FocusFlow', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Master your digital environment.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant)),
                const SizedBox(height: 8),
                Text('Version 1.0.0', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceVariant.withValues(alpha: 0.6))),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          // Links
          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _LinkTile(
                  icon: Icons.privacy_tip_rounded,
                  label: 'Privacy Policy',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PolicyContentScreen(
                        title: 'Privacy Policy',
                        content: PolicyData.privacyPolicy,
                      ),
                    ),
                  ),
                ),
                _Divider(),
                _LinkTile(
                  icon: Icons.description_rounded,
                  label: 'Terms of Service',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PolicyContentScreen(
                        title: 'Terms of Service',
                        content: PolicyData.termsOfService,
                      ),
                    ),
                  ),
                ),
                _Divider(),
                _LinkTile(
                  icon: Icons.code_rounded,
                  label: 'Open Source Licenses',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PolicyContentScreen(
                        title: 'Licenses',
                        content: PolicyData.licenses,
                      ),
                    ),
                  ),
                ),
                _Divider(),
                _LinkTile(
                  icon: Icons.star_rounded,
                  label: 'Rate on Play Store',
                  onTap: () async {
                    final url = Uri.parse('https://play.google.com/store/apps/details?id=com.dhrubaraj.focusflow');
                    if (await canLaunchUrl(url)) {
                      await launchUrl(url, mode: LaunchMode.externalApplication);
                    }
                  },
                ),
                _Divider(),
                _LinkTile(
                  icon: Icons.bug_report_rounded,
                  label: 'Report a Bug',
                  onTap: () async {
                    final Uri emailLaunchUri = Uri(
                      scheme: 'mailto',
                      path: 'dhrubarajchaudhary498@gmail.com',
                      query: encodeQueryParameters(<String, String>{
                        'subject': 'FocusFlow Bug Report',
                        'body': 'Device: Android\nVersion: 1.0.0\nIssue description: ',
                      }),
                    );
                    if (await canLaunchUrl(emailLaunchUri)) {
                      await launchUrl(emailLaunchUri);
                    }
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          // Privacy promise
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.primaryFixed.withValues(alpha: 0.5),
              borderRadius: AppRadius.cardRadius,
            ),
            child: Column(
              children: [
                const Icon(Icons.verified_user_rounded, color: AppColors.primary, size: 32),
                const SizedBox(height: AppSpacing.sm),
                Text('Privacy First', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppColors.primary)),
                const SizedBox(height: 4),
                Text(
                  'All your data is processed on-device. Usage statistics are only synced to your personal account and are never sold or shared with third parties.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.primary.withValues(alpha: 0.8), height: 1.5),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.xl),
          Center(
            child: Text(
              '© 2025 FocusFlow. All rights reserved.',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        height: 1,
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        color: AppColors.outlineVariant.withValues(alpha: 0.15),
      );
}

class _LinkTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _LinkTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary, size: 22),
      title: Text(label, style: Theme.of(context).textTheme.bodyMedium),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.onSurfaceVariant),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
    );
  }
}

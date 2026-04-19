import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:focusflow/core/theme/app_theme.dart';
import 'package:focusflow/shared/widgets/gradient_button.dart';

/// Screen 2: Permission Pitch
/// Explains WHY each permission is needed — builds trust before requesting.
class PermissionPitchScreen extends StatelessWidget {
  const PermissionPitchScreen({super.key});

  static const _pitches = [
    _PitchItem(
      icon: Icons.bar_chart_rounded,
      color: AppColors.primary,
      title: 'Usage Access',
      subtitle: 'We read how long you use each app — never shared with anyone.',
    ),
    _PitchItem(
      icon: Icons.accessibility_new_rounded,
      color: AppColors.tertiary,
      title: 'Accessibility Service',
      subtitle: 'Detects which app is in the foreground so we can enforce limits.',
    ),
    _PitchItem(
      icon: Icons.layers_rounded,
      color: Color(0xFF7C3AED),
      title: 'Display Over Apps',
      subtitle: 'Shows the blocker overlay when you hit your daily limit.',
    ),
    _PitchItem(
      icon: Icons.admin_panel_settings_rounded,
      color: Color(0xFFEA580C),
      title: 'Device Admin',
      subtitle: 'Prevents uninstallation in Strict Mode — your accountability lock.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    padding: EdgeInsets.zero,
                    style: IconButton.styleFrom(
                        foregroundColor: AppColors.onBackground),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Why we\nneed access',
                      style: Theme.of(context)
                          .textTheme
                          .headlineLarge
                          ?.copyWith(height: 1.1)),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'FocusFlow works entirely on-device. Your data never leaves your phone.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.onSurfaceVariant, height: 1.5),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xl),

            // ── Permission Cards ───────────────────────────────────────────
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                itemCount: _pitches.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.md),
                itemBuilder: (ctx, i) {
                  final p = _pitches[i];
                  return Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLowest,
                      borderRadius: AppRadius.cardRadius,
                      boxShadow: AppColors.cardShadow,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: p.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: Icon(p.icon, color: p.color, size: 26),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.title,
                                  style:
                                      Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: 4),
                              Text(p.subtitle,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: AppColors.onSurfaceVariant,
                                          height: 1.4)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // ── CTA ─────────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: GradientButton(
                label: 'Grant Permissions',
                icon: Icons.shield_rounded,
                onPressed: () => context.go('/onboarding/guide'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PitchItem {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  const _PitchItem(
      {required this.icon,
      required this.color,
      required this.title,
      required this.subtitle});
}

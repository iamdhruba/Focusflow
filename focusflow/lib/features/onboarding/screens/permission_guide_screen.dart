import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:focusflow/core/theme/app_theme.dart';
import 'package:focusflow/core/storage/secure_storage.dart';
import '../providers/permission_provider.dart';
import 'package:focusflow/shared/widgets/gradient_button.dart';
import 'package:focusflow/core/services/native_channel_service.dart';
import 'package:focusflow/shared/widgets/brand_logo.dart';

/// Screen 3: Permission Guide
/// Interactive checklist — each row shows granted/pending status.
class PermissionGuideScreen extends ConsumerStatefulWidget {
  const PermissionGuideScreen({super.key});

  @override
  ConsumerState<PermissionGuideScreen> createState() =>
      _PermissionGuideScreenState();
}

class _PermissionGuideScreenState
    extends ConsumerState<PermissionGuideScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(permissionProvider.notifier).checkAll());
  }

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(permissionProvider);
    final notifier = ref.read(permissionProvider.notifier);

    final items = [
      _PermItem(
        icon: Icons.bar_chart_rounded,
        title: 'Usage Stats Access',
        subtitle: 'Required to track daily screen time',
        granted: perms.usageStats,
        onGrant: notifier.requestUsageStats,
      ),
      _PermItem(
        icon: Icons.accessibility_new_rounded,
        title: 'Accessibility Service',
        subtitle: 'Required to detect & block apps',
        granted: perms.accessibility,
        onGrant: notifier.requestAccessibility,
      ),
      _PermItem(
        icon: Icons.layers_rounded,
        title: 'Display Over Apps',
        subtitle: 'Required to show the blocker overlay',
        granted: perms.overlay,
        onGrant: notifier.requestOverlay,
      ),
      _PermItem(
        icon: Icons.admin_panel_settings_rounded,
        title: 'Device Admin',
        subtitle: 'Enables Strict Mode uninstall protection',
        granted: perms.deviceAdmin,
        onGrant: notifier.requestDeviceAdmin,
        optional: true,
      ),
      _PermItem(
        icon: Icons.battery_saver_rounded,
        title: 'Battery Optimization',
        subtitle: 'Prevents Android from killing the blocker',
        granted: perms.batteryOptimization,
        onGrant: notifier.requestBatteryOptimization,
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Align(
                    alignment: Alignment.centerRight,
                    child: BrandLogo(size: 40, iconSize: 22),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // Progress indicator
                  Row(
                    children: List.generate(5, (i) {
                      final active = i < perms.grantedCount;
                      return Expanded(
                        child: Container(
                          height: 4,
                          margin: EdgeInsets.only(right: i < 4 ? 6 : 0),
                          decoration: BoxDecoration(
                            color: active
                                ? AppColors.tertiary
                                : AppColors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    '${perms.grantedCount} of 5\npermissions granted',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(height: 1.1),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    perms.allGranted
                        ? 'All set! FocusFlow is ready to protect your focus.'
                        : 'Tap each permission below to grant access.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppColors.onSurfaceVariant),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xl),

            Expanded(
              child: ListView.separated(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.md),
                itemBuilder: (ctx, i) => _PermissionRow(item: items[i]),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                children: [
                  GradientButton(
                    label: perms.allGranted
                        ? 'Continue to Dashboard'
                        : 'Re-check Permissions',
                    icon: perms.allGranted
                        ? Icons.check_circle_rounded
                        : Icons.refresh_rounded,
                    onPressed: perms.allGranted
                        ? () async {
                            await SecureStorage.setOnboardingDone();
                            if (context.mounted) context.go('/dashboard');
                          }
                        : () => notifier.checkAll(),
                  ),
                  if (!perms.allGranted) ...[
                    const SizedBox(height: AppSpacing.sm),
                    TextButton(
                      onPressed: () => _showRestrictedSettingsGuide(context),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.help_outline_rounded,
                              size: 16, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Having trouble granting permissions?',
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                  color: AppColors.primary,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextButton(
                      onPressed: () async {
                        await SecureStorage.setOnboardingDone();
                        if (context.mounted) context.go('/dashboard');
                      },
                      child: Text(
                        'Skip for now',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRestrictedSettingsGuide(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permissions Blocked?'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'On Android 13+, system settings may be restricted for apps installed via APK.',
            ),
            SizedBox(height: AppSpacing.md),
            Text('To fix this:', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: AppSpacing.sm),
            Text('1. Tap "Open App Info" below.'),
            Text('2. Tap the ︙ (three dots) in the top right corner.'),
            Text('3. Select "Allow restricted settings".'),
            Text('4. Come back here and try granting permissions again.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Dismiss'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              NativeChannelService().openAppSettings();
            },
            child: const Text('Open App Info'),
          ),
        ],
      ),
    );
  }
}

class _PermItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool granted;
  final Future<void> Function() onGrant;
  final bool optional;

  const _PermItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.granted,
    required this.onGrant,
    this.optional = false,
  });
}

class _PermissionRow extends StatelessWidget {
  final _PermItem item;
  const _PermissionRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: item.granted
            ? AppColors.tertiary.withValues(alpha: 0.06)
            : AppColors.surfaceContainerLowest,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(
          color: item.granted
              ? AppColors.tertiary.withValues(alpha: 0.3)
              : AppColors.outlineVariant.withValues(alpha: 0.15),
          width: 1,
        ),
        boxShadow: item.granted ? null : AppColors.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: item.granted
                  ? AppColors.tertiary.withValues(alpha: 0.12)
                  : AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(
              item.icon,
              color: item.granted ? AppColors.tertiary : AppColors.onSurfaceVariant,
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(item.title,
                        style: Theme.of(context).textTheme.titleSmall),
                    if (item.optional) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.secondaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('Optional',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                    color: AppColors.onSecondaryContainer)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(item.subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (item.granted)
            const Icon(Icons.check_circle_rounded,
                color: AppColors.tertiary, size: 26)
          else
            TextButton(
              onPressed: item.onGrant,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
              child: const Text('Grant'),
            ),
        ],
      ),
    );
  }
}

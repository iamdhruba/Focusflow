import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:focusflow/core/theme/app_theme.dart';
import 'package:focusflow/features/apps/providers/apps_provider.dart';
import 'package:focusflow/features/auth/providers/auth_provider.dart';
import 'package:focusflow/shared/widgets/gradient_button.dart';

/// Screen 6: Set Limit
/// Time-limit slider + reset cycle picker for a single app.
class SetLimitScreen extends ConsumerStatefulWidget {
  final AppPolicyModel policy;
  const SetLimitScreen({super.key, required this.policy});

  @override
  ConsumerState<SetLimitScreen> createState() => _SetLimitScreenState();
}

class _SetLimitScreenState extends ConsumerState<SetLimitScreen> {
  late double _limitMinutes;
  bool _isFullBlock = false;
  bool _isSaving = false;

  static const _presets = [15, 30, 60, 90, 120, 180, 240];

  @override
  void initState() {
    super.initState();
    _limitMinutes = widget.policy.timeLimitMinutes.toDouble().clamp(5, 480);
    _isFullBlock = widget.policy.timeLimitMinutes == 0;
  }

  String _formatMinutes(double mins) {
    if (mins < 60) return '${mins.toInt()}m';
    final h = mins ~/ 60;
    final m = (mins % 60).toInt();
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final success = await ref.read(appsProvider.notifier).upsertPolicy(
          packageName: widget.policy.packageName,
          appName: widget.policy.appName,
          timeLimitMinutes: _isFullBlock ? 0 : _limitMinutes.toInt(),
        );
    setState(() => _isSaving = false);
    if (success && mounted) context.go('/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    final apps = ref.watch(appsProvider);
    // Find the latest policy state for this package
    final currentPolicy = apps.policies.firstWhere(
      (p) => p.packageName == widget.policy.packageName,
      orElse: () => widget.policy,
    );
    
    final isOverLimit = currentPolicy.isOverLimit;
    final isStrict = ref.watch(authProvider).strictMode;
    final isLocked = isStrict || isOverLimit;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Set Limit'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── App Info ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: AppRadius.cardRadius,
                boxShadow: AppColors.cardShadow,
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.primaryFixed,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Center(
                      child: Text(
                        widget.policy.appName.isNotEmpty
                            ? widget.policy.appName[0].toUpperCase()
                            : 'A',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800,
                            fontSize: 22),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.policy.appName,
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(widget.policy.packageName,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppColors.onSurfaceVariant),
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xl),

            if (isOverLimit && !isStrict)
              Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.errorContainer.withValues(alpha: 0.2),
                  borderRadius: AppRadius.cardRadius,
                  border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock_clock_rounded, color: AppColors.error),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        'This app is currently over its limit. Settings are locked until tomorrow to prevent bypass.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.error),
                      ),
                    ),
                  ],
                ),
              ),

            // ── Full Block Toggle ─────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: _isFullBlock
                    ? AppColors.errorContainer.withValues(alpha: 0.4)
                    : AppColors.surfaceContainerLowest,
                borderRadius: AppRadius.cardRadius,
                border: Border.all(
                  color: _isFullBlock
                      ? AppColors.error.withValues(alpha: 0.3)
                      : AppColors.outlineVariant.withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.block_rounded,
                      color: _isFullBlock
                          ? AppColors.error
                          : AppColors.onSurfaceVariant),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Full Block',
                            style: Theme.of(context).textTheme.titleSmall),
                        Text('Prevent all access to this app',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Switch(
                    value: _isFullBlock,
                    activeTrackColor: AppColors.error,
                    onChanged: isLocked
                        ? null
                        : (val) => setState(() {
                              _isFullBlock = val;
                            }),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xl),

            // ── Time Limit Slider ─────────────────────────────────────────
            AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: _isFullBlock ? 0.3 : 1.0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Daily Time Limit',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.lg),

                  // Big time display
                  Center(
                    child: Text(
                      _isFullBlock ? 'Blocked' : _formatMinutes(_limitMinutes),
                      style:
                          Theme.of(context).textTheme.displaySmall?.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w800,
                              ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Slider
                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 6,
                      activeTrackColor: AppColors.primary,
                      inactiveTrackColor: AppColors.surfaceContainerHigh,
                      thumbColor: AppColors.primary,
                      overlayColor: AppColors.primaryFixed.withValues(alpha: 0.3),
                      thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 12),
                    ),
                    child: Slider(
                      value: _limitMinutes,
                      min: 5,
                      max: 480,
                      divisions: 95,
                      onChanged: (_isFullBlock || isLocked)
                          ? null
                          : (val) => setState(() => _limitMinutes = val),
                    ),
                  ),

                  // Min/Max labels
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('5m',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: AppColors.onSurfaceVariant)),
                        Text('8h',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: AppColors.onSurfaceVariant)),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.lg),

                  // Preset chips
                  Text('Quick Presets',
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: AppColors.onSurfaceVariant,
                              letterSpacing: 0.8)),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    children: _presets.map<Widget>((mins) {
                      final selected = !_isFullBlock &&
                          _limitMinutes.toInt() == mins;
                      return GestureDetector(
                        onTap: (_isFullBlock || isLocked)
                            ? null
                            : () => setState(() => _limitMinutes = mins.toDouble()),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.primaryFixed
                                : AppColors.surfaceContainerLow,
                            borderRadius:
                                BorderRadius.circular(AppRadius.full),
                            border: Border.all(
                              color: selected
                                  ? AppColors.primary
                                  : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Text(
                            _formatMinutes(mins.toDouble()),
                            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: selected
                                      ? AppColors.primary
                                      : AppColors.onSurfaceVariant,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xxxl),

            GradientButton(
              label: 'Save Limit',
              icon: Icons.save_rounded,
              isLoading: _isSaving,
              onPressed: isLocked ? null : _save,
            ),

            // ── Per-screen section blocking link ─────────────────────────────
            const SizedBox(height: AppSpacing.lg),
            if (!isLocked)
              Container(
                decoration: BoxDecoration(
                  color: AppColors.primaryFixed.withValues(alpha: 0.5),
                  borderRadius: AppRadius.cardRadius,
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.18),
                      width: 1),
                ),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.cardRadius),
                  leading: const Icon(Icons.layers_rounded,
                      color: AppColors.primary),
                  title: Text('Block specific sections',
                      style: Theme.of(context).textTheme.titleSmall),
                  subtitle: Text(
                    'e.g. Reels, Stories, Explore in ${widget.policy.appName}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded,
                      color: AppColors.primary),
                  onTap: () => context.push(
                    '/apps/detail',
                    extra: {
                      'packageName': widget.policy.packageName,
                      'appName': widget.policy.appName,
                    },
                  ),
                ),
              ),

            // Delete button if already exists
            if (widget.policy.id != null) ...[
              const SizedBox(height: AppSpacing.md),
              GradientButton(
                label: 'Remove App',
                isSecondary: true,
                icon: Icons.delete_outline_rounded,
                onPressed: isLocked ? null : () async {
                  await ref.read(appsProvider.notifier).deletePolicy(widget.policy.packageName);
                  if (context.mounted) context.go('/dashboard');
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:focusflow/core/theme/app_theme.dart';
import 'package:focusflow/features/apps/providers/apps_provider.dart';
import 'package:focusflow/features/auth/providers/auth_provider.dart';
import 'package:focusflow/shared/widgets/glass_card.dart';
import 'package:focusflow/shared/widgets/progress_ring.dart';

/// Screen 4: Main Dashboard
/// Today's usage summary, active blocks, focus ring, sync status.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(appsProvider.notifier).syncUsage());
  }

  String _formatDuration(int ms) {
    final mins = ms ~/ 60000;
    if (mins < 60) return '${mins}m';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }

  @override
  Widget build(BuildContext context) {
    final apps = ref.watch(appsProvider);
    final auth = ref.watch(authProvider);
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Good morning'
        : now.hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    final totalMs = apps.totalUsageMs;
    final dailyGoalMs = auth.dailyGoalMinutes * 60 * 1000;
    final progress = (totalMs / dailyGoalMs).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          backgroundColor: AppColors.surfaceContainerLowest,
          onRefresh: () => ref.read(appsProvider.notifier).syncUsage(),
          child: CustomScrollView(
            slivers: [
              // ── App Bar ─────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(greeting,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                        color: AppColors.onSurfaceVariant,
                                        letterSpacing: 0.8)),
                            Text(
                              auth.user?['name']?.toString().split(' ').first ??
                                  'Focus',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                      // Sync indicator
                      if (apps.isSyncing)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.primary),
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.sync_rounded),
                          color: AppColors.primary,
                          onPressed: () =>
                              ref.read(appsProvider.notifier).syncUsage(),
                        ),
                      const SizedBox(width: 4),
                      // Settings
                      IconButton(
                        icon: const Icon(Icons.settings_rounded),
                        color: AppColors.onSurfaceVariant,
                        onPressed: () => context.push('/settings/strict'),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Today's Focus Ring ────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: GlassCard(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      children: [
                        Text('Today\'s Screen Time',
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(letterSpacing: 0.8)),
                        const SizedBox(height: AppSpacing.xl),
                        ProgressRing(
                          progress: progress,
                          size: 160,
                          strokeWidth: 14,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _formatDuration(totalMs),
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: progress >= 1.0
                                            ? AppColors.error
                                            : AppColors.onBackground),
                              ),
                              Text('used today',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                          color: AppColors.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),

                        // ── Quick Stats ─────────────────────────────────────
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _QuickStat(
                              label: 'Apps Tracked',
                              value: apps.policies.length.toString(),
                              icon: Icons.apps_rounded,
                            ),
                            Container(
                                width: 1,
                                height: 36,
                                color: AppColors.outlineVariant.withValues(alpha: 0.3)),
                            _QuickStat(
                              label: 'Over Limit',
                              value: apps.overLimitCount.toString(),
                              icon: Icons.block_rounded,
                              valueColor: apps.overLimitCount > 0
                                  ? AppColors.error
                                  : AppColors.tertiary,
                            ),
                            Container(
                                width: 1,
                                height: 36,
                                color: AppColors.outlineVariant.withValues(alpha: 0.3)),
                            _QuickStat(
                              label: 'Sync',
                              value: apps.lastSync != null
                                  ? DateFormat('HH:mm').format(apps.lastSync!)
                                  : '--',
                              icon: Icons.cloud_sync_rounded,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Blocked Apps Header ────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Tracked Apps',
                            style: Theme.of(context).textTheme.titleMedium),
                      ),
                      TextButton.icon(
                        onPressed: () => context.push('/apps/select'),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add App'),
                        style: TextButton.styleFrom(
                            foregroundColor: AppColors.primary),
                      ),
                    ],
                  ),
                ),
              ),

              // ── App List ────────────────────────────────────────────────
              if (apps.isLoading)
                const SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.xxxl),
                      child: CircularProgressIndicator(color: AppColors.primary),
                    ),
                  ),
                )
              else if (apps.policies.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: SurfaceCard(
                      child: Column(
                        children: [
                          const Icon(Icons.add_circle_outline_rounded,
                              size: 48, color: AppColors.onSurfaceVariant),
                          const SizedBox(height: AppSpacing.md),
                          Text('No apps tracked yet',
                              style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 4),
                          Text('Tap "Add App" to start blocking distractions.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xxxl),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        final policy = apps.policies[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: _AppUsageCard(
                            policy: policy,
                            onTap: () => context.go(
                                '/apps/set-limit',
                                extra: policy),
                          ),
                        );
                      },
                      childCount: apps.policies.length,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),

      // ── Bottom Nav ─────────────────────────────────────────────────────────
      bottomNavigationBar: const _BottomNav(currentIndex: 0),
    );
  }
}

class _QuickStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;

  const _QuickStat(
      {required this.label,
      required this.value,
      required this.icon,
      this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: valueColor ?? AppColors.onBackground,
                )),
        const SizedBox(height: 2),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: AppColors.onSurfaceVariant)),
      ],
    );
  }
}

class _AppUsageCard extends StatelessWidget {
  final AppPolicyModel policy;
  final VoidCallback onTap;

  const _AppUsageCard({required this.policy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: AppRadius.cardRadius,
          boxShadow: AppColors.cardShadow,
        ),
        child: Row(
          children: [
            // App icon placeholder
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primaryFixed,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Center(
                child: Text(
                  policy.appName.isNotEmpty ? policy.appName[0].toUpperCase() : 'A',
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 18),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(policy.appName,
                            style: Theme.of(context).textTheme.titleSmall),
                      ),
                      if (policy.isOverLimit)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.errorContainer,
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                          ),
                          child: Text('Over limit',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: AppColors.error)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  UsageProgressBar(progress: policy.progressFraction),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(policy.usedFormatted,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: policy.isOverLimit
                                  ? AppColors.error
                                  : AppColors.tertiary,
                              fontWeight: FontWeight.w600)),
                      Text(' / ${policy.limitFormatted}',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: AppColors.onSurfaceVariant)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  const _BottomNav({required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest.withValues(alpha: 0.95),
        border: Border(
            top: BorderSide(
                color: AppColors.outlineVariant.withValues(alpha: 0.15), width: 1)),
      ),
      child: NavigationBar(
        selectedIndex: currentIndex,
        backgroundColor: Colors.transparent,
        indicatorColor: AppColors.primaryFixed,
        onDestinationSelected: (i) {
          switch (i) {
            case 0:
              context.go('/dashboard');
            case 1:
              context.go('/apps/select');
            case 2:
              context.go('/settings/strict');
          }
        },
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.dashboard_rounded), label: 'Dashboard'),
          NavigationDestination(
              icon: Icon(Icons.apps_rounded), label: 'Apps'),
          NavigationDestination(
              icon: Icon(Icons.settings_rounded), label: 'Settings'),
        ],
      ),
    );
  }
}

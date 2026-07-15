import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:focusflow/core/theme/app_theme.dart';
import 'package:focusflow/features/apps/providers/apps_provider.dart';
import 'package:focusflow/shared/widgets/glass_card.dart';
import 'package:focusflow/shared/widgets/progress_ring.dart';
import 'package:focusflow/shared/widgets/brand_logo.dart';
import 'package:focusflow/core/services/native_channel_service.dart';
import 'package:focusflow/features/auth/providers/auth_provider.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(appsProvider.notifier).refreshUsage());
  }

  String _formatDuration(int ms) {
    final mins = ms ~/ 60000;
    if (mins < 60) return '${mins}m';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }

  /// Bug D UX (Nov 2025): one-tap tracking from the dashboard's
  /// "Available to track" section. Creates an AppPolicy with a
  /// 60-minute soft cap (non-invasive default — doesn't lock the user
  /// out of the app's workflow, but starts tracking immediately) and
  /// lets `load()` re-flow the just-tracked entry into the Tracked
  /// Apps list above. Editable later via SetLimitScreen.
  Future<void> _trackApp(InstalledApp app) async {
    await ref.read(appsProvider.notifier).upsertPolicy(
          packageName: app.packageName,
          appName: app.appName,
          timeLimitMinutes: 60,
          isActive: true,
        );
  }

  @override
  Widget build(BuildContext context) {
    final apps = ref.watch(appsProvider);
    // Bug D UX (Nov 2025): installed apps minus already-tracked ones,
    // capped at 8 rows to keep the dashboard fast. The user can still
    // reach the full list via the "See all" link → /apps/select.
    final untrackedApps = apps.installedApps
        .where((a) => !apps.policies.any((p) => p.packageName == a.packageName))
        .take(8)
        .toList();
    final now = DateTime.now();
    final greeting = now.hour < 12 ? 'Good morning' : now.hour < 17 ? 'Good afternoon' : 'Good evening';

    final totalMs = apps.totalUsageMs;
    final progress = apps.dailyProgress;
    final dailyGoalMinutes = apps.dailyGoalMinutes;
    final dailyGoalMs = dailyGoalMinutes * 60 * 1000;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: Stack(
          children: [
            // ── Background Mesh Blobs ──────────────────────────────────────────
            Positioned(
              top: -100, right: -50,
              child: _BlurredBlob(color: AppColors.primary.withValues(alpha: 0.1), size: 300),
            ),
            Positioned(
              bottom: 100, left: -100,
              child: _BlurredBlob(color: AppColors.tertiary.withValues(alpha: 0.08), size: 400),
            ),

            SafeArea(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (context, opacity, child) {
                  return Opacity(
                    opacity: opacity,
                    child: Transform.translate(
                      offset: Offset(0, 15 * (1 - opacity)),
                      child: child!,
                    ),
                  );
                },
                child: RefreshIndicator(
                  color: AppColors.primary,
                  backgroundColor: AppColors.surfaceContainerLowest,
                  onRefresh: () => ref.read(appsProvider.notifier).refreshUsage(),
                  child: CustomScrollView(
                    slivers: <Widget>[
                // ── App Bar ─────────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, 0),
                    child: Row(
                      children: [
                        const BrandLogo(size: 44, iconSize: 24),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(greeting,
                                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                      color: AppColors.onSurfaceVariant, letterSpacing: 0.8)),
                              Text(
                                'Focus User',
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.sync_rounded),
                          color: AppColors.primary,
                          onPressed: () => ref.read(appsProvider.notifier).refreshUsage(),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.settings_rounded),
                          color: AppColors.onSurfaceVariant,
                          onPressed: () => context.push('/settings/strict'),
                        ),
                      ],
                    ),
                  ),
                ),
  
                // ── Strict Mode Banner ───────────────────────────────────────
                if (ref.watch(authProvider).strictMode)
                  SliverToBoxAdapter(
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.xl, 0),
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppColors.errorContainer.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_rounded, color: AppColors.error, size: 16),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              'Strict Mode Active: Limits are locked for 24h.',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.error, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // ── Today's Focus Ring ────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, AppSpacing.md),
                    child: GlassCard(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Column(
                        children: [
                          Text('Today\'s Screen Time',
                              style: Theme.of(context).textTheme.labelMedium?.copyWith(letterSpacing: 0.8)),
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
                                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: progress >= 1.0 ? AppColors.error : AppColors.onBackground,
                                      ),
                                ),
                                Text('used today',
                                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
  
                          // ── Progress Comparison ─────────────────────────────────────
                          GestureDetector(
                            onTap: () => _showGoalPicker(context, ref, dailyGoalMinutes),
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: (progress >= 1.0 ? AppColors.error : AppColors.primary).withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(AppRadius.full),
                                border: Border.all(
                                  color: (progress >= 1.0 ? AppColors.error : AppColors.primary).withValues(alpha: 0.2),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    progress >= 1.0 ? Icons.warning_amber_rounded : Icons.check_circle_rounded,
                                    size: 16,
                                    color: progress >= 1.0 ? AppColors.error : AppColors.tertiary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    progress >= 1.0 
                                      ? 'Goal Exceeded' 
                                      : '${_formatDuration(dailyGoalMs - totalMs)} Left',
                                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                      color: progress >= 1.0 ? AppColors.error : AppColors.onSurface,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.edit_rounded, 
                                    size: 14, 
                                    color: (progress >= 1.0 ? AppColors.error : AppColors.primary).withValues(alpha: 0.6)
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Detailed Stats Grid ─────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
                    child: GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      mainAxisSpacing: AppSpacing.md,
                      crossAxisSpacing: AppSpacing.md,
                      childAspectRatio: 1.6,
                      children: [
                        _StatCard(
                          label: 'Blocked Attempts',
                          value: apps.blockedAttempts.toString(),
                          icon: Icons.security_rounded,
                          color: AppColors.primary,
                        ),
                        _StatCard(
                          label: 'Phone Pickups',
                          value: apps.phonePickups.toString(),
                          icon: Icons.phonelink_ring_rounded,
                          color: AppColors.tertiary,
                        ),
                        _StatCard(
                          label: 'Apps Tracked',
                          value: apps.policies.length.toString(),
                          icon: Icons.apps_rounded,
                          color: AppColors.onSurfaceVariant,
                        ),
                        _StatCard(
                          label: 'Daily Goal',
                          value: dailyGoalMinutes < 60
                            ? '${dailyGoalMinutes}m'
                            : dailyGoalMinutes % 60 == 0
                              ? '${dailyGoalMinutes ~/ 60}h'
                              : '${dailyGoalMinutes ~/ 60}h ${dailyGoalMinutes % 60}m',
                          icon: Icons.timer_rounded,
                          color: Colors.amber[700]!,
                          onTap: () => _showGoalPicker(context, ref, dailyGoalMinutes),
                        ),
                      ],
                    ),
                  ),
                ),
  
                // ── Blocked Apps Header ────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.md),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('Tracked Apps', style: Theme.of(context).textTheme.titleMedium),
                        ),
                        TextButton.icon(
                          onPressed: ref.watch(authProvider).strictMode 
                            ? () => ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Cannot add apps in Strict Mode'))
                              )
                            : () => context.push('/apps/select'),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Add App'),
                          style: TextButton.styleFrom(
                            foregroundColor: ref.watch(authProvider).strictMode 
                              ? AppColors.onSurfaceVariant.withValues(alpha: 0.5) 
                              : AppColors.primary
                          ),
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
                            const Icon(Icons.add_circle_outline_rounded, size: 48, color: AppColors.onSurfaceVariant),
                            const SizedBox(height: AppSpacing.md),
                            Text('No apps tracked yet', style: Theme.of(context).textTheme.titleSmall),
                            const SizedBox(height: 4),
                            Text('Tap "Add App" to start blocking distractions.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xxxl),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) {
                          final policy = apps.policies[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.md),
                            child: _AppUsageCard(
                              policy: policy,
                              onTap: ref.watch(authProvider).strictMode
                                ? () => ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Strict Mode: App limits cannot be changed'))
                                  )
                                : () => context.push('/apps/set-limit', extra: policy),
                            ),
                          );
                        },
                        childCount: apps.policies.length,
                      ),
                    ),
                  ),

                  // ── Available-to-track section (Bug D UX) ─────────────────
                  // Surface installed-but-not-yet-tracked apps inline so
                  // the user never has to navigate to /apps/select first.
                  if (untrackedApps.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                            AppSpacing.xl,
                            AppSpacing.lg,
                            AppSpacing.xl,
                            AppSpacing.sm),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text('Available to track',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium),
                            ),
                            Text('${untrackedApps.length} more',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                        color:
                                            AppColors.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xxxl),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) => _UntrackedAppCard(
                            app: untrackedApps[i],
                            onTrack: () => _trackApp(untrackedApps[i]),
                          ),
                          childCount: untrackedApps.length,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    ),
        bottomNavigationBar: const _BottomNav(currentIndex: 0),
      ),
    );
  }
}

class _BlurredBlob extends StatelessWidget {
  final Color color;
  final double size;
  const _BlurredBlob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
        child: Container(color: Colors.transparent),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Stack(
          children: [
            if (onTap != null)
              Positioned(
                top: 0, right: 0,
                child: Icon(Icons.edit_rounded, size: 10, color: color.withValues(alpha: 0.5)),
              ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppColors.onSurfaceVariant,
                              fontSize: 10,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

void _showGoalPicker(BuildContext context, WidgetRef ref, int currentMinutes) {
  // sliderVal must live outside the builder so setState doesn't reset it
  double sliderVal = currentMinutes.toDouble().clamp(15.0, 480.0);

  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xl, AppSpacing.xl,
                MediaQuery.of(context).padding.bottom + AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.outlineVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Set Daily Focus Goal', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Choose a preset or slide to customize your daily budget.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.xl),

                // ── Presets ──────────────────────────────────────────────────
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.sm,
                  alignment: WrapAlignment.center,
                  children: [60, 120, 180, 240, 300].map((mins) {
                    // isSelected reflects the live slider value, not stale currentMinutes
                    final isSelected = sliderVal.toInt() == mins;
                    return ChoiceChip(
                      label: Text('${mins ~/ 60}h'),
                      selected: isSelected,
                      onSelected: (_) {
                        setState(() => sliderVal = mins.toDouble());
                      },
                    );
                  }).toList(),
                ),

                const SizedBox(height: AppSpacing.xxl),
                const Divider(),
                const SizedBox(height: AppSpacing.lg),

                // ── Custom Slider ────────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Custom Budget', style: Theme.of(context).textTheme.titleSmall),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      child: Text(
                        sliderVal.toInt() < 60
                          ? '${sliderVal.toInt()}m'
                          : '${sliderVal.toInt() ~/ 60}h ${sliderVal.toInt() % 60 > 0 ? "${sliderVal.toInt() % 60}m" : ""}',
                        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: sliderVal,
                  min: 15,
                  max: 480,
                  divisions: 31, // 15-min increments
                  label: sliderVal.toInt() < 60
                    ? '${sliderVal.toInt()}m'
                    : '${sliderVal.toInt() ~/ 60}h ${sliderVal.toInt() % 60}m',
                  activeColor: AppColors.primary,
                  onChanged: (val) => setState(() => sliderVal = val),
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: () {
                      ref.read(appsProvider.notifier).updateDailyGoal(sliderVal.toInt());
                      Navigator.pop(context);
                    },
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                    ),
                    child: const Text('Apply Goal'),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
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
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              clipBehavior: Clip.antiAlias,
              child: _AppIcon(packageName: policy.packageName, appName: policy.appName),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(policy.appName, style: Theme.of(context).textTheme.titleSmall),
                      ),
                      if (policy.isOverLimit)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.errorContainer,
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                          ),
                          child: Text('Over limit',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.error)),
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
                              color: policy.isOverLimit ? AppColors.error : AppColors.tertiary,
                              fontWeight: FontWeight.w600)),
                      Text(' / ${policy.limitFormatted}',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.onSurfaceVariant)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            const Icon(Icons.chevron_right_rounded, color: AppColors.onSurfaceVariant),
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
        border: Border(top: BorderSide(color: AppColors.outlineVariant.withValues(alpha: 0.15), width: 1)),
      ),
      child: NavigationBar(
        selectedIndex: currentIndex,
        backgroundColor: Colors.transparent,
        indicatorColor: AppColors.primaryFixed,
        onDestinationSelected: (i) {
          switch (i) {
            case 0: context.go('/dashboard');
            case 1: context.push('/apps/select');
            case 2: context.push('/settings/strict');
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_rounded), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.apps_rounded), label: 'Apps'),
          NavigationDestination(icon: Icon(Icons.settings_rounded), label: 'Settings'),
        ],
      ),
    );
  }
}

class _AppIcon extends StatelessWidget {
  final String packageName;
  final String appName;
  const _AppIcon({required this.packageName, required this.appName});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: NativeChannelService().getAppIcon(packageName),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return Image.memory(
            base64Decode(snapshot.data!),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _Placeholder(name: appName),
          );
        }
        return _Placeholder(name: appName);
      },
    );
  }
}

/// Bug D UX (Nov 2025): inline card for one-tap tracking from the
/// dashboard's "Available to track" section. Smaller and less heavy
/// than _AppUsageCard because there's no usage bar / progress to
/// render yet — just icon, name, package, and a Track button.
class _UntrackedAppCard extends StatelessWidget {
  final InstalledApp app;
  final VoidCallback onTrack;

  const _UntrackedAppCard({required this.app, required this.onTrack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: AppRadius.cardRadius,
          border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              clipBehavior: Clip.antiAlias,
              child: app.iconBase64 != null
                  ? Image.memory(
                      base64Decode(app.iconBase64!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _Placeholder(name: app.appName),
                    )
                  : _Placeholder(name: app.appName),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(app.appName,
                      style: Theme.of(context).textTheme.titleSmall),
                  Text(
                    app.packageName,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: onTrack,
              icon: const Icon(Icons.add_circle_rounded,
                  size: 18, color: AppColors.primary),
              label: const Text('Track'),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  final String name;
  const _Placeholder({required this.name});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : 'A',
        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 18),
      ),
    );
  }
}

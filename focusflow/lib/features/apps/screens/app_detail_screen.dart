import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:focusflow/core/theme/app_theme.dart';
import 'package:focusflow/core/services/screen_catalog.dart';
import 'package:focusflow/features/apps/providers/apps_provider.dart';
import 'package:focusflow/shared/widgets/gradient_button.dart';

/// Screen 6b: App Detail — per-screen blocking for a single host app.
///
/// Reachable from SetLimitScreen via the "Block specific sections" button
/// or via a long-press on a tracked app card. Renders one row per
/// SupportedScreen (from kSupportedScreens) for [widget.packageName]:
///
///   ┌───────────────────────────────────────────────┐
///   │  🎬  Reels                       [Active ◯ ]  │
///   │       Daily limit    [────●────────] 30m     │
///   └───────────────────────────────────────────────┘
///
/// Each row is independently local-state-dirty until the user taps
/// "Save Changes" — at which point every dirty screen calls
/// AppsNotifier.upsertScreenPolicy() and the native engine gets
/// the new rule table via updateScreenBlockingRules().
class AppDetailScreen extends ConsumerStatefulWidget {
  final String packageName;
  final String appName;

  const AppDetailScreen({
    super.key,
    required this.packageName,
    required this.appName,
  });

  @override
  ConsumerState<AppDetailScreen> createState() => _AppDetailScreenState();
}

class _AppDetailScreenState extends ConsumerState<AppDetailScreen> {
  /// `<packageName>:<screenKey>` → local edit state.
  /// null = not present yet (use server value as-is).
  final Map<String, _ScreenEditor> _editors = {};
  bool _isSaving = false;

  /// Editors for screens supported by this host app. Pre-populated from
  /// the current Riverpod state. `appsProvider.screenPolicies` already
  /// holds whatever the screen-notifier has loaded, so reading it
  /// synchronously here is enough — no async/await / post-frame race.
  @override
  void initState() {
    super.initState();
    _hydrateEditors();
  }

  void _hydrateEditors() {
    final existing = ref.read(appsProvider).screensFor(widget.packageName);
    final forPackage = supportedScreensFor(widget.packageName);

    for (final screen in forPackage) {
      final key = '${screen.packageName}:${screen.screenKey}';
      final matchIndex =
          existing.indexWhere((p) => p.screenKey == screen.screenKey);
      final hasPrior = matchIndex >= 0;
      final current = hasPrior
          ? existing[matchIndex]
          : ScreenPolicyModel(
              packageName: screen.packageName,
              screenKey: screen.screenKey,
              friendlyName: screen.friendlyName,
            );
      _editors[key] = _ScreenEditor(
        supported: screen,
        isActive: current.isActive,
        // No prior rule → seed minutes to 15 so the toggle has a sensible
        // place to land. A prior rule preservation intent: keep stored
        // minutes exactly so re-enabling preserves the chosen cap.
        minutes: hasPrior ? current.timeLimitMinutes : 15,
      );
    }
  }

  bool get _isDirty =>
      _editors.values.any((e) => e.isActive != e.initialIsActive || e.minutes != e.initialMinutes);

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final notifier = ref.read(appsProvider.notifier);
    bool ok = true;
    for (final editor in _editors.values) {
      if (editor.isActive == editor.initialIsActive &&
          editor.minutes == editor.initialMinutes) {
        continue; // untouched
      }
      final result = await notifier.upsertScreenPolicy(
        ScreenPolicyModel(
          serverId: editor.saved?.serverId,
          packageName: editor.supported.packageName,
          screenKey: editor.supported.screenKey,
          friendlyName: editor.supported.friendlyName,
          timeLimitMinutes: editor.minutes,
          isActive: editor.isActive,
        ),
      );
      if (result) {
        editor.initialIsActive = editor.isActive;
        editor.initialMinutes = editor.minutes;
        editor.saved = ScreenPolicyModel(
          serverId: editor.saved?.serverId,
          packageName: editor.supported.packageName,
          screenKey: editor.supported.screenKey,
          friendlyName: editor.supported.friendlyName,
          timeLimitMinutes: editor.minutes,
          isActive: editor.isActive,
        );
      } else {
        ok = false;
      }
    }
    if (mounted) {
      setState(() => _isSaving = false);
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Screen rules saved'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        context.pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Some rules failed to save. Please retry.'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = supportedScreensFor(widget.packageName);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Specific Sections'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _isDirty
              ? () async {
                  final discard = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Discard changes?'),
                      content: const Text(
                        'Your unsaved edits will be lost.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Keep editing'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Discard'),
                        ),
                      ],
                    ),
                  );
                  if (discard == true && context.mounted) context.pop();
                }
              : () => context.pop(),
        ),
      ),
      body: screens.isEmpty
          ? const _EmptyState()
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.xxxl,
              ),
              children: [
                _AppHeader(
                  packageName: widget.packageName,
                  appName: widget.appName,
                ),
                const SizedBox(height: AppSpacing.xl),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs, vertical: AppSpacing.sm),
                  child: Text(
                    'Block specific sections of ${widget.appName} instead of the whole app. Toggle a section ON to set a daily limit or full block.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                ...screens.map((s) {
                  final key = '${s.packageName}:${s.screenKey}';
                  final editor = _editors[key];
                  if (editor == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: _ScreenRuleCard(
                      editor: editor,
                      onChanged: () => setState(() {}),
                    ),
                  );
                }),
                const SizedBox(height: AppSpacing.xl),
                GradientButton(
                  label: _isDirty ? 'Save Changes' : 'Saved',
                  icon: _isDirty ? Icons.save_rounded : Icons.check_circle_rounded,
                  isLoading: _isSaving,
                  onPressed: !_isDirty ? null : _save,
                ),
              ],
            ),
    );
  }
}

// ─── Helpers ────────────────────────────────────────────────────────────────

class _ScreenEditor {
  final SupportedScreen supported;
  bool isActive;
  int minutes;
  bool initialIsActive;
  int initialMinutes;
  ScreenPolicyModel? saved;

  _ScreenEditor({
    required this.supported,
    required this.isActive,
    required this.minutes,
  })  : initialIsActive = isActive,
        initialMinutes = minutes;
}

class _AppHeader extends StatelessWidget {
  final String packageName;
  final String appName;
  const _AppHeader({required this.packageName, required this.appName});

  @override
  Widget build(BuildContext context) {
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
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.primaryFixed,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Center(
              child: Text(
                appName.isNotEmpty ? appName[0].toUpperCase() : 'A',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(appName, style: Theme.of(context).textTheme.titleMedium),
                Text(
                  packageName,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScreenRuleCard extends ConsumerWidget {
  final _ScreenEditor editor;
  final VoidCallback onChanged;

  const _ScreenRuleCard({required this.editor, required this.onChanged});

  String _formatMinutes(int mins) {
    if (mins < 60) return '${mins}m';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }

  String _formatMs(int usedMs) {
    final mins = usedMs ~/ 60000;
    if (mins < 1) return '<1m';
    if (mins < 60) return '${mins}m';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = editor.supported;
    // Phase 4: pull just the one matching screen's policy via select() —
    // ScreenPolicyModel now has content-equality, so this widget rebuilds
    // ONLY when THIS screen's usedMs/timeLimitMinutes/isActive change,
    // not on every appsProvider state mutation (e.g. another screen's
    // flush arriving via channel).
    final saved = ref.watch(appsProvider.select((state) {
      final i = state.screenPolicies.indexWhere(
        (p) => p.packageName == s.packageName && p.screenKey == s.screenKey,
      );
      return i >= 0 ? state.screenPolicies[i] : null;
    }));

    final limitMinutes = saved?.timeLimitMinutes ?? 0;
    final usedMs = saved?.todayUsageMs ?? 0;
    final hasSlidingCap =
        limitMinutes > 0 && (saved?.isActive ?? false);
    final fraction = hasSlidingCap && limitMinutes > 0
        ? (usedMs / (limitMinutes * 60 * 1000)).clamp(0.0, 1.0)
        : null;
    final progressColor = fraction == null
        ? AppColors.primary
        : fraction > 0.9
            ? AppColors.error
            : fraction > 0.7
                ? AppColors.warning
                : AppColors.primary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        color: editor.isActive
            ? AppColors.primaryFixed.withValues(alpha: 0.65)
            : AppColors.surfaceContainerLowest,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(
          color: editor.isActive
              ? AppColors.primary.withValues(alpha: 0.3)
              : Colors.transparent,
          width: 1,
        ),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                // Emoji chip
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Center(
                    child: Text(s.emoji, style: const TextStyle(fontSize: 22)),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.friendlyName,
                          style: Theme.of(context).textTheme.titleSmall),
                      Text(
                        editor.isActive
                            ? (editor.minutes == 0
                                ? 'Full block'
                                : '${_formatMinutes(editor.minutes)} per day')
                            : 'Off',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: editor.isActive
                                  ? AppColors.primary
                                  : AppColors.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: editor.isActive,
                  activeTrackColor: AppColors.primary,
                  onChanged: (v) {
                    editor.isActive = v;
                    onChanged();
                  },
                ),
              ],
            ),
          ),
          // Phase 4: live usage progress (driven by the saved rule's
          // todayUsageMs — independent of in-editor slider state).
          if (hasSlidingCap)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                60, // align with title text (44 emoji + 16 gap)
                0,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      child: LinearProgressIndicator(
                        value: fraction,
                        minHeight: 5,
                        backgroundColor: AppColors.surfaceContainerHigh,
                        color: progressColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '${_formatMs(usedMs)} of ${_formatMinutes(limitMinutes)}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: progressColor,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
          // Slider appears only when active
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: editor.isActive
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
                    child: Column(
                      children: [
                        const Divider(height: 1),
                        const SizedBox(height: AppSpacing.md),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Limit',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(letterSpacing: 0.8),
                            ),
                            // Full-block toggle pill
                            GestureDetector(
                              onTap: () {
                                editor.minutes =
                                    editor.minutes == 0 ? 15 : 0;
                                onChanged();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: editor.minutes == 0
                                      ? AppColors.errorContainer
                                      : AppColors.surfaceContainerLow,
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.full),
                                ),
                                child: Text(
                                  editor.minutes == 0
                                      ? 'Full block'
                                      : 'Soft cap',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: editor.minutes == 0
                                            ? AppColors.error
                                            : AppColors.onSurfaceVariant,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (editor.minutes > 0) ...[
                          const SizedBox(height: AppSpacing.sm),
                          SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 5,
                              activeTrackColor: AppColors.primary,
                              inactiveTrackColor:
                                  AppColors.surfaceContainerHigh,
                              thumbColor: AppColors.primary,
                              thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 10),
                              overlayShape: SliderComponentShape.noOverlay,
                            ),
                            child: Slider(
                              value: editor.minutes.toDouble().clamp(5, 120),
                              min: 5,
                              max: 120,
                              divisions: 23,
                              label: _formatMinutes(editor.minutes),
                              onChanged: (v) {
                                editor.minutes = (v.round() ~/ 5) * 5;
                                onChanged();
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm),
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text('5m',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                            color: AppColors.onSurfaceVariant)),
                                Text(_formatMinutes(editor.minutes),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w700,
                                        )),
                                Text('2h',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                            color: AppColors.onSurfaceVariant)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded,
                size: 56, color: AppColors.onSurfaceVariant),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No supported sections',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'This app doesn\'t have any section-level rules yet. The full-app limit already covers it.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

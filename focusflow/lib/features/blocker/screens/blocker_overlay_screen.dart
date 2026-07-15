import 'package:flutter/material.dart';
import 'package:focusflow/core/theme/app_theme.dart';
import 'package:focusflow/shared/widgets/brand_logo.dart';

/// Blocker overlay — shown when an app or specific in-app screen is blocked.
///
/// Phase 1 supports per-screen rendering:
///   • If [screenName] is provided (e.g. "Reels", "For You"), the overlay
///     reads "Reels are blocked today" instead of generic app-level copy.
///   • Fallback is the original "Your daily limit for {appName} has been reached."
class BlockerOverlayScreen extends StatefulWidget {
  final String appName;
  final String? screenName;
  final VoidCallback? onGoBack;

  const BlockerOverlayScreen({
    super.key,
    this.appName = 'This App',
    this.screenName,
    this.onGoBack,
  });

  @override
  State<BlockerOverlayScreen> createState() => _BlockerOverlayScreenState();
}

class _BlockerOverlayScreenState extends State<BlockerOverlayScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.88, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String get _headline => "Time's Up.";

  String get _body {
    final screen = widget.screenName;
    if (screen == null || screen.isEmpty) {
      return 'Your daily limit for ${widget.appName} has been reached.';
    }
    // Per-screen copy. Article heuristics - "Reels" -> "are"; "For You" -> "is".
    final article = _articleFor(screen).toLowerCase();
    return '$screen $article blocked today. You\'ve reached your limit for this section of ${widget.appName}.';
  }

  /// Tiny heuristic - "For You", "TikTok Live" take "is"; others take "are".
  String _articleFor(String screen) {
    final lower = screen.toLowerCase();
    if (lower == 'for you' || lower.endsWith('live') || lower.endsWith('search')) {
      return 'is';
    }
    return 'are';
  }

  @override
  Widget build(BuildContext context) {
    final hasScreen = widget.screenName != null && widget.screenName!.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.inverseSurface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              ScaleTransition(
                scale: _pulse,
                child: const BrandLogo(size: 120, iconSize: 56),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                _headline,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                _body,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.surfaceDim,
                      height: 1.5,
                    ),
              ),
              if (hasScreen) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'You can keep using ${widget.appName}\u2019s other features normally.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.surfaceDim.withValues(alpha: 0.85),
                        height: 1.5,
                      ),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.schedule_rounded, color: AppColors.tertiaryFixedDim, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'Resets at midnight',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white),
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 2),
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: AppRadius.cardRadius,
                ),
                child: Text(
                  '"Every minute on social media is a minute not spent on your goals."',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.surfaceDim,
                        fontStyle: FontStyle.italic,
                        height: 1.6,
                      ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: widget.onGoBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Go Back'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.surfaceContainerLowest,
                    foregroundColor: AppColors.onBackground,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.buttonRadius),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}

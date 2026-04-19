import 'package:flutter/material.dart';
import 'package:focusflow/core/theme/app_theme.dart';

class BlockerOverlayScreen extends StatefulWidget {
  final String appName;
  final VoidCallback? onGoBack;
  const BlockerOverlayScreen({super.key, this.appName = 'This App', this.onGoBack});

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

  @override
  Widget build(BuildContext context) {
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
                child: Container(
                  width: 120, height: 120,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF1E3A6E), Color(0xFF1D4ED8)],
                        begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(AppRadius.xl + 8),
                    boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 40, offset: const Offset(0, 12))],
                  ),
                  child: const Icon(Icons.shield_rounded, color: Colors.white, size: 56),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text("Time's Up.", style: Theme.of(context).textTheme.displaySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
              const SizedBox(height: AppSpacing.md),
              Text('Your daily limit for ${widget.appName} has been reached.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.surfaceDim, height: 1.5)),
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
                    Text('Resets at midnight', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white)),
                  ],
                ),
              ),
              const Spacer(flex: 2),
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: AppRadius.cardRadius),
                child: Text(
                  '"Every minute on social media is a minute not spent on your goals."',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.surfaceDim, fontStyle: FontStyle.italic, height: 1.6),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity, height: 56,
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

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:focusflow/core/theme/app_theme.dart';
import 'package:focusflow/shared/widgets/gradient_button.dart';

/// Screen 1: Welcome Screen
/// Emotional landing experience — "The Cognitive Sanctuary"
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeCtrl;
  late AnimationController _slideCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _slideCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut));
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));

    Future.delayed(const Duration(milliseconds: 200), () {
      _fadeCtrl.forward();
      _slideCtrl.forward();
    });
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _slideCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(flex: 2),

                  // ── Brand Mark ───────────────────────────────────────────
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      boxShadow: AppColors.ambientShadow,
                    ),
                    child: const Icon(Icons.self_improvement_rounded,
                        color: AppColors.onPrimary, size: 34),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // ── Headline ─────────────────────────────────────────────
                  Text(
                    'Your mind\ndeserves\nquiet.',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.5,
                          height: 1.05,
                          color: AppColors.onBackground,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // ── Subtitle ─────────────────────────────────────────────
                  Text(
                    'FocusFlow gives you back control — one blocked app at a time.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: AppColors.onSurfaceVariant,
                          height: 1.6,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.xxxl),

                  // ── Stats Row ─────────────────────────────────────────────
                  const Row(
                    children: [
                      _StatPill(label: 'Users', value: '50K+'),
                      SizedBox(width: AppSpacing.md),
                      _StatPill(label: 'Apps Blocked', value: '2M+'),
                      SizedBox(width: AppSpacing.md),
                      _StatPill(label: 'Hours Saved', value: '10M+'),
                    ],
                  ),

                  const Spacer(flex: 3),

                  // ── CTA Buttons ───────────────────────────────────────────
                  GradientButton(
                    label: 'Get Started',
                    icon: Icons.arrow_forward_rounded,
                    onPressed: () => context.go('/login'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  GradientButton(
                    label: 'I already have an account',
                    isSecondary: true,
                    onPressed: () => context.go('/login'),
                  ),

                  const SizedBox(height: AppSpacing.lg),

                  // ── Legal ─────────────────────────────────────────────────
                  Center(
                    child: Text(
                      'By continuing you agree to our Terms & Privacy Policy',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;
  const _StatPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.sm + 2, horizontal: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          children: [
            Text(value,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    )),
            const SizedBox(height: 2),
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: AppColors.onSurfaceVariant),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

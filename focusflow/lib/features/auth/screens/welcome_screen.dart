import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:focusflow/core/theme/app_theme.dart';
import 'package:focusflow/shared/widgets/gradient_button.dart';
import 'package:focusflow/shared/widgets/brand_logo.dart';

/// Screen 1: Welcome Screen (Get Started)
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with TickerProviderStateMixin {
  late AnimationController _fadeCtrl;
  late AnimationController _slideCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _slideCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut));
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));

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
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(flex: 2),
                  const BrandLogo(),
                  const SizedBox(height: AppSpacing.xl),
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
                  Text(
                    'FocusFlow gives you back control — one blocked app at a time.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: AppColors.onSurfaceVariant,
                          height: 1.6,
                        ),
                  ),
                  const Spacer(flex: 3),
                  GradientButton(
                    label: 'Get Started',
                    icon: Icons.arrow_forward_rounded,
                    onPressed: () => context.go('/onboarding/pitch'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // Optional sign-in for returning users. The app is fully
                  // usable without an account; sign-in only enables cloud
                  // sync of block lists across devices + Strict Mode
                  // enforcement backed by the server.
                  Center(
                    child: TextButton(
                      onPressed: () => context.go('/login'),
                      child: Text(
                        'I already have an account',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Center(
                    child: Text(
                      'FocusFlow works on-device. Your data never leaves your phone.',
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

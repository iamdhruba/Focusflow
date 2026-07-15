import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Glassmorphic card widget — the "frosted glass" floating element
/// from the Cognitive Sanctuary design system.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final double borderRadius;
  final List<BoxShadow>? shadows;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.backgroundColor,
    this.borderRadius = AppRadius.lg,
    this.shadows,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = backgroundColor ?? AppColors.surfaceContainerLowest;
    
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: cardColor.withValues(alpha: 0.7), // Semi-transparent for glass effect
              borderRadius: BorderRadius.circular(borderRadius),
              boxShadow: shadows ?? AppColors.cardShadow,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 1,
              ),
            ),
            child: Padding(
              padding: padding ?? const EdgeInsets.all(AppSpacing.md),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// A surface-container-low section card (recessed / no elevation).
class SurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final double borderRadius;

  const SurfaceCard({
    super.key,
    required this.child,
    this.padding,
    this.color,
    this.borderRadius = AppRadius.lg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color ?? AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(AppSpacing.md),
        child: child,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:focusflow/core/theme/app_theme.dart';

class BrandLogo extends StatelessWidget {
  final double size;
  final double iconSize;
  const BrandLogo({super.key, this.size = 64, this.iconSize = 34});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(size * 0.28), // Proportional radius
        boxShadow: AppColors.ambientShadow,
      ),
      child: Icon(
        Icons.self_improvement_rounded,
        color: AppColors.onPrimary,
        size: iconSize,
      ),
    );
  }
}

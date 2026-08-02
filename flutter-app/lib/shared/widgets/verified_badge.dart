import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';

/// 认证徽章（黄色对勾圆形）。
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, this.size = 12});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: AppColors.verified,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.check,
        size: size * 0.75,
        color: Colors.white,
      ),
    );
  }
}

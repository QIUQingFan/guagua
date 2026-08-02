import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();

  static const primary = Color(0xFFDC1257);
  static const primaryDark = Color(0xFFC6104E);

  static const backgroundLight = Color(0xFFF7F7F7);
  static const surfaceLight = Colors.white;
  static const textPrimaryLight = Color(0xFF333333);
  static const textSecondaryLight = Color(0xFF5C5C5C);
  static const textHintLight = Color(0xFF858585);
  static const dividerLight = Color(0xFFEBEBEB);

  static const backgroundDark = Color(0xFF121212);
  static const surfaceDark = Color(0xFF1E1E1E);
  static const textPrimaryDark = Color(0xFFE0E0E0);
  static const textSecondaryDark = Color(0xFFB0B0B0);
  static const textHintDark = Color(0xFF909090);
  static const dividerDark = Color(0xFF242424);

  static const like = Color(0xFFFF0C30);
  static const collect = Color(0xFFFFB300);
  static const verified = Color(0xFFFFB300);
  static const online = Color(0xFF4CAF50);
}

class AppSpacing {
  const AppSpacing._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

class AppRadius {
  const AppRadius._();
  static const card = 12.0;
  static const button = 24.0;
  static const image = 8.0;
  static const chip = 16.0;
}

class AppTextSize {
  const AppTextSize._();
  static const display = 24.0;
  static const titleLarge = 20.0;
  static const title = 16.0;
  static const body = 14.0;
  static const caption = 12.0;
  static const micro = 10.0;
}

const kPagePadding = EdgeInsets.symmetric(
  horizontal: AppSpacing.lg,
  vertical: AppSpacing.sm,
);

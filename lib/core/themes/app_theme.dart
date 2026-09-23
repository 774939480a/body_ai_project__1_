// lib/core/themes/app_theme.dart
// ─────────────────────────────────────────────────────────────────────────────
// Futuristic dark AI theme — neon cyan / electric-blue accents on near-black.
// All colours are defined as static constants so painters can reuse them
// without importing Flutter's material package everywhere.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

/// Central colour palette — import this file instead of hardcoding hex values.
class AppColors {
  AppColors._();

  // ── Backgrounds ─────────────────────────────────────────────────────────
  static const Color backgroundPrimary   = Color(0xFF080C14); // near-black
  static const Color backgroundSecondary = Color(0xFF0D1521); // dark navy
  static const Color surfaceCard         = Color(0xFF112030); // card surface

  // ── Neon accents ────────────────────────────────────────────────────────
  static const Color neonCyan    = Color(0xFF00F5FF); // primary accent
  static const Color neonBlue    = Color(0xFF0090FF); // secondary accent
  static const Color neonGreen   = Color(0xFF00FF94); // positive / stable
  static const Color neonOrange  = Color(0xFFFF8C00); // warning
  static const Color neonRed     = Color(0xFFFF2D55); // error / critical
  static const Color neonPurple  = Color(0xFFBF5AF2); // analysis highlight

  // ── Skeleton overlay ────────────────────────────────────────────────────
  static const Color skeletonJoint       = neonCyan;
  static const Color skeletonBone        = Color(0xFF00C8D5);
  static const Color skeletonAxisLine    = Color(0x8800F5FF); // semi-transparent
  static const Color guideFrameRed       = Color(0xB3FF2D55); // ~70 % opaque
  static const Color guideLineColor      = Color(0x66FF2D55); // ~40 % opaque

  // ── Text ────────────────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFFEAF4FF);
  static const Color textSecondary = Color(0xFF7AB8D4);
  static const Color textDisabled  = Color(0xFF3D5A70);

  // ── Status colours ──────────────────────────────────────────────────────
  static const Color statusStable   = neonGreen;
  static const Color statusUnstable = neonOrange;
  static const Color statusCritical = neonRed;
}

/// Central typography — uses a monospace feel appropriate for data overlays.
class AppTextStyles {
  AppTextStyles._();

  static const String _fontFamily = 'Courier'; // monospace; swap for a custom font

  static const TextStyle displayLarge = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: 1.5,
  );

  static const TextStyle measurementLabel = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: AppColors.neonCyan,
    letterSpacing: 0.8,
  );

  static const TextStyle statusLabel = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.2,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 10,
    color: AppColors.textSecondary,
    letterSpacing: 0.5,
  );
}

/// MaterialApp ThemeData factory.
class AppTheme {
  AppTheme._();

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.backgroundPrimary,
    colorScheme: const ColorScheme.dark(
      primary:   AppColors.neonCyan,
      secondary: AppColors.neonBlue,
      surface:   AppColors.backgroundSecondary,
      error:     AppColors.neonRed,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.backgroundPrimary,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: 'Courier',
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: 2.0,
        color: AppColors.neonCyan,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.neonCyan,
        foregroundColor: AppColors.backgroundPrimary,
        textStyle: const TextStyle(
          fontFamily: 'Courier',
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surfaceCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF1A3A55), width: 1),
      ),
    ),
    fontFamily: 'Courier',
  );
}

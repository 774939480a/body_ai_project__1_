// lib/widgets/fps_indicator.dart
// ─────────────────────────────────────────────────────────────────────────────
// Live FPS counter displayed in the top HUD.
// Colour-codes the value: green ≥ 25, orange 15–24, red < 15.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../core/themes/app_theme.dart';

class FpsIndicator extends StatelessWidget {
  const FpsIndicator({super.key, required this.fps});

  final int fps;

  Color get _fpsColor {
    if (fps >= 25) return AppColors.neonGreen;
    if (fps >= 15) return AppColors.neonOrange;
    return AppColors.neonRed;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary.withOpacity(0.75),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _fpsColor.withOpacity(0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _fpsColor,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            '${fps} FPS',
            style: TextStyle(
              fontFamily: 'Courier',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _fpsColor,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

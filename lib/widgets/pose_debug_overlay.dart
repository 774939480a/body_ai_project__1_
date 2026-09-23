// lib/widgets/pose_debug_overlay.dart
// ─────────────────────────────────────────────────────────────────────────────
// PoseDebugOverlay — lightweight real-time status widget used in Phase 2 to
// verify that pose detection is working before the full skeleton painter
// (Phase 4) is integrated.
//
// Displays:
//   • Detection status (SEARCHING / DETECTED / PARTIAL)
//   • Number of reliable landmarks out of 33
//   • ML Kit average inference latency
//   • Whether the pose meets measurement / posture readiness thresholds
//
// This widget will remain as a developer-toggle in later phases.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../core/themes/app_theme.dart';
import '../models/pose_data.dart';

class PoseDebugOverlay extends StatelessWidget {
  const PoseDebugOverlay({
    super.key,
    required this.poseData,
    required this.inferenceLatencyMs,
    this.visible = true,
  });

  /// Latest pose from [PoseDetectorService].  Null = no detection.
  final PoseData? poseData;

  /// Average ML Kit inference latency in ms (from [PoseDetectorService]).
  final double inferenceLatencyMs;

  /// Set to false to hide the overlay without rebuilding the tree.
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    final pose = poseData;

    return Positioned(
      bottom: 110,
      left: 12,
      right: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary.withOpacity(0.82),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _statusColor(pose).withOpacity(0.5),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Status row ──────────────────────────────────────────────
            Row(
              children: [
                _DotIndicator(color: _statusColor(pose)),
                const SizedBox(width: 6),
                Text(
                  _statusLabel(pose),
                  style: AppTextStyles.statusLabel.copyWith(
                    color: _statusColor(pose),
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                Text(
                  'ML Kit  ${inferenceLatencyMs.toStringAsFixed(1)} ms',
                  style: AppTextStyles.bodySmall,
                ),
              ],
            ),

            if (pose != null) ...[
              const SizedBox(height: 6),

              // ── Landmark count bar ──────────────────────────────────
              _LandmarkBar(reliable: pose.reliableLandmarkCount, total: 33),

              const SizedBox(height: 4),

              // ── Readiness flags ──────────────────────────────────────
              Row(
                children: [
                  _ReadinessChip(
                    label: 'MEASURE',
                    ready: pose.isMeasurementReady,
                  ),
                  const SizedBox(width: 6),
                  _ReadinessChip(
                    label: 'POSTURE',
                    ready: pose.isPostureReady,
                  ),
                  const SizedBox(width: 6),
                  _ReadinessChip(
                    label: 'FRONT CAM',
                    ready: pose.isFrontCamera,
                    trueColor: AppColors.neonBlue,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _statusLabel(PoseData? pose) {
    if (pose == null) return 'SEARCHING...';
    if (pose.isMeasurementReady) return 'POSE DETECTED ✓';
    if (pose.reliableLandmarkCount >= 6) return 'PARTIAL DETECTION';
    return 'LOW CONFIDENCE';
  }

  Color _statusColor(PoseData? pose) {
    if (pose == null) return AppColors.neonOrange;
    if (pose.isMeasurementReady) return AppColors.neonGreen;
    if (pose.reliableLandmarkCount >= 6) return AppColors.neonOrange;
    return AppColors.neonRed;
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _DotIndicator extends StatelessWidget {
  const _DotIndicator({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class _LandmarkBar extends StatelessWidget {
  const _LandmarkBar({required this.reliable, required this.total});

  final int reliable;
  final int total;

  @override
  Widget build(BuildContext context) {
    final fraction = (reliable / total).clamp(0.0, 1.0);
    final barColor = fraction > 0.7
        ? AppColors.neonGreen
        : fraction > 0.4
            ? AppColors.neonOrange
            : AppColors.neonRed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'LANDMARKS',
              style: AppTextStyles.bodySmall,
            ),
            Text(
              '$reliable / $total',
              style: AppTextStyles.bodySmall.copyWith(
                color: barColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        LayoutBuilder(
          builder: (_, constraints) {
            return Stack(
              children: [
                // Background track
                Container(
                  height: 4,
                  width: constraints.maxWidth,
                  decoration: BoxDecoration(
                    color: AppColors.backgroundPrimary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Fill
                Container(
                  height: 4,
                  width: constraints.maxWidth * fraction,
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [BoxShadow(color: barColor.withOpacity(0.5), blurRadius: 4)],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ReadinessChip extends StatelessWidget {
  const _ReadinessChip({
    required this.label,
    required this.ready,
    this.trueColor = AppColors.neonGreen,
  });

  final String label;
  final bool ready;
  final Color trueColor;

  @override
  Widget build(BuildContext context) {
    final color = ready ? trueColor : AppColors.textDisabled;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.4), width: 0.8),
      ),
      child: Text(
        label,
        style: AppTextStyles.bodySmall.copyWith(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

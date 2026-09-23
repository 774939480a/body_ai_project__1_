// lib/widgets/skeleton_overlay.dart
// ─────────────────────────────────────────────────────────────────────────────
// SkeletonOverlayWidget — mounts [SkeletonPainter] and [OverlayPainter]
// as two independent [CustomPaint] layers, each wrapped in its own
// [RepaintBoundary].
//
// Layer stack (bottom → top):
//   Layer 1 — SkeletonPainter   (bones + joints + body axis)
//   Layer 2 — OverlayPainter    (alignment lines + angles + labels)
//
// Why two separate layers?
//   In theory, both could be merged into a single CustomPainter.  Splitting
//   them gives two independent repaint scopes so future optimisations can
//   update the overlay layer (labels + angles) at a lower frequency than the
//   skeleton layer without restructuring the painter hierarchy.
//
// RepaintBoundary placement:
//   Each CustomPaint has its own RepaintBoundary so the camera preview and
//   guide-frame layers are never triggered by a pose update.
//   The two overlay layers share the same rebuild cycle (both update at 30fps)
//   so isolating them from each other yields minimal extra benefit — the
//   separation is mainly for architectural clarity.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../models/measurement_result.dart';
import '../models/pose_data.dart';
import '../painters/overlay_painter.dart';
import '../painters/skeleton_painter.dart';

class SkeletonOverlayWidget extends StatelessWidget {
  const SkeletonOverlayWidget({
    super.key,
    required this.poseData,
    required this.measurement,
  });

  /// Latest smoothed pose from [PoseSmoother] via [MeasurementEngine].
  final PoseData? poseData;

  /// Latest measurement snapshot from [MeasurementEngine].
  final MeasurementResult measurement;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Layer 1: Skeleton (bones + joints) ─────────────────────────
        RepaintBoundary(
          child: CustomPaint(
            painter: SkeletonPainter(poseData: poseData),
            // isComplex = true hints to Flutter that this layer should be
            // rasterised and cached on the GPU between frames where
            // shouldRepaint returns false.
            isComplex: true,
            // willChange = true tells Flutter this layer changes frequently
            // so it should prepare a GPU cache layer.
            willChange: true,
            child: const SizedBox.expand(),
          ),
        ),

        // ── Layer 2: Overlay (measurements + angles + alignment) ────────
        RepaintBoundary(
          child: CustomPaint(
            painter: OverlayPainter(
              poseData:    poseData,
              measurement: measurement,
            ),
            isComplex: true,
            willChange: true,
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }
}

// lib/painters/skeleton_painter.dart
// ─────────────────────────────────────────────────────────────────────────────
// SkeletonPainter — draws the live neon AI skeleton overlay.
//
// Draw order (back → front):
//   1. Central body-axis dashed line (spine guide)
//   2. All bone segments with neon glow (from PoseConnections.all)
//   3. All reliable joint circles with glow
//
// Performance strategy:
//   • [shouldRepaint] compares timestamps → skips paint if pose unchanged.
//   • Glow effect uses [MaskFilter.blur] which is GPU-accelerated on Android.
//   • Only landmarks with [isReliable] == true are drawn — unreliable
//     landmarks are skipped entirely to avoid phantom joint flicker.
//   • Wrapped in [RepaintBoundary] by [SkeletonOverlayWidget] so it never
//     triggers a repaint of the camera preview or guide-frame layers.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../core/constants/app_constants.dart';
import '../core/themes/app_theme.dart';
import '../models/joint_point.dart';
import '../models/pose_connections.dart';
import '../models/pose_data.dart';
import 'painter_utils.dart';

class SkeletonPainter extends CustomPainter {
  const SkeletonPainter({
    required this.poseData,
  });

  /// The latest smoothed pose. Null → nothing is drawn (person not detected).
  final PoseData? poseData;

  // ─────────────────────────────────────────────────────────────────────────
  // Paint
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    final pose = poseData;
    if (pose == null || pose.landmarks.isEmpty) return;

    // ── 1. Central body axis ────────────────────────────────────────────
    _drawBodyAxis(canvas, size, pose);

    // ── 2. Bone segments ────────────────────────────────────────────────
    _drawBones(canvas, size, pose);

    // ── 3. Joint circles ────────────────────────────────────────────────
    _drawJoints(canvas, size, pose);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Body axis
  // ─────────────────────────────────────────────────────────────────────────

  void _drawBodyAxis(Canvas canvas, Size size, PoseData pose) {
    // Compute the mid-shoulder and mid-hip virtual joints.
    final ls = pose.leftShoulder;
    final rs = pose.rightShoulder;
    final lh = pose.leftHip;
    final rh = pose.rightHip;

    if (ls == null || rs == null || lh == null || rh == null) return;
    if (!ls.isReliable || !rs.isReliable || !lh.isReliable || !rh.isReliable) {
      return;
    }

    final shoulderMidX = ((ls.x + rs.x) / 2) * size.width;
    final shoulderMidY = ((ls.y + rs.y) / 2) * size.height;
    final hipMidX      = ((lh.x + rh.x) / 2) * size.width;
    final hipMidY      = ((lh.y + rh.y) / 2) * size.height;

    // Extend the axis line from nose (top) down to ankle midpoint (bottom).
    final nose = pose.nose;
    final la   = pose.leftAnkle;
    final ra   = pose.rightAnkle;

    final topY    = (nose != null && nose.isReliable)
        ? nose.y * size.height
        : shoulderMidY - 20;
    final bottomY = (la != null && ra != null && la.isReliable && ra.isReliable)
        ? ((la.y + ra.y) / 2) * size.height
        : hipMidY + 40;

    // X of the axis line = midpoint of shoulders (more stable than hips).
    final axisX = shoulderMidX;

    PainterUtils.drawBodyAxis(
      canvas,
      Offset(axisX, topY),
      Offset(axisX, bottomY),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Bones
  // ─────────────────────────────────────────────────────────────────────────

  void _drawBones(Canvas canvas, Size size, PoseData pose) {
    for (final bone in PoseConnections.all) {
      final startJoint = pose.landmarks[bone.start];
      final endJoint   = pose.landmarks[bone.end];

      // Skip bone if either endpoint is missing or unreliable.
      if (startJoint == null || endJoint == null) continue;
      if (!startJoint.isReliable || !endJoint.isReliable) continue;

      final startOffset = startJoint.toOffset(size);
      final endOffset   = endJoint.toOffset(size);

      // Opacity is the minimum confidence of the two endpoints.
      final opacity = (startJoint.likelihood * 0.5 + endJoint.likelihood * 0.5)
          .clamp(0.6, 1.0);

      PainterUtils.drawBone(
        canvas,
        startOffset,
        endOffset,
        bone.color,
        strokeWidth: OverlayConfig.boneStrokeWidth,
        opacity: opacity,
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Joints
  // ─────────────────────────────────────────────────────────────────────────

  void _drawJoints(Canvas canvas, Size size, PoseData pose) {
    for (final entry in pose.landmarks.entries) {
      final joint = entry.value;
      if (!joint.isReliable) continue;

      final center = joint.toOffset(size);

      // Choose joint colour by body region.
      final color = _jointColor(entry.key);

      // Head landmarks are drawn smaller to avoid cluttering the face area.
      final isHeadLandmark = _isHeadLandmark(entry.key);
      final radius = isHeadLandmark
          ? OverlayConfig.jointRadius * 0.65
          : OverlayConfig.jointRadius;

      PainterUtils.drawJoint(
        canvas,
        center,
        color,
        radius:     radius,
        likelihood: joint.likelihood,
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  Color _jointColor(PoseLandmarkType type) {
    if (_isHeadLandmark(type))   return AppColors.neonCyan;
    if (_isArmLandmark(type))    return AppColors.neonPurple;
    if (_isLegLandmark(type))    return AppColors.neonGreen;
    return AppColors.neonBlue; // torso
  }

  bool _isHeadLandmark(PoseLandmarkType t) {
    return const {
      PoseLandmarkType.nose,
      PoseLandmarkType.leftEye,        PoseLandmarkType.rightEye,
      PoseLandmarkType.leftEyeInner,   PoseLandmarkType.rightEyeInner,
      PoseLandmarkType.leftEyeOuter,   PoseLandmarkType.rightEyeOuter,
      PoseLandmarkType.leftEar,        PoseLandmarkType.rightEar,
      PoseLandmarkType.leftMouth,      PoseLandmarkType.rightMouth,
    }.contains(t);
  }

  bool _isArmLandmark(PoseLandmarkType t) {
    return const {
      PoseLandmarkType.leftShoulder,   PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftElbow,      PoseLandmarkType.rightElbow,
      PoseLandmarkType.leftWrist,      PoseLandmarkType.rightWrist,
      PoseLandmarkType.leftThumb,      PoseLandmarkType.rightThumb,
      PoseLandmarkType.leftIndex,      PoseLandmarkType.rightIndex,
      PoseLandmarkType.leftPinky,      PoseLandmarkType.rightPinky,
    }.contains(t);
  }

  bool _isLegLandmark(PoseLandmarkType t) {
    return const {
      PoseLandmarkType.leftHip,        PoseLandmarkType.rightHip,
      PoseLandmarkType.leftKnee,       PoseLandmarkType.rightKnee,
      PoseLandmarkType.leftAnkle,      PoseLandmarkType.rightAnkle,
      PoseLandmarkType.leftHeel,       PoseLandmarkType.rightHeel,
      PoseLandmarkType.leftFootIndex,  PoseLandmarkType.rightFootIndex,
    }.contains(t);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // shouldRepaint — timestamp guard for 30-FPS efficiency
  // ─────────────────────────────────────────────────────────────────────────

  @override
  bool shouldRepaint(SkeletonPainter oldDelegate) {
    // Repaint only when a new pose frame arrives.
    return poseData?.timestamp != oldDelegate.poseData?.timestamp;
  }
}

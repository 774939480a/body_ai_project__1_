// lib/math/body_math.dart
// ─────────────────────────────────────────────────────────────────────────────
// BodyMath — stateless utility class with all geometric operations needed by
// the MeasurementEngine and PostureEngine.
//
// All methods accept [JointPoint] with normalised [0,1] coordinates and a
// [Size canvasSize] to convert to real pixel distances.
//
// Design: pure static methods — no state, fully testable.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../models/joint_point.dart';

class BodyMath {
  BodyMath._();

  // ─────────────────────────────────────────────────────────────────────────
  // Distance calculations
  // ─────────────────────────────────────────────────────────────────────────

  /// Euclidean pixel distance between two [JointPoint]s scaled to [canvas].
  ///
  /// Uses separate x/y scaling because the canvas may not be square:
  ///   dx = (a.x - b.x) * canvasWidth
  ///   dy = (a.y - b.y) * canvasHeight
  static double pixelDistance(JointPoint a, JointPoint b, Size canvas) {
    final dx = (a.x - b.x) * canvas.width;
    final dy = (a.y - b.y) * canvas.height;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Sum of distances along a chain of joints (e.g. shoulder → elbow → wrist).
  ///
  /// Returns null if any joint in [chain] is null.
  static double? chainPixelDistance(
    List<JointPoint?> chain,
    Size canvas,
  ) {
    if (chain.length < 2) return null;
    double total = 0.0;
    for (int i = 0; i < chain.length - 1; i++) {
      final a = chain[i];
      final b = chain[i + 1];
      if (a == null || b == null) return null;
      total += pixelDistance(a, b, canvas);
    }
    return total;
  }

  /// Horizontal-only pixel distance (for width measurements).
  /// Uses only the x component so perspective distortion in y is excluded.
  static double horizontalPixelDistance(
    JointPoint a,
    JointPoint b,
    Size canvas,
  ) {
    return ((a.x - b.x) * canvas.width).abs();
  }

  /// Vertical-only pixel distance (for height/length measurements).
  static double verticalPixelDistance(
    JointPoint a,
    JointPoint b,
    Size canvas,
  ) {
    return ((a.y - b.y) * canvas.height).abs();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Angle calculations
  // ─────────────────────────────────────────────────────────────────────────

  /// Angle (in degrees) at vertex [b] formed by rays [b→a] and [b→c].
  ///
  /// Uses the dot-product formula:
  ///   cos(θ) = (ba · bc) / (|ba| · |bc|)
  ///
  /// Returns null if any point is null or the vectors are zero-length.
  static double? angleDeg(
    JointPoint? a,
    JointPoint? b,
    JointPoint? c,
    Size canvas,
  ) {
    if (a == null || b == null || c == null) return null;

    // Vectors in pixel space
    final bax = (a.x - b.x) * canvas.width;
    final bay = (a.y - b.y) * canvas.height;
    final bcx = (c.x - b.x) * canvas.width;
    final bcy = (c.y - b.y) * canvas.height;

    final dot   = bax * bcx + bay * bcy;
    final magBA = math.sqrt(bax * bax + bay * bay);
    final magBC = math.sqrt(bcx * bcx + bcy * bcy);

    if (magBA < 1e-6 || magBC < 1e-6) return null;

    // Clamp to [-1, 1] to guard against floating-point rounding past ±1.
    final cosTheta = (dot / (magBA * magBC)).clamp(-1.0, 1.0);
    return math.acos(cosTheta) * (180.0 / math.pi);
  }

  /// Signed angle (degrees) of the line [a→b] relative to the horizontal axis.
  /// Positive = downward slope (y increases downward in screen coordinates).
  /// Range: -90° to +90°.
  static double lineAngleDeg(JointPoint a, JointPoint b, Size canvas) {
    final dx = (b.x - a.x) * canvas.width;
    final dy = (b.y - a.y) * canvas.height;
    return math.atan2(dy, dx) * (180.0 / math.pi);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Midpoint
  // ─────────────────────────────────────────────────────────────────────────

  /// Midpoint between [a] and [b].
  /// Returns null if either point is null.
  static JointPoint? midpoint(
    JointPoint? a,
    JointPoint? b,
    PoseLandmarkType type,
  ) {
    if (a == null || b == null) return null;
    return JointPoint(
      type:       type,
      x:          (a.x + b.x) / 2.0,
      y:          (a.y + b.y) / 2.0,
      z:          (a.z + b.z) / 2.0,
      likelihood: math.min(a.likelihood, b.likelihood),
    );
  }

  /// Canvas-space [Offset] midpoint between two joints (for painting).
  static Offset? midpointOffset(
    JointPoint? a,
    JointPoint? b,
    Size canvas,
  ) {
    if (a == null || b == null) return null;
    return Offset(
      ((a.x + b.x) / 2.0) * canvas.width,
      ((a.y + b.y) / 2.0) * canvas.height,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Symmetry & tilt
  // ─────────────────────────────────────────────────────────────────────────

  /// Tilt angle of a horizontal body axis (e.g. shoulders) in degrees.
  ///
  /// A perfect level axis returns 0°.
  /// Positive = right side lower than left.
  static double? horizontalTiltDeg(
    JointPoint? left,
    JointPoint? right,
    Size canvas,
  ) {
    if (left == null || right == null) return null;
    // In screen space: y increases downward.
    // If rightY > leftY, right is lower → positive tilt.
    final dy = (right.y - left.y) * canvas.height;
    final dx = (right.x - left.x) * canvas.width;
    if (dx.abs() < 1e-6) return 90.0;
    return math.atan2(dy, dx) * (180.0 / math.pi);
  }

  /// Symmetry ratio: how much larger the left side is vs the right.
  ///
  /// Returns a value centred at 0.0:
  ///   0.0  = perfectly symmetrical
  ///  +1.0  = fully left-dominant
  ///  -1.0  = fully right-dominant
  ///
  /// [leftLen] / [rightLen] are pixel lengths of mirrored body segments.
  static double? symmetryRatio(double? leftLen, double? rightLen) {
    if (leftLen == null || rightLen == null) return null;
    final total = leftLen + rightLen;
    if (total < 1e-6) return null;
    return (leftLen - rightLen) / total;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Z-axis depth estimation
  // ─────────────────────────────────────────────────────────────────────────

  /// Estimates Z-axis rotation (depth skew) from the shoulder width ratio.
  ///
  /// When the user faces the camera squarely, both shoulders are visible and
  /// their projected width is at its maximum.  As they rotate away from the
  /// camera, the visible shoulder-to-shoulder distance shrinks.
  ///
  /// [observedWidthPx]  — current pixel distance between shoulders.
  /// [expectedWidthPx]  — calibrated "full-face" shoulder width in pixels
  ///                      (set during calibration).
  ///
  /// Returns a skew value [0.0, 1.0]:
  ///   0.0 = facing camera directly
  ///   1.0 = fully side-on (90° rotation)
  ///
  /// Compare against [PostureConfig.zSkewThreshold] to decide whether to
  /// trigger "UNSTABLE ROTATION".
  static double? zSkewRatio({
    required double observedWidthPx,
    required double expectedWidthPx,
  }) {
    if (expectedWidthPx < 1e-6) return null;
    final ratio = (observedWidthPx / expectedWidthPx).clamp(0.0, 1.0);
    // 1 - ratio: 0 when fully visible, 1 when fully side-on.
    return 1.0 - ratio;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Unit conversion helpers (pixel ↔ cm)
  // ─────────────────────────────────────────────────────────────────────────

  /// Convert pixel distance to centimetres using the calibration scale.
  /// [pixelsPerCm] comes from [CalibrationData].
  static double? pixelsToCm(double? pixels, double pixelsPerCm) {
    if (pixels == null || pixelsPerCm <= 0) return null;
    return pixels / pixelsPerCm;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Spine axis
  // ─────────────────────────────────────────────────────────────────────────

  /// Computes the spine tilt: angle of the line connecting the mid-shoulder
  /// point to the mid-hip point, relative to vertical (90° = perfectly upright).
  ///
  /// Deviation from 90° gives the forward/back lean in degrees.
  static double? spineTiltDeg(
    JointPoint? leftShoulder,
    JointPoint? rightShoulder,
    JointPoint? leftHip,
    JointPoint? rightHip,
    Size canvas,
  ) {
    final shoulderMid = midpoint(
      leftShoulder, rightShoulder,
      PoseLandmarkType.nose, // placeholder type for virtual joint
    );
    final hipMid = midpoint(
      leftHip, rightHip,
      PoseLandmarkType.nose,
    );
    if (shoulderMid == null || hipMid == null) return null;

    final dx = (hipMid.x - shoulderMid.x) * canvas.width;
    final dy = (hipMid.y - shoulderMid.y) * canvas.height;

    // Angle of spine vector relative to vertical (pointing down = 90°).
    final angleFromHoriz = math.atan2(dy, dx) * (180.0 / math.pi);
    // Convert to deviation from vertical: 90° - atan(dx/dy)
    return (angleFromHoriz - 90.0).abs();
  }
}

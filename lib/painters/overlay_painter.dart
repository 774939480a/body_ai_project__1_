// lib/painters/overlay_painter.dart
// ─────────────────────────────────────────────────────────────────────────────
// OverlayPainter — draws all data-driven overlays on top of the skeleton:
//
//   1. Alignment axis lines (shoulder axis, hip axis — horizontal dashes)
//   2. Joint angle arcs (elbows, knees) with degree labels
//   3. Measurement span lines with cm labels at key body segments
//   4. Body height indicator (vertical bracket on the left edge)
//   5. Posture status banner (drawn at the top of the body)
//
// Draw order matches visual depth — alignment lines first (deepest),
// angle arcs second, measurement labels last (closest to viewer).
//
// Performance:
//   • shouldRepaint uses timestamp comparison (same strategy as SkeletonPainter).
//   • All TextPainter objects are created per-paint-call but are very cheap
//     compared to the GPU cost of MaskFilter.blur used in SkeletonPainter.
//   • No state is held — this is a pure function from data → canvas.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../core/themes/app_theme.dart';
import '../models/joint_point.dart';
import '../models/measurement_result.dart';
import '../models/pose_data.dart';
import 'painter_utils.dart';

class OverlayPainter extends CustomPainter {
  const OverlayPainter({
    required this.poseData,
    required this.measurement,
  });

  final PoseData?         poseData;
  final MeasurementResult measurement;

  // ─────────────────────────────────────────────────────────────────────────
  // Paint entry point
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    final pose = poseData;
    if (pose == null || pose.landmarks.isEmpty) return;

    // ── 1. Alignment axis lines ─────────────────────────────────────────
    _drawAlignmentAxes(canvas, size, pose);

    // ── 2. Joint angle arcs ─────────────────────────────────────────────
    _drawAngleArcs(canvas, size, pose);

    // ── 3. Measurement span lines + labels ──────────────────────────────
    if (measurement.isCalibrated) {
      _drawMeasurementSpans(canvas, size, pose, measurement);
    }

    // ── 4. Height indicator ─────────────────────────────────────────────
    if (measurement.isCalibrated) {
      _drawHeightIndicator(canvas, size, pose, measurement.bodyHeightCm);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 1. Alignment axes
  // ─────────────────────────────────────────────────────────────────────────

  void _drawAlignmentAxes(Canvas canvas, Size size, PoseData pose) {
    // Shoulder horizontal axis.
    final ls = pose.leftShoulder;
    final rs = pose.rightShoulder;
    if (ls != null && rs != null && ls.isReliable && rs.isReliable) {
      final midY  = ((ls.y + rs.y) / 2) * size.height;
      final midX  = ((ls.x + rs.x) / 2) * size.width;
      PainterUtils.drawHorizontalAxis(
        canvas,
        Offset(midX, midY),
        size.width * 0.40,
        AppColors.neonBlue,
      );
    }

    // Hip horizontal axis.
    final lh = pose.leftHip;
    final rh = pose.rightHip;
    if (lh != null && rh != null && lh.isReliable && rh.isReliable) {
      final midY = ((lh.y + rh.y) / 2) * size.height;
      final midX = ((lh.x + rh.x) / 2) * size.width;
      PainterUtils.drawHorizontalAxis(
        canvas,
        Offset(midX, midY),
        size.width * 0.35,
        AppColors.neonBlue.withOpacity(0.7),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 2. Joint angle arcs
  // ─────────────────────────────────────────────────────────────────────────

  void _drawAngleArcs(Canvas canvas, Size size, PoseData pose) {
    // Left elbow.
    _tryDrawArc(
      canvas, size,
      a:      pose.leftShoulder,
      vertex: pose.leftElbow,
      c:      pose.leftWrist,
      angle:  measurement.elbowAngleLeft,
      color:  AppColors.neonPurple,
    );

    // Right elbow.
    _tryDrawArc(
      canvas, size,
      a:      pose.rightShoulder,
      vertex: pose.rightElbow,
      c:      pose.rightWrist,
      angle:  measurement.elbowAngleRight,
      color:  AppColors.neonPurple,
    );

    // Left knee.
    _tryDrawArc(
      canvas, size,
      a:      pose.leftHip,
      vertex: pose.leftKnee,
      c:      pose.leftAnkle,
      angle:  measurement.kneeAngleLeft,
      color:  AppColors.neonGreen,
      arcRadius: 18.0,
    );

    // Right knee.
    _tryDrawArc(
      canvas, size,
      a:      pose.rightHip,
      vertex: pose.rightKnee,
      c:      pose.rightAnkle,
      angle:  measurement.kneeAngleRight,
      color:  AppColors.neonGreen,
      arcRadius: 18.0,
    );

    // Left shoulder.
    _tryDrawArc(
      canvas, size,
      a:      pose.leftElbow,
      vertex: pose.leftShoulder,
      c:      pose.leftHip,
      angle:  measurement.shoulderAngleLeft,
      color:  AppColors.neonCyan,
      arcRadius: 16.0,
    );

    // Right shoulder.
    _tryDrawArc(
      canvas, size,
      a:      pose.rightElbow,
      vertex: pose.rightShoulder,
      c:      pose.rightHip,
      angle:  measurement.shoulderAngleRight,
      color:  AppColors.neonCyan,
      arcRadius: 16.0,
    );
  }

  void _tryDrawArc(
    Canvas canvas,
    Size size, {
    required JointPoint? a,
    required JointPoint? vertex,
    required JointPoint? c,
    required double? angle,
    required Color color,
    double arcRadius = 22.0,
  }) {
    if (a == null || vertex == null || c == null || angle == null) return;
    if (!a.isReliable || !vertex.isReliable || !c.isReliable) return;

    PainterUtils.drawAngleArc(
      canvas,
      vertex.toOffset(size),
      a.toOffset(size),
      c.toOffset(size),
      angle,
      color,
      arcRadius: arcRadius,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 3. Measurement span lines
  // ─────────────────────────────────────────────────────────────────────────

  void _drawMeasurementSpans(
    Canvas canvas,
    Size size,
    PoseData pose,
    MeasurementResult m,
  ) {
    // ── Shoulder width ─────────────────────────────────────────────────
    _tryDrawSpan(
      canvas, size,
      a:       pose.leftShoulder,
      b:       pose.rightShoulder,
      valueCm: m.shoulderWidthCm,
      color:   AppColors.neonCyan,
      yOffset: -16.0,   // draw label above the shoulder line
    );

    // ── Hip width ──────────────────────────────────────────────────────
    _tryDrawSpan(
      canvas, size,
      a:       pose.leftHip,
      b:       pose.rightHip,
      valueCm: m.hipWidthCm,
      color:   AppColors.neonBlue,
      yOffset: 14.0,    // draw label below the hip line
    );

    // ── Left arm (elbow marker) ────────────────────────────────────────
    _tryDrawLimbLabel(
      canvas, size,
      joint:   pose.leftElbow,
      label:   'L.Arm',
      valueCm: m.leftArmLengthCm,
      color:   AppColors.neonPurple,
      xOffset: -46.0,   // push label to the left
    );

    // ── Right arm (elbow marker) ───────────────────────────────────────
    _tryDrawLimbLabel(
      canvas, size,
      joint:   pose.rightElbow,
      label:   'R.Arm',
      valueCm: m.rightArmLengthCm,
      color:   AppColors.neonPurple,
      xOffset:  46.0,
    );

    // ── Torso (mid-torso label) ────────────────────────────────────────
    final shoulderMid = _midOffset(pose.leftShoulder, pose.rightShoulder, size);
    final hipMid      = _midOffset(pose.leftHip,      pose.rightHip,      size);
    if (shoulderMid != null && hipMid != null && m.torsoLengthCm != null) {
      final torsoMid = (shoulderMid + hipMid) / 2;
      // Label offset to the right of body axis.
      final rightEdge = torsoMid + const Offset(50, 0);
      PainterUtils.drawLabel(
        canvas,
        'Torso\n${m.torsoLengthCm!.toStringAsFixed(1)} cm',
        rightEdge,
        AppColors.neonBlue,
        fontSize: 9.0,
        showBorder: true,
      );
    }

    // ── Left thigh (knee label) ────────────────────────────────────────
    _tryDrawLimbLabel(
      canvas, size,
      joint:   pose.leftKnee,
      label:   'L.Thigh',
      valueCm: m.leftThighCm,
      color:   AppColors.neonGreen,
      xOffset: -48.0,
    );

    // ── Right thigh (knee label) ───────────────────────────────────────
    _tryDrawLimbLabel(
      canvas, size,
      joint:   pose.rightKnee,
      label:   'R.Thigh',
      valueCm: m.rightThighCm,
      color:   AppColors.neonGreen,
      xOffset:  48.0,
    );
  }

  void _tryDrawSpan(
    Canvas canvas,
    Size size, {
    required JointPoint? a,
    required JointPoint? b,
    required double? valueCm,
    required Color color,
    double yOffset = 0,
  }) {
    if (a == null || b == null) return;
    if (!a.isReliable || !b.isReliable) return;

    final ao = a.toOffset(size) + Offset(0, yOffset);
    final bo = b.toOffset(size) + Offset(0, yOffset);

    PainterUtils.drawMeasurementSpan(canvas, ao, bo, valueCm, color);
  }

  void _tryDrawLimbLabel(
    Canvas canvas,
    Size size, {
    required JointPoint? joint,
    required String label,
    required double? valueCm,
    required Color color,
    double xOffset = 0,
    double yOffset = 0,
  }) {
    if (joint == null || !joint.isReliable || valueCm == null) return;

    final pos = joint.toOffset(size) + Offset(xOffset, yOffset);
    PainterUtils.drawLabel(
      canvas,
      '$label\n${valueCm.toStringAsFixed(1)} cm',
      pos,
      color,
      fontSize: 9.0,
      showBorder: true,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 4. Height indicator (vertical bracket on left side)
  // ─────────────────────────────────────────────────────────────────────────

  void _drawHeightIndicator(
    Canvas canvas,
    Size size,
    PoseData pose,
    double? heightCm,
  ) {
    if (heightCm == null) return;

    final nose = pose.nose;
    final la   = pose.leftAnkle;
    final ra   = pose.rightAnkle;

    if (nose == null || la == null || ra == null) return;
    if (!nose.isReliable || !la.isReliable || !ra.isReliable) return;

    final topY    = nose.y * size.height;
    final bottomY = ((la.y + ra.y) / 2) * size.height;

    // Position the bracket on the far left of the body (left shoulder x - margin).
    final ls = pose.leftShoulder;
    final bracketX = ls != null && ls.isReliable
        ? (ls.x * size.width) - 28.0
        : 20.0;

    final bracketX2 = bracketX - 8.0;

    // Vertical bracket line.
    PainterUtils.drawDashedLine(
      canvas,
      Offset(bracketX2, topY),
      Offset(bracketX2, bottomY),
      AppColors.neonCyan.withOpacity(0.6),
      strokeWidth: 1.0,
      dashLen: 6,
      gapLen: 4,
    );

    // Top and bottom ticks.
    final tickPaint = Paint()
      ..color       = AppColors.neonCyan.withOpacity(0.7)
      ..strokeWidth = 1.5
      ..strokeCap   = StrokeCap.round;
    canvas.drawLine(
      Offset(bracketX2 - 4, topY),
      Offset(bracketX2 + 4, topY),
      tickPaint,
    );
    canvas.drawLine(
      Offset(bracketX2 - 4, bottomY),
      Offset(bracketX2 + 4, bottomY),
      tickPaint,
    );

    // Height label at midpoint.
    final midY = (topY + bottomY) / 2;
    PainterUtils.drawLabel(
      canvas,
      'H\n${heightCm.toStringAsFixed(1)}cm',
      Offset(bracketX2 - 22, midY),
      AppColors.neonCyan,
      fontSize: 9.0,
      showBorder: true,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  Offset? _midOffset(JointPoint? a, JointPoint? b, Size size) {
    if (a == null || b == null) return null;
    if (!a.isReliable || !b.isReliable) return null;
    return Offset(
      ((a.x + b.x) / 2) * size.width,
      ((a.y + b.y) / 2) * size.height,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // shouldRepaint
  // ─────────────────────────────────────────────────────────────────────────

  @override
  bool shouldRepaint(OverlayPainter oldDelegate) {
    return measurement.timestamp != oldDelegate.measurement.timestamp ||
           poseData?.timestamp   != oldDelegate.poseData?.timestamp;
  }
}

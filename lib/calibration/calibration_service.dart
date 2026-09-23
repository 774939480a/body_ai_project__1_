// lib/calibration/calibration_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// CalibrationService — manages the active [CalibrationData] and exposes
// calibration triggers for both supported modes (height / A4 paper).
//
// This service is stateful: it holds the most recent [CalibrationData] and
// broadcasts updates through [calibrationStream] so the UI and measurement
// engine can react without polling.
//
// Calibration flow:
//   Height mode:
//     1. UI calls [calibrateFromHeight(userHeightCm, poseData, canvasSize)].
//     2. Service extracts nose-to-ankle pixel distance from the current pose.
//     3. Creates a new [CalibrationData] and broadcasts it.
//
//   A4 mode (Phase 5 UI will wire this):
//     1. UI calls [calibrateFromA4(a4HeightPixels, canvasSize)].
//     2. Service uses the known A4 dimensions to compute px/cm.
//     3. Creates a new [CalibrationData] and broadcasts it.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:logger/logger.dart';

import '../math/body_math.dart';
import '../models/pose_data.dart';
import 'calibration_data.dart';

// ── Calibration result ────────────────────────────────────────────────────────

/// Result returned by calibration methods — wraps either success or a
/// human-readable failure reason.
sealed class CalibrationResult {
  const CalibrationResult();
}

class CalibrationSuccess extends CalibrationResult {
  const CalibrationSuccess(this.data);
  final CalibrationData data;
}

class CalibrationFailure extends CalibrationResult {
  const CalibrationFailure(this.reason);
  final String reason;
}

// ── CalibrationService ────────────────────────────────────────────────────────

class CalibrationService {
  CalibrationService({required Logger logger}) : _logger = logger;

  final Logger _logger;

  // ── Internal state ────────────────────────────────────────────────────────

  CalibrationData _current = CalibrationData.uncalibrated();

  final StreamController<CalibrationData> _controller =
      StreamController<CalibrationData>.broadcast();

  // ── Public API ────────────────────────────────────────────────────────────

  /// The most recent [CalibrationData] — starts as uncalibrated.
  CalibrationData get current => _current;

  /// Broadcasts every time calibration changes.
  Stream<CalibrationData> get calibrationStream => _controller.stream;

  // ── Height-based calibration ──────────────────────────────────────────────

  /// Calibrate using the user's known height.
  ///
  /// [userHeightCm] — height the user entered (must be 50–250 cm).
  /// [poseData]     — current fully-detected pose (must be measurement-ready).
  /// [canvasSize]   — current display canvas size.
  ///
  /// Returns [CalibrationSuccess] if all joints are visible and the pixel
  /// distance is plausible, or [CalibrationFailure] with a reason string.
  CalibrationResult calibrateFromHeight({
    required double userHeightCm,
    required PoseData poseData,
    required Size canvasSize,
  }) {
    _logger.i('[CalibrationService] Attempting height calibration: '
        '${userHeightCm.toStringAsFixed(1)} cm');

    // ── Validation ────────────────────────────────────────────────────────
    if (userHeightCm < 50 || userHeightCm > 250) {
      return const CalibrationFailure(
        'Height must be between 50 cm and 250 cm.',
      );
    }

    if (!poseData.isMeasurementReady) {
      return const CalibrationFailure(
        'Stand fully visible in the frame before calibrating.',
      );
    }

    // ── Extract nose → ankle midpoint ─────────────────────────────────────
    final nose       = poseData.nose;
    final leftAnkle  = poseData.leftAnkle;
    final rightAnkle = poseData.rightAnkle;

    if (nose == null || leftAnkle == null || rightAnkle == null) {
      return const CalibrationFailure(
        'Head and both ankles must be visible.',
      );
    }

    // Midpoint of both ankles as floor reference.
    final ankleMid = BodyMath.midpoint(
      leftAnkle,
      rightAnkle,
      PoseLandmarkType.leftAnkle,
    )!;

    final noseToAnklePx = BodyMath.pixelDistance(nose, ankleMid, canvasSize);

    // ── Sanity check ─────────────────────────────────────────────────────
    // The pixel span should be at least 30 % of the canvas height.
    if (noseToAnklePx < canvasSize.height * 0.30) {
      return const CalibrationFailure(
        'Stand further back so your full body is visible.',
      );
    }

    // ── Build CalibrationData ─────────────────────────────────────────────
    final data = CalibrationData.fromHeight(
      userHeightCm:  userHeightCm,
      noseToAnklePx: noseToAnklePx,
      canvas:        canvasSize,
    );

    _logger.i(
      '[CalibrationService] Height calibration OK — '
      '${data.pixelsPerCm.toStringAsFixed(2)} px/cm',
    );

    _setCurrent(data);
    return CalibrationSuccess(data);
  }

  // ── A4 paper calibration ──────────────────────────────────────────────────

  /// Calibrate using a detected A4 paper.
  ///
  /// [a4HeightPixels] — pixel height of the A4 paper on the current canvas.
  /// [canvasSize]     — current display canvas size.
  ///
  /// The [a4HeightPixels] measurement is determined by Phase 5 UI
  /// (user drags guide lines to match the paper edges).
  CalibrationResult calibrateFromA4({
    required double a4HeightPixels,
    required Size canvasSize,
  }) {
    _logger.i('[CalibrationService] Attempting A4 calibration: '
        '${a4HeightPixels.toStringAsFixed(1)} px');

    if (a4HeightPixels < 20) {
      return const CalibrationFailure(
        'A4 measurement too small — hold the paper closer to the camera.',
      );
    }

    final data = CalibrationData.fromA4(
      a4HeightPixels: a4HeightPixels,
      canvas:         canvasSize,
    );

    _logger.i(
      '[CalibrationService] A4 calibration OK — '
      '${data.pixelsPerCm.toStringAsFixed(2)} px/cm',
    );

    _setCurrent(data);
    return CalibrationSuccess(data);
  }

  // ── Baseline shoulder width ───────────────────────────────────────────────

  /// Records the calibration-time shoulder width in pixels.
  ///
  /// This value is stored in the service (not in [CalibrationData]) and used
  /// by [PostureEngine] for Z-skew ratio calculation.  It is set automatically
  /// when [calibrateFromHeight] succeeds.
  double? _calibratedShoulderWidthPx;
  double? get calibratedShoulderWidthPx => _calibratedShoulderWidthPx;

  /// Call after a successful height calibration to record the shoulder
  /// width baseline for Z-axis skew detection.
  void recordShoulderBaseline(PoseData pose, Size canvas) {
    final ls = pose.leftShoulder;
    final rs = pose.rightShoulder;
    if (ls == null || rs == null) return;
    _calibratedShoulderWidthPx = BodyMath.pixelDistance(ls, rs, canvas);
    _logger.d('[CalibrationService] Shoulder baseline: '
        '${_calibratedShoulderWidthPx!.toStringAsFixed(1)} px');
  }

  // ── Reset ─────────────────────────────────────────────────────────────────

  /// Clear calibration state — returns to uncalibrated.
  void reset() {
    _calibratedShoulderWidthPx = null;
    _setCurrent(CalibrationData.uncalibrated());
    _logger.i('[CalibrationService] Reset to uncalibrated.');
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    await _controller.close();
  }

  // ── Private ───────────────────────────────────────────────────────────────

  void _setCurrent(CalibrationData data) {
    _current = data;
    if (!_controller.isClosed) {
      _controller.add(data);
    }
  }
}

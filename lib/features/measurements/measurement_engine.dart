// lib/features/measurements/measurement_engine.dart
// ─────────────────────────────────────────────────────────────────────────────
// MeasurementEngine — the central computation engine for Phase 3.
//
// Responsibilities:
//   • Accept a (smoothed) [PoseData] and the active [CalibrationData].
//   • Compute all body measurements in centimetres via [BodyMath].
//   • Compute all joint angles in degrees.
//   • Package results into an immutable [MeasurementResult].
//   • Apply a second-level temporal smoothing buffer so that individual
//     outlier frames don't spike the displayed numbers.
//   • Expose results as a [Stream<MeasurementResult>] for the UI.
//
// Design:
//   • Stateless calculation methods (pure functions) — easy to unit-test.
//   • Stateful smoothing buffer (rolling window average over recent frames).
//   • Subscribes to [PoseDetectorService.poseStream] internally.
//
// Threading:
//   • All computations are O(1) floating-point operations on 33 landmarks.
//   • Safe to run on the main isolate — no blocking I/O.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:logger/logger.dart';

import '../../calibration/calibration_data.dart';
import '../../calibration/calibration_service.dart';
import '../../core/constants/app_constants.dart';
import '../../math/body_math.dart';
import '../../math/pose_smoother.dart';
import '../../models/joint_point.dart';
import '../../models/measurement_result.dart';
import '../../models/pose_data.dart';
import '../../services/pose_detector_service.dart';

class MeasurementEngine {
  MeasurementEngine({
    required PoseDetectorService poseDetectorService,
    required CalibrationService  calibrationService,
    required Logger logger,
  })  : _poseDetector    = poseDetectorService,
        _calibrationSvc  = calibrationService,
        _logger          = logger;

  final PoseDetectorService _poseDetector;
  final CalibrationService  _calibrationSvc;
  final Logger              _logger;

  // ── Smoother (Phase 2 landmark smoothing) ─────────────────────────────────
  final PoseSmoother _smoother = PoseSmoother();

  // ── Temporal smoothing buffer ─────────────────────────────────────────────
  // Rolling window of recent [MeasurementResult] values.
  // The published result is an average across the window to dampen outliers.
  final Queue<MeasurementResult> _buffer = Queue();

  // ── Stream plumbing ───────────────────────────────────────────────────────
  StreamSubscription<PoseData?>? _poseSub;
  final StreamController<MeasurementResult> _resultController =
      StreamController<MeasurementResult>.broadcast();

  Stream<MeasurementResult> get measurementStream => _resultController.stream;

  // ── Canvas size ───────────────────────────────────────────────────────────
  // Updated by the screen each frame via [updateCanvasSize].
  Size _canvasSize = const Size(1, 1);

  // ── State ─────────────────────────────────────────────────────────────────
  bool _isRunning  = false;
  bool _isDisposed = false;
  MeasurementResult _lastResult = MeasurementResult.empty();

  /// Set externally by CameraScreen when PostureEngine reports suspension.
  bool isSuspendedByPosture = false;

  MeasurementResult get lastResult => _lastResult;

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  /// Start the engine — subscribe to the pose stream.
  void start() {
    if (_isRunning || _isDisposed) return;
    _isRunning = true;

    _poseSub = _poseDetector.poseStream.listen(
      _onPose,
      onError: (Object e) =>
          _logger.e('[MeasurementEngine] Pose stream error', error: e),
    );

    _logger.i('[MeasurementEngine] Started.');
  }

  /// Update the canvas dimensions (call from the build method / LayoutBuilder).
  void updateCanvasSize(Size size) {
    if (size == _canvasSize) return;
    _canvasSize = size;
  }

  Future<void> dispose() async {
    _isDisposed = true;
    _isRunning  = false;
    await _poseSub?.cancel();
    await _resultController.close();
    _logger.i('[MeasurementEngine] Disposed.');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Pose → MeasurementResult pipeline
  // ─────────────────────────────────────────────────────────────────────────

  void _onPose(PoseData? rawPose) {
    if (_isDisposed || _resultController.isClosed) return;

    // No pose detected — reset smoother and emit empty result.
    if (rawPose == null) {
      _smoother.reset();
      _buffer.clear();
      final empty = MeasurementResult.empty();
      _lastResult = empty;
      _resultController.add(empty);
      return;
    }

    // ── 0. Check posture suspension (Phase 5) ─────────────────────────
    // When the user has rotated too far from the camera, measurements are
    // frozen at their last valid value rather than emitting junk data.
    if (isSuspendedByPosture) return;
    final pose = _smoother.smooth(rawPose);

    // ── 2. Compute raw measurements ───────────────────────────────────────
    final raw = _compute(pose, _calibrationSvc.current, _canvasSize);

    // ── 3. Temporal smoothing buffer ──────────────────────────────────────
    _buffer.addLast(raw);
    if (_buffer.length > MeasurementConfig.smoothingWindowSize) {
      _buffer.removeFirst();
    }

    // ── 4. Average across buffer ──────────────────────────────────────────
    final averaged = _average(raw, _buffer);

    // ── 5. Publish ────────────────────────────────────────────────────────
    _lastResult = averaged;
    _resultController.add(averaged);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Core computation — pure function
  // ─────────────────────────────────────────────────────────────────────────

  MeasurementResult _compute(
    PoseData pose,
    CalibrationData cal,
    Size canvas,
  ) {
    final toCm = cal.isCalibrated
        ? (double px) => px / cal.pixelsPerCm
        : (double _) => null as double?;  // returns null when uncalibrated

    // Shorthand for converting a nullable pixel distance to cm.
    double? pxToCm(double? px) =>
        (px == null || !cal.isCalibrated) ? null : px / cal.pixelsPerCm;

    // ── Widths ─────────────────────────────────────────────────────────────
    final shoulderPx = _safeDistance(pose.leftShoulder, pose.rightShoulder, canvas);
    final hipPx      = _safeDistance(pose.leftHip,      pose.rightHip,      canvas);
    // Chest width is approximated as 85 % of shoulder width.
    final chestPx    = shoulderPx != null ? shoulderPx * 0.85 : null;

    // ── Arm lengths ────────────────────────────────────────────────────────
    final leftArmPx = BodyMath.chainPixelDistance(
      [pose.leftShoulder, pose.leftElbow, pose.leftWrist], canvas,
    );
    final rightArmPx = BodyMath.chainPixelDistance(
      [pose.rightShoulder, pose.rightElbow, pose.rightWrist], canvas,
    );
    final leftForearmPx  = _safeDistance(pose.leftElbow,  pose.leftWrist,  canvas);
    final rightForearmPx = _safeDistance(pose.rightElbow, pose.rightWrist, canvas);

    // ── Torso ──────────────────────────────────────────────────────────────
    final shoulderMid = BodyMath.midpoint(
      pose.leftShoulder, pose.rightShoulder,
      PoseLandmarkType.nose,
    );
    final hipMid = BodyMath.midpoint(
      pose.leftHip, pose.rightHip,
      PoseLandmarkType.leftHip,
    );
    final torsoPx = _safeDistance(shoulderMid, hipMid, canvas);

    // ── Legs ───────────────────────────────────────────────────────────────
    final leftThighPx  = _safeDistance(pose.leftHip,   pose.leftKnee,   canvas);
    final rightThighPx = _safeDistance(pose.rightHip,  pose.rightKnee,  canvas);
    final leftShinPx   = _safeDistance(pose.leftKnee,  pose.leftAnkle,  canvas);
    final rightShinPx  = _safeDistance(pose.rightKnee, pose.rightAnkle, canvas);

    // ── Body height ────────────────────────────────────────────────────────
    // nose → ankle midpoint (then adjusted by calibration's 0.94 factor).
    final ankleMid = BodyMath.midpoint(
      pose.leftAnkle, pose.rightAnkle,
      PoseLandmarkType.leftAnkle,
    );
    double? heightPx;
    if (pose.nose != null && ankleMid != null) {
      heightPx = BodyMath.pixelDistance(pose.nose!, ankleMid, canvas);
      // Undo the 0.94 nose-to-ankle fraction applied during calibration
      // so the output is the true full height.
      heightPx = heightPx / 0.94;
    }

    // ── Joint angles ───────────────────────────────────────────────────────
    final elbowL  = BodyMath.angleDeg(
      pose.leftShoulder, pose.leftElbow, pose.leftWrist, canvas,
    );
    final elbowR  = BodyMath.angleDeg(
      pose.rightShoulder, pose.rightElbow, pose.rightWrist, canvas,
    );
    final kneeL   = BodyMath.angleDeg(
      pose.leftHip, pose.leftKnee, pose.leftAnkle, canvas,
    );
    final kneeR   = BodyMath.angleDeg(
      pose.rightHip, pose.rightKnee, pose.rightAnkle, canvas,
    );
    final shoulderAngleL = BodyMath.angleDeg(
      pose.leftElbow, pose.leftShoulder, pose.leftHip, canvas,
    );
    final shoulderAngleR = BodyMath.angleDeg(
      pose.rightElbow, pose.rightShoulder, pose.rightHip, canvas,
    );
    final hipAngleL = BodyMath.angleDeg(
      pose.leftShoulder, pose.leftHip, pose.leftKnee, canvas,
    );
    final hipAngleR = BodyMath.angleDeg(
      pose.rightShoulder, pose.rightHip, pose.rightKnee, canvas,
    );

    return MeasurementResult(
      timestamp:    pose.timestamp,
      isCalibrated: cal.isCalibrated,

      // cm values
      shoulderWidthCm:  pxToCm(shoulderPx),
      chestWidthCm:     pxToCm(chestPx),
      hipWidthCm:       pxToCm(hipPx),
      leftArmLengthCm:  pxToCm(leftArmPx),
      rightArmLengthCm: pxToCm(rightArmPx),
      leftForearmCm:    pxToCm(leftForearmPx),
      rightForearmCm:   pxToCm(rightForearmPx),
      torsoLengthCm:    pxToCm(torsoPx),
      leftThighCm:      pxToCm(leftThighPx),
      rightThighCm:     pxToCm(rightThighPx),
      leftShinCm:       pxToCm(leftShinPx),
      rightShinCm:      pxToCm(rightShinPx),
      bodyHeightCm:     pxToCm(heightPx),

      // angles
      elbowAngleLeft:    elbowL,
      elbowAngleRight:   elbowR,
      kneeAngleLeft:     kneeL,
      kneeAngleRight:    kneeR,
      shoulderAngleLeft:  shoulderAngleL,
      shoulderAngleRight: shoulderAngleR,
      hipAngleLeft:       hipAngleL,
      hipAngleRight:      hipAngleR,

      // anchor points for overlay labels
      shoulderMidPoint: shoulderMid,
      hipMidPoint:      hipMid,
      leftElbowPoint:   pose.leftElbow,
      rightElbowPoint:  pose.rightElbow,
      leftKneePoint:    pose.leftKnee,
      rightKneePoint:   pose.rightKnee,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Temporal averaging (rolling window)
  // ─────────────────────────────────────────────────────────────────────────

  /// Average nullable double fields across the buffer.
  MeasurementResult _average(
    MeasurementResult latest,
    Queue<MeasurementResult> buffer,
  ) {
    if (buffer.length <= 1) return latest;

    // Helper: compute mean of a nullable field across buffer entries.
    double? mean(double? Function(MeasurementResult) getter) {
      final vals = buffer
          .map(getter)
          .whereType<double>()
          .toList(growable: false);
      if (vals.isEmpty) return null;
      return vals.reduce((a, b) => a + b) / vals.length;
    }

    return MeasurementResult(
      timestamp:    latest.timestamp,
      isCalibrated: latest.isCalibrated,

      shoulderWidthCm:  mean((r) => r.shoulderWidthCm),
      chestWidthCm:     mean((r) => r.chestWidthCm),
      hipWidthCm:       mean((r) => r.hipWidthCm),
      leftArmLengthCm:  mean((r) => r.leftArmLengthCm),
      rightArmLengthCm: mean((r) => r.rightArmLengthCm),
      leftForearmCm:    mean((r) => r.leftForearmCm),
      rightForearmCm:   mean((r) => r.rightForearmCm),
      torsoLengthCm:    mean((r) => r.torsoLengthCm),
      leftThighCm:      mean((r) => r.leftThighCm),
      rightThighCm:     mean((r) => r.rightThighCm),
      leftShinCm:       mean((r) => r.leftShinCm),
      rightShinCm:      mean((r) => r.rightShinCm),
      bodyHeightCm:     mean((r) => r.bodyHeightCm),

      // Angles: not averaged — use latest for responsiveness.
      elbowAngleLeft:    latest.elbowAngleLeft,
      elbowAngleRight:   latest.elbowAngleRight,
      kneeAngleLeft:     latest.kneeAngleLeft,
      kneeAngleRight:    latest.kneeAngleRight,
      shoulderAngleLeft:  latest.shoulderAngleLeft,
      shoulderAngleRight: latest.shoulderAngleRight,
      hipAngleLeft:       latest.hipAngleLeft,
      hipAngleRight:      latest.hipAngleRight,

      // Anchor points from latest.
      shoulderMidPoint: latest.shoulderMidPoint,
      hipMidPoint:      latest.hipMidPoint,
      leftElbowPoint:   latest.leftElbowPoint,
      rightElbowPoint:  latest.rightElbowPoint,
      leftKneePoint:    latest.leftKneePoint,
      rightKneePoint:   latest.rightKneePoint,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns the pixel distance between [a] and [b] only when both are
  /// reliable, else null.
  double? _safeDistance(JointPoint? a, JointPoint? b, Size canvas) {
    if (a == null || b == null) return null;
    if (!a.isReliable || !b.isReliable) return null;
    return BodyMath.pixelDistance(a, b, canvas);
  }
}

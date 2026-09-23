// lib/posture/posture_engine.dart
// ─────────────────────────────────────────────────────────────────────────────
// PostureEngine — analyses real-time body alignment and emits [PostureResult].
//
// Computed metrics (every frame):
//   • Shoulder tilt angle          (signed, degrees)
//   • Spine tilt from vertical     (degrees)
//   • Hip tilt angle               (signed, degrees)
//   • Z-axis skew ratio            (depth rotation, 0–1)
//   • Body symmetry ratio          (-1 to +1)
//
// State machine:
//   UNSTABLE ROTATION (highest priority)
//     └─ z-skew > PostureConfig.zSkewThreshold
//        → suspend measurements, emit UNSTABLE_ROTATION
//   LEANING
//     └─ |shoulderTilt| > maxShoulderTiltDeg
//        OR |spineTilt|  > maxSpineTiltDeg
//        → reset stable counter, emit LEANING_LEFT / LEANING_RIGHT / FORWARD
//   STABLE
//     └─ all metrics within thresholds for ≥ stableFrameCount frames
//        → emit STABLE
//
// Measurement suspension:
//   When [PostureResult.isMeasurementSuspended] is true, [CameraScreen]
//   shows an "UNSTABLE ROTATION" banner and the [MeasurementEngine] skips
//   emitting new values — old values remain frozen on the panel.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';

import '../calibration/calibration_service.dart';
import '../core/constants/app_constants.dart';
import '../math/body_math.dart';
import '../models/pose_data.dart';
import '../services/pose_detector_service.dart';
import 'posture_result.dart';

class PostureEngine {
  PostureEngine({
    required PoseDetectorService poseDetector,
    required CalibrationService  calibrationService,
    required Logger              logger,
  })  : _poseDetector       = poseDetector,
        _calibrationService = calibrationService,
        _logger             = logger;

  final PoseDetectorService _poseDetector;
  final CalibrationService  _calibrationService;
  final Logger              _logger;

  // ── Canvas size (updated by screen each build) ────────────────────────────
  Size _canvasSize = const Size(1, 1);
  void updateCanvasSize(Size size) => _canvasSize = size;

  // ── Stability state machine ───────────────────────────────────────────────
  int  _stableFrameCount = 0;
  bool _wasUnstable      = false;       // debounce flag for log spam

  // ── Stream plumbing ───────────────────────────────────────────────────────
  StreamSubscription<PoseData?>? _poseSub;

  final StreamController<PostureResult> _postureController =
      StreamController<PostureResult>.broadcast();

  Stream<PostureResult> get postureStream => _postureController.stream;

  // ── Lifecycle state ───────────────────────────────────────────────────────
  bool _isRunning  = false;
  bool _isDisposed = false;

  bool get isRunning  => _isRunning;

  PostureResult _lastResult = PostureResult.analyzing();
  PostureResult get lastResult => _lastResult;

  // ── Public API ────────────────────────────────────────────────────────────

  void start() {
    if (_isRunning || _isDisposed) return;
    _isRunning = true;

    _poseSub = _poseDetector.poseStream.listen(
      _onPose,
      onError: (Object e) =>
          _logger.e('[PostureEngine] Pose stream error', error: e),
    );

    _logger.i('[PostureEngine] Started.');
  }

  void pause() => _poseSub?.pause();
  void resume() => _poseSub?.resume();

  Future<void> dispose() async {
    _isDisposed = true;
    _isRunning  = false;
    await _poseSub?.cancel();
    await _postureController.close();
    _logger.i('[PostureEngine] Disposed.');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Per-frame analysis pipeline
  // ─────────────────────────────────────────────────────────────────────────

  void _onPose(PoseData? pose) {
    if (_isDisposed || _postureController.isClosed) return;

    if (pose == null || !pose.isPostureReady) {
      _stableFrameCount = 0;
      _emit(PostureResult.empty());
      return;
    }

    final canvas = _canvasSize;

    // ── 1. Compute shoulder tilt ──────────────────────────────────────────
    final shoulderTilt = BodyMath.horizontalTiltDeg(
      pose.leftShoulder, pose.rightShoulder, canvas,
    ) ?? 0.0;

    // ── 2. Compute spine tilt ─────────────────────────────────────────────
    final spineTilt = BodyMath.spineTiltDeg(
      pose.leftShoulder, pose.rightShoulder,
      pose.leftHip,      pose.rightHip,
      canvas,
    ) ?? 0.0;

    // ── 3. Compute hip tilt ───────────────────────────────────────────────
    final hipTilt = BodyMath.horizontalTiltDeg(
      pose.leftHip, pose.rightHip, canvas,
    ) ?? 0.0;

    // ── 4. Z-axis skew (depth rotation) ──────────────────────────────────
    double? zSkew;
    final baselinePx = _calibrationService.calibratedShoulderWidthPx;
    if (baselinePx != null && baselinePx > 0) {
      final ls = pose.leftShoulder;
      final rs = pose.rightShoulder;
      if (ls != null && rs != null && ls.isReliable && rs.isReliable) {
        final currentPx = BodyMath.pixelDistance(ls, rs, canvas);
        zSkew = BodyMath.zSkewRatio(
          observedWidthPx: currentPx,
          expectedWidthPx: baselinePx,
        );
      }
    }

    // ── 5. Symmetry ratio ─────────────────────────────────────────────────
    double? symmetry;
    final leftArmPx = BodyMath.chainPixelDistance(
      [pose.leftShoulder, pose.leftElbow, pose.leftWrist], canvas,
    );
    final rightArmPx = BodyMath.chainPixelDistance(
      [pose.rightShoulder, pose.rightElbow, pose.rightWrist], canvas,
    );
    symmetry = BodyMath.symmetryRatio(leftArmPx, rightArmPx);

    // ── 6. Determine status ───────────────────────────────────────────────
    final status = _determineStatus(
      shoulderTilt: shoulderTilt,
      spineTilt:    spineTilt,
      zSkew:        zSkew,
    );

    // ── 7. Emit ───────────────────────────────────────────────────────────
    final result = PostureResult(
      status:          status,
      timestamp:       pose.timestamp,
      shoulderTiltDeg: shoulderTilt,
      spineTiltDeg:    spineTilt,
      hipTiltDeg:      hipTilt,
      zSkewRatio:      zSkew,
      symmetryRatio:   symmetry,
      stableFrameCount: _stableFrameCount,
    );

    _emit(result);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Status state machine
  // ─────────────────────────────────────────────────────────────────────────

  PostureStatus _determineStatus({
    required double  shoulderTilt,
    required double  spineTilt,
    required double? zSkew,
  }) {
    // ── Priority 1: Z-axis rotation (measurement suspension) ─────────────
    if (zSkew != null && zSkew > PostureConfig.zSkewThreshold) {
      _stableFrameCount = 0;
      if (!_wasUnstable) {
        _logger.w('[PostureEngine] UNSTABLE ROTATION — z-skew: '
            '${zSkew.toStringAsFixed(2)}');
        _wasUnstable = true;
      }
      return PostureStatus.unstableRotation;
    }
    _wasUnstable = false;

    // ── Priority 2: Tilt checks ────────────────────────────────────────
    final absShoulderTilt = shoulderTilt.abs();
    final absSpineTilt    = spineTilt.abs();

    if (absShoulderTilt > PostureConfig.maxShoulderTiltDeg ||
        absSpineTilt    > PostureConfig.maxSpineTiltDeg) {
      _stableFrameCount = 0;

      // Determine lean direction from shoulder tilt sign.
      if (shoulderTilt > PostureConfig.maxShoulderTiltDeg) {
        return PostureStatus.leaningRight;
      }
      if (shoulderTilt < -PostureConfig.maxShoulderTiltDeg) {
        return PostureStatus.leaningLeft;
      }
      return PostureStatus.leaningForward;
    }

    // ── Priority 3: Stability accumulation ────────────────────────────
    _stableFrameCount++;
    if (_stableFrameCount >= PostureConfig.stableFrameCount) {
      _stableFrameCount = PostureConfig.stableFrameCount; // cap it
      return PostureStatus.stable;
    }

    // Still accumulating stable frames — stay in previous state to avoid
    // flickering between stable and analyzing.
    return _lastResult.status == PostureStatus.stable
        ? PostureStatus.stable
        : PostureStatus.analyzing;
  }

  void _emit(PostureResult result) {
    _lastResult = result;
    if (!_postureController.isClosed) {
      _postureController.add(result);
    }
  }
}

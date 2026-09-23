// lib/models/measurement_result.dart
// ─────────────────────────────────────────────────────────────────────────────
// MeasurementResult — immutable snapshot of all body measurements computed
// from a single [PoseData] frame after calibration.
//
// All values are in CENTIMETRES.  A null value means that measurement could
// not be computed (insufficient landmark visibility or no calibration).
//
// The [jointAngles] map holds joint angles in degrees for the four main
// joints (elbows, knees, hips, shoulders).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:equatable/equatable.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'joint_point.dart';

// ── Measurement labels — used by OverlayPainter ──────────────────────────────

/// Stable string key for each measurement.
/// Used as Map keys and display labels in the overlay.
class MeasurementKey {
  MeasurementKey._();

  static const String shoulderWidth    = 'Shoulder W.';
  static const String chestWidth       = 'Chest W.';
  static const String leftArmLength    = 'L. Arm';
  static const String rightArmLength   = 'R. Arm';
  static const String leftForearm      = 'L. Forearm';
  static const String rightForearm     = 'R. Forearm';
  static const String torsoLength      = 'Torso';
  static const String hipWidth         = 'Hip W.';
  static const String leftThigh        = 'L. Thigh';
  static const String rightThigh       = 'R. Thigh';
  static const String leftShin         = 'L. Shin';
  static const String rightShin        = 'R. Shin';
  static const String bodyHeight        = 'Height';

  /// All keys in display order.
  static const List<String> all = [
    bodyHeight,
    shoulderWidth,
    chestWidth,
    torsoLength,
    hipWidth,
    leftArmLength,
    rightArmLength,
    leftForearm,
    rightForearm,
    leftThigh,
    rightThigh,
    leftShin,
    rightShin,
  ];
}

// ── MeasurementResult ─────────────────────────────────────────────────────────

class MeasurementResult extends Equatable {
  const MeasurementResult({
    required this.timestamp,
    required this.isCalibrated,
    // ── Widths ──
    this.shoulderWidthCm,
    this.chestWidthCm,
    this.hipWidthCm,
    // ── Lengths ──
    this.leftArmLengthCm,
    this.rightArmLengthCm,
    this.leftForearmCm,
    this.rightForearmCm,
    this.torsoLengthCm,
    this.leftThighCm,
    this.rightThighCm,
    this.leftShinCm,
    this.rightShinCm,
    this.bodyHeightCm,
    // ── Joint angles ──
    this.elbowAngleLeft,
    this.elbowAngleRight,
    this.kneeAngleLeft,
    this.kneeAngleRight,
    this.shoulderAngleLeft,
    this.shoulderAngleRight,
    this.hipAngleLeft,
    this.hipAngleRight,
    // ── Mid-points (for overlay labels) ──
    this.shoulderMidPoint,
    this.hipMidPoint,
    this.leftElbowPoint,
    this.rightElbowPoint,
    this.leftKneePoint,
    this.rightKneePoint,
  });

  final DateTime timestamp;
  final bool isCalibrated;

  // ── Width measurements (cm) ───────────────────────────────────────────────
  final double? shoulderWidthCm;
  final double? chestWidthCm;
  final double? hipWidthCm;

  // ── Length measurements (cm) ──────────────────────────────────────────────
  final double? leftArmLengthCm;
  final double? rightArmLengthCm;
  final double? leftForearmCm;
  final double? rightForearmCm;
  final double? torsoLengthCm;
  final double? leftThighCm;
  final double? rightThighCm;
  final double? leftShinCm;
  final double? rightShinCm;
  final double? bodyHeightCm;

  // ── Joint angles (degrees) ────────────────────────────────────────────────
  final double? elbowAngleLeft;
  final double? elbowAngleRight;
  final double? kneeAngleLeft;
  final double? kneeAngleRight;
  final double? shoulderAngleLeft;
  final double? shoulderAngleRight;
  final double? hipAngleLeft;
  final double? hipAngleRight;

  // ── Label anchor points (normalised 0–1, for OverlayPainter) ─────────────
  final JointPoint? shoulderMidPoint;
  final JointPoint? hipMidPoint;
  final JointPoint? leftElbowPoint;
  final JointPoint? rightElbowPoint;
  final JointPoint? leftKneePoint;
  final JointPoint? rightKneePoint;

  // ── Convenience map for OverlayPainter ───────────────────────────────────

  /// All measurements as a label → value map.
  /// Null values are excluded.
  Map<String, double> get asMap {
    final m = <String, double>{};
    void add(String k, double? v) { if (v != null) m[k] = v; }

    add(MeasurementKey.bodyHeight,     bodyHeightCm);
    add(MeasurementKey.shoulderWidth,  shoulderWidthCm);
    add(MeasurementKey.chestWidth,     chestWidthCm);
    add(MeasurementKey.torsoLength,    torsoLengthCm);
    add(MeasurementKey.hipWidth,       hipWidthCm);
    add(MeasurementKey.leftArmLength,  leftArmLengthCm);
    add(MeasurementKey.rightArmLength, rightArmLengthCm);
    add(MeasurementKey.leftForearm,    leftForearmCm);
    add(MeasurementKey.rightForearm,   rightForearmCm);
    add(MeasurementKey.leftThigh,      leftThighCm);
    add(MeasurementKey.rightThigh,     rightThighCm);
    add(MeasurementKey.leftShin,       leftShinCm);
    add(MeasurementKey.rightShin,      rightShinCm);

    return m;
  }

  // ── Empty sentinel ────────────────────────────────────────────────────────

  static MeasurementResult empty() => MeasurementResult(
    timestamp:    DateTime.now(),
    isCalibrated: false,
  );

  // ── Equatable ─────────────────────────────────────────────────────────────

  @override
  List<Object?> get props => [
    timestamp,
    isCalibrated,
    shoulderWidthCm,
    bodyHeightCm,
  ];

  @override
  String toString() =>
      'MeasurementResult('
      'height=${bodyHeightCm?.toStringAsFixed(1)}, '
      'shoulder=${shoulderWidthCm?.toStringAsFixed(1)}, '
      'calibrated=$isCalibrated)';
}

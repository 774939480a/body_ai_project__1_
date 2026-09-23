// lib/models/joint_point.dart
// ─────────────────────────────────────────────────────────────────────────────
// JointPoint — immutable value-object representing a single ML Kit pose
// landmark after coordinate normalisation and orientation correction.
//
// All coordinates are stored as NORMALISED values [0.0, 1.0] relative to the
// display canvas, so painters can directly multiply by canvas size without
// any additional math.
//
// The raw ML Kit values are in image-pixel space and must be converted via
// [ImageConverter.normaliseLandmark] before wrapping in this model.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../core/constants/app_constants.dart';

/// A single body landmark after normalisation.
class JointPoint extends Equatable {
  const JointPoint({
    required this.type,
    required this.x,
    required this.y,
    required this.z,
    required this.likelihood,
  });

  // ── Identity ──────────────────────────────────────────────────────────────

  /// Which body joint this point represents.
  final PoseLandmarkType type;

  // ── Coordinates (normalised 0.0–1.0, display-space) ──────────────────────

  /// Horizontal position, 0 = left edge, 1 = right edge of the canvas.
  final double x;

  /// Vertical position, 0 = top edge, 1 = bottom edge of the canvas.
  final double y;

  /// Relative depth estimate from ML Kit (same scale as x/y).
  /// Negative = closer to the camera than the hip mid-point.
  final double z;

  // ── Confidence ────────────────────────────────────────────────────────────

  /// Detection confidence in [0.0, 1.0].
  /// Values below [MeasurementConfig.minLandmarkVisibility] are unreliable.
  final double likelihood;

  // ── Derived helpers ───────────────────────────────────────────────────────

  /// True when the landmark is detected with sufficient confidence.
  bool get isReliable =>
      likelihood >= MeasurementConfig.minLandmarkVisibility;

  /// Convert to a Flutter [Offset] scaled to [canvasSize].
  Offset toOffset(Size canvasSize) =>
      Offset(x * canvasSize.width, y * canvasSize.height);

  /// Euclidean distance to [other] in normalised coordinate space.
  double distanceTo(JointPoint other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return (dx * dx + dy * dy);  // squared — call sqrt externally if needed
  }

  /// Euclidean distance to [other] scaled to [canvasSize] in pixels.
  double pixelDistanceTo(JointPoint other, Size canvasSize) {
    final dx = (x - other.x) * canvasSize.width;
    final dy = (y - other.y) * canvasSize.height;
    return (dx * dx + dy * dy);
  }

  // ── Factory ───────────────────────────────────────────────────────────────

  /// Build from a raw [PoseLandmark] after coordinate normalisation.
  /// [imageWidth] / [imageHeight] are the native sensor dimensions.
  /// [flipX] is true for front-facing camera (mirror correction).
  factory JointPoint.fromLandmark(
    PoseLandmark landmark, {
    required double imageWidth,
    required double imageHeight,
    required bool flipX,
  }) {
    double nx = landmark.x / imageWidth;
    double ny = landmark.y / imageHeight;

    // Mirror the x-axis for front camera so the overlay matches
    // what the user sees on screen.
    if (flipX) nx = 1.0 - nx;

    // Clamp to [0,1] — ML Kit occasionally returns out-of-bounds values
    // for partially occluded landmarks.
    nx = nx.clamp(0.0, 1.0);
    ny = ny.clamp(0.0, 1.0);

    return JointPoint(
      type:       landmark.type,
      x:          nx,
      y:          ny,
      z:          landmark.z,
      likelihood: landmark.likelihood.clamp(0.0, 1.0),
    );
  }

  // ── Equatable ─────────────────────────────────────────────────────────────

  @override
  List<Object?> get props => [type, x, y, z, likelihood];

  @override
  String toString() =>
      'JointPoint(${type.name}, x=${x.toStringAsFixed(3)}, '
      'y=${y.toStringAsFixed(3)}, z=${z.toStringAsFixed(3)}, '
      'likelihood=${likelihood.toStringAsFixed(2)})';
}

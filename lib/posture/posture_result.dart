// lib/posture/posture_result.dart
// ─────────────────────────────────────────────────────────────────────────────
// PostureResult — immutable snapshot of a single posture analysis frame.
//
// Emitted by [PostureEngine] on every processed pose frame.
// Consumed by [PostureBanner], [CameraScreen], and [ResultsScreen].
// ─────────────────────────────────────────────────────────────────────────────

import 'package:equatable/equatable.dart';

// ── PostureStatus enum ────────────────────────────────────────────────────────

/// The current full-body alignment state.
enum PostureStatus {
  /// Not enough data yet — engine is warming up.
  analyzing,

  /// Body is within all tilt and skew thresholds.
  stable,

  /// Right shoulder lower than left beyond threshold.
  leaningLeft,

  /// Left shoulder lower than right beyond threshold.
  leaningRight,

  /// Spine tilting forward.
  leaningForward,

  /// User has rotated too far away from the camera —
  /// measurements are suspended until they face forward again.
  unstableRotation,

  /// No pose detected in the current frame.
  noData,
}

extension PostureStatusX on PostureStatus {
  /// Short display label for the banner.
  String get label {
    switch (this) {
      case PostureStatus.analyzing:       return 'ANALYZING...';
      case PostureStatus.stable:          return '✓  STABLE';
      case PostureStatus.leaningLeft:     return '◄  LEANING LEFT';
      case PostureStatus.leaningRight:    return 'LEANING RIGHT  ►';
      case PostureStatus.leaningForward:  return '▼  LEANING FORWARD';
      case PostureStatus.unstableRotation:return '⚠  UNSTABLE ROTATION';
      case PostureStatus.noData:          return '—  NO POSE';
    }
  }

  /// True when measurements should be suspended.
  bool get suspendsMeasurements => this == PostureStatus.unstableRotation;

  /// True when the user's pose is actionable (not just initialising).
  bool get hasData => this != PostureStatus.analyzing && this != PostureStatus.noData;
}

// ── PostureResult ─────────────────────────────────────────────────────────────

class PostureResult extends Equatable {
  const PostureResult({
    required this.status,
    required this.timestamp,
    required this.shoulderTiltDeg,
    required this.spineTiltDeg,
    required this.hipTiltDeg,
    required this.stableFrameCount,
    this.zSkewRatio,
    this.symmetryRatio,
  });

  // ── Status ─────────────────────────────────────────────────────────────────
  final PostureStatus status;
  final DateTime      timestamp;

  // ── Tilt metrics (degrees) ─────────────────────────────────────────────────

  /// Signed angle of the shoulder axis — positive = right side lower.
  final double shoulderTiltDeg;

  /// Deviation of the spine from vertical — positive = forward lean.
  final double spineTiltDeg;

  /// Signed angle of the hip axis — positive = right side lower.
  final double hipTiltDeg;

  // ── Depth rotation ────────────────────────────────────────────────────────

  /// Z-axis skew ratio [0.0–1.0].
  /// 0 = fully facing camera, 1 = fully side-on.
  /// Null when no calibration baseline is available.
  final double? zSkewRatio;

  // ── Symmetry ──────────────────────────────────────────────────────────────

  /// Body symmetry ratio [-1.0, 1.0].
  /// 0 = perfectly symmetrical.
  /// Null when not enough landmarks are visible.
  final double? symmetryRatio;

  // ── Stability counter ─────────────────────────────────────────────────────

  /// Number of consecutive frames that have been within all thresholds.
  /// Reaches [PostureConfig.stableFrameCount] when truly stable.
  final int stableFrameCount;

  // ── Derived helpers ───────────────────────────────────────────────────────

  bool get isMeasurementSuspended => status.suspendsMeasurements;
  bool get isStable               => status == PostureStatus.stable;

  // ── Sentinel ──────────────────────────────────────────────────────────────

  static PostureResult empty() => PostureResult(
    status:          PostureStatus.noData,
    timestamp:       DateTime.now(),
    shoulderTiltDeg: 0,
    spineTiltDeg:    0,
    hipTiltDeg:      0,
    stableFrameCount: 0,
  );

  static PostureResult analyzing() => PostureResult(
    status:          PostureStatus.analyzing,
    timestamp:       DateTime.now(),
    shoulderTiltDeg: 0,
    spineTiltDeg:    0,
    hipTiltDeg:      0,
    stableFrameCount: 0,
  );

  // ── Equatable ─────────────────────────────────────────────────────────────

  @override
  List<Object?> get props => [status, timestamp];

  @override
  String toString() =>
      'PostureResult(${status.label}, '
      'shoulder=${shoulderTiltDeg.toStringAsFixed(1)}°, '
      'spine=${spineTiltDeg.toStringAsFixed(1)}°, '
      'z=${zSkewRatio?.toStringAsFixed(2) ?? "—"})';
}

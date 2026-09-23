// lib/models/pose_data.dart
// ─────────────────────────────────────────────────────────────────────────────
// PoseData — immutable snapshot of a detected human pose.
//
// Contains all 33 ML Kit landmarks wrapped as [JointPoint] objects with
// typed accessor properties for every anatomically named joint.
//
// Downstream engines (MeasurementEngine, PostureEngine) operate exclusively
// on [PoseData] — they never touch raw ML Kit types.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../core/constants/app_constants.dart';
import 'joint_point.dart';

/// Immutable snapshot of a fully-processed human pose.
class PoseData extends Equatable {
  const PoseData({
    required this.landmarks,
    required this.timestamp,
    required this.imageSize,
    required this.isFrontCamera,
  });

  // ── Core data ─────────────────────────────────────────────────────────────

  /// All detected landmarks keyed by [PoseLandmarkType].
  /// All coordinates are normalised [0.0, 1.0] — display-space ready.
  final Map<PoseLandmarkType, JointPoint> landmarks;

  /// Wall-clock time when the originating frame was captured.
  final DateTime timestamp;

  /// Native sensor image size used to normalise coordinates.
  final Size imageSize;

  /// True when this pose came from the front-facing camera.
  final bool isFrontCamera;

  // ─────────────────────────────────────────────────────────────────────────
  // Typed landmark accessors — avoids Map lookup boilerplate in engines.
  // Each property returns null if the landmark was not detected.
  // ─────────────────────────────────────────────────────────────────────────

  // ── Head ─────────────────────────────────────────────────────────────────
  JointPoint? get nose          => landmarks[PoseLandmarkType.nose];
  JointPoint? get leftEyeInner  => landmarks[PoseLandmarkType.leftEyeInner];
  JointPoint? get leftEye       => landmarks[PoseLandmarkType.leftEye];
  JointPoint? get leftEyeOuter  => landmarks[PoseLandmarkType.leftEyeOuter];
  JointPoint? get rightEyeInner => landmarks[PoseLandmarkType.rightEyeInner];
  JointPoint? get rightEye      => landmarks[PoseLandmarkType.rightEye];
  JointPoint? get rightEyeOuter => landmarks[PoseLandmarkType.rightEyeOuter];
  JointPoint? get leftEar       => landmarks[PoseLandmarkType.leftEar];
  JointPoint? get rightEar      => landmarks[PoseLandmarkType.rightEar];
  JointPoint? get mouthLeft     => landmarks[PoseLandmarkType.leftMouth];
  JointPoint? get mouthRight    => landmarks[PoseLandmarkType.rightMouth];

  // ── Upper body ───────────────────────────────────────────────────────────
  JointPoint? get leftShoulder  => landmarks[PoseLandmarkType.leftShoulder];
  JointPoint? get rightShoulder => landmarks[PoseLandmarkType.rightShoulder];
  JointPoint? get leftElbow     => landmarks[PoseLandmarkType.leftElbow];
  JointPoint? get rightElbow    => landmarks[PoseLandmarkType.rightElbow];
  JointPoint? get leftWrist     => landmarks[PoseLandmarkType.leftWrist];
  JointPoint? get rightWrist    => landmarks[PoseLandmarkType.rightWrist];
  JointPoint? get leftPinky     => landmarks[PoseLandmarkType.leftPinky];
  JointPoint? get rightPinky    => landmarks[PoseLandmarkType.rightPinky];
  JointPoint? get leftIndex     => landmarks[PoseLandmarkType.leftIndex];
  JointPoint? get rightIndex    => landmarks[PoseLandmarkType.rightIndex];
  JointPoint? get leftThumb     => landmarks[PoseLandmarkType.leftThumb];
  JointPoint? get rightThumb    => landmarks[PoseLandmarkType.rightThumb];

  // ── Lower body ───────────────────────────────────────────────────────────
  JointPoint? get leftHip       => landmarks[PoseLandmarkType.leftHip];
  JointPoint? get rightHip      => landmarks[PoseLandmarkType.rightHip];
  JointPoint? get leftKnee      => landmarks[PoseLandmarkType.leftKnee];
  JointPoint? get rightKnee     => landmarks[PoseLandmarkType.rightKnee];
  JointPoint? get leftAnkle     => landmarks[PoseLandmarkType.leftAnkle];
  JointPoint? get rightAnkle    => landmarks[PoseLandmarkType.rightAnkle];
  JointPoint? get leftHeel      => landmarks[PoseLandmarkType.leftHeel];
  JointPoint? get rightHeel     => landmarks[PoseLandmarkType.rightHeel];
  JointPoint? get leftFootIndex => landmarks[PoseLandmarkType.leftFootIndex];
  JointPoint? get rightFootIndex=> landmarks[PoseLandmarkType.rightFootIndex];

  // ─────────────────────────────────────────────────────────────────────────
  // Computed mid-points (virtual joints used by measurement engine)
  // ─────────────────────────────────────────────────────────────────────────

  /// Mid-point between both shoulders — used as chest anchor.
  JointPoint? get chestCenter {
    final l = leftShoulder;
    final r = rightShoulder;
    if (l == null || r == null) return null;
    return _midpoint(PoseLandmarkType.nose /* placeholder type */, l, r);
  }

  /// Mid-point between both hips — pelvis anchor.
  JointPoint? get hipCenter {
    final l = leftHip;
    final r = rightHip;
    if (l == null || r == null) return null;
    return _midpoint(PoseLandmarkType.nose /* placeholder type */, l, r);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Visibility / reliability helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Count of landmarks with sufficient detection confidence.
  int get reliableLandmarkCount =>
      landmarks.values.where((j) => j.isReliable).length;

  /// True when the core body joints required for measurement are all visible.
  bool get isMeasurementReady {
    const required = [
      PoseLandmarkType.leftShoulder,
      PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftHip,
      PoseLandmarkType.rightHip,
      PoseLandmarkType.leftAnkle,
      PoseLandmarkType.rightAnkle,
      PoseLandmarkType.nose,
    ];
    return required.every(
      (t) => landmarks[t]?.isReliable == true,
    );
  }

  /// True when enough upper-body landmarks are visible for posture analysis.
  bool get isPostureReady {
    const required = [
      PoseLandmarkType.leftShoulder,
      PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftHip,
      PoseLandmarkType.rightHip,
    ];
    return required.every(
      (t) => landmarks[t]?.isReliable == true,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Factory
  // ─────────────────────────────────────────────────────────────────────────

  /// Build a [PoseData] from a raw ML Kit [Pose].
  ///
  /// Normalises all landmark coordinates to [0.0, 1.0] canvas-space and
  /// applies front-camera mirroring when [isFrontCamera] is true.
  factory PoseData.fromMlKitPose(
    Pose pose, {
    required Size imageSize,
    required bool isFrontCamera,
  }) {
    final map = <PoseLandmarkType, JointPoint>{};

    for (final entry in pose.landmarks.entries) {
      map[entry.key] = JointPoint.fromLandmark(
        entry.value,
        imageWidth:  imageSize.width,
        imageHeight: imageSize.height,
        flipX:       isFrontCamera,
      );
    }

    return PoseData(
      landmarks:     map,
      timestamp:     DateTime.now(),
      imageSize:     imageSize,
      isFrontCamera: isFrontCamera,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  JointPoint _midpoint(
    PoseLandmarkType type,
    JointPoint a,
    JointPoint b,
  ) {
    return JointPoint(
      type:       type,
      x:          (a.x + b.x) / 2.0,
      y:          (a.y + b.y) / 2.0,
      z:          (a.z + b.z) / 2.0,
      likelihood: (a.likelihood + b.likelihood) / 2.0,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Equatable
  // ─────────────────────────────────────────────────────────────────────────

  @override
  List<Object?> get props => [timestamp, isFrontCamera, reliableLandmarkCount];

  @override
  String toString() =>
      'PoseData(landmarks=${landmarks.length}, '
      'reliable=$reliableLandmarkCount, '
      'measurementReady=$isMeasurementReady)';
}

/// Sentinel for "no pose detected this frame".
class NoPoseData extends PoseData {
  const NoPoseData()
      : super(
          landmarks:     const {},
          timestamp:     const _EpochDateTime(),
          imageSize:     Size.zero,
          isFrontCamera: false,
        );

  @override
  bool get isMeasurementReady => false;

  @override
  bool get isPostureReady => false;

  @override
  int get reliableLandmarkCount => 0;
}

/// Compile-time const DateTime workaround.
class _EpochDateTime implements DateTime {
  const _EpochDateTime();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

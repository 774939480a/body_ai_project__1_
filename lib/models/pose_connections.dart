// lib/models/pose_connections.dart
// ─────────────────────────────────────────────────────────────────────────────
// Defines the full skeleton topology — which joints are connected by bones.
// Used exclusively by [SkeletonPainter] (Phase 4) to draw bone lines.
//
// Also defines colour groups so different body segments can be rendered
// with distinct neon hues for a professional, readable overlay.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../core/themes/app_theme.dart';

/// A directed (start → end) bone segment between two landmark types.
class BoneConnection {
  const BoneConnection(this.start, this.end, this.color);

  final PoseLandmarkType start;
  final PoseLandmarkType end;

  /// Colour used to render this bone in [SkeletonPainter].
  final Color color;
}

/// All 35 bone segments of the full MediaPipe/ML Kit 33-point skeleton,
/// grouped by body region with matching neon colours.
class PoseConnections {
  PoseConnections._();

  // Colour scheme per region:
  //   Head     → neonCyan
  //   Torso    → neonBlue
  //   Arms     → neonPurple
  //   Legs     → neonGreen

  static const _head   = AppColors.neonCyan;
  static const _torso  = AppColors.neonBlue;
  static const _arms   = AppColors.neonPurple;
  static const _legs   = AppColors.neonGreen;

  /// Complete ordered list of all bone connections.
  static const List<BoneConnection> all = [

    // ── Head / Face ─────────────────────────────────────────────────────────
    BoneConnection(PoseLandmarkType.nose,          PoseLandmarkType.leftEyeInner,   _head),
    BoneConnection(PoseLandmarkType.leftEyeInner,  PoseLandmarkType.leftEye,        _head),
    BoneConnection(PoseLandmarkType.leftEye,       PoseLandmarkType.leftEyeOuter,   _head),
    BoneConnection(PoseLandmarkType.leftEyeOuter,  PoseLandmarkType.leftEar,        _head),
    BoneConnection(PoseLandmarkType.nose,          PoseLandmarkType.rightEyeInner,  _head),
    BoneConnection(PoseLandmarkType.rightEyeInner, PoseLandmarkType.rightEye,       _head),
    BoneConnection(PoseLandmarkType.rightEye,      PoseLandmarkType.rightEyeOuter,  _head),
    BoneConnection(PoseLandmarkType.rightEyeOuter, PoseLandmarkType.rightEar,       _head),
    BoneConnection(PoseLandmarkType.leftMouth,     PoseLandmarkType.rightMouth,     _head),

    // ── Torso / Spine axis ───────────────────────────────────────────────────
    BoneConnection(PoseLandmarkType.leftShoulder,  PoseLandmarkType.rightShoulder,  _torso),
    BoneConnection(PoseLandmarkType.leftShoulder,  PoseLandmarkType.leftHip,        _torso),
    BoneConnection(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip,       _torso),
    BoneConnection(PoseLandmarkType.leftHip,       PoseLandmarkType.rightHip,       _torso),

    // ── Left arm ─────────────────────────────────────────────────────────────
    BoneConnection(PoseLandmarkType.leftShoulder,  PoseLandmarkType.leftElbow,      _arms),
    BoneConnection(PoseLandmarkType.leftElbow,     PoseLandmarkType.leftWrist,      _arms),
    BoneConnection(PoseLandmarkType.leftWrist,     PoseLandmarkType.leftThumb,      _arms),
    BoneConnection(PoseLandmarkType.leftWrist,     PoseLandmarkType.leftIndex,      _arms),
    BoneConnection(PoseLandmarkType.leftWrist,     PoseLandmarkType.leftPinky,      _arms),
    BoneConnection(PoseLandmarkType.leftIndex,     PoseLandmarkType.leftPinky,      _arms),

    // ── Right arm ────────────────────────────────────────────────────────────
    BoneConnection(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow,     _arms),
    BoneConnection(PoseLandmarkType.rightElbow,    PoseLandmarkType.rightWrist,     _arms),
    BoneConnection(PoseLandmarkType.rightWrist,    PoseLandmarkType.rightThumb,     _arms),
    BoneConnection(PoseLandmarkType.rightWrist,    PoseLandmarkType.rightIndex,     _arms),
    BoneConnection(PoseLandmarkType.rightWrist,    PoseLandmarkType.rightPinky,     _arms),
    BoneConnection(PoseLandmarkType.rightIndex,    PoseLandmarkType.rightPinky,     _arms),

    // ── Left leg ─────────────────────────────────────────────────────────────
    BoneConnection(PoseLandmarkType.leftHip,       PoseLandmarkType.leftKnee,       _legs),
    BoneConnection(PoseLandmarkType.leftKnee,      PoseLandmarkType.leftAnkle,      _legs),
    BoneConnection(PoseLandmarkType.leftAnkle,     PoseLandmarkType.leftHeel,       _legs),
    BoneConnection(PoseLandmarkType.leftAnkle,     PoseLandmarkType.leftFootIndex,  _legs),
    BoneConnection(PoseLandmarkType.leftHeel,      PoseLandmarkType.leftFootIndex,  _legs),

    // ── Right leg ────────────────────────────────────────────────────────────
    BoneConnection(PoseLandmarkType.rightHip,      PoseLandmarkType.rightKnee,      _legs),
    BoneConnection(PoseLandmarkType.rightKnee,     PoseLandmarkType.rightAnkle,     _legs),
    BoneConnection(PoseLandmarkType.rightAnkle,    PoseLandmarkType.rightHeel,      _legs),
    BoneConnection(PoseLandmarkType.rightAnkle,    PoseLandmarkType.rightFootIndex, _legs),
    BoneConnection(PoseLandmarkType.rightHeel,     PoseLandmarkType.rightFootIndex, _legs),
  ];

  /// Connections that form the central spine axis — used to draw the
  /// body-alignment guide line in [OverlayPainter].
  static const List<BoneConnection> spineAxis = [
    BoneConnection(PoseLandmarkType.nose,          PoseLandmarkType.leftShoulder,   _torso),
    BoneConnection(PoseLandmarkType.leftShoulder,  PoseLandmarkType.leftHip,        _torso),
    BoneConnection(PoseLandmarkType.leftHip,       PoseLandmarkType.leftAnkle,      _torso),
  ];
}

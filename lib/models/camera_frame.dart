// lib/models/camera_frame.dart
// ─────────────────────────────────────────────────────────────────────────────
// Immutable value-object that represents a single camera frame delivered
// by [CameraService].  Wraps the raw [CameraImage] together with metadata
// needed by downstream processing stages (pose detection, painting).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:camera/camera.dart';
import 'package:equatable/equatable.dart';

/// Describes the active camera lens.
enum ActiveCamera { front, back }

/// A lightweight, immutable snapshot delivered per camera frame.
///
/// [CameraService] creates one of these per accepted frame and emits it
/// on its [frameStream].  Downstream consumers (PoseDetectorService, etc.)
/// receive and transform it without mutating the original.
class CameraFrame extends Equatable {
  const CameraFrame({
    required this.image,
    required this.timestamp,
    required this.activeCamera,
    required this.sensorOrientation,
    required this.imageWidth,
    required this.imageHeight,
  });

  /// Raw YUV / BGRA frame data from the camera hardware.
  final CameraImage image;

  /// Wall-clock timestamp when this frame was captured.
  final DateTime timestamp;

  /// Which camera lens produced this frame.
  final ActiveCamera activeCamera;

  /// Sensor orientation in degrees (0, 90, 180, 270).
  /// Required to correctly orient landmarks returned by ML Kit.
  final int sensorOrientation;

  /// Native image width in pixels (before any rotation).
  final int imageWidth;

  /// Native image height in pixels (before any rotation).
  final int imageHeight;

  // ── Derived helpers ──────────────────────────────────────────────────────

  /// True when the frame comes from the front camera.
  bool get isFrontCamera => activeCamera == ActiveCamera.front;

  /// Aspect ratio of the raw sensor image (width / height).
  double get aspectRatio => imageWidth / imageHeight;

  // ── Equatable ────────────────────────────────────────────────────────────

  @override
  List<Object?> get props => [timestamp, activeCamera, imageWidth, imageHeight];

  @override
  String toString() =>
      'CameraFrame(${imageWidth}x$imageHeight, $activeCamera, '
      't=${timestamp.millisecondsSinceEpoch})';
}

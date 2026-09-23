// lib/utils/image_converter.dart
// ─────────────────────────────────────────────────────────────────────────────
// ImageConverter — stateless utility class.
//
// Converts a Flutter [CameraImage] (raw YUV420 / BGRA8888 sensor data) into a
// [google_mlkit_pose_detection] compatible [InputImage] with the correct
// rotation metadata, so the model receives a properly oriented frame.
//
// Why rotation matters:
//   Android sensors deliver frames in their native orientation (usually 90°
//   for portrait use).  Without the correct [InputImageRotation] tag, ML Kit
//   maps landmarks to the wrong axis — causing the skeleton to appear rotated
//   90° on screen.
//
// Threading:
//   All methods are synchronous and very fast (byte-array operations only).
//   They are safe to call on the platform/camera thread via startImageStream.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../models/camera_frame.dart';

class ImageConverter {
  ImageConverter._();

  // ── Public API ────────────────────────────────────────────────────────────

  /// Convert a [CameraFrame] into an [InputImage] ready for ML Kit inference.
  ///
  /// Returns null if the image format is unsupported or the frame is corrupt.
  static InputImage? toInputImage(CameraFrame frame) {
    final image = frame.image;

    // ── 1. Build raw byte buffer ──────────────────────────────────────────
    final bytes = _buildByteBuffer(image);
    if (bytes == null) return null;

    // ── 2. Resolve InputImageRotation ─────────────────────────────────────
    final rotation = _resolveRotation(
      sensorOrientation: frame.sensorOrientation,
      isFrontCamera:     frame.isFrontCamera,
    );

    // ── 3. Resolve InputImageFormat ───────────────────────────────────────
    final format = _resolveFormat(image.format.group);
    if (format == null) return null;

    // ── 4. Assemble InputImage ─────────────────────────────────────────────
    final metadata = InputImageMetadata(
      size:         Size(image.width.toDouble(), image.height.toDouble()),
      rotation:     rotation,
      format:       format,
      bytesPerRow:  image.planes[0].bytesPerRow,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  /// Concatenates all YUV / BGRA planes into a single contiguous byte array.
  ///
  /// For YUV_420_888:  planes[0] = Y, planes[1] = U, planes[2] = V.
  /// For BGRA8888:     planes[0] = interleaved BGRA.
  static Uint8List? _buildByteBuffer(CameraImage image) {
    try {
      if (image.planes.isEmpty) return null;

      // Fast path for single-plane formats (e.g. BGRA8888 on iOS)
      if (image.planes.length == 1) {
        return image.planes[0].bytes;
      }

      // Multi-plane: allocate and copy each plane sequentially.
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      return allBytes.done().buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// Maps the camera sensor orientation + lens direction to an
  /// [InputImageRotation] constant understood by ML Kit.
  ///
  /// On most Android phones:
  ///   Rear  camera sensor orientation → 90°
  ///   Front camera sensor orientation → 270°
  ///
  /// Since we locked the app to portrait we don't need to account for
  /// device rotation — the sensor orientation alone is sufficient.
  static InputImageRotation _resolveRotation({
    required int sensorOrientation,
    required bool isFrontCamera,
  }) {
    // Front cameras on Android report 270° but the image is already mirrored
    // by the hardware, so we treat it as 90° for ML Kit's coordinate system.
    int effectiveOrientation = sensorOrientation;
    if (isFrontCamera && defaultTargetPlatform == TargetPlatform.android) {
      effectiveOrientation = (360 - sensorOrientation) % 360;
    }

    switch (effectiveOrientation) {
      case 0:   return InputImageRotation.rotation0deg;
      case 90:  return InputImageRotation.rotation90deg;
      case 180: return InputImageRotation.rotation180deg;
      case 270: return InputImageRotation.rotation270deg;
      default:  return InputImageRotation.rotation90deg; // safe fallback
    }
  }

  /// Maps a Flutter [ImageFormatGroup] to an [InputImageFormat].
  /// Returns null for unsupported formats.
  static InputImageFormat? _resolveFormat(ImageFormatGroup group) {
    switch (group) {
      case ImageFormatGroup.yuv420:
        return InputImageFormat.yuv_420_888;
      case ImageFormatGroup.bgra8888:
        return InputImageFormat.bgra8888;
      case ImageFormatGroup.nv21:
        return InputImageFormat.nv21;
      default:
        return null; // jpeg / unknown — not supported by ML Kit stream API
    }
  }
}

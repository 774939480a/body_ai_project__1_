// lib/calibration/calibration_data.dart
// ─────────────────────────────────────────────────────────────────────────────
// CalibrationData — immutable value object that stores the result of a
// calibration session.
//
// The central value is [pixelsPerCm]: how many canvas pixels correspond to
// 1 centimetre in real-world space at the current camera distance.
//
// This ratio is then used by [MeasurementEngine] to convert every pixel
// distance into centimetres.
//
// CalibrationData is immutable — a new instance is created whenever the user
// re-calibrates.  The previous instance is simply discarded.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';

// ── Calibration mode enum ─────────────────────────────────────────────────────

/// Which calibration method was used to derive the pixel/cm ratio.
enum CalibrationMode {
  /// User entered their known height in cm.
  /// The ratio is derived from the nose-to-ankle pixel distance.
  userHeight,

  /// User held an A4 paper (29.7 × 21.0 cm) in front of the camera.
  /// The ratio is derived from the detected paper height in pixels.
  a4Paper,

  /// No calibration has been performed.
  /// [CalibrationData.isCalibrated] will be false.
  none,
}

// ── CalibrationData ───────────────────────────────────────────────────────────

class CalibrationData extends Equatable {

  // ── Constructors ────────────────────────────────────────────────────────────

  const CalibrationData._({
    required this.pixelsPerCm,
    required this.mode,
    required this.referenceValueCm,
    required this.referencePixels,
    required this.canvasSize,
    required this.calibratedAt,
  });

  /// Creates an un-calibrated sentinel — used before first calibration.
  factory CalibrationData.uncalibrated() => const CalibrationData._(
    pixelsPerCm:      0.0,
    mode:             CalibrationMode.none,
    referenceValueCm: 0.0,
    referencePixels:  0.0,
    canvasSize:       Size.zero,
    calibratedAt:     _epoch,
  );

  /// Create from a user-height calibration.
  ///
  /// [userHeightCm]    — the height the user entered.
  /// [nosToAnklePx]    — pixel distance from nose to ankle midpoint on canvas.
  /// [canvas]          — the canvas size when calibration was performed.
  factory CalibrationData.fromHeight({
    required double userHeightCm,
    required double noseToAnklePx,
    required Size canvas,
  }) {
    assert(userHeightCm > 0 && noseToAnklePx > 0);

    // We use 94 % of the user height because nose-to-ankle is slightly less
    // than the true head-to-floor height.
    const double noseToAnkleFraction = 0.94;
    final double effectiveHeightCm = userHeightCm * noseToAnkleFraction;

    return CalibrationData._(
      pixelsPerCm:      noseToAnklePx / effectiveHeightCm,
      mode:             CalibrationMode.userHeight,
      referenceValueCm: userHeightCm,
      referencePixels:  noseToAnklePx,
      canvasSize:       canvas,
      calibratedAt:     DateTime.now(),
    );
  }

  /// Create from an A4 paper calibration.
  ///
  /// [a4HeightPixels] — pixel height of the A4 paper on canvas.
  /// [canvas]         — the canvas size when calibration was performed.
  factory CalibrationData.fromA4({
    required double a4HeightPixels,
    required Size canvas,
  }) {
    assert(a4HeightPixels > 0);
    return CalibrationData._(
      pixelsPerCm:      a4HeightPixels / MeasurementConfig.a4LongSideCm,
      mode:             CalibrationMode.a4Paper,
      referenceValueCm: MeasurementConfig.a4LongSideCm,
      referencePixels:  a4HeightPixels,
      canvasSize:       canvas,
      calibratedAt:     DateTime.now(),
    );
  }

  // ── Fields ──────────────────────────────────────────────────────────────────

  /// Number of canvas pixels that equal 1 centimetre in real space.
  /// 0.0 when not calibrated.
  final double pixelsPerCm;

  /// Which method was used to calibrate.
  final CalibrationMode mode;

  /// The real-world reference value used (height in cm or A4 height in cm).
  final double referenceValueCm;

  /// The pixel measurement of the reference object at calibration time.
  final double referencePixels;

  /// Canvas size when calibration was performed.
  /// If the canvas size changes (orientation flip), re-calibration is needed.
  final Size canvasSize;

  /// When this calibration was computed.
  final DateTime calibratedAt;

  // ── Derived ─────────────────────────────────────────────────────────────────

  /// True when a valid calibration has been performed.
  bool get isCalibrated =>
      mode != CalibrationMode.none && pixelsPerCm > 0;

  /// Convert a pixel distance to centimetres.
  /// Returns null if not calibrated.
  double? toCm(double pixels) {
    if (!isCalibrated) return null;
    return pixels / pixelsPerCm;
  }

  /// Convert centimetres to pixels.
  double toPixels(double cm) => cm * pixelsPerCm;

  /// Human-readable summary for the debug overlay.
  String get summary {
    if (!isCalibrated) return 'UNCALIBRATED';
    final modeLabel = mode == CalibrationMode.userHeight
        ? 'HEIGHT ${referenceValueCm.toStringAsFixed(0)} cm'
        : 'A4 PAPER';
    return '$modeLabel  •  ${pixelsPerCm.toStringAsFixed(2)} px/cm';
  }

  // ── Equatable ────────────────────────────────────────────────────────────────

  @override
  List<Object?> get props =>
      [pixelsPerCm, mode, canvasSize, calibratedAt];

  @override
  String toString() =>
      'CalibrationData(mode=$mode, px/cm=${pixelsPerCm.toStringAsFixed(2)})';
}

// Compile-time constant epoch for the uncalibrated sentinel.
// ignore: constant_identifier_names
const _epoch = _CompileTimeEpoch();

class _CompileTimeEpoch implements DateTime {
  const _CompileTimeEpoch();
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

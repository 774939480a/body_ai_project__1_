// lib/core/constants/app_constants.dart
// ─────────────────────────────────────────────────────────────────────────────
// Global application constants — single source of truth for magic numbers,
// configuration values, and tunable parameters.
// ─────────────────────────────────────────────────────────────────────────────

/// Camera & stream configuration
class CameraConfig {
  CameraConfig._();

  /// Target FPS for the pose-detection pipeline.
  /// Frames arriving faster than this are dropped to avoid back-pressure.
  static const int targetFps = 30;

  /// Minimum milliseconds between processed frames  (1000 / targetFps).
  static const int frameIntervalMs = 1000 ~/ targetFps;

  /// Camera resolution preset — balances quality vs. processing cost.
  /// Use [medium] on low-end devices, [high] on flagships.
  static const String defaultResolutionPreset = 'high';

  /// How many frames to skip between heavy pose-detection runs when the
  /// device is under load (frame-skipping strategy).
  static const int heavyProcessingSkipCount = 1;

  /// Maximum number of unprocessed frames allowed in the stream buffer
  /// before older frames are discarded.
  static const int streamBufferSize = 2;
}

/// Measurement & calibration constants
class MeasurementConfig {
  MeasurementConfig._();

  /// Default user height in cm used when no calibration has been performed.
  static const double defaultHeightCm = 170.0;

  /// A4 paper long-side in cm (used for A4-calibration mode).
  static const double a4LongSideCm = 29.7;

  /// A4 paper short-side in cm.
  static const double a4ShortSideCm = 21.0;

  /// Minimum visibility score (0.0–1.0) from MediaPipe/ML-Kit below which a
  /// landmark is considered unreliable and excluded from calculations.
  static const double minLandmarkVisibility = 0.5;

  /// How many historical measurement samples the smoothing filter retains.
  static const int smoothingWindowSize = 10;
}

/// Posture analysis thresholds
class PostureConfig {
  PostureConfig._();

  /// Maximum shoulder-tilt angle (degrees) before reporting "Leaning".
  static const double maxShoulderTiltDeg = 5.0;

  /// Maximum spine-tilt angle (degrees) before reporting "Leaning".
  static const double maxSpineTiltDeg = 7.0;

  /// Z-axis skew ratio above which "UNSTABLE ROTATION" is triggered.
  /// Derived from the ratio of shoulder width to expected shoulder width
  /// projected onto the 2D plane.
  static const double zSkewThreshold = 0.35;

  /// Minimum consecutive stable frames before state is reported as Stable.
  static const int stableFrameCount = 8;
}

/// One-Euro Filter tuning parameters (used in MeasurementFilter).
class FilterConfig {
  FilterConfig._();

  /// Minimum cutoff frequency — lower → smoother but more lag.
  static const double minCutoff = 1.0;

  /// Speed coefficient — higher → less lag at fast motion.
  static const double beta = 0.007;

  /// Derivative cutoff frequency.
  static const double dCutoff = 1.0;
}

/// UI / overlay constants
class OverlayConfig {
  OverlayConfig._();

  /// Neon skeleton joint radius in logical pixels.
  static const double jointRadius = 6.0;

  /// Skeleton bone stroke width in logical pixels.
  static const double boneStrokeWidth = 2.5;

  /// Guide-frame opacity (0.0–1.0).
  static const double guideFrameOpacity = 0.45;

  /// Measurement label font size.
  static const double labelFontSize = 11.0;

  /// FPS counter update interval in milliseconds.
  static const int fpsUpdateIntervalMs = 500;
}

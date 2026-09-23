// lib/math/one_euro_filter.dart
// ─────────────────────────────────────────────────────────────────────────────
// One Euro Filter — real-time adaptive low-pass filter for noisy signals.
//
// Published by Géry Casiez, Nicolas Roussel, Daniel Vogel (2012).
// Paper: "1 € Filter: A Simple Speed-Based Low-Pass Filter for Noisy Input"
//
// Why One Euro over Kalman:
//   • Simpler to tune — only 3 parameters (minCutoff, beta, dCutoff).
//   • Adaptive: high cutoff (less smoothing) when the signal moves fast so
//     lag is minimised during movement; low cutoff (more smoothing) when
//     the signal is static so noise is suppressed during stance.
//   • Ideal for pose landmark coordinates that alternate between fast motion
//     and near-stationary holding positions.
//
// Usage:
//   final filter = OneEuroFilter(minCutoff: 1.0, beta: 0.007);
//   final smooth = filter.filter(rawValue, timestampSeconds);
//
// Parameters:
//   minCutoff — minimum cutoff frequency in Hz.
//               Lower → smoother but more lag when person is still.
//               Recommended: 0.5–2.0 for body landmarks.
//
//   beta      — speed coefficient.
//               Higher → less lag during fast movement but more noise.
//               Recommended: 0.001–0.05 for body landmarks.
//
//   dCutoff   — cutoff for the derivative (speed) signal.
//               Usually left at 1.0.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;

// ─────────────────────────────────────────────────────────────────────────────
// Internal: first-order low-pass filter (building block)
// ─────────────────────────────────────────────────────────────────────────────

class _LowPassFilter {
  _LowPassFilter(double initialValue)
      : _y    = initialValue,
        _dy   = 0.0,
        _initialized = true;

  _LowPassFilter.uninitialized()
      : _y    = 0.0,
        _dy   = 0.0,
        _initialized = false;

  double _y;
  double _dy;
  bool   _initialized;

  double get value => _y;

  /// Filter [x] with smoothing factor [alpha] ∈ (0, 1].
  /// alpha = 1 → no smoothing (raw value).
  /// alpha → 0 → maximum smoothing.
  double filter(double x, double alpha) {
    if (!_initialized) {
      _y           = x;
      _initialized = true;
      return _y;
    }
    _dy = x - _y;
    _y  = alpha * x + (1.0 - alpha) * _y;
    return _y;
  }

  void reset() {
    _initialized = false;
    _y  = 0.0;
    _dy = 0.0;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OneEuroFilter — public API
// ─────────────────────────────────────────────────────────────────────────────

class OneEuroFilter {
  OneEuroFilter({
    this.minCutoff = 1.0,
    this.beta      = 0.007,
    this.dCutoff   = 1.0,
  })  : _xFilter  = _LowPassFilter.uninitialized(),
        _dxFilter = _LowPassFilter.uninitialized(),
        _lastTimestamp = -1.0;

  // ── Configuration ─────────────────────────────────────────────────────────

  /// Minimum cutoff frequency in Hz. Lower = smoother at rest.
  final double minCutoff;

  /// Speed coefficient. Higher = less lag during fast motion.
  final double beta;

  /// Cutoff frequency for the derivative signal.
  final double dCutoff;

  // ── Internal state ────────────────────────────────────────────────────────

  final _LowPassFilter _xFilter;
  final _LowPassFilter _dxFilter;
  double               _lastTimestamp;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Apply the filter to [rawValue] at [timestampSeconds].
  ///
  /// [timestampSeconds] must be monotonically increasing (e.g.
  /// `DateTime.now().millisecondsSinceEpoch / 1000.0`).
  ///
  /// Returns the filtered value.
  double filter(double rawValue, double timestampSeconds) {
    // Compute sampling rate from successive timestamps.
    final double rate = (_lastTimestamp < 0.0)
        ? 120.0                            // Assume 120 Hz on first call
        : 1.0 / (timestampSeconds - _lastTimestamp).abs().clamp(1e-6, 1.0);

    _lastTimestamp = timestampSeconds;

    // ── Derivative (speed) ────────────────────────────────────────────────
    final double dAlpha = _alpha(rate, dCutoff);
    final double dx     = (_xFilter._initialized)
        ? (rawValue - _xFilter.value) * rate
        : 0.0;
    final double dxHat  = _dxFilter.filter(dx, dAlpha);

    // ── Adaptive cutoff based on speed ────────────────────────────────────
    final double cutoff  = minCutoff + beta * dxHat.abs();
    final double xAlpha  = _alpha(rate, cutoff);

    // ── Smoothed value ────────────────────────────────────────────────────
    return _xFilter.filter(rawValue, xAlpha);
  }

  /// Reset internal state — call when tracking is lost or camera switches.
  void reset() {
    _xFilter.reset();
    _dxFilter.reset();
    _lastTimestamp = -1.0;
  }

  // ── Private ───────────────────────────────────────────────────────────────

  /// Compute the EMA alpha from sampling rate and cutoff frequency.
  static double _alpha(double rate, double cutoff) {
    final double te = 1.0 / rate;
    final double tau = 1.0 / (2.0 * math.pi * cutoff);
    return 1.0 / (1.0 + tau / te);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OneEuroFilter2D — convenience wrapper for (x, y) coordinate pairs
// ─────────────────────────────────────────────────────────────────────────────

/// Applies independent [OneEuroFilter] instances to x and y channels.
/// Use this to smooth 2D joint positions.
class OneEuroFilter2D {
  OneEuroFilter2D({
    double minCutoff = 1.0,
    double beta      = 0.007,
    double dCutoff   = 1.0,
  })  : _xf = OneEuroFilter(minCutoff: minCutoff, beta: beta, dCutoff: dCutoff),
        _yf = OneEuroFilter(minCutoff: minCutoff, beta: beta, dCutoff: dCutoff);

  final OneEuroFilter _xf;
  final OneEuroFilter _yf;

  /// Filter a (rawX, rawY) point at [timestampSeconds].
  /// Returns a filtered (x, y) record.
  (double x, double y) filter(
    double rawX,
    double rawY,
    double timestampSeconds,
  ) {
    return (
      _xf.filter(rawX, timestampSeconds),
      _yf.filter(rawY, timestampSeconds),
    );
  }

  /// Reset both axes — call when pose is lost.
  void reset() {
    _xf.reset();
    _yf.reset();
  }
}

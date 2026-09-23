// lib/features/measurements/measurement_providers.dart
// ─────────────────────────────────────────────────────────────────────────────
// Riverpod providers for Phase 3 — CalibrationService, MeasurementEngine,
// and their reactive streams.
//
// These complement pose_providers.dart and follow the same pattern:
//   • Service provider  → lazily resolves singleton from DI container.
//   • Stream provider   → exposes a reactive stream to the widget tree.
//   • State notifier    → for CalibrationData (mutable, user-triggered).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../calibration/calibration_data.dart';
import '../../calibration/calibration_service.dart';
import '../../core/di/service_locator.dart';
import '../../features/measurements/measurement_engine.dart';
import '../../models/measurement_result.dart';

// ── Service providers ─────────────────────────────────────────────────────────

/// Provides the singleton [CalibrationService].
final calibrationServiceProvider = Provider<CalibrationService>((ref) {
  final svc = sl<CalibrationService>();
  ref.onDispose(svc.dispose);
  return svc;
});

/// Provides the singleton [MeasurementEngine].
final measurementEngineProvider = Provider<MeasurementEngine>((ref) {
  final engine = sl<MeasurementEngine>();
  if (!engine.isRunning) engine.start();
  ref.onDispose(engine.dispose);
  return engine;
});

// ── Stream providers ──────────────────────────────────────────────────────────

/// Reactive stream of [MeasurementResult] — emits on every processed frame.
///
/// Each result contains all body measurements in cm (null if uncalibrated)
/// and joint angles in degrees.
final measurementStreamProvider = StreamProvider<MeasurementResult>((ref) {
  return ref.watch(measurementEngineProvider).measurementStream;
});

/// Reactive stream of [CalibrationData] — emits when user re-calibrates.
final calibrationStreamProvider = StreamProvider<CalibrationData>((ref) {
  return ref.watch(calibrationServiceProvider).calibrationStream;
});

/// Provides the current [CalibrationData] synchronously (latest value).
final currentCalibrationProvider = Provider<CalibrationData>((ref) {
  return ref.watch(calibrationServiceProvider).current;
});

// ── Convenience computed providers ────────────────────────────────────────────

/// True if calibration has been performed.
final isCalibrationReadyProvider = Provider<bool>((ref) {
  return ref.watch(currentCalibrationProvider).isCalibrated;
});

/// The latest body height measurement in cm, or null.
final bodyHeightProvider = Provider<double?>((ref) {
  return ref.watch(measurementEngineProvider).lastResult.bodyHeightCm;
});

/// The latest shoulder width in cm, or null.
final shoulderWidthProvider = Provider<double?>((ref) {
  return ref.watch(measurementEngineProvider).lastResult.shoulderWidthCm;
});

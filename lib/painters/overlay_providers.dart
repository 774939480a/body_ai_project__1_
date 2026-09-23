// lib/painters/overlay_providers.dart
// ─────────────────────────────────────────────────────────────────────────────
// Riverpod providers that combine pose and measurement streams into a single
// reactive source consumed by [SkeletonOverlayWidget].
//
// Using a combined provider avoids two separate stream subscriptions in the
// widget tree and ensures the skeleton + overlay repaint together atomically.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/body_tracking/pose_providers.dart';
import '../features/measurements/measurement_providers.dart';
import '../models/measurement_result.dart';
import '../models/pose_data.dart';

// ── Combined overlay state ─────────────────────────────────────────────────

/// Bundles the latest pose and measurement into one record so
/// [SkeletonOverlayWidget] only needs a single provider watch.
typedef OverlayState = ({PoseData? pose, MeasurementResult measurement});

/// Reactive provider of the combined [OverlayState].
///
/// Rebuilds the overlay whenever either the pose OR the measurement changes,
/// which at 30fps will typically be on every frame.
final overlayStateProvider = Provider<OverlayState>((ref) {
  // Watch the latest pose (null = not detected).
  final poseAsync = ref.watch(poseStreamProvider);
  final pose      = poseAsync.valueOrNull;

  // Watch the latest measurement result.
  final measureAsync  = ref.watch(measurementStreamProvider);
  final measurement   = measureAsync.valueOrNull ?? MeasurementResult.empty();

  return (pose: pose, measurement: measurement);
});

/// True when the skeleton is fully visible and measurements are ready to read.
final isBodyReadyProvider = Provider<bool>((ref) {
  final state = ref.watch(overlayStateProvider);
  return state.pose?.isMeasurementReady ?? false;
});

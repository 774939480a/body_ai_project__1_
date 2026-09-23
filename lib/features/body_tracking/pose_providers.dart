// lib/features/body_tracking/pose_providers.dart
// ─────────────────────────────────────────────────────────────────────────────
// Riverpod providers that expose [PoseDetectorService] streams to the widget
// tree without coupling widgets directly to the service layer.
//
// Using StreamProvider means Flutter automatically:
//   • Rebuilds widgets when a new pose arrives.
//   • Shows a loading state while the first frame is processed.
//   • Propagates errors without try/catch in every widget.
//
// All providers are lazy — the detector only starts when first listened to.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/service_locator.dart';
import '../../models/pose_data.dart';
import '../../services/pose_detector_service.dart';

// ── Service provider ──────────────────────────────────────────────────────────

/// Provides the singleton [PoseDetectorService] from the DI container.
final poseDetectorServiceProvider = Provider<PoseDetectorService>(
  (ref) {
    final service = sl<PoseDetectorService>();

    // Ensure the service is started when first accessed.
    if (!service.isRunning) {
      service.start();
    }

    // Stop the service when the provider is disposed (e.g. widget tree teardown)
    ref.onDispose(service.dispose);

    return service;
  },
);

// ── Stream providers ───────────────────────────────────────────────────────────

/// Reactive stream of [PoseData?] — null means no person detected this frame.
///
/// Subscribe in a widget with:
/// ```dart
/// final poseAsync = ref.watch(poseStreamProvider);
/// poseAsync.when(
///   data:    (pose) => ...,
///   loading: ()     => ...,
///   error:   (e, _) => ...,
/// );
/// ```
final poseStreamProvider = StreamProvider<PoseData?>(
  (ref) {
    final service = ref.watch(poseDetectorServiceProvider);
    return service.poseStream;
  },
);

/// Convenience provider — emits only non-null, measurement-ready poses.
/// Widgets that only care about fully-visible body poses use this to avoid
/// handling null checks.
final measurablePoseProvider = StreamProvider<PoseData>(
  (ref) {
    return ref
        .watch(poseDetectorServiceProvider)
        .poseStream
        .where((p) => p != null && p.isMeasurementReady)
        .cast<PoseData>();
  },
);

/// Provides the latest average inference latency in milliseconds.
/// Used by the FPS/debug overlay.
final inferenceLatencyProvider = Provider<double>(
  (ref) {
    return ref.watch(poseDetectorServiceProvider).averageInferenceLatencyMs;
  },
);

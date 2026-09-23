// lib/posture/posture_providers.dart
// ─────────────────────────────────────────────────────────────────────────────
// Riverpod providers that expose [PostureEngine] to the widget tree.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/di/service_locator.dart';
import 'posture_engine.dart';
import 'posture_result.dart';

/// Singleton [PostureEngine] from the DI container.
final postureEngineProvider = Provider<PostureEngine>((ref) {
  final engine = sl<PostureEngine>();
  if (!engine.isRunning) engine.start();
  ref.onDispose(engine.dispose);
  return engine;
});

/// Reactive stream of [PostureResult] — emits on every processed frame.
final postureStreamProvider = StreamProvider<PostureResult>((ref) {
  return ref.watch(postureEngineProvider).postureStream;
});

/// Convenience provider: true when measurements must be suspended.
final measurementSuspendedProvider = Provider<bool>((ref) {
  return ref
      .watch(postureStreamProvider)
      .valueOrNull
      ?.isMeasurementSuspended ?? false;
});

/// Current posture status (synchronous — no async wrapper needed in HUD).
final postureStatusProvider = Provider<PostureStatus>((ref) {
  return ref
      .watch(postureStreamProvider)
      .valueOrNull
      ?.status ?? PostureStatus.analyzing;
});

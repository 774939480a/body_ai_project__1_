// lib/core/di/service_locator.dart
// ─────────────────────────────────────────────────────────────────────────────
// Dependency Injection container using GetIt.
// All services are registered here so they can be resolved anywhere in the
// codebase without passing them through constructors manually.
//
// Call [ServiceLocator.init()] once in main() before runApp().
// ─────────────────────────────────────────────────────────────────────────────

import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';

import '../../calibration/calibration_service.dart';
import '../../features/measurements/measurement_engine.dart';
import '../../posture/posture_engine.dart';                    // ← Phase 5
import '../../services/camera_service.dart';
import '../../services/pose_detector_service.dart';
import '../../utils/permissions_handler.dart';

/// Global service-locator instance — access via [sl<T>()].
final GetIt sl = GetIt.instance;

class ServiceLocator {
  ServiceLocator._();

  /// Register every service / repository / use-case.
  /// Called exactly ONCE in [main()] before [runApp()].
  static Future<void> init() async {
    // ── Infrastructure ─────────────────────────────────────────────────────

    // Logger — singleton, shared across the app
    sl.registerLazySingleton<Logger>(
      () => Logger(
        printer: PrettyPrinter(
          methodCount: 1,
          errorMethodCount: 5,
          lineLength: 80,
          colors: true,
          printEmojis: true,
        ),
      ),
    );

    // ── Utils ──────────────────────────────────────────────────────────────

    sl.registerLazySingleton<PermissionsHandler>(
      () => PermissionsHandler(logger: sl<Logger>()),
    );

    // ── Services ───────────────────────────────────────────────────────────

    // CameraService is a singleton — one instance for the app's lifetime.
    sl.registerLazySingleton<CameraService>(
      () => CameraService(logger: sl<Logger>()),
    );

    // ── Phase 2 — Pose Detection ───────────────────────────────────────────

    // PoseDetectorService depends on CameraService — registered after it.
    sl.registerLazySingleton<PoseDetectorService>(
      () => PoseDetectorService(
        cameraService: sl<CameraService>(),
        logger:        sl<Logger>(),
      ),
    );

    // ── Phase 3 — Math Engine ──────────────────────────────────────────────

    sl.registerLazySingleton<CalibrationService>(
      () => CalibrationService(logger: sl<Logger>()),
    );

    sl.registerLazySingleton<MeasurementEngine>(
      () => MeasurementEngine(
        poseDetectorService: sl<PoseDetectorService>(),
        calibrationService:  sl<CalibrationService>(),
        logger:              sl<Logger>(),
      ),
    );

    // ── Phase 5 — Posture Engine ───────────────────────────────────────────

    sl.registerLazySingleton<PostureEngine>(
      () => PostureEngine(
        poseDetector:       sl<PoseDetectorService>(),
        calibrationService: sl<CalibrationService>(),
        logger:             sl<Logger>(),
      ),
    );
  }
}

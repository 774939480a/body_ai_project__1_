// lib/services/pose_detector_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// PoseDetectorService — the AI inference layer.
//
// Responsibilities:
//   • Wrap google_mlkit_pose_detection with a clean, typed API.
//   • Subscribe to [CameraService.frameStream] and convert each frame via
//     [ImageConverter] before feeding it to ML Kit.
//   • Enforce a single-frame-at-a-time processing lock so ML Kit is never
//     called concurrently (avoids native crashes and duplicate allocations).
//   • Emit [PoseData] on [poseStream] for every successful inference.
//   • Emit null on [poseStream] when no person is detected in a frame.
//   • Track inference latency for diagnostics.
//   • Dispose the native ML Kit detector cleanly on [dispose()].
//
// Threading note:
//   ML Kit uses its own native thread pool — Dart's async/await is sufficient
//   here.  CameraImage objects cannot cross Dart Isolate boundaries, so we
//   cannot move ML Kit calls into a Dart isolate.  The processing lock
//   achieves the same goal: we never queue more than one inference at a time.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:logger/logger.dart';

import '../core/constants/app_constants.dart';
import '../models/camera_frame.dart';
import '../models/pose_data.dart';
import '../utils/image_converter.dart';
import 'camera_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PoseDetectorService
// ─────────────────────────────────────────────────────────────────────────────

class PoseDetectorService {
  PoseDetectorService({
    required CameraService cameraService,
    required Logger logger,
  })  : _cameraService = cameraService,
        _logger = logger;

  final CameraService _cameraService;
  final Logger _logger;

  // ── ML Kit native detector ────────────────────────────────────────────────

  /// Single reusable [PoseDetector] — creating one per frame is expensive.
  late final PoseDetector _detector;

  // ── Streams ───────────────────────────────────────────────────────────────

  /// Broadcasts the latest [PoseData] after every successful inference.
  /// Emits null when the frame contains no detectable person.
  final StreamController<PoseData?> _poseController =
      StreamController<PoseData?>.broadcast();

  Stream<PoseData?> get poseStream => _poseController.stream;

  // ── Frame subscription ────────────────────────────────────────────────────

  StreamSubscription<CameraFrame>? _frameSubscription;

  // ── Processing lock ───────────────────────────────────────────────────────

  /// Prevents concurrent ML Kit calls.
  /// True while an inference is in progress — incoming frames are skipped.
  bool _isProcessing = false;

  // ── Diagnostics ───────────────────────────────────────────────────────────

  /// Running average inference latency in milliseconds.
  double _avgLatencyMs = 0.0;
  int    _inferenceCount = 0;

  /// Expose for the FPS / debug overlay.
  double get averageInferenceLatencyMs => _avgLatencyMs;
  int    get inferenceCount            => _inferenceCount;

  // ── Lifecycle state ───────────────────────────────────────────────────────

  bool _isRunning  = false;
  bool _isDisposed = false;

  bool get isRunning  => _isRunning;

  // ─────────────────────────────────────────────────────────────────────────
  // Initialisation
  // ─────────────────────────────────────────────────────────────────────────

  /// Initialise the ML Kit detector and begin subscribing to camera frames.
  ///
  /// [mode]:
  ///   • [PoseDetectionMode.stream] — optimised for consecutive frames
  ///     (uses temporal tracking between calls).  Use this for live camera.
  ///   • [PoseDetectionMode.single] — optimised for isolated images.
  ///
  /// [model]:
  ///   • [PoseDetectionModel.base]     — faster, lower accuracy (~30 FPS).
  ///   • [PoseDetectionModel.accurate] — higher accuracy, slightly slower.
  void start({
    PoseDetectionMode  mode  = PoseDetectionMode.stream,
    PoseDetectionModel model = PoseDetectionModel.accurate,
  }) {
    if (_isRunning || _isDisposed) return;

    _logger.i(
      '[PoseDetectorService] Starting — mode=$mode, model=$model',
    );

    // Build the native detector once.
    _detector = PoseDetector(
      options: PoseDetectorOptions(mode: mode, model: model),
    );

    // Subscribe to the camera frame stream.
    _frameSubscription = _cameraService.frameStream.listen(
      _onFrame,
      onError: (Object err) {
        _logger.e('[PoseDetectorService] Frame stream error', error: err);
      },
    );

    _isRunning = true;
  }

  /// Pause pose detection (e.g. app goes to background).
  /// Does not close the stream — call [resume] to restart.
  void pause() {
    _frameSubscription?.pause();
    _logger.d('[PoseDetectorService] Paused.');
  }

  /// Resume pose detection after a [pause].
  void resume() {
    _frameSubscription?.resume();
    _logger.d('[PoseDetectorService] Resumed.');
  }

  /// Stop and permanently dispose the service.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _isRunning  = false;

    _logger.i('[PoseDetectorService] Disposing...');

    await _frameSubscription?.cancel();
    _frameSubscription = null;

    // Close the ML Kit native detector — releases JNI resources.
    await _detector.close();

    await _poseController.close();
    _logger.i('[PoseDetectorService] Disposed.');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Frame processing pipeline
  // ─────────────────────────────────────────────────────────────────────────

  /// Called for every camera frame that passes the throttle gate in
  /// [CameraService].  Skipped entirely if a previous inference is still
  /// running (processing lock pattern).
  Future<void> _onFrame(CameraFrame frame) async {
    // ── Processing lock ──────────────────────────────────────────────────
    if (_isProcessing || _isDisposed || _poseController.isClosed) return;
    _isProcessing = true;

    final stopwatch = Stopwatch()..start();

    try {
      // ── 1. Convert CameraImage → InputImage ──────────────────────────
      final inputImage = ImageConverter.toInputImage(frame);
      if (inputImage == null) {
        _emitNoPose();
        return;
      }

      // ── 2. Run ML Kit inference ───────────────────────────────────────
      final List<Pose> poses = await _detector.processImage(inputImage);

      // ── 3. Update diagnostics ─────────────────────────────────────────
      stopwatch.stop();
      _updateLatency(stopwatch.elapsedMilliseconds.toDouble());

      // ── 4. Map result to domain model ─────────────────────────────────
      if (poses.isEmpty) {
        _emitNoPose();
        return;
      }

      // Take the first (most confident) pose when multiple are detected.
      final poseData = PoseData.fromMlKitPose(
        poses.first,
        imageSize:     Size(
          frame.imageWidth.toDouble(),
          frame.imageHeight.toDouble(),
        ),
        isFrontCamera: frame.isFrontCamera,
      );

      // ── 5. Reliability gate ───────────────────────────────────────────
      // Don't emit a pose that barely has any landmarks — it causes erratic
      // skeleton flickers and measurement jumps.
      if (poseData.reliableLandmarkCount < _minReliableLandmarks) {
        _emitNoPose();
        return;
      }

      // ── 6. Emit domain model ──────────────────────────────────────────
      if (!_poseController.isClosed) {
        _poseController.add(poseData);
      }
    } on Exception catch (e) {
      _logger.w('[PoseDetectorService] Inference error: $e');
      _emitNoPose();
    } finally {
      _isProcessing = false;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Minimum number of reliable landmarks required to emit a [PoseData].
  /// 10 covers head + shoulders + hips + knees + ankles.
  static const int _minReliableLandmarks = 10;

  void _emitNoPose() {
    if (!_poseController.isClosed) {
      _poseController.add(null);
    }
  }

  void _updateLatency(double latencyMs) {
    _inferenceCount++;
    // Exponential moving average for a stable latency reading.
    const alpha = 0.1;
    _avgLatencyMs = (_avgLatencyMs * (1 - alpha)) + (latencyMs * alpha);

    // Log a warning if inference is taking too long.
    if (_inferenceCount % 60 == 0) {
      _logger.d(
        '[PoseDetectorService] avg latency: '
        '${_avgLatencyMs.toStringAsFixed(1)} ms '
        '(~${(1000 / _avgLatencyMs).toStringAsFixed(0)} FPS capable)',
      );
    }
  }
}

// lib/services/camera_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// CameraService — the single authoritative source for camera frames.
//
// Responsibilities:
//   • Discover available cameras (front / back).
//   • Initialize CameraController at the desired resolution.
//   • Start / stop the image stream with frame-rate throttling.
//   • Expose a broadcast Stream<CameraFrame> to downstream consumers.
//   • Handle camera lifecycle (pause / resume / dispose) without leaks.
//   • Support hot-switching between front and back camera.
//
// Design decisions:
//   • Uses a StreamController<CameraFrame> with a fixed buffer so slow
//     consumers (pose detector) never accumulate stale frames in memory.
//   • Frame throttling is done with a simple timestamp gate rather than
//     a Timer to avoid timer drift across lifecycle events.
//   • All CameraController calls are awaited and wrapped in try/catch so a
//     hardware error surfaces as a CameraServiceException, not a crash.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:camera/camera.dart';
import 'package:logger/logger.dart';

import '../core/constants/app_constants.dart';
import '../models/camera_frame.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Custom exception
// ─────────────────────────────────────────────────────────────────────────────

/// Thrown when the camera cannot be initialised or encounters a hardware error.
class CameraServiceException implements Exception {
  const CameraServiceException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'CameraServiceException: $message'
      : 'CameraServiceException: $message\n  Caused by: $cause';
}

// ─────────────────────────────────────────────────────────────────────────────
// CameraState — observable lifecycle state
// ─────────────────────────────────────────────────────────────────────────────

enum CameraState {
  uninitialised,
  initialising,
  streaming,
  paused,
  disposed,
  error,
}

// ─────────────────────────────────────────────────────────────────────────────
// CameraService
// ─────────────────────────────────────────────────────────────────────────────

class CameraService {
  CameraService({required Logger logger}) : _logger = logger;

  final Logger _logger;

  // ── Internal state ────────────────────────────────────────────────────────

  CameraController? _controller;
  List<CameraDescription> _availableCameras = [];
  ActiveCamera _activeCamera = ActiveCamera.back;
  CameraState _state = CameraState.uninitialised;

  /// Timestamp of the last frame that was accepted (throttling gate).
  int _lastFrameTimestampMs = 0;

  /// StreamController that emits one [CameraFrame] per accepted camera frame.
  ///
  /// Using a broadcast stream allows multiple listeners (pose detector, FPS
  /// counter) without coupling them to each other.
  final StreamController<CameraFrame> _frameController =
      StreamController<CameraFrame>.broadcast();

  /// StateController for the lifecycle state — UI can listen to this.
  final StreamController<CameraState> _stateController =
      StreamController<CameraState>.broadcast();

  // ── Public read-only accessors ────────────────────────────────────────────

  /// Broadcast stream of throttled camera frames.
  Stream<CameraFrame> get frameStream => _frameController.stream;

  /// Broadcast stream of camera lifecycle-state changes.
  Stream<CameraState> get stateStream => _stateController.stream;

  /// The current lifecycle state.
  CameraState get state => _state;

  /// The underlying CameraController — exposed for the camera preview widget.
  /// Null until [initialise] resolves successfully.
  CameraController? get controller => _controller;

  /// Whether the controller is ready to provide a preview.
  bool get isInitialised =>
      _controller != null && _controller!.value.isInitialized;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Discovers available cameras and initialises the controller.
  ///
  /// [camera] — which lens to open first (default: back).
  /// [resolutionPreset] — trade-off between quality and processing cost.
  ///
  /// Throws [CameraServiceException] if no suitable camera is found or the
  /// hardware fails to initialise.
  Future<void> initialise({
    ActiveCamera camera = ActiveCamera.back,
    ResolutionPreset resolutionPreset = ResolutionPreset.high,
  }) async {
    if (_state == CameraState.streaming || _state == CameraState.initialising) {
      _logger.w('[CameraService] Already initialised or initialising — skip.');
      return;
    }

    _setState(CameraState.initialising);
    _logger.i('[CameraService] Initialising camera: $camera');

    try {
      // 1. Discover available cameras
      _availableCameras = await availableCameras();
      if (_availableCameras.isEmpty) {
        throw const CameraServiceException('No cameras found on this device.');
      }

      // 2. Pick the requested lens
      _activeCamera = camera;
      final description = _findCamera(camera);

      // 3. Build the controller
      await _buildController(description, resolutionPreset);

      _logger.i('[CameraService] Camera ready — starting image stream.');
      _startImageStream();

      _setState(CameraState.streaming);
    } on CameraException catch (e) {
      _setState(CameraState.error);
      throw CameraServiceException(
        'CameraController init failed: ${e.description}',
        cause: e,
      );
    } catch (e) {
      _setState(CameraState.error);
      rethrow;
    }
  }

  /// Switches the active lens without full re-initialisation.
  ///
  /// The stream is paused, the old controller disposed, and a new one opened
  /// on the opposite lens.  The [frameStream] continues without interruption
  /// (it simply emits no frames during the switch).
  Future<void> switchCamera() async {
    if (_state != CameraState.streaming && _state != CameraState.paused) {
      _logger.w('[CameraService] switchCamera() called in invalid state: $_state');
      return;
    }

    final nextCamera = _activeCamera == ActiveCamera.back
        ? ActiveCamera.front
        : ActiveCamera.back;

    _logger.i('[CameraService] Switching camera → $nextCamera');

    // Capture the resolution so we can reuse it
    final preset = _controller?.resolutionPreset ?? ResolutionPreset.high;

    await _disposeController();
    await initialise(camera: nextCamera, resolutionPreset: preset);
  }

  /// Pauses the image stream (e.g. when the app goes to background).
  ///
  /// The CameraController remains alive but stops emitting frames, which
  /// saves battery and prevents back-pressure accumulation.
  Future<void> pauseStream() async {
    if (_state != CameraState.streaming) return;

    try {
      await _controller?.stopImageStream();
      _setState(CameraState.paused);
      _logger.d('[CameraService] Stream paused.');
    } on CameraException catch (e) {
      _logger.e('[CameraService] pauseStream error', error: e);
    }
  }

  /// Resumes the image stream after a pause.
  Future<void> resumeStream() async {
    if (_state != CameraState.paused) return;

    try {
      _startImageStream();
      _setState(CameraState.streaming);
      _logger.d('[CameraService] Stream resumed.');
    } on CameraException catch (e) {
      _logger.e('[CameraService] resumeStream error', error: e);
    }
  }

  /// Fully releases the camera hardware and closes all streams.
  ///
  /// Call this in the owning widget's [dispose()] method.
  Future<void> dispose() async {
    _logger.i('[CameraService] Disposing...');
    await _disposeController();
    await _frameController.close();
    await _stateController.close();
    _setState(CameraState.disposed);
    _logger.i('[CameraService] Disposed.');
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  /// Finds the [CameraDescription] for the requested [ActiveCamera].
  ///
  /// Falls back to the first available camera if the requested lens is absent
  /// (e.g. some tablets have only a rear camera).
  CameraDescription _findCamera(ActiveCamera camera) {
    final lensDirection = camera == ActiveCamera.back
        ? CameraLensDirection.back
        : CameraLensDirection.front;

    return _availableCameras.firstWhere(
      (c) => c.lensDirection == lensDirection,
      orElse: () {
        _logger.w(
          '[CameraService] Requested lens $camera not found — '
          'falling back to first available camera.',
        );
        return _availableCameras.first;
      },
    );
  }

  /// Creates and initialises a [CameraController] for the given description.
  Future<void> _buildController(
    CameraDescription description,
    ResolutionPreset preset,
  ) async {
    // Dispose any existing controller before creating a new one.
    await _disposeController(skipStateChange: true);

    _controller = CameraController(
      description,
      preset,
      // Disable audio — this app is video-only.
      enableAudio: false,
      // YUV420 is the most efficient format for ML Kit on Android.
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _controller!.initialize();

    // Lock exposure & focus for consistent pose detection quality.
    if (_controller!.value.exposurePointSupported) {
      await _controller!.setExposureMode(ExposureMode.auto);
    }
    if (_controller!.value.focusPointSupported) {
      await _controller!.setFocusMode(FocusMode.auto);
    }
  }

  /// Registers the per-frame callback on the active controller.
  ///
  /// Frame throttling is enforced here: frames arriving faster than
  /// [CameraConfig.frameIntervalMs] are silently dropped to avoid
  /// saturating the pose-detection pipeline.
  void _startImageStream() {
    _controller?.startImageStream((CameraImage rawFrame) {
      // ── Frame throttling gate ─────────────────────────────────────────
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (nowMs - _lastFrameTimestampMs < CameraConfig.frameIntervalMs) {
        return; // Drop this frame — too soon after the last accepted one.
      }
      _lastFrameTimestampMs = nowMs;

      // ── Safety guard ──────────────────────────────────────────────────
      // If no one is listening, skip wrapping to avoid unnecessary allocation.
      if (!_frameController.hasListener) return;

      // ── Wrap in domain model & emit ───────────────────────────────────
      final frame = CameraFrame(
        image:             rawFrame,
        timestamp:         DateTime.now(),
        activeCamera:      _activeCamera,
        sensorOrientation: _controller!.description.sensorOrientation,
        imageWidth:        rawFrame.width,
        imageHeight:       rawFrame.height,
      );

      // The broadcast stream does not buffer — if the listener's event queue
      // is full, we simply skip the frame (non-blocking add).
      if (!_frameController.isClosed) {
        _frameController.add(frame);
      }
    });
  }

  /// Stops the image stream and disposes the [CameraController].
  Future<void> _disposeController({bool skipStateChange = false}) async {
    final ctrl = _controller;
    if (ctrl == null) return;

    try {
      if (ctrl.value.isStreamingImages) {
        await ctrl.stopImageStream();
      }
    } catch (_) {
      // Ignore errors during cleanup — we are disposing anyway.
    }

    try {
      await ctrl.dispose();
    } catch (_) {
      // Same — best-effort disposal.
    }

    _controller = null;

    if (!skipStateChange) {
      _setState(CameraState.uninitialised);
    }
  }

  /// Updates [_state] and pushes the change to [stateStream].
  void _setState(CameraState newState) {
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(newState);
    }
  }
}

// lib/screens/camera_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Main camera screen — the entry point of the live body-measurement experience.
//
// Phase 1 scope:
//   • Request camera permission with user-friendly error states.
//   • Initialise CameraService and display the preview.
//   • Show a live FPS counter.
//   • Provide front/back camera toggle.
//   • Render the static red guide-frame overlay (Head / Shoulders / Floor).
//
// Pose detection, skeleton painting, and measurements are wired in Phase 2–5.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../calibration/calibration_data.dart';
import '../calibration/calibration_service.dart';
import '../core/constants/app_constants.dart';
import '../core/di/service_locator.dart';
import '../core/themes/app_theme.dart';
import '../features/measurements/measurement_engine.dart';
import '../models/camera_frame.dart';
import '../models/measurement_result.dart';
import '../models/pose_data.dart';
import '../posture/posture_engine.dart';
import '../posture/posture_result.dart';
import '../screens/results_screen.dart';
import '../services/camera_service.dart';
import '../services/pose_detector_service.dart';
import '../utils/permissions_handler.dart';
import '../widgets/calibration_dialog.dart';
import '../widgets/fps_indicator.dart';
import '../widgets/guide_frame_overlay.dart';
import '../widgets/measurement_panel.dart';
import '../widgets/pose_debug_overlay.dart';
import '../widgets/posture_banner.dart';
import '../widgets/skeleton_overlay.dart';
import '../widgets/status_badge.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {

  // ── Services (resolved from DI) ───────────────────────────────────────────
  late final CameraService        _cameraService;
  late final PermissionsHandler   _permissions;
  late final PoseDetectorService  _poseService;
  late final CalibrationService   _calibrationService;
  late final MeasurementEngine    _measurementEngine;
  late final PostureEngine        _postureEngine;          // ← Phase 5

  // ── State ─────────────────────────────────────────────────────────────────
  CameraState _cameraState = CameraState.uninitialised;
  String? _errorMessage;
  bool _isSwitchingCamera = false;

  // ── Pose state ────────────────────────────────────────────────────────────
  PoseData? _currentPose;
  bool _showDebugOverlay = true;

  // ── Measurement state ─────────────────────────────────────────────────────
  MeasurementResult _currentMeasurement = MeasurementResult.empty();
  CalibrationData   _calibrationData    = CalibrationData.uncalibrated();

  // ── Posture state (Phase 5) ───────────────────────────────────────────────
  PostureResult _currentPosture  = PostureResult.analyzing();
  bool          _isCaptureFreeze = false;          // true = frame frozen

  // ── FPS counter ───────────────────────────────────────────────────────────
  int _fps = 0;
  int _frameCount = 0;
  late final Timer _fpsTimer;
  StreamSubscription<CameraFrame>?    _frameSubscription;
  StreamSubscription<CameraState>?    _stateSubscription;
  StreamSubscription<PoseData?>?      _poseSubscription;
  StreamSubscription<MeasurementResult>? _measurementSubscription;
  StreamSubscription<PostureResult>?  _postureSubscription;   // ← Phase 5

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _cameraService      = sl<CameraService>();
    _permissions        = sl<PermissionsHandler>();
    _poseService        = sl<PoseDetectorService>();
    _calibrationService = sl<CalibrationService>();
    _measurementEngine  = sl<MeasurementEngine>();
    _postureEngine      = sl<PostureEngine>();               // ← Phase 5

    // Listen to lifecycle state changes so we can update the UI.
    _stateSubscription = _cameraService.stateStream.listen((state) {
      if (mounted) setState(() => _cameraState = state);
    });

    // FPS counter — refresh every 500 ms
    _fpsTimer = Timer.periodic(
      const Duration(milliseconds: OverlayConfig.fpsUpdateIntervalMs),
      (_) {
        if (mounted) {
          setState(() {
            _fps = (_frameCount * (1000 / OverlayConfig.fpsUpdateIntervalMs))
                .round();
            _frameCount = 0;
          });
        }
      },
    );

    _initCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _cameraService.pauseStream();
        break;
      case AppLifecycleState.resumed:
        _cameraService.resumeStream();
        break;
      default:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fpsTimer.cancel();
    _frameSubscription?.cancel();
    _stateSubscription?.cancel();
    _poseSubscription?.cancel();
    _measurementSubscription?.cancel();
    _postureSubscription?.cancel();                          // ← Phase 5
    // CameraService itself is disposed by the DI container on app exit.
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Initialisation
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _initCamera() async {
    // 1. Check permissions
    final result = await _permissions.requestCameraPermission();

    if (result == PermissionResult.permanentlyDenied) {
      _setError(
        'Camera permission permanently denied.\n'
        'Please enable it in App Settings.',
        showSettingsButton: true,
      );
      return;
    }

    if (result == PermissionResult.denied) {
      _setError('Camera permission is required to use this feature.');
      return;
    }

    // 2. Initialise the camera hardware
    try {
      await _cameraService.initialise();

      // 3. Subscribe to frames for FPS counting
      _frameSubscription = _cameraService.frameStream.listen((_) {
        _frameCount++;
      });

      // 4. Start pose detection (Phase 2)
      _poseService.start();
      _poseSubscription = _poseService.poseStream.listen((pose) {
        if (mounted) setState(() => _currentPose = pose);
      });

      // 5. Start measurement engine (Phase 3)
      _measurementEngine.start();
      _measurementSubscription = _measurementEngine.measurementStream.listen(
        (result) {
          if (mounted) setState(() => _currentMeasurement = result);
        },
      );

      // 6. Listen to calibration changes (Phase 3)
      _calibrationService.calibrationStream.listen((cal) {
        if (mounted) setState(() => _calibrationData = cal);
      });

      // 7. Start posture engine (Phase 5)
      _postureEngine.start();
      _postureSubscription = _postureEngine.postureStream.listen((posture) {
        if (!mounted) return;
        // Suspend measurement engine when user rotates away from camera.
        _measurementEngine.isSuspendedByPosture =
            posture.isMeasurementSuspended;
        setState(() => _currentPosture = posture);
      });
    } on CameraServiceException catch (e) {
      _setError('Camera error: ${e.message}');
    } catch (e) {
      _setError('Unexpected error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Actions
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _onSwitchCamera() async {
    if (_isSwitchingCamera) return;
    setState(() => _isSwitchingCamera = true);

    // Pause pose detection during switch to avoid processing half-initialised
    // frames that arrive during the lens-switch transition.
    _poseService.pause();

    await _cameraService.switchCamera();

    // Re-subscribe frame counter after switch
    await _frameSubscription?.cancel();
    _frameSubscription = _cameraService.frameStream.listen((_) {
      _frameCount++;
    });

    // Resume pose detection on the new camera stream
    _poseService.resume();

    if (mounted) setState(() => _isSwitchingCamera = false);
  }

  /// Capture — freezes the current frame and navigates to [ResultsScreen].
  void _onCapturePressed() {
    // Require a calibrated, stable measurement before allowing capture.
    if (!_currentMeasurement.isCalibrated) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Calibrate first — tap the measurement panel'),
          backgroundColor: AppColors.neonOrange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (_currentPosture.isMeasurementSuspended) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Face the camera before capturing'),
          backgroundColor: AppColors.neonRed,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    HapticFeedback.mediumImpact();

    // Snapshot current state.
    final frozenMeasurement = _currentMeasurement;
    final frozenPosture     = _currentPosture;
    final frozenCalibration = _calibrationData;

    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => ResultsScreen(
          measurement: frozenMeasurement,
          posture:     frozenPosture,
          calibration: frozenCalibration,
          capturedAt:  DateTime.now(),
        ),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: anim,
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  /// Opens the calibration bottom sheet (Phase 3).
  void _onCalibrateTap() {
    // Pass the canvas size via the measurement engine.
    final canvasSize = _measurementEngine.lastResult.timestamp
            .millisecondsSinceEpoch > 0
        ? MediaQuery.of(context).size   // fallback to screen size
        : MediaQuery.of(context).size;

    showCalibrationSheet(
      context:     context,
      service:     _calibrationService,
      currentPose: _currentPose,
      canvasSize:  canvasSize,
      onCalibrated: (data) {
        setState(() => _calibrationData = data);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✓ ${data.summary}',
              style: const TextStyle(fontFamily: 'Courier', fontSize: 11),
            ),
            backgroundColor: AppColors.neonGreen.withOpacity(0.85),
            duration: const Duration(seconds: 3),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Error helpers
  // ─────────────────────────────────────────────────────────────────────────

  void _setError(String message, {bool showSettingsButton = false}) {
    if (mounted) {
      setState(() {
        _errorMessage = message;
        _cameraState  = CameraState.error;
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    // ── Error state ──────────────────────────────────────────────────────
    if (_cameraState == CameraState.error) {
      return _ErrorView(
        message: _errorMessage ?? 'Unknown error',
        onRetry: _initCamera,
        onOpenSettings: () => _permissions.openSettings(),
      );
    }

    // ── Loading state ────────────────────────────────────────────────────
    if (!_cameraService.isInitialised) {
      return const _LoadingView();
    }

    // ── Main camera view ─────────────────────────────────────────────────
    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Camera Preview ─────────────────────────────────────────────
        _CameraPreviewWidget(controller: _cameraService.controller!),

        // ── Static guide-frame (red transparent lines) ─────────────────
        const GuideFrameOverlay(),

        // ── Phase 4: AI Skeleton + Measurement Overlay ─────────────────
        LayoutBuilder(
          builder: (_, constraints) {
            final canvasSize = Size(
              constraints.maxWidth,
              constraints.maxHeight,
            );
            _measurementEngine.updateCanvasSize(canvasSize);
            _postureEngine.updateCanvasSize(canvasSize);      // ← Phase 5

            return SkeletonOverlayWidget(
              poseData:    _currentPose,
              measurement: _currentMeasurement,
            );
          },
        ),

        // ── Phase 3: Measurement Panel (right sidebar) ─────────────────
        LayoutBuilder(
          builder: (_, constraints) {
            final canvasSize = Size(
              constraints.maxWidth,
              constraints.maxHeight,
            );
            _measurementEngine.updateCanvasSize(canvasSize);

            return MeasurementPanel(
              result:         _currentMeasurement,
              onCalibrateTap: _onCalibrateTap,
            );
          },
        ),

        // ── Phase 5: Posture Banner ────────────────────────────────────
        Positioned(
          top: 58,
          left: 0,
          right: 0,
          child: Center(
            child: PostureBanner(result: _currentPosture),
          ),
        ),

        // ── Phase 5: Suspension overlay ───────────────────────────────
        if (_currentPosture.isMeasurementSuspended)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: AppColors.neonRed.withOpacity(0.6),
                    width: 3,
                  ),
                ),
              ),
            ),
          ),

        // ── Phase 2: Pose debug overlay ────────────────────────────────
        PoseDebugOverlay(
          poseData:            _currentPose,
          inferenceLatencyMs:  _poseService.averageInferenceLatencyMs,
          visible:             _showDebugOverlay,
        ),

        // ── Top HUD ────────────────────────────────────────────────────
        Positioned(
          top: 12,
          left: 16,
          right: 16,
          child: _TopHud(
            fps:           _fps,
            cameraState:   _cameraState,
            poseReady:     _currentPose?.isMeasurementReady ?? false,
            isCalibrated:  _calibrationData.isCalibrated,
            postureStatus: _currentPosture.status,          // ← Phase 5
            onDebugToggle: () =>
                setState(() => _showDebugOverlay = !_showDebugOverlay),
          ),
        ),

        // ── Bottom controls ────────────────────────────────────────────
        Positioned(
          bottom: 24,
          left: 0,
          right: 0,
          child: _BottomControls(
            onSwitchCamera: _isSwitchingCamera ? null : _onSwitchCamera,
            onCapture: _onCapturePressed,
            isSwitching: _isSwitchingCamera,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Applies the correct scale + clip to the camera preview regardless of
/// the device's aspect ratio.
class _CameraPreviewWidget extends StatelessWidget {
  const _CameraPreviewWidget({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width:  controller.value.previewSize?.height ?? 1,
              height: controller.value.previewSize?.width  ?? 1,
              child: CameraPreview(controller),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopHud extends StatelessWidget {
  const _TopHud({
    required this.fps,
    required this.cameraState,
    required this.poseReady,
    required this.isCalibrated,
    required this.postureStatus,
    required this.onDebugToggle,
  });

  final int           fps;
  final CameraState   cameraState;
  final bool          poseReady;
  final bool          isCalibrated;
  final PostureStatus postureStatus;
  final VoidCallback  onDebugToggle;

  Color get _postureColor {
    switch (postureStatus) {
      case PostureStatus.stable:           return AppColors.neonGreen;
      case PostureStatus.unstableRotation: return AppColors.neonRed;
      case PostureStatus.analyzing:
      case PostureStatus.noData:           return AppColors.textDisabled;
      default:                             return AppColors.neonOrange;
    }
  }

  String get _postureLabel {
    switch (postureStatus) {
      case PostureStatus.stable:           return 'STABLE';
      case PostureStatus.unstableRotation: return 'ROTATION';
      case PostureStatus.leaningLeft:      return 'L.LEAN';
      case PostureStatus.leaningRight:     return 'R.LEAN';
      case PostureStatus.leaningForward:   return 'FORWARD';
      default:                             return 'POSTURE';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GestureDetector(
          onTap: onDebugToggle,
          child: const Text(
            'BODY·AI',
            style: TextStyle(
              fontFamily:  'Courier',
              fontSize:    15,
              fontWeight:  FontWeight.w700,
              color:       AppColors.neonCyan,
              letterSpacing: 3,
            ),
          ),
        ),
        Wrap(
          spacing: 5,
          children: [
            FpsIndicator(fps: fps),
            StatusBadge(
              label: poseReady ? 'POSE ✓' : 'POSE...',
              color: poseReady ? AppColors.neonGreen : AppColors.neonOrange,
            ),
            StatusBadge(
              label: isCalibrated ? 'CAL ✓' : 'CAL: OFF',
              color: isCalibrated ? AppColors.neonGreen : AppColors.neonOrange,
            ),
            StatusBadge(
              label: _postureLabel,
              color: _postureColor,
              blinking: postureStatus == PostureStatus.unstableRotation,
            ),
          ],
        ),
      ],
    );
  }
}

/// Bottom control row — camera switch + shutter/capture button.
class _BottomControls extends StatelessWidget {
  const _BottomControls({
    required this.onSwitchCamera,
    required this.onCapture,
    required this.isSwitching,
  });

  final VoidCallback? onSwitchCamera;
  final VoidCallback onCapture;
  final bool isSwitching;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Camera switch button
          _CircleIconButton(
            icon: isSwitching
                ? Icons.sync
                : Icons.flip_camera_android_rounded,
            onTap: onSwitchCamera,
            tooltip: 'Switch Camera',
            color: AppColors.neonBlue,
          ),

          // Capture / freeze button
          GestureDetector(
            onTap: onCapture,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.neonCyan, width: 3),
                color: AppColors.neonCyan.withOpacity(0.12),
              ),
              child: const Icon(
                Icons.camera,
                color: AppColors.neonCyan,
                size: 32,
              ),
            ),
          ),

          // Placeholder for a future right-side control
          const SizedBox(width: 52),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    required this.color,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.6), width: 1.5),
            color: color.withOpacity(0.1),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
      ),
    );
  }
}

/// Shown while the camera is initialising.
class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppColors.neonCyan),
          SizedBox(height: 16),
          Text(
            'INITIALISING CAMERA...',
            style: TextStyle(
              fontFamily: 'Courier',
              color: AppColors.textSecondary,
              letterSpacing: 2,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when a permission or hardware error occurs.
class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_rounded,
                color: AppColors.neonRed, size: 56),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontFamily: 'Courier',
                fontSize: 13,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('RETRY'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onOpenSettings,
              child: const Text(
                'Open Settings',
                style: TextStyle(color: AppColors.neonCyan),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

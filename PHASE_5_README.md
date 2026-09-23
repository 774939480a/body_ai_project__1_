# Phase 5 — Posture Analysis & UI Finalization ✅

## Files Created / Updated

```
lib/posture/
 ├── posture_result.dart     ← immutable PostureResult model + PostureStatus enum
 ├── posture_engine.dart     ← full posture analysis: tilt, z-skew, stability FSM
 └── posture_providers.dart  ← Riverpod providers for posture stream

lib/screens/
 └── results_screen.dart     ← frozen-frame results: measurements + angles + posture

lib/widgets/
 └── posture_banner.dart     ← animated slide-in banner (STABLE/LEANING/ROTATION)

Updated:
 ├── service_locator.dart    ← registers PostureEngine
 ├── measurement_engine.dart ← isSuspendedByPosture gate
 └── camera_screen.dart      ← PostureEngine wired, capture→ResultsScreen, banner
```

---

## Complete Project Architecture

```
lib/
 ├── core/
 │   ├── constants/     app_constants.dart
 │   ├── themes/        app_theme.dart
 │   └── di/            service_locator.dart
 │
 ├── models/
 │   ├── camera_frame.dart
 │   ├── joint_point.dart
 │   ├── pose_data.dart
 │   ├── pose_connections.dart
 │   └── measurement_result.dart
 │
 ├── services/
 │   ├── camera_service.dart          Phase 1
 │   └── pose_detector_service.dart   Phase 2
 │
 ├── calibration/
 │   ├── calibration_data.dart        Phase 3
 │   └── calibration_service.dart     Phase 3
 │
 ├── math/
 │   ├── one_euro_filter.dart         Phase 3
 │   ├── pose_smoother.dart           Phase 3
 │   └── body_math.dart               Phase 3
 │
 ├── features/
 │   ├── body_tracking/
 │   │   └── pose_providers.dart      Phase 2
 │   └── measurements/
 │       ├── measurement_engine.dart  Phase 3
 │       └── measurement_providers.dart Phase 3
 │
 ├── posture/
 │   ├── posture_result.dart          Phase 5
 │   ├── posture_engine.dart          Phase 5
 │   └── posture_providers.dart       Phase 5
 │
 ├── painters/
 │   ├── painter_utils.dart           Phase 4
 │   ├── skeleton_painter.dart        Phase 4
 │   ├── overlay_painter.dart         Phase 4
 │   └── overlay_providers.dart       Phase 4
 │
 ├── screens/
 │   ├── camera_screen.dart           All Phases
 │   └── results_screen.dart          Phase 5
 │
 ├── widgets/
 │   ├── fps_indicator.dart           Phase 1
 │   ├── guide_frame_overlay.dart     Phase 1
 │   ├── status_badge.dart            Phase 1
 │   ├── pose_debug_overlay.dart      Phase 2
 │   ├── calibration_dialog.dart      Phase 3
 │   ├── measurement_panel.dart       Phase 3
 │   ├── skeleton_overlay.dart        Phase 4
 │   └── posture_banner.dart          Phase 5
 │
 ├── utils/
 │   ├── permissions_handler.dart
 │   └── image_converter.dart
 │
 └── main.dart
```

---

## Complete Data Flow

```
Mobile Camera
    │
    ▼ (30 FPS, YUV420)
CameraService.frameStream
    │
    ├──► PoseDetectorService (ML Kit, processing lock)
    │         │
    │         ▼ Stream<PoseData?>
    │    ┌────┴────────────────────────┐
    │    │                             │
    │    ▼                             ▼
    │  MeasurementEngine          PostureEngine
    │  (PoseSmoother +            (tilt, z-skew,
    │   rolling average)           stability FSM)
    │    │                             │
    │    ▼                             ▼
    │  Stream<MeasurementResult>  Stream<PostureResult>
    │    │                             │
    └────┴─────────────────────────────┘
                      │
                      ▼
               CameraScreen (setState)
                      │
          ┌───────────┼───────────────┐
          ▼           ▼               ▼
    SkeletonOverlay  PostureBanner  MeasurementPanel
    (Phase 4)        (Phase 5)      (Phase 3)
          │
    ┌─────┴──────┐
    ▼            ▼
SkeletonPainter OverlayPainter
(bones+joints)  (angles+spans+height)
```

---

## Posture State Machine

```
     ┌──────────────┐
     │  NO POSE /   │
     │  ANALYZING   │◄── pose stream null / < 4 stable frames
     └──────┬───────┘
            │ pose detected
            ▼
     ┌──────────────┐      z-skew > 0.35      ┌────────────────────┐
     │  TILT CHECK  │─────────────────────────►│ UNSTABLE ROTATION  │
     └──────┬───────┘                          │ (measurements      │
            │                                  │  suspended, red    │
            │ |shoulderTilt| > 5°              │  border + banner)  │
            ▼                                  └────────────────────┘
     ┌──────────────┐
     │  LEANING     │  LEFT / RIGHT / FORWARD
     │  (orange     │◄── stable counter reset
     │   banner)    │
     └──────┬───────┘
            │ all within thresholds × 8 frames
            ▼
     ┌──────────────┐
     │    STABLE    │  green flash → banner hides
     └──────────────┘
```

---

## Capture Flow

```
User taps Shutter ──► validation:
   • isCalibrated?     NO  → SnackBar "calibrate first"
   • isSuspended?      YES → SnackBar "face the camera"
   • Both OK           ──► snapshot frozen state
                           ──► Navigator.push(ResultsScreen)
                                │
                                ▼
                         ResultsScreen
                         ├── measurements grid
                         ├── joint angles tiles
                         ├── posture metrics
                         └── COPY to clipboard / RETAKE
```

---

## Running the App

```bash
# 1. Install dependencies
flutter pub get

# 2. Connect Android device (API 21+)
# 3. Ensure AndroidManifest has CAMERA permission + ML Kit meta-data
# 4. Run
flutter run --release   # release for best performance
```

### Performance expectations

| Device class        | Expected FPS | ML Kit latency |
|---------------------|-------------|----------------|
| Flagship (SD 8 Gen) | 28–30 FPS   | 25–40 ms       |
| Mid-range (SD 665)  | 22–27 FPS   | 40–70 ms       |
| Budget (SD 460)     | 15–22 FPS   | 70–110 ms      |

If FPS is low, switch to `PoseDetectionModel.base` in `PoseDetectorService`.

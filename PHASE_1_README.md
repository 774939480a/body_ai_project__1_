# Phase 1 — Setup Checklist & Notes

## 1. AndroidManifest.xml — Required Permissions

Add the following inside `<manifest>` in `android/app/src/main/AndroidManifest.xml`:

```xml
<!-- Camera hardware access -->
<uses-permission android:name="android.permission.CAMERA" />
<uses-feature android:name="android.hardware.camera" android:required="true" />
<uses-feature android:name="android.hardware.camera.autofocus" />

<!-- Required for google_mlkit_pose_detection (Phase 2) -->
<uses-feature android:name="android.hardware.camera.front" android:required="false" />
```

Inside `<application>`:
```xml
<meta-data
    android:name="com.google.mlkit.vision.DEPENDENCIES"
    android:value="pose" />
```

---

## 2. android/app/build.gradle — minSdkVersion

```groovy
android {
    defaultConfig {
        minSdkVersion 21   // ML Kit requires API 21+
        targetSdkVersion 34
        compileSdkVersion 34
    }
}
```

---

## 3. Folder structure created in Phase 1

```
lib/
 ├── core/
 │   ├── constants/   app_constants.dart
 │   ├── themes/      app_theme.dart
 │   └── di/          service_locator.dart
 ├── models/          camera_frame.dart
 ├── screens/         camera_screen.dart
 ├── services/        camera_service.dart      ← MAIN DELIVERABLE
 ├── utils/           permissions_handler.dart
 ├── widgets/
 │   ├── fps_indicator.dart
 │   ├── guide_frame_overlay.dart
 │   └── status_badge.dart
 └── main.dart
```

---

## 4. Phase 2 Preview — What comes next

Phase 2 will add:
- `lib/services/pose_detector_service.dart`  — wraps ML Kit, runs in isolate
- `lib/models/pose_data.dart`               — 33-landmark PoseData model
- `lib/models/joint_point.dart`             — individual landmark with visibility
- Integration into `CameraScreen.frameStream` listener
- Landmark coordinate normalisation + orientation correction

---

## 5. Key Design Decisions (Phase 1)

| Decision | Rationale |
|---|---|
| `broadcast()` stream | Allows FPS counter + pose detector to share the same stream independently |
| Frame throttling (timestamp gate) | Simpler & lower overhead than a Timer; immune to timer drift |
| `RepaintBoundary` on guide overlay | Static widget — prevents it triggering camera preview repaints |
| `WidgetsBindingObserver` | Correct way to pause/resume camera on app lifecycle changes |
| `ResolutionPreset.high` default | Best quality/performance balance; can be lowered per device |

# Phase 2 — Android Configuration

## AndroidManifest.xml  (`android/app/src/main/AndroidManifest.xml`)

Add inside `<manifest>`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-feature android:name="android.hardware.camera" android:required="true" />
<uses-feature android:name="android.hardware.camera.autofocus" />
```

Add inside `<application>` — this triggers ML Kit to **bundle the pose model**
inside the APK so it works 100% offline without a download on first use:

```xml
<meta-data
    android:name="com.google.mlkit.vision.DEPENDENCIES"
    android:value="pose_accurate" />
```

> Use `"pose"` for the lighter base model, `"pose_accurate"` for the accurate model.
> This matches `PoseDetectionModel.accurate` in `PoseDetectorService`.

---

## android/app/build.gradle

```groovy
android {
    defaultConfig {
        minSdkVersion 21          // ML Kit hard requirement
        targetSdkVersion 34
        compileSdkVersion 34
        multiDexEnabled true      // Required for ML Kit on API < 21
    }
}

dependencies {
    implementation 'com.android.support:multidex:1.0.3'
}
```

---

## ProGuard / R8  (`android/app/proguard-rules.pro`)

If you build a release APK with minification enabled, add:

```
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.mlkit.**
```

---

## Verify integration

Run in debug mode and watch logcat for:

```
[PoseDetectorService] Starting — mode=PoseDetectionMode.stream, model=PoseDetectionModel.accurate
[PoseDetectorService] avg latency: XX.X ms (~YY FPS capable)
```

If you see latency > 100 ms on a mid-range device, switch to `PoseDetectionModel.base`
in `PoseDetectorService.start()`.

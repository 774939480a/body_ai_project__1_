# Phase 4 — CustomPainter: Skeleton & Measurement Overlay

## Files created

```
lib/painters/
 ├── painter_utils.dart      ← shared Canvas primitives (bones, joints, labels, arcs)
 ├── skeleton_painter.dart   ← neon skeleton layer (bones + joints + body axis)
 ├── overlay_painter.dart    ← data layer (angles + spans + height indicator)
 └── overlay_providers.dart  ← Riverpod combined pose+measurement provider

lib/widgets/
 └── skeleton_overlay.dart   ← mounts both painters in RepaintBoundary stack
```

---

## Layer draw order

```
Camera Preview                  (CameraPreview widget)
 └─ GuideFrameOverlay           (static red guide lines — never repaints)
     └─ SkeletonOverlayWidget
         ├─ RepaintBoundary
         │   └─ SkeletonPainter    (bones → joints → body axis)
         └─ RepaintBoundary
             └─ OverlayPainter     (alignment → angle arcs → spans → height)
         └─ MeasurementPanel       (right sidebar)
         └─ PoseDebugOverlay       (bottom debug strip)
         └─ TopHud                 (FPS + status badges)
         └─ BottomControls         (capture + camera switch)
```

---

## Neon glow effect — two-pass strategy

Every bone line and joint circle is drawn **twice**:

| Pass | Width      | Opacity | MaskFilter                      | Purpose        |
|------|------------|---------|---------------------------------|----------------|
| 1    | 4.5×       | 22 %    | `BlurStyle.normal, sigma=6`     | Soft glow halo |
| 2    | 1×         | 100 %   | none                            | Sharp core     |

This mimics a real neon tube without GPU shaders and works on mid-range Android.

---

## Performance characteristics

| Metric            | Value                                           |
|-------------------|-------------------------------------------------|
| Repaint trigger   | `poseData.timestamp` change (timestamp guard)   |
| Painters per frame| 2 (skeleton + overlay)                          |
| TextPainter calls | ~10–15 per frame (measurement labels)           |
| MaskFilter blurs  | ~40 per frame (35 bones × 2-pass + 33 joints)  |
| Target            | ≥ 25 FPS on mid-range Android (Snapdragon 665+) |

If FPS drops below 20, disable glow by setting `MaskFilter` to null in
`PainterUtils.drawBone` and `PainterUtils.drawJoint`.

---

## Measurement label positions

| Label          | Anchor joint      | Offset direction    |
|----------------|-------------------|---------------------|
| Shoulder Width | L+R shoulder mid  | -16 px vertical     |
| Hip Width      | L+R hip mid       | +14 px vertical     |
| L. Arm         | Left elbow        | -46 px horizontal   |
| R. Arm         | Right elbow       | +46 px horizontal   |
| Torso          | Mid shoulder+hip  | +50 px horizontal   |
| L. Thigh       | Left knee         | -48 px horizontal   |
| R. Thigh       | Right knee        | +48 px horizontal   |
| Height         | Left of body axis | bracket + label     |

---

## Phase 5 — what comes next

Phase 5 will add:
- `PostureEngine` — stability analysis, z-skew detection, UNSTABLE ROTATION banner
- `ResultsScreen` — frozen frame with final measurements export
- Shutter/Capture button fully wired
- A4 paper drag-line calibration UI
- `PostureStatusBanner` — overlay banner (STABLE / LEANING LEFT / UNSTABLE ROTATION)

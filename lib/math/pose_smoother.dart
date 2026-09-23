// lib/math/pose_smoother.dart
// ─────────────────────────────────────────────────────────────────────────────
// PoseSmoother — applies independent [OneEuroFilter2D] instances to every
// landmark in a [PoseData] snapshot.
//
// Problem solved:
//   Raw ML Kit landmarks flicker several pixels between consecutive frames
//   even when the person is perfectly still.  This causes measurement numbers
//   to jump ± 1–3 cm and the skeleton overlay to vibrate visibly.
//
// Solution:
//   Maintain one [OneEuroFilter2D] per [PoseLandmarkType] (33 filters total).
//   Each frame, smooth every landmark's (x, y) independently.
//   The z-coordinate is smoothed with a separate 1D filter per landmark.
//
// Lifecycle:
//   • [PoseSmoother] is a long-lived object — create once and reuse.
//   • Call [reset()] when the person leaves the frame (pose = null) so the
//     filter doesn't accumulate stale history that produces a "snap" artefact
//     when they return.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../core/constants/app_constants.dart';
import '../models/joint_point.dart';
import '../models/pose_data.dart';
import 'one_euro_filter.dart';

class PoseSmoother {
  PoseSmoother({
    double minCutoff = FilterConfig.minCutoff,
    double beta      = FilterConfig.beta,
    double dCutoff   = FilterConfig.dCutoff,
  }) : _minCutoff = minCutoff,
       _beta      = beta,
       _dCutoff   = dCutoff {
    _initFilters();
  }

  final double _minCutoff;
  final double _beta;
  final double _dCutoff;

  // One 2D filter per landmark for (x, y).
  final Map<PoseLandmarkType, OneEuroFilter2D> _xy = {};

  // One 1D filter per landmark for z (depth).
  final Map<PoseLandmarkType, OneEuroFilter>   _z  = {};

  // ── Public API ────────────────────────────────────────────────────────────

  /// Apply smoothing to every landmark in [raw] and return a new [PoseData]
  /// with filtered coordinates.
  ///
  /// The returned object has the same metadata (timestamp, imageSize,
  /// isFrontCamera) as [raw] — only the landmark positions are altered.
  PoseData smooth(PoseData raw) {
    final ts   = raw.timestamp.millisecondsSinceEpoch / 1000.0;
    final smoothed = <PoseLandmarkType, JointPoint>{};

    for (final entry in raw.landmarks.entries) {
      final type  = entry.key;
      final joint = entry.value;

      // Ensure filters exist for this landmark type.
      _xy.putIfAbsent(
        type,
        () => OneEuroFilter2D(
          minCutoff: _minCutoff,
          beta:      _beta,
          dCutoff:   _dCutoff,
        ),
      );
      _z.putIfAbsent(
        type,
        () => OneEuroFilter(
          minCutoff: _minCutoff,
          beta:      _beta,
          dCutoff:   _dCutoff,
        ),
      );

      // Filter coordinates.
      final (sx, sy) = _xy[type]!.filter(joint.x, joint.y, ts);
      final double sz = _z[type]!.filter(joint.z, ts);

      smoothed[type] = JointPoint(
        type:       type,
        x:          sx.clamp(0.0, 1.0),
        y:          sy.clamp(0.0, 1.0),
        z:          sz,
        likelihood: joint.likelihood,   // confidence is not smoothed
      );
    }

    return PoseData(
      landmarks:     smoothed,
      timestamp:     raw.timestamp,
      imageSize:     raw.imageSize,
      isFrontCamera: raw.isFrontCamera,
    );
  }

  /// Reset all internal filter histories.
  ///
  /// Call when the pose stream emits null (person left frame) to prevent
  /// stale history from snapping when the person re-enters.
  void reset() {
    for (final f in _xy.values) f.reset();
    for (final f in _z.values)  f.reset();
  }

  // ── Private ───────────────────────────────────────────────────────────────

  void _initFilters() {
    // Pre-allocate filters for all 33 known landmark types so the first frame
    // doesn't incur allocation overhead.
    for (final type in PoseLandmarkType.values) {
      _xy[type] = OneEuroFilter2D(
        minCutoff: _minCutoff,
        beta:      _beta,
        dCutoff:   _dCutoff,
      );
      _z[type] = OneEuroFilter(
        minCutoff: _minCutoff,
        beta:      _beta,
        dCutoff:   _dCutoff,
      );
    }
  }
}

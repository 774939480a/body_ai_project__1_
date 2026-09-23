// lib/widgets/guide_frame_overlay.dart
// ─────────────────────────────────────────────────────────────────────────────
// Static red transparent guide frame — drawn with CustomPainter.
// Three horizontal reference lines: Head Level, Shoulder Axis, Floor Level.
// The outer rectangle acts as a full-body framing guide.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../core/themes/app_theme.dart';
import '../core/constants/app_constants.dart';

class GuideFrameOverlay extends StatelessWidget {
  const GuideFrameOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      // RepaintBoundary isolates repaints — this widget is STATIC so it
      // should almost never repaint. The boundary prevents the camera preview
      // from triggering unnecessary redraws of this layer.
      child: CustomPaint(
        painter: _GuideFramePainter(),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _GuideFramePainter extends CustomPainter {
  // ── Paints ────────────────────────────────────────────────────────────────

  /// Outer rectangle border — solid red, partially transparent.
  final Paint _borderPaint = Paint()
    ..color = AppColors.guideFrameRed
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;

  /// Horizontal guide lines — more transparent than the border.
  final Paint _linePaint = Paint()
    ..color = AppColors.guideLineColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;

  /// Corner tick marks — opaque accent.
  final Paint _cornerPaint = Paint()
    ..color = AppColors.neonRed.withOpacity(0.85)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5
    ..strokeCap = StrokeCap.round;

  // ── Layout proportions (relative to canvas size) ─────────────────────────

  /// Horizontal inset of the guide rectangle as a fraction of canvas width.
  static const double _hInset = 0.08;

  /// Vertical inset of the guide rectangle as a fraction of canvas height.
  static const double _vInset = 0.04;

  /// Vertical position of the "Head Level" guide line (fraction of height).
  static const double _headLevelFraction = 0.12;

  /// Vertical position of the "Shoulder Axis" guide line (fraction of height).
  static const double _shoulderFraction = 0.30;

  /// Vertical position of the "Floor Level" guide line (fraction of height).
  static const double _floorFraction = 0.90;

  /// Length of each corner tick mark in logical pixels.
  static const double _cornerLength = 18.0;

  // ── Draw ──────────────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    final left   = size.width  * _hInset;
    final right  = size.width  * (1 - _hInset);
    final top    = size.height * _vInset;
    final bottom = size.height * (1 - _vInset);

    final guideRect = Rect.fromLTRB(left, top, right, bottom);

    // 1. Outer rectangle
    canvas.drawRect(guideRect, _borderPaint);

    // 2. Corner tick marks (L-shaped highlights at each corner)
    _drawCornerTicks(canvas, guideRect);

    // 3. Horizontal guide lines with labels
    _drawGuideLine(
      canvas, size,
      fraction: _headLevelFraction,
      label: '── HEAD LEVEL',
      left: left, right: right,
    );

    _drawGuideLine(
      canvas, size,
      fraction: _shoulderFraction,
      label: '── SHOULDER AXIS',
      left: left, right: right,
    );

    _drawGuideLine(
      canvas, size,
      fraction: _floorFraction,
      label: '── FLOOR LEVEL',
      left: left, right: right,
    );
  }

  void _drawCornerTicks(Canvas canvas, Rect rect) {
    final tl = rect.topLeft;
    final tr = rect.topRight;
    final bl = rect.bottomLeft;
    final br = rect.bottomRight;
    final c  = _cornerLength;

    // Top-left
    canvas.drawLine(tl, tl + Offset(c, 0), _cornerPaint);
    canvas.drawLine(tl, tl + Offset(0, c), _cornerPaint);

    // Top-right
    canvas.drawLine(tr, tr + Offset(-c, 0), _cornerPaint);
    canvas.drawLine(tr, tr + Offset(0,   c), _cornerPaint);

    // Bottom-left
    canvas.drawLine(bl, bl + Offset(c,   0), _cornerPaint);
    canvas.drawLine(bl, bl + Offset(0,  -c), _cornerPaint);

    // Bottom-right
    canvas.drawLine(br, br + Offset(-c,  0), _cornerPaint);
    canvas.drawLine(br, br + Offset(0,  -c), _cornerPaint);
  }

  void _drawGuideLine(
    Canvas canvas,
    Size size, {
    required double fraction,
    required String label,
    required double left,
    required double right,
  }) {
    final y = size.height * fraction;

    // Dashed-style line (drawn as two segments: left and right of label)
    canvas.drawLine(Offset(left, y), Offset(right, y), _linePaint);

    // Label — drawn to the right inside the frame
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontFamily: 'Courier',
          fontSize: OverlayConfig.labelFontSize,
          color: AppColors.guideFrameRed,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(
      canvas,
      Offset(left + 6, y - tp.height - 3),
    );
  }

  // This painter is purely static — never needs to repaint.
  @override
  bool shouldRepaint(_GuideFramePainter oldDelegate) => false;
}

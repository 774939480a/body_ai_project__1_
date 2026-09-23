// lib/painters/painter_utils.dart
// ─────────────────────────────────────────────────────────────────────────────
// PainterUtils — shared Canvas drawing primitives.
//
// All methods are static and pure — they accept a [Canvas] and draw to it
// without holding any state.  Both [SkeletonPainter] and [OverlayPainter]
// import this file rather than duplicating low-level drawing logic.
//
// Neon glow effect strategy:
//   Each line/circle is drawn twice:
//     Pass 1 — wide, blurred, low-opacity stroke  → "halo / glow"
//     Pass 2 — narrow, sharp, full-opacity stroke → "core"
//   This mimics a real neon tube without requiring GPU shaders.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../core/themes/app_theme.dart';

class PainterUtils {
  PainterUtils._();

  // ── Reusable Paint objects (allocated once, mutated per draw call) ─────────
  static final Paint _glowPaint  = Paint()..style = PaintingStyle.stroke;
  static final Paint _corePaint  = Paint()..style = PaintingStyle.stroke
                                                   ..strokeCap = StrokeCap.round;
  static final Paint _fillPaint  = Paint()..style = PaintingStyle.fill;
  static final Paint _bgPaint    = Paint()..style = PaintingStyle.fill;
  static final Paint _borderPaint= Paint()..style = PaintingStyle.stroke;

  // ── Bone / line drawing ───────────────────────────────────────────────────

  /// Draw a neon bone between [start] and [end] with a soft glow halo.
  ///
  /// [color]       — bone colour (from [PoseConnections]).
  /// [strokeWidth] — core line width in logical pixels.
  /// [opacity]     — additional opacity multiplier (1.0 = fully opaque).
  static void drawBone(
    Canvas canvas,
    Offset start,
    Offset end,
    Color color, {
    double strokeWidth = OverlayConfig.boneStrokeWidth,
    double opacity = 1.0,
  }) {
    // ── Glow halo ───────────────────────────────────────────────────────
    _glowPaint
      ..color       = color.withOpacity(0.22 * opacity)
      ..strokeWidth = strokeWidth * 4.5
      ..maskFilter  = const MaskFilter.blur(BlurStyle.normal, 6.0);
    canvas.drawLine(start, end, _glowPaint);

    // ── Core line ────────────────────────────────────────────────────────
    _corePaint
      ..color       = color.withOpacity(opacity)
      ..strokeWidth = strokeWidth
      ..maskFilter  = null;
    canvas.drawLine(start, end, _corePaint);
  }

  /// Draw a dashed line (used for alignment guides and axis lines).
  static void drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Color color, {
    double strokeWidth = 1.0,
    double dashLen     = 8.0,
    double gapLen      = 5.0,
  }) {
    final totalLen = (end - start).distance;
    if (totalLen < 1e-6) return;

    final dir      = (end - start) / totalLen;
    double drawn   = 0.0;
    bool   drawing = true;

    final paint = Paint()
      ..color       = color
      ..strokeWidth = strokeWidth
      ..strokeCap   = StrokeCap.round;

    while (drawn < totalLen) {
      final segLen = drawing ? dashLen : gapLen;
      final segEnd = math.min(drawn + segLen, totalLen);

      if (drawing) {
        canvas.drawLine(
          start + dir * drawn,
          start + dir * segEnd,
          paint,
        );
      }

      drawn   += segLen;
      drawing  = !drawing;
    }
  }

  // ── Joint drawing ─────────────────────────────────────────────────────────

  /// Draw a neon joint circle at [center] with a glow halo.
  ///
  /// [color]      — joint colour (usually [AppColors.skeletonJoint]).
  /// [radius]     — outer radius in logical pixels.
  /// [likelihood] — confidence [0,1]: low-confidence joints are drawn dimmer.
  static void drawJoint(
    Canvas canvas,
    Offset center,
    Color color, {
    double radius     = OverlayConfig.jointRadius,
    double likelihood = 1.0,
  }) {
    final opacity = (likelihood * 0.7 + 0.3).clamp(0.0, 1.0);

    // ── Glow ────────────────────────────────────────────────────────────
    _glowPaint
      ..color       = color.withOpacity(0.30 * opacity)
      ..strokeWidth = radius * 1.8
      ..maskFilter  = const MaskFilter.blur(BlurStyle.normal, 5.0);
    canvas.drawCircle(center, radius * 1.2, _glowPaint);

    // ── Outer ring ───────────────────────────────────────────────────────
    _borderPaint
      ..color       = color.withOpacity(0.85 * opacity)
      ..strokeWidth = 1.5
      ..maskFilter  = null;
    canvas.drawCircle(center, radius, _borderPaint);

    // ── Inner filled dot ─────────────────────────────────────────────────
    _fillPaint
      ..color = color.withOpacity(0.55 * opacity);
    canvas.drawCircle(center, radius * 0.45, _fillPaint);
  }

  // ── Angle arc ─────────────────────────────────────────────────────────────

  /// Draw an angle arc at [vertex] between rays toward [rayA] and [rayC].
  ///
  /// [angleDeg] — the pre-computed angle (from [BodyMath.angleDeg]) shown
  ///              as a label near the arc.
  /// [color]    — arc / label colour.
  /// [arcRadius]— arc radius in logical pixels.
  static void drawAngleArc(
    Canvas canvas,
    Offset vertex,
    Offset rayA,
    Offset rayC,
    double angleDeg,
    Color color, {
    double arcRadius = 22.0,
  }) {
    // Direction angles from vertex to each ray endpoint.
    final angleToA = math.atan2(rayA.dy - vertex.dy, rayA.dx - vertex.dx);
    final angleToC = math.atan2(rayC.dy - vertex.dy, rayC.dx - vertex.dx);

    // Compute sweep — always take the shorter arc.
    double sweep = angleToC - angleToA;
    if (sweep >  math.pi) sweep -= 2 * math.pi;
    if (sweep < -math.pi) sweep += 2 * math.pi;

    final arcRect = Rect.fromCircle(center: vertex, radius: arcRadius);

    // Glow arc.
    canvas.drawArc(
      arcRect, angleToA, sweep, false,
      Paint()
        ..color       = color.withOpacity(0.25)
        ..strokeWidth = 4.0
        ..style       = PaintingStyle.stroke
        ..maskFilter  = const MaskFilter.blur(BlurStyle.normal, 3.0),
    );

    // Core arc.
    canvas.drawArc(
      arcRect, angleToA, sweep, false,
      Paint()
        ..color       = color
        ..strokeWidth = 1.5
        ..style       = PaintingStyle.stroke
        ..maskFilter  = null,
    );

    // Label: position along the bisecting angle, just outside the arc.
    final bisect   = angleToA + sweep / 2.0;
    final labelPos = vertex + Offset(
      math.cos(bisect) * (arcRadius + 13),
      math.sin(bisect) * (arcRadius + 13),
    );

    drawLabel(
      canvas,
      '${angleDeg.toStringAsFixed(0)}°',
      labelPos,
      color,
      fontSize: 9.0,
    );
  }

  // ── Text label with background pill ──────────────────────────────────────

  /// Draw a text label with a dark rounded-rect background for readability.
  ///
  /// [text]     — label content.
  /// [center]   — canvas position (label is centred here).
  /// [color]    — text and border colour.
  /// [fontSize] — label font size.
  static void drawLabel(
    Canvas canvas,
    String text,
    Offset center,
    Color color, {
    double fontSize   = OverlayConfig.labelFontSize,
    bool   showBorder = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color:      color,
          fontSize:   fontSize,
          fontWeight: FontWeight.w700,
          fontFamily: 'Courier',
          letterSpacing: 0.4,
          // Soft text shadow for extra legibility on busy backgrounds.
          shadows: [
            Shadow(
              color:  Colors.black.withOpacity(0.85),
              blurRadius: 3,
              offset: const Offset(0.5, 0.5),
            ),
          ],
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();

    final hPad = 5.0;
    final vPad = 3.0;
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center,
        width:  tp.width  + hPad * 2,
        height: tp.height + vPad * 2,
      ),
      const Radius.circular(4),
    );

    // Background.
    _bgPaint.color = Colors.black.withOpacity(0.62);
    canvas.drawRRect(bgRect, _bgPaint);

    // Optional border.
    if (showBorder) {
      canvas.drawRRect(
        bgRect,
        Paint()
          ..color       = color.withOpacity(0.45)
          ..strokeWidth = 0.8
          ..style       = PaintingStyle.stroke,
      );
    }

    // Text.
    tp.paint(
      canvas,
      center - Offset(tp.width / 2, tp.height / 2),
    );
  }

  // ── Measurement span line ─────────────────────────────────────────────────

  /// Draw a measurement bracket line between [a] and [b] with a value label
  /// at the midpoint.  Used for shoulder-width, hip-width etc.
  ///
  /// [valueCm]  — the measurement value (null = not calibrated, shows '—').
  /// [color]    — line and label colour.
  /// [offset]   — perpendicular offset from the joint line (push label away).
  static void drawMeasurementSpan(
    Canvas canvas,
    Offset a,
    Offset b,
    double? valueCm,
    Color color, {
    double tickLen = 6.0,
  }) {
    final mid = (a + b) / 2;

    // Perpendicular unit vector (rotated 90°).
    final dir  = (b - a);
    final len  = dir.distance;
    if (len < 1e-6) return;
    final perp = Offset(-dir.dy, dir.dx) / len;

    final labelText = valueCm != null
        ? '${valueCm.toStringAsFixed(1)} cm'
        : '— cm';

    // Main span line.
    drawDashedLine(canvas, a, b, color.withOpacity(0.55),
        strokeWidth: 0.8, dashLen: 5, gapLen: 3);

    // Tick marks at each end.
    final tickPaint = Paint()
      ..color       = color.withOpacity(0.7)
      ..strokeWidth = 1.0
      ..strokeCap   = StrokeCap.round;
    canvas.drawLine(a + perp * tickLen, a - perp * tickLen, tickPaint);
    canvas.drawLine(b + perp * tickLen, b - perp * tickLen, tickPaint);

    // Value label at midpoint, offset perpendicularly.
    final labelOffset = mid + perp * (tickLen + 10);
    drawLabel(canvas, labelText, labelOffset, color,
        fontSize: 9.5, showBorder: true);
  }

  // ── Alignment axis ────────────────────────────────────────────────────────

  /// Draw a vertical dashed body-axis line from [top] to [bottom].
  static void drawBodyAxis(Canvas canvas, Offset top, Offset bottom) {
    drawDashedLine(
      canvas, top, bottom,
      AppColors.skeletonAxisLine,
      strokeWidth: 1.0,
      dashLen: 10,
      gapLen:  6,
    );
  }

  /// Draw a horizontal alignment tick line centred at [center].
  static void drawHorizontalAxis(
    Canvas canvas,
    Offset center,
    double halfWidth,
    Color color,
  ) {
    drawDashedLine(
      canvas,
      center - Offset(halfWidth, 0),
      center + Offset(halfWidth, 0),
      color.withOpacity(0.55),
      strokeWidth: 0.8,
      dashLen: 6,
      gapLen:  4,
    );
  }
}

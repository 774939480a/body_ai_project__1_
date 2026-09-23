// lib/widgets/status_badge.dart
// ─────────────────────────────────────────────────────────────────────────────
// Generic status badge for the HUD — used for calibration state,
// posture status, and other real-time indicators.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../core/themes/app_theme.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.blinking = false,
  });

  final String label;
  final Color color;

  /// If true, the badge pulses to draw attention (e.g. UNSTABLE ROTATION).
  final bool blinking;

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary.withOpacity(0.75),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.5), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Courier',
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 1.0,
        ),
      ),
    );

    if (!blinking) return badge;

    // Blinking version — Phase 5 will wire this to posture engine state.
    return _BlinkingBadge(child: badge);
  }
}

class _BlinkingBadge extends StatefulWidget {
  const _BlinkingBadge({required this.child});
  final Widget child;

  @override
  State<_BlinkingBadge> createState() => _BlinkingBadgeState();
}

class _BlinkingBadgeState extends State<_BlinkingBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);

    _opacity = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _opacity, child: widget.child);
  }
}

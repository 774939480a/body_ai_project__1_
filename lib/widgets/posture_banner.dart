// lib/widgets/posture_banner.dart
// ─────────────────────────────────────────────────────────────────────────────
// PostureBanner — animated status strip shown below the top HUD.
//
// Behaviour:
//   • Slides in from the top when status changes to non-stable.
//   • Stays visible while the condition persists.
//   • Slides out when status returns to STABLE (after a short hold).
//   • UNSTABLE ROTATION: red background + pulsing opacity animation.
//   • LEANING LEFT/RIGHT: orange background + slide-in icon.
//   • STABLE: brief green flash then hides.
//   • ANALYZING / NO DATA: hidden.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/themes/app_theme.dart';
import '../posture/posture_result.dart';

class PostureBanner extends StatefulWidget {
  const PostureBanner({super.key, required this.result});

  final PostureResult result;

  @override
  State<PostureBanner> createState() => _PostureBannerState();
}

class _PostureBannerState extends State<PostureBanner>
    with TickerProviderStateMixin {

  // ── Slide animation ────────────────────────────────────────────────────────
  late final AnimationController _slideCtrl;
  late final Animation<Offset>   _slideAnim;

  // ── Pulse animation (UNSTABLE ROTATION only) ───────────────────────────────
  late final AnimationController _pulseCtrl;
  late final Animation<double>   _pulseAnim;

  // ── Auto-hide timer for STABLE flash ──────────────────────────────────────
  Timer? _hideTimer;
  bool   _visible = false;

  @override
  void initState() {
    super.initState();

    _slideCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 280),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end:   Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));

    _pulseCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.55, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _updateVisibility(widget.result.status);
  }

  @override
  void didUpdateWidget(PostureBanner old) {
    super.didUpdateWidget(old);
    if (widget.result.status != old.result.status) {
      _updateVisibility(widget.result.status);
    }
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    _pulseCtrl.dispose();
    _hideTimer?.cancel();
    super.dispose();
  }

  // ── Visibility controller ─────────────────────────────────────────────────

  void _updateVisibility(PostureStatus status) {
    _hideTimer?.cancel();

    switch (status) {
      case PostureStatus.stable:
        // Show briefly then hide.
        _show();
        _hideTimer = Timer(const Duration(seconds: 2), _hide);

      case PostureStatus.analyzing:
      case PostureStatus.noData:
        _hide();

      default:
        // All warning states — show persistently.
        _show();
    }
  }

  void _show() {
    if (!mounted) return;
    setState(() => _visible = true);
    _slideCtrl.forward();
  }

  void _hide() {
    if (!mounted) return;
    _slideCtrl.reverse().then((_) {
      if (mounted) setState(() => _visible = false);
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    final status = widget.result.status;
    final config = _BannerConfig.forStatus(status);
    final isUnstable = status == PostureStatus.unstableRotation;

    Widget banner = SlideTransition(
      position: _slideAnim,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color:        config.bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: config.fgColor.withOpacity(0.6), width: 1),
          boxShadow: [
            BoxShadow(
              color:      config.fgColor.withOpacity(0.25),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(config.icon, color: config.fgColor, size: 16),
            const SizedBox(width: 8),
            Text(
              status.label,
              style: TextStyle(
                fontFamily:  'Courier',
                fontSize:    12,
                fontWeight:  FontWeight.w700,
                color:       config.fgColor,
                letterSpacing: 1.4,
              ),
            ),
            // Tilt angle detail
            if (widget.result.shoulderTiltDeg.abs() > 1 &&
                status != PostureStatus.stable) ...[
              const SizedBox(width: 8),
              Text(
                '${widget.result.shoulderTiltDeg.abs().toStringAsFixed(1)}°',
                style: TextStyle(
                  fontFamily: 'Courier',
                  fontSize:   10,
                  color:      config.fgColor.withOpacity(0.75),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    // Pulse wrapper for UNSTABLE ROTATION.
    if (isUnstable) {
      banner = FadeTransition(opacity: _pulseAnim, child: banner);
    }

    return banner;
  }
}

// ── Banner configuration per status ──────────────────────────────────────────

class _BannerConfig {
  const _BannerConfig({
    required this.bgColor,
    required this.fgColor,
    required this.icon,
  });

  final Color   bgColor;
  final Color   fgColor;
  final IconData icon;

  static _BannerConfig forStatus(PostureStatus status) {
    switch (status) {
      case PostureStatus.stable:
        return _BannerConfig(
          bgColor: AppColors.neonGreen.withOpacity(0.15),
          fgColor: AppColors.neonGreen,
          icon:    Icons.check_circle_outline_rounded,
        );
      case PostureStatus.unstableRotation:
        return _BannerConfig(
          bgColor: AppColors.neonRed.withOpacity(0.20),
          fgColor: AppColors.neonRed,
          icon:    Icons.rotate_90_degrees_ccw_rounded,
        );
      case PostureStatus.leaningLeft:
      case PostureStatus.leaningRight:
        return _BannerConfig(
          bgColor: AppColors.neonOrange.withOpacity(0.15),
          fgColor: AppColors.neonOrange,
          icon:    Icons.swap_horiz_rounded,
        );
      case PostureStatus.leaningForward:
        return _BannerConfig(
          bgColor: AppColors.neonOrange.withOpacity(0.15),
          fgColor: AppColors.neonOrange,
          icon:    Icons.arrow_downward_rounded,
        );
      default:
        return _BannerConfig(
          bgColor: AppColors.backgroundSecondary,
          fgColor: AppColors.textSecondary,
          icon:    Icons.hourglass_top_rounded,
        );
    }
  }
}

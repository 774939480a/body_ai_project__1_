// lib/widgets/measurement_panel.dart
// ─────────────────────────────────────────────────────────────────────────────
// MeasurementPanel — displays the live body measurements from
// [MeasurementResult] in a compact sidebar panel.
//
// Shown on the right edge of the camera screen. Each measurement line
// flashes briefly when its value changes (delta > 0.5 cm) to draw attention.
//
// Phase 3 scope: full measurement panel with calibration prompt.
// Phase 4 will add inline measurement labels on the skeleton overlay.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../core/themes/app_theme.dart';
import '../models/measurement_result.dart';

class MeasurementPanel extends StatelessWidget {
  const MeasurementPanel({
    super.key,
    required this.result,
    required this.onCalibrateTap,
  });

  final MeasurementResult result;
  final VoidCallback onCalibrateTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 70,
      right: 0,
      child: Container(
        width: 118,
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary.withOpacity(0.88),
          borderRadius: const BorderRadius.only(
            topLeft:    Radius.circular(10),
            bottomLeft: Radius.circular(10),
          ),
          border: Border(
            left:   BorderSide(color: AppColors.neonCyan.withOpacity(0.3), width: 1),
            top:    BorderSide(color: AppColors.neonCyan.withOpacity(0.2), width: 1),
            bottom: BorderSide(color: AppColors.neonCyan.withOpacity(0.2), width: 1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Panel header ──────────────────────────────────────────
            _PanelHeader(
              isCalibrated: result.isCalibrated,
              onCalibrateTap: onCalibrateTap,
            ),

            // ── Measurements list ─────────────────────────────────────
            if (result.isCalibrated)
              ..._buildMeasurementRows(result)
            else
              _UncalibratedPrompt(onTap: onCalibrateTap),

            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildMeasurementRows(MeasurementResult r) {
    final data = r.asMap;

    return MeasurementKey.all
        .where((k) => data.containsKey(k))
        .map((k) => _MeasurementRow(label: k, valueCm: data[k]!))
        .toList();
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.isCalibrated,
    required this.onCalibrateTap,
  });

  final bool isCalibrated;
  final VoidCallback onCalibrateTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onCalibrateTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.neonCyan.withOpacity(0.08),
          border: Border(
            bottom: BorderSide(color: AppColors.neonCyan.withOpacity(0.2), width: 1),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'MEASURE',
              style: TextStyle(
                fontFamily: 'Courier',
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: AppColors.neonCyan,
                letterSpacing: 1.5,
              ),
            ),
            Icon(
              isCalibrated ? Icons.check_circle : Icons.tune,
              color: isCalibrated ? AppColors.neonGreen : AppColors.neonOrange,
              size: 12,
            ),
          ],
        ),
      ),
    );
  }
}

class _MeasurementRow extends StatelessWidget {
  const _MeasurementRow({required this.label, required this.valueCm});

  final String label;
  final double valueCm;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Label
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Courier',
                fontSize: 9,
                color: AppColors.textSecondary,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Value
          Text(
            '${valueCm.toStringAsFixed(1)}',
            style: const TextStyle(
              fontFamily: 'Courier',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.neonCyan,
            ),
          ),
          const Text(
            'cm',
            style: TextStyle(
              fontFamily: 'Courier',
              fontSize: 8,
              color: AppColors.textDisabled,
            ),
          ),
        ],
      ),
    );
  }
}

class _UncalibratedPrompt extends StatelessWidget {
  const _UncalibratedPrompt({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            const Icon(Icons.tune, color: AppColors.neonOrange, size: 20),
            const SizedBox(height: 6),
            const Text(
              'Tap to\ncalibrate',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Courier',
                fontSize: 9,
                color: AppColors.neonOrange,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Measurements\nshow in px\nuntil calibrated',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Courier',
                fontSize: 8,
                color: AppColors.textDisabled,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

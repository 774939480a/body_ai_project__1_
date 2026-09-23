// lib/widgets/calibration_dialog.dart
// ─────────────────────────────────────────────────────────────────────────────
// CalibrationDialog — bottom-sheet dialog that lets the user trigger
// height-based calibration or A4 paper calibration.
//
// Phase 3 scope: height-based calibration fully wired.
// A4 calibration: UI present, marked as "Phase 5" (drag-line interaction).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../calibration/calibration_data.dart';
import '../calibration/calibration_service.dart';
import '../core/themes/app_theme.dart';
import '../models/pose_data.dart';

/// Show the calibration bottom sheet.
///
/// [onCalibrated] is called with the resulting [CalibrationData] on success.
Future<void> showCalibrationSheet({
  required BuildContext context,
  required CalibrationService service,
  required PoseData? currentPose,
  required Size canvasSize,
  required void Function(CalibrationData) onCalibrated,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.backgroundSecondary,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      side: BorderSide(color: Color(0xFF1A3A55), width: 1),
    ),
    builder: (_) => _CalibrationSheet(
      service:      service,
      currentPose:  currentPose,
      canvasSize:   canvasSize,
      onCalibrated: onCalibrated,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class _CalibrationSheet extends StatefulWidget {
  const _CalibrationSheet({
    required this.service,
    required this.currentPose,
    required this.canvasSize,
    required this.onCalibrated,
  });

  final CalibrationService  service;
  final PoseData?           currentPose;
  final Size                canvasSize;
  final void Function(CalibrationData) onCalibrated;

  @override
  State<_CalibrationSheet> createState() => _CalibrationSheetState();
}

class _CalibrationSheetState extends State<_CalibrationSheet> {
  final TextEditingController _heightController = TextEditingController();
  String? _errorMessage;
  bool _isLoading = false;

  @override
  void dispose() {
    _heightController.dispose();
    super.dispose();
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  void _calibrateHeight() {
    setState(() { _errorMessage = null; _isLoading = true; });

    final text = _heightController.text.trim();
    final height = double.tryParse(text);

    if (height == null) {
      setState(() {
        _errorMessage = 'Enter a valid number (e.g. 175).';
        _isLoading = false;
      });
      return;
    }

    final result = widget.service.calibrateFromHeight(
      userHeightCm: height,
      poseData:     widget.currentPose ?? PoseData(
        landmarks:     const {},
        timestamp:     DateTime.now(),
        imageSize:     Size.zero,
        isFrontCamera: false,
      ),
      canvasSize: widget.canvasSize,
    );

    if (result is CalibrationSuccess) {
      // Record shoulder baseline for Z-skew detection.
      if (widget.currentPose != null) {
        widget.service.recordShoulderBaseline(
          widget.currentPose!, widget.canvasSize,
        );
      }
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop();
      widget.onCalibrated(result.data);
    } else if (result is CalibrationFailure) {
      setState(() {
        _errorMessage = result.reason;
        _isLoading = false;
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final poseReady = widget.currentPose?.isMeasurementReady ?? false;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24, 20, 24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'CALIBRATION',
                style: TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.neonCyan,
                  letterSpacing: 3,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: AppColors.textSecondary),
              ),
            ],
          ),

          const SizedBox(height: 4),
          Text(
            'Set a reference to convert pixels → centimetres.',
            style: AppTextStyles.bodySmall.copyWith(fontSize: 12),
          ),

          const SizedBox(height: 20),

          // ── Mode A: Height ───────────────────────────────────────────
          _SectionHeader(label: 'MODE A — USER HEIGHT'),
          const SizedBox(height: 10),

          // Pose readiness indicator
          _PoseReadinessRow(isReady: poseReady),
          const SizedBox(height: 12),

          // Height input
          TextField(
            controller: _heightController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontFamily: 'Courier',
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
            decoration: InputDecoration(
              hintText: '175',
              hintStyle: const TextStyle(color: AppColors.textDisabled),
              suffixText: 'cm',
              suffixStyle: const TextStyle(
                color: AppColors.neonCyan,
                fontFamily: 'Courier',
                fontWeight: FontWeight.w700,
              ),
              filled: true,
              fillColor: AppColors.backgroundPrimary,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.neonCyan, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.neonCyan, width: 2),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF1A3A55), width: 1),
              ),
            ),
          ),

          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: const TextStyle(
                color: AppColors.neonRed,
                fontFamily: 'Courier',
                fontSize: 11,
              ),
            ),
          ],

          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _calibrateHeight,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.backgroundPrimary,
                      ),
                    )
                  : const Text('CALIBRATE WITH HEIGHT'),
            ),
          ),

          const SizedBox(height: 24),

          // ── Mode B: A4 Paper ─────────────────────────────────────────
          _SectionHeader(label: 'MODE B — A4 PAPER'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.backgroundPrimary,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1A3A55), width: 1),
            ),
            child: Row(
              children: [
                const Icon(Icons.construction, color: AppColors.neonOrange, size: 18),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'A4 drag-line calibration will be added in Phase 5.',
                    style: TextStyle(
                      color: AppColors.neonOrange,
                      fontFamily: 'Courier',
                      fontSize: 10,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 3, height: 14, color: AppColors.neonCyan),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Courier',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }
}

class _PoseReadinessRow extends StatelessWidget {
  const _PoseReadinessRow({required this.isReady});
  final bool isReady;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isReady ? AppColors.neonGreen : AppColors.neonOrange,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          isReady
              ? 'Full body detected — ready to calibrate'
              : 'Stand fully visible in the guide frame first',
          style: TextStyle(
            fontFamily: 'Courier',
            fontSize: 11,
            color: isReady ? AppColors.neonGreen : AppColors.neonOrange,
          ),
        ),
      ],
    );
  }
}

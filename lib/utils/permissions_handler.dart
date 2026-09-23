// lib/utils/permissions_handler.dart
// ─────────────────────────────────────────────────────────────────────────────
// Wraps the permission_handler package for safe, testable permission checking.
// Never call platform APIs directly — always go through this class.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:logger/logger.dart';
import 'package:permission_handler/permission_handler.dart';

/// Result of a permission request.
enum PermissionResult {
  granted,
  denied,
  permanentlyDenied, // user tapped "Don't ask again"
}

/// Manages runtime permissions required by the application.
class PermissionsHandler {
  PermissionsHandler({required Logger logger}) : _logger = logger;

  final Logger _logger;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Request camera permission and return the result.
  ///
  /// Callers should react to [PermissionResult.permanentlyDenied] by showing
  /// an app-settings dialog.
  Future<PermissionResult> requestCameraPermission() async {
    _logger.d('[PermissionsHandler] Checking camera permission...');

    final status = await Permission.camera.status;
    _logger.d('[PermissionsHandler] Current status: $status');

    if (status.isGranted) {
      return PermissionResult.granted;
    }

    if (status.isPermanentlyDenied) {
      _logger.w('[PermissionsHandler] Camera permission permanently denied.');
      return PermissionResult.permanentlyDenied;
    }

    // Request from the user
    final result = await Permission.camera.request();
    _logger.d('[PermissionsHandler] Request result: $result');

    if (result.isGranted) return PermissionResult.granted;
    if (result.isPermanentlyDenied) return PermissionResult.permanentlyDenied;
    return PermissionResult.denied;
  }

  /// Returns true if the camera permission is currently granted.
  Future<bool> get isCameraGranted async =>
      (await Permission.camera.status).isGranted;

  /// Opens the device app-settings screen so the user can manually grant
  /// a permanently denied permission.
  Future<bool> openSettings() => openAppSettings();
}

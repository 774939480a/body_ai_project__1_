// lib/main.dart
// ─────────────────────────────────────────────────────────────────────────────
// Application entry point.
//
// Execution order:
//   1. Ensure Flutter engine is bound.
//   2. Lock portrait orientation (body measurement works best upright).
//   3. Initialise the DI container (ServiceLocator).
//   4. Run the app wrapped in ProviderScope (Riverpod).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


import 'core/di/service_locator.dart';
import 'core/themes/app_theme.dart';
import 'screens/camera_screen.dart';


Future<void> main() async {
  // Must be called before any platform-channel interaction.
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait so sensor orientation maths are consistent.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Extend UI behind the system status bar for the full-screen camera look.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // Initialise dependency injection.
  await ServiceLocator.init();

  runApp(
    // Riverpod scope — Phase 2+ providers will live here.
    const ProviderScope(
      child: BodyAiApp(),
    ),
  );
}

class BodyAiApp extends StatelessWidget {
  const BodyAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Body AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const CameraScreen(),
    );
  }
}
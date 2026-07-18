import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';

import 'app.dart';
import 'core/network/driver_dio_client.dart';
import 'core/network_quality_service.dart';
import 'core/push_notification_service.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Surveillance connectivité (bannière hors-ligne du shell).
  NetworkQualityService.instance.init();

  // Portrait only — delivery app is portrait-first
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Status bar styling
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  // Initialize Dio with JWT refresh
  await DriverDioClient.initialize();

  // Firebase (push notifications). Guarded so a failed init — e.g. an
  // unreachable Firebase CDN on web — never blanks the app.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await PushNotificationService.initialize();
  } catch (e) {
    debugPrint('[Firebase] init skipped: $e');
  }

  runApp(const ProviderScope(child: DriverApp()));
}

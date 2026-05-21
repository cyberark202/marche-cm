import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/network/driver_dio_client.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  runApp(const ProviderScope(child: DriverApp()));
}

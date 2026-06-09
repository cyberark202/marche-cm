// Smoke test for the Market CM Driver app.
//
// The router-driven app needs DriverDioClient.initialize() at boot, so we
// assert the standalone theme builder instead of pumping the full tree.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driver_app/core/theme/driver_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test('DriverTheme.light builds a light theme', () {
    final theme = DriverTheme.light();
    expect(theme.brightness, Brightness.light);
  });
}

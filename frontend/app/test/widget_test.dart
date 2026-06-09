// Smoke tests for the Marché CM multi-role app.
//
// Booting the full app requires SecureDioClient.initialize(), secure storage
// and Firebase, which aren't available in the test sandbox — so we assert the
// core building blocks instead (theme + session defaults).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marche_cm/core/app_theme.dart';
import 'package:marche_cm/features/auth/session_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test('AppTheme.light builds a Material 3 light theme', () {
    final theme = AppTheme.light();
    expect(theme.useMaterial3, isTrue);
    expect(theme.brightness, Brightness.light);
  });

  test('SessionStore starts unauthenticated as buyer', () {
    final session = SessionStore();
    expect(session.isAuthenticated, isFalse);
    expect(session.role, UserRole.buyer);
  });
}

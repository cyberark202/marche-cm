/// Device security service — root/jailbreak, Frida, emulator, debugger detection.
///
/// Architecture:
///   - Checks run at app launch and before every sensitive operation.
///   - Detection is layered: each signal adds to a suspicion score.
///   - Score >= BLOCK_THRESHOLD → hard block (sensitive features disabled).
///   - All checks are best-effort: a sophisticated attacker may bypass some.
///     Defense-in-depth: backend verification is the authoritative gate.
///
/// OWASP MASVS-RESILIENCE-1 through MASVS-RESILIENCE-4
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

/// Minimum suspicion score that triggers hard-blocking of sensitive features.
const int _blockThreshold = 3;

/// Result of a device security assessment.
class DeviceSecurityResult {
  final int score;
  final List<String> signals;

  const DeviceSecurityResult({required this.score, required this.signals});

  bool get isCompromised => score >= _blockThreshold;

  bool get isSuspicious => score > 0 && score < _blockThreshold;

  @override
  String toString() =>
      'DeviceSecurityResult(score=$score, signals=$signals)';
}

class DeviceSecurityService {
  DeviceSecurityService._();

  /// Run all device security checks and return a composite result.
  ///
  /// In debug builds, all checks are skipped (returns score=0) so developers
  /// are not blocked during local development.
  static Future<DeviceSecurityResult> assess() async {
    if (kDebugMode) {
      return const DeviceSecurityResult(score: 0, signals: ['debug_mode_bypass']);
    }

    final signals = <String>[];
    var score = 0;

    void add(String signal, int weight) {
      signals.add(signal);
      score += weight;
    }

    if (Platform.isAndroid) {
      if (await _androidIsRooted()) add('android_root', 3);
      if (_androidEmulatorDetected()) add('android_emulator', 2);
      if (await _fridaDetected()) add('frida_detected', 3);
      if (_debuggerAttached()) add('debugger_attached', 2);
    } else if (Platform.isIOS) {
      if (await _iosIsJailbroken()) add('ios_jailbreak', 3);
      if (await _fridaDetected()) add('frida_detected', 3);
      if (_debuggerAttached()) add('debugger_attached', 2);
    }

    return DeviceSecurityResult(score: score, signals: signals);
  }

  // ── Android root detection ─────────────────────────────────────────────────

  static Future<bool> _androidIsRooted() async {
    // Check for well-known root indicators — each alone is weak,
    // but together they form a reliable signal.
    final rootPaths = [
      '/system/app/Superuser.apk',
      '/system/app/SuperSU.apk',
      '/sbin/su',
      '/system/bin/su',
      '/system/xbin/su',
      '/system/xbin/daemonsu',
      '/data/local/xbin/su',
      '/data/local/bin/su',
      '/data/local/su',
      '/system/sd/xbin/su',
      '/system/bin/.ext/.su',
      '/system/usr/we-need-root/su',
      '/system/bin/failsafe/su',
      '/dev/com.koushikdutta.superuser.daemon/',
      '/system/app/Kinguser.apk',
      '/data/data/com.noshufou.android.su',
      '/data/data/com.noshufou.android.su.elite',
      '/data/data/eu.chainfire.supersu',
      '/data/data/com.koushikdutta.superuser',
      '/data/data/com.thirdparty.superuser',
      '/data/data/com.yellowes.su',
    ];

    for (final path in rootPaths) {
      if (await File(path).exists()) return true;
    }

    // Check if /system partition is writable (on a rooted device it often is).
    try {
      final testFile = File('/system/.root_check_test');
      await testFile.writeAsString('test');
      await testFile.delete();
      return true; // Should never succeed on stock Android
    } catch (_) {
      // Expected — /system is read-only on stock devices.
    }

    return false;
  }

  static bool _androidEmulatorDetected() {
    // Emulator-specific environment signals (best-effort via Platform APIs).
    // For stronger detection, use a platform channel to read Build.FINGERPRINT,
    // Build.MODEL, Build.MANUFACTURER from native code.
    if (Platform.environment['ANDROID_EMULATOR_SDK'] != null) return true;
    if (Platform.environment['ANDROID_AVD_NAME'] != null) return true;
    return false;
  }

  // ── iOS jailbreak detection ─────────────────────────────────────────────────

  static Future<bool> _iosIsJailbroken() async {
    final jailbreakPaths = [
      '/Applications/Cydia.app',
      '/Applications/blackra1n.app',
      '/Applications/FakeCarrier.app',
      '/Applications/Icy.app',
      '/Applications/IntelliScreen.app',
      '/Applications/MxTube.app',
      '/Applications/RockApp.app',
      '/Applications/SBSettings.app',
      '/Applications/WinterBoard.app',
      '/Library/MobileSubstrate/MobileSubstrate.dylib',
      '/bin/bash',
      '/bin/sh',
      '/usr/sbin/sshd',
      '/usr/libexec/sftp-server',
      '/private/var/lib/apt/',
      '/private/var/lib/cydia',
      '/private/var/stash',
      '/private/var/mobile/Library/SBSettings/Themes',
      '/System/Library/LaunchDaemons/com.ikey.bbot.plist',
      '/System/Library/LaunchDaemons/com.saurik.Cydia.Startup.plist',
      '/etc/apt',
    ];

    for (final path in jailbreakPaths) {
      if (await File(path).exists()) return true;
      if (await Directory(path).exists()) return true;
    }

    // Attempt to write outside sandbox — jailbroken devices allow this.
    try {
      final testPath = '/private/jailbreak_test_${DateTime.now().millisecondsSinceEpoch}';
      await File(testPath).writeAsString('test');
      await File(testPath).delete();
      return true;
    } catch (_) {
      // Expected — sandbox prevents this on stock iOS.
    }

    return false;
  }

  // ── Frida / instrumentation framework detection ────────────────────────────

  static Future<bool> _fridaDetected() async {
    // Frida injects a gadget and opens a local server on a known port.
    // Attempting to connect to that port is a reliable detection signal.
    const fridaPorts = [27042, 27043];

    for (final port in fridaPorts) {
      try {
        final socket = await Socket.connect(
          '127.0.0.1',
          port,
          timeout: const Duration(milliseconds: 200),
        );
        await socket.close();
        return true; // Connection succeeded — Frida is listening
      } catch (_) {
        // Expected — port closed on clean device
      }
    }

    // Check for Frida-related files on Android.
    if (Platform.isAndroid) {
      final fridaFiles = [
        '/data/local/tmp/frida-server',
        '/data/local/tmp/re.frida.server',
      ];
      for (final f in fridaFiles) {
        if (await File(f).exists()) return true;
      }
    }

    return false;
  }

  // ── Debugger detection ─────────────────────────────────────────────────────

  static bool _debuggerAttached() {
    // In release mode, the VM should not be in debug/profile mode.
    // kDebugMode and kProfileMode are compile-time constants — tree-shaken
    // in release builds, so this check is a no-op in release.
    if (kDebugMode || kProfileMode) return true;
    return false;
  }
}

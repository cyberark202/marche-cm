library;

import 'dart:io';

import 'package:flutter/foundation.dart';

const int _blockThreshold = 3;

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


  static Future<bool> _androidIsRooted() async {
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

    try {
      final testFile = File('/system/.root_check_test');
      await testFile.writeAsString('test');
      await testFile.delete();
      return true;
    } catch (_) {
    }

    return false;
  }

  static bool _androidEmulatorDetected() {
    if (Platform.environment['ANDROID_EMULATOR_SDK'] != null) return true;
    if (Platform.environment['ANDROID_AVD_NAME'] != null) return true;
    return false;
  }


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

    try {
      final testPath = '/private/jailbreak_test_${DateTime.now().millisecondsSinceEpoch}';
      await File(testPath).writeAsString('test');
      await File(testPath).delete();
      return true;
    } catch (_) {
    }

    return false;
  }


  static Future<bool> _fridaDetected() async {
    const fridaPorts = [27042, 27043];

    for (final port in fridaPorts) {
      try {
        final socket = await Socket.connect(
          '127.0.0.1',
          port,
          timeout: const Duration(milliseconds: 200),
        );
        await socket.close();
        return true;
      } catch (_) {
      }
    }

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


  static bool _debuggerAttached() {
    if (kDebugMode || kProfileMode) return true;
    return false;
  }
}

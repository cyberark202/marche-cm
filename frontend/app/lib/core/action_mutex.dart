import 'dart:async';

import 'package:flutter/services.dart';

class ActionMutex {
  bool _locked = false;
  DateTime? _lastCompleted;

  bool get isLocked => _locked;

  Future<T?> run<T>(
    Future<T> Function() action, {
    Duration cooldown = const Duration(milliseconds: 800),
    bool haptic = true,
  }) async {
    if (_locked) return null;
    if (_lastCompleted != null &&
        DateTime.now().difference(_lastCompleted!) < cooldown) {
      return null;
    }
    _locked = true;
    if (haptic) HapticFeedback.lightImpact();
    try {
      return await action();
    } finally {
      _locked = false;
      _lastCompleted = DateTime.now();
    }
  }

  Future<T?> runOrThrow<T>(
    Future<T> Function() action, {
    Duration cooldown = const Duration(milliseconds: 800),
    bool haptic = true,
  }) async {
    if (_locked) return null;
    if (_lastCompleted != null &&
        DateTime.now().difference(_lastCompleted!) < cooldown) {
      return null;
    }
    _locked = true;
    if (haptic) HapticFeedback.lightImpact();
    try {
      return await action();
    } catch (e) {
      rethrow;
    } finally {
      _locked = false;
      _lastCompleted = DateTime.now();
    }
  }

  void reset() {
    _locked = false;
    _lastCompleted = null;
  }
}

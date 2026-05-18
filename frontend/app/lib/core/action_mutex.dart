import 'dart:async';

import 'package:flutter/services.dart';

/// Lightweight mutex preventing concurrent execution of async actions.
///
/// Designed for fintech payment flows on low-end Android (Tecno Spark, Infinix
/// Hot) where tap events can queue before the first call returns. Prevents:
///   - Double payment submissions
///   - Multi-submit forms
///   - Spam tap races on slow devices
///
/// Usage:
///   final _mutex = ActionMutex();
///   onTap: () => _mutex.run(_submitPayment),
class ActionMutex {
  bool _locked = false;
  DateTime? _lastCompleted;

  bool get isLocked => _locked;

  /// Runs [action] exclusively. Returns null if already locked or in cooldown.
  ///
  /// [cooldown] prevents rapid re-triggering after unlock (default 800ms).
  /// [haptic] triggers a light vibration on first accepted tap (default true).
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

  /// Same as [run] but re-throws exceptions instead of swallowing them.
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

  /// Resets all state. Use after navigation away from a form.
  void reset() {
    _locked = false;
    _lastCompleted = null;
  }
}

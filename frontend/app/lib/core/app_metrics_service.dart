import 'dart:collection';

/// Event types tracked for product observability.
enum MetricEvent {
  apiTimeout,
  apiError,
  apiSuccess,
  paymentInitiated,
  paymentSuccess,
  paymentFailed,
  paymentTimedOut,
  rageTap,
  cacheHit,
  cacheMiss,
  offlineStart,
  offlineEnd,
  notchPayPollCycle,
}

class MetricEntry {
  MetricEntry({
    required this.event,
    required this.ts,
    this.latencyMs,
    this.extra,
  });

  final MetricEvent event;
  final DateTime ts;
  final int? latencyMs;
  // Non-PII metadata only (screen name, provider code, etc.)
  final Map<String, String>? extra;

  @override
  String toString() =>
      '[${ts.toIso8601String()}] ${event.name}'
      '${latencyMs != null ? ' ${latencyMs}ms' : ''}'
      '${extra != null ? ' $extra' : ''}';
}

/// In-memory ring buffer for product observability metrics.
///
/// No PII is ever stored — only event types, latencies, and non-PII labels
/// (screen name, payment provider code, etc.).
/// Ring buffer caps at [maxEntries] to bound memory on low-end Android.
/// Consumers can read [recentEvents] or subscribe to the synchronous
/// [onEvent] callback for live dashboards.
class AppMetricsService {
  AppMetricsService._();
  static final AppMetricsService instance = AppMetricsService._();

  final int maxEntries = 200;
  final ListQueue<MetricEntry> _buffer = ListQueue();

  // Optional live listener (e.g. debug overlay). Not persistent.
  void Function(MetricEntry)? onEvent;

  // ── Recording ─────────────────────────────────────────────────────────────

  void record(
    MetricEvent event, {
    int? latencyMs,
    Map<String, String>? extra,
  }) {
    final entry = MetricEntry(
      event: event,
      ts: DateTime.now(),
      latencyMs: latencyMs,
      extra: extra,
    );
    if (_buffer.length >= maxEntries) _buffer.removeFirst();
    _buffer.addLast(entry);
    onEvent?.call(entry);
  }

  void recordApiSuccess(String screen, int latencyMs) => record(
        MetricEvent.apiSuccess,
        latencyMs: latencyMs,
        extra: {'screen': screen},
      );

  void recordApiTimeout(String screen) => record(
        MetricEvent.apiTimeout,
        extra: {'screen': screen},
      );

  void recordApiError(String screen) => record(
        MetricEvent.apiError,
        extra: {'screen': screen},
      );

  void recordPaymentInitiated(String provider) => record(
        MetricEvent.paymentInitiated,
        extra: {'provider': provider},
      );

  void recordPaymentSuccess(String provider, int latencyMs) => record(
        MetricEvent.paymentSuccess,
        latencyMs: latencyMs,
        extra: {'provider': provider},
      );

  void recordPaymentFailed(String provider) => record(
        MetricEvent.paymentFailed,
        extra: {'provider': provider},
      );

  void recordPaymentTimedOut(String provider) => record(
        MetricEvent.paymentTimedOut,
        extra: {'provider': provider},
      );

  void recordRageTap(String screen) => record(
        MetricEvent.rageTap,
        extra: {'screen': screen},
      );

  void recordCacheHit(String key) => record(
        MetricEvent.cacheHit,
        extra: {'key': key},
      );

  void recordCacheMiss(String key) => record(
        MetricEvent.cacheMiss,
        extra: {'key': key},
      );

  // ── Aggregates ────────────────────────────────────────────────────────────

  UnmodifiableListView<MetricEntry> get recentEvents =>
      UnmodifiableListView(_buffer);

  int countSince(MetricEvent event, Duration window) {
    final cutoff = DateTime.now().subtract(window);
    return _buffer
        .where((e) => e.event == event && e.ts.isAfter(cutoff))
        .length;
  }

  double? avgLatency(MetricEvent event, {Duration window = const Duration(minutes: 5)}) {
    final cutoff = DateTime.now().subtract(window);
    final entries = _buffer
        .where((e) => e.event == event && e.ts.isAfter(cutoff) && e.latencyMs != null)
        .toList();
    if (entries.isEmpty) return null;
    return entries.map((e) => e.latencyMs!).reduce((a, b) => a + b) /
        entries.length;
  }

  int get timeoutCount =>
      _buffer.where((e) => e.event == MetricEvent.apiTimeout).length;
  int get rageTapCount =>
      _buffer.where((e) => e.event == MetricEvent.rageTap).length;
  int get paymentFailCount =>
      _buffer.where((e) => e.event == MetricEvent.paymentFailed).length;

  // ── Debug ─────────────────────────────────────────────────────────────────

  void clear() => _buffer.clear();

  String dump() => _buffer.map((e) => e.toString()).join('\n');
}

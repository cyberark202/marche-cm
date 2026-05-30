import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/format.dart';

/// Shared display logic for shipment disputes.
class DisputeHelpers {
  const DisputeHelpers._();

  static bool isUrgent(Map<String, dynamic> dispute) {
    final created = DateTime.tryParse('${dispute['created_at'] ?? ''}');
    if (created == null) return false;
    return DateTime.now().difference(created).inDays >= 2;
  }

  static String short(dynamic id) {
    final s = '$id';
    return s.length > 7 ? s.substring(0, 7).toUpperCase() : s.toUpperCase();
  }

  static String statusLabel(String status) {
    switch (status) {
      case 'OPEN':
        return 'OUVERT';
      case 'UNDER_REVIEW':
        return 'EN TRAITEMENT';
      case 'INSPECTION_PENDING':
        return 'INSPECTION';
      case 'APPEAL_REQUESTED':
        return 'APPEL';
      case 'RESOLVED':
        return 'RÉSOLU';
      case 'CLOSED_NO_ACTION':
        return 'FERMÉ';
      default:
        return status;
    }
  }

  static Color statusColor(String status) {
    switch (status) {
      case 'OPEN':
        return AppPalette.warning;
      case 'RESOLVED':
        return AppPalette.success;
      case 'CLOSED_NO_ACTION':
        return AppPalette.textMuted;
      default:
        return AppPalette.info;
    }
  }

  static String partyName(dynamic display) {
    if (display is Map) {
      final name = '${display['username'] ?? ''}'.trim();
      if (name.isNotEmpty) return name;
    }
    return '—';
  }

  /// Best-effort monetary amount associated with a dispute.
  static num amount(Map<String, dynamic> d) {
    for (final key in [
      'disputed_amount',
      'escrow_amount',
      'amount',
      'guarantee_fund_amount',
    ]) {
      final v = d[key];
      if (v != null) {
        final n = Fmt.amount(v);
        if (n > 0) return n;
      }
    }
    return 0;
  }
}

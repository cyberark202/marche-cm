import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Backend role enum → human label + accent colour, shared across screens.
class Roles {
  const Roles._();

  static String label(String? raw) {
    switch (raw) {
      case 'GENERAL_ADMIN':
        return 'Admin';
      case 'SUPPLIER':
        return 'Fournisseur';
      case 'WHOLESALER':
        return 'Grossiste';
      case 'TRANSIT_AGENT':
        return 'Livreur';
      case 'BUYER':
        return 'Acheteur';
      default:
        return raw ?? '—';
    }
  }

  static Color color(String? raw) {
    switch (raw) {
      case 'GENERAL_ADMIN':
        return AppPalette.secondary;
      case 'SUPPLIER':
      case 'WHOLESALER':
        return AppPalette.primary;
      case 'TRANSIT_AGENT':
        return AppPalette.info;
      case 'BUYER':
        return AppPalette.accent;
      default:
        return AppPalette.textMuted;
    }
  }

  /// The catalogue's coarse filter buckets (screen 33).
  static bool matchesBucket(String bucket, String? rawRole) {
    switch (bucket) {
      case 'Acheteur':
        return rawRole == 'BUYER';
      case 'Vendeur':
        return rawRole == 'SUPPLIER' || rawRole == 'WHOLESALER';
      case 'Livreur':
        return rawRole == 'TRANSIT_AGENT';
      default:
        return true;
    }
  }
}
